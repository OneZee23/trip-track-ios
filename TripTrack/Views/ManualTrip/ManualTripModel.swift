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
    /// Почему не записалось. Снимается при каждой новой попытке; `nil` —
    /// «ещё не пробовали» или «всё вышло». Раньше отказ не оставлял ВООБЩЕ
    /// НИЧЕГО: лист стоял открытым, кнопка снова становилась активной, и
    /// понять, записалась поездка или нет, было нечем.
    @Published private(set) var createError: ManualTripCreateError?

    /// Убрать карточку отказа.
    ///
    /// Зовётся, когда человек ушёл её разбирать — на пейвол или повторным
    /// нажатием. Модель при этом ЖИВА, и набранное остаётся само: пейвол
    /// показывается вторым листом ПОВЕРХ, а не подменой содержимого хоста
    /// (§12.2 спеки). Подменить содержимое значило бы уничтожить `@StateObject`
    /// вместе с точками, остановками, временем и машиной — и писать
    /// восстановление состояния, которого иначе не нужно.
    func clearCreateError() {
        createError = nil
    }

    #if DEBUG
    /// Шов для тестов: карточку отказа иначе не получить вовсе.
    ///
    /// `.noAccess` приходит от гейта подписки, `.notSaved` — от CoreData, и
    /// подделать в тесте ни то, ни другое нечем. Только в Debug.
    func failForTesting(_ error: ManualTripCreateError) {
        createError = error
    }
    #endif
    /// Человек хоть раз подвинул длительность стрелкой ± — решение владельца
    /// 20 сен: пока флаг снят, свежепосчитанный маршрут сам подставляет
    /// `suggestedDuration` (`ManualTripDurationPolicy`), а тронутое рукой
    /// пересчёт больше не трогает.
    @Published private(set) var durationTouched = false

    // MARK: - Поиск

    @Published var query: String = ""
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    /// Запрос отправлен, ответа ещё нет.
    ///
    /// Без этого флага пустой список означал ТРИ разных вещи сразу — «ничего
    /// не набрано», «ищем» и «не нашлось», — и экран показывал на все три одно
    /// и то же белое место. Различить их снаружи нечем: `MKLocalSearchCompleter`
    /// отвечает и на неудачу пустым списком (нарочно — краснеть на каждом
    /// втором символе экран не должен).
    @Published private(set) var isSearching = false

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
            self?.isSearching = false
        }
    }

    /// Лист открыт уже заполненным — тап по пустому дню в календаре или
    /// «Добавить обратную дорогу» после успешной записи. `startDate:` у
    /// обычного `init` сдвигает «сейчас» на час назад — здесь дата пресета
    /// уже прошедшая и трогать её не нужно, поэтому она ставится ПОСЛЕ.
    convenience init(preset: ManualTripPreset) {
        self.init()
        from = preset.from
        to = preset.to
        vehicleId = preset.vehicleId
        if let startDate = preset.startDate { self.startDate = startDate }
        if let duration = preset.duration { self.duration = duration }
        if from != nil || to != nil { recomputeRoute() }
    }

    // MARK: - Поиск места

    func updateSearch(_ text: String) {
        query = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else {
            completions = []
            isSearching = false
            completer.queryFragment = ""
            return
        }
        isSearching = true
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
        //
        // Не тронутую рукой длительность решение владельца 20 сен ставит на
        // подсказку Apple сама — `ManualTripDurationPolicy` держит это
        // правило чистой функцией.
        duration = clampDuration(ManualTripDurationPolicy.resolve(
            current: duration, suggested: suggestedDuration,
            touched: durationTouched, step: Self.durationStep
        ))
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
        durationTouched = true
        duration = clampDuration(duration + delta)
    }

    /// Явное согласие на подсказку Apple — не «правка», а отказ от своей и
    /// возврат к автоследованию: следующий пересчитанный маршрут снова
    /// подставит свежую подсказку сам.
    func applySuggestedDuration() {
        guard let suggested = suggestedDuration else { return }
        durationTouched = false
        duration = clampDuration((suggested / Self.durationStep).rounded() * Self.durationStep)
    }

    private func clampDuration(_ value: TimeInterval) -> TimeInterval {
        min(ManualTripBuilder.maximumDuration, max(minimumDuration, value))
    }

    /// Даты — только прошедшие, как у путешествия (`JourneyEditSheet`):
    /// поездка, которой ещё не было, вписана быть не может.
    var startBounds: ClosedRange<Date> { ManualTripDateDefaults.bounds(for: startDate) }

    /// Чипы «Сегодня»/«Вчера»: меняют дату, время встаёт на умолчание
    /// (`ManualTripDateDefaults`) — набранное время человек здесь ещё не
    /// трогал, поэтому переписывать нечего.
    func setStartDay(_ day: Date) {
        startDate = ManualTripDateDefaults.defaultStartDate(forDay: day)
    }

    /// Убрать заготовку промежуточной точки, за которой человек так и не
    /// выбрал места.
    ///
    /// Живёт здесь, а не в листе, по общему правилу проекта: правило, которое
    /// держит открытый экран, проверяется руками. Отвечает `true`, только если
    /// строку действительно убрали, — заполненную точку «Отмена» трогать не
    /// имеет права.
    @discardableResult
    func discardPlaceholderVia(at index: Int) -> Bool {
        guard index >= 0, index < via.count, via[index].isPlaceholder else { return false }
        via.remove(at: index)
        return true
    }

    /// Точка от чипа («Дом», частое место, тап по карте) — в активное поле:
    /// сначала «Откуда», потом «Куда» (`ManualTripActiveField`).
    func assignQuickPoint(_ point: ManualTripPoint) {
        switch ManualTripActiveField.resolve(from: from, to: to) {
        case .from: from = point
        case .to: to = point
        }
        recomputeRoute()
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

    /// Финиш ещё не наступил: старт в прошлом, а длительность такая, что
    /// поездка «кончится» позже, чем сейчас. Правило считает
    /// `ManualTripBuilder.hasEnded` — то же, которым `build` отказывает, —
    /// иначе экран и сборка разошлись бы, и отказ был бы молчаливым.
    var endsLater: Bool {
        !ManualTripBuilder.hasEnded(startDate: startDate, duration: duration)
    }

    var canCreate: Bool {
        route != nil && !isRouting && !isRouteTooLong && !endsLater
            && duration >= minimumDuration
    }

    // MARK: - Создание

    /// Поездка в базе, и дальше — `ManualTripAftermath`: места и слой
    /// открытого, и ничего больше. Ни `PostTripTrackProcessor`, ни наград —
    /// см. `TripManager.createManualTrip`.
    ///
    /// Возвращает не голый `UUID`, а точки/машину/конец поездки — тот же
    /// набор, из которого лист сам собран, а «Добавить обратную дорогу»
    /// строит зеркальный `ManualTripPreset`, не перечитывая базу.
    func create(using manager: TripManager) async -> ManualTripCreationResult? {
        // Гейт спрашивается ЗДЕСЬ, а не только при открытии листа:
        // содержимое `.sheet` выбирается один раз, при показе, и
        // отозванная (возврат денег) за эти секунды подписка поездку бы не
        // остановила. Тот же довод, по которому `recordableVehicleId`
        // спрашивает хранилище, а не список в памяти.
        createError = nil
        guard ManualTripEntry.level == .open else {
            createError = .noAccess
            return nil
        }
        guard let route, let from, let to else {
            createError = .notSaved
            return nil
        }
        let draft = ManualTripBuilder.Draft(
            coordinates: route.coordinates,
            startDate: startDate,
            duration: duration,
            vehicleId: vehicleId,
            title: title
        )
        guard let built = ManualTripBuilder.build(draft),
              let saved = manager.createManualTrip(built) else {
            createError = .notSaved
            return nil
        }

        await ManualTripAftermath.settle(tripId: saved.id)
        return ManualTripCreationResult(
            tripId: saved.id, from: from, to: to, vehicleId: vehicleId,
            endDate: startDate.addingTimeInterval(duration)
        )
    }
}

