import Foundation
import Combine
import CoreLocation
import MapKit
import OSLog

/// Одна точка маршрута, как её набрал человек: имя для строки и координата
/// для `MKDirections`.
struct ManualTripPoint: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var coordinate: CLLocationCoordinate2D

    static func == (a: ManualTripPoint, b: ManualTripPoint) -> Bool { a.id == b.id }

    /// Заготовка промежуточной точки: строка в списке уже есть, места за ней
    /// ещё нет. Ноль-ноль — законная координата (Гвинейский залив), поэтому
    /// проверяется вместе с пустым именем, а не вместо него.
    var isPlaceholder: Bool {
        name.isEmpty && coordinate.latitude == 0 && coordinate.longitude == 0
    }
}

/// Состояние листа «Вписать поездку» — всё, что считается, живёт здесь, а не
/// в `body`.
///
/// Причина та же, что у `PlacesTabViewModel`: `body` перерисовывается на
/// каждый символ в поиске и на каждый кадр перетаскивания листа, а здесь
/// поднимаются ответы `MKLocalSearchCompleter`, ходит в сеть `MKDirections` и
/// собирается трек.
@MainActor
final class ManualTripModel: ObservableObject {

    // MARK: - Что набрал человек

    @Published var from: ManualTripPoint?
    @Published var to: ManualTripPoint?
    @Published var via: [ManualTripPoint] = []
    @Published var startDate: Date
    @Published var duration: TimeInterval = 3600
    @Published var vehicleId: UUID?
    @Published var title: String = ""

    // MARK: - Что посчиталось

    @Published private(set) var route: ManualTripRouter.Route?
    @Published private(set) var isRouting = false
    @Published private(set) var routeError: ManualTripRouteError?

    // MARK: - Поиск

    @Published var query: String = ""
    @Published private(set) var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private let completerBox = CompleterBox()
    private var routeTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.triptrack", category: "manualtrip")

    /// Шаг длительности — четверть часа. Минуты человек здесь не помнит, а
    /// секунды не помнит никто: поездка вписывается спустя дни.
    static let durationStep: TimeInterval = 15 * 60

    init(startDate: Date = Date()) {
        // Поездка вписывается ЗАДНИМ числом, поэтому «сейчас» — плохое
        // умолчание: оно предлагает будущее в тот же час. Час назад — самое
        // близкое прошлое, которое уже прошло.
        self.startDate = startDate.addingTimeInterval(-3600)
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = completerBox
        completerBox.onResults = { [weak self] results in
            self?.completions = results
        }
    }

    // MARK: - Поиск места

    func updateSearch(_ text: String) {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else {
            completions = []
            completer.queryFragment = ""
            return
        }
        completer.queryFragment = trimmed
    }

    /// Подсказка `MKLocalSearchCompleter` координаты не несёт — её достаёт
    /// второй запрос, `MKLocalSearch`. Отсюда `async`: нажатие на строку
    /// списка это ещё один поход в сеть, а не готовый ответ.
    func resolve(_ completion: MKLocalSearchCompletion) async -> ManualTripPoint? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first,
              let coord = item.placemark.location?.coordinate else { return nil }
        let name = item.name ?? completion.title
        return ManualTripPoint(name: name, coordinate: coord)
    }

    /// Точка, поставленная пальцем по карте. Имя спрашивается у геокодера, но
    /// его отсутствие не мешает: координата уже есть, а подпись — украшение.
    func point(at coordinate: CLLocationCoordinate2D) async -> ManualTripPoint {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let name = placemark?.name ?? placemark?.locality ?? placemark?.administrativeArea
        return ManualTripPoint(name: name ?? "", coordinate: coordinate)
    }

    // MARK: - Маршрут

    /// Один живой расчёт на лист: предыдущий отменяется, а не доживает.
    /// Тот же приём, что у `FogLoadSequencer` — ложится ПОСЛЕДНИЙ запущенный,
    /// а не последний ответивший, иначе смена «куда» на быстром ответе
    /// перезаписывалась бы медленным ответом прежней пары.
    func recomputeRoute() {
        routeTask?.cancel()
        guard let from, let to else {
            route = nil
            routeError = nil
            isRouting = false
            return
        }
        // Заготовка без места маршрут не удлиняет — она его уронила бы
        // в ноль широты и ноль долготы.
        let stops = via.filter { !$0.isPlaceholder }.map(\.coordinate)
        isRouting = true
        routeError = nil
        routeTask = Task { [weak self] in
            do {
                let built = try await ManualTripRouter.route(
                    from: from.coordinate, to: to.coordinate, via: stops)
                guard !Task.isCancelled else { return }
                self?.apply(built)
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(error)
            }
        }
    }

    private func apply(_ built: ManualTripRouter.Route) {
        route = built
        routeError = nil
        isRouting = false
        // Маршрут приехал длиннее, чем позволяет уже набранное время —
        // подтягиваем время, а не показываем ошибку: человек ещё ничего не
        // сделал неправильно, он просто выбрал точки после того, как выставил
        // длительность.
        duration = clampDuration(duration)
    }

    private func fail(_ error: Error) {
        route = nil
        isRouting = false
        let mapped = (error as? ManualTripRouteError)
            ?? ManualTripRouter.translate(error as NSError)
        routeError = mapped
        // В лог уезжает ВИД ошибки, а не текст Apple: тот приходит с сервера
        // маршрутов и относится к тому же классу данных, что чистит
        // `PIIScrubber`.
        log.notice("route failed: \(String(describing: mapped), privacy: .public)")
    }

    /// Сколько Apple насчитала по этому маршруту — предложение, не приговор.
    var suggestedDuration: TimeInterval? {
        guard let route, route.expectedTravelTime > 0 else { return nil }
        return route.expectedTravelTime
    }

    /// Нижняя граница длительности для НЫНЕШНЕГО маршрута, округлённая вверх
    /// до шага. Ниже неё `TripDistanceGate` выбросил бы каждый отрезок как
    /// телепорт, и поездка легла бы в базу с нулём километров —
    /// см. `ManualTripBuilder.feasibleDuration`.
    var minimumDuration: TimeInterval {
        let metres = route?.appleDistance ?? 0
        let feasible = ManualTripBuilder.feasibleDuration(forRouteMetres: metres)
        return (feasible / Self.durationStep).rounded(.up) * Self.durationStep
    }

    func adjustDuration(by delta: TimeInterval) {
        duration = clampDuration(duration + delta)
    }

    func applySuggestedDuration() {
        guard let suggested = suggestedDuration else { return }
        duration = clampDuration((suggested / Self.durationStep).rounded() * Self.durationStep)
    }

    private func clampDuration(_ value: TimeInterval) -> TimeInterval {
        min(ManualTripBuilder.maximumDuration, max(minimumDuration, value))
    }

    /// Даты — только прошедшие, как у путешествия (`JourneyEditSheet`):
    /// поездка, которой ещё не было, вписана быть не может.
    var startBounds: ClosedRange<Date> {
        let now = Date()
        let earliest = Calendar.current.date(byAdding: .year, value: -20, to: now) ?? now
        // Перевернуть нельзя по построению: верхняя граница не меньше уже
        // выбранного значения. `a...b` с `b < a` — падение, а не пустой
        // диапазон (CLAUDE.md, «Ловушки»).
        return min(earliest, startDate)...max(now, startDate)
    }

    /// Дорога, которую нельзя проехать даже за верхний предел длительности.
    ///
    /// Потолок в неделю выбран так, что `MKDirections` такого маршрута не
    /// вернёт (30 240 км), — но проверка стоит ОТДЕЛЬНО и с ней связана
    /// строка на экране: иначе единственным следом этого состояния была бы
    /// выключенная кнопка без объяснения, а это ровно та мёртвая кнопка,
    /// ради которой потолок и поднимали.
    var isRouteTooLong: Bool {
        route != nil && minimumDuration > ManualTripBuilder.maximumDuration
    }

    var canCreate: Bool {
        route != nil && !isRouting && !isRouteTooLong && duration >= minimumDuration
    }

    // MARK: - Создание

    /// Поездка в базе, и дальше — `ManualTripAftermath`: места и слой
    /// открытого, и ничего больше. Ни `PostTripTrackProcessor`, ни наград —
    /// см. `TripManager.createManualTrip`.
    func create(using manager: TripManager) async -> UUID? {
        // Гейт спрашивается ЗДЕСЬ, а не только при открытии листа:
        // содержимое `.sheet` выбирается один раз, при показе, и
        // отозванная (возврат денег) за эти секунды подписка поездку бы не
        // остановила. Тот же довод, по которому `recordableVehicleId`
        // спрашивает хранилище, а не список в памяти.
        guard ManualTripEntry.level == .open else { return nil }
        guard let route else { return nil }
        let draft = ManualTripBuilder.Draft(
            coordinates: route.coordinates,
            startDate: startDate,
            duration: duration,
            vehicleId: vehicleId,
            title: title
        )
        guard let built = ManualTripBuilder.build(draft),
              let saved = manager.createManualTrip(built) else { return nil }

        await ManualTripAftermath.settle(tripId: saved.id)
        return saved.id
    }
}

/// Делегат `MKLocalSearchCompleter` отдельным объектом.
///
/// `ManualTripModel` изолирован главным актёром, а требования протокола —
/// нет: изолированный метод не удовлетворяет неизолированное требование, и в
/// Swift 6 это уже ошибка. Коробка неизолирована, а внутрь модели входит
/// через `assumeIsolated` — MapKit зовёт делегата с главного потока, и
/// перепрыгивать через `Task` значило бы показать список подсказок на кадр
/// позже, чем его набрали.
private final class CompleterBox: NSObject, MKLocalSearchCompleterDelegate {
    var onResults: (([MKLocalSearchCompletion]) -> Void)?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { onResults?(completer.results) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Пустой список — честный ответ «ничего не нашлось». Строки ошибки
        // здесь нет нарочно: подсказки не находятся постоянно, пока человек
        // ещё набирает, и краснеть на каждом втором символе экран не должен.
        MainActor.assumeIsolated { onResults?([]) }
    }
}