/// Почему «Записать» ничего не записало.
///
/// Два случая, и слова у них разные: подписку отозвали, пока лист стоял
/// открытым (гейт спрашивается ЗАНОВО в момент записи — и правильно делает),
/// либо база отказала. Общее «не удалось» на оба означало бы, что человек с
/// кончившейся подпиской будет жать кнопку, пока не устанет.
enum ManualTripCreateError: Equatable {
    case noAccess
    case notSaved

    /// Что предлагает кнопка на карточке отказа.
    ///
    /// Два случая — две РАЗНЫЕ кнопки, и это не косметика: у человека с
    /// кончившейся подпиской «Повторить» ничего не изменит, он будет жать её,
    /// пока не устанет. А у отказа базы «Продлить» уведёт его покупать то,
    /// что у него и так есть.
    enum Action: Equatable { case renew, retry }

    var action: Action {
        switch self {
        case .noAccess: return .renew
        case .notSaved: return .retry
        }
    }
}

/// Итог успешного создания — то, чем кормится тост «Открыть поездку» /
/// «Добавить обратную дорогу».
struct ManualTripCreationResult: Identifiable {
    let tripId: UUID
    let from: ManualTripPoint
    let to: ManualTripPoint
    let vehicleId: UUID?
    let endDate: Date

    var id: UUID { tripId }
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
