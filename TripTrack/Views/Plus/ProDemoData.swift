import CoreGraphics
import CoreLocation
import SwiftUI

/// Данные человека для страниц демонстрации — снимок, считанный ОДИН раз.
///
/// Снимок, а не живые запросы: страницы пролистывают пальцем, и поход в
/// CoreData за маршрутом на каждом кадре листания — это фриз. Маршрут при этом
/// приезжает сюда уже В ЕДИНИЧНОМ пространстве: у превью нет карты, ему не
/// нужны ни широта, ни проекция.
struct ProDemoData: Equatable {
    var name: String
    var avatarEmoji: String
    var trips: Int
    /// Пройденное расстояние в МЕТРАХ.
    ///
    /// Безымянное по единице нарочно: правило 0.6.7 — хранение метрическое и
    /// имя единицы в поле не пишется, а на показе делит ровно одно место,
    /// `Measure`. Сторож `UnitsDisciplineTests` поймал здесь первую редакцию,
    /// где поле звалось `distanceKm`.
    var distanceMetres: Double
    /// Название машины из гаража. `nil` — гараж пуст (состояние 3).
    var vehicleTitle: String?
    /// Последний маршрут в единичном пространстве. Пусто — поездок нет.
    var route: [CGPoint]

    /// Первый премиальный фон карточки машины и первый премиальный цвет линии.
    /// Названы здесь, чтобы «первый» у демонстрации и у витрин задачи 7 не
    /// разъехался.
    static let cardStyle: VehicleCardStyle = .gold
    static let lineStyle: RouteLineStyle = .amber
    static var lineColor: Color { lineStyle.color ?? AppTheme.accent }

    /// Нарисованный пример маршрута — для того, у кого поездок ещё нет.
    /// Подписывается примером на экране (`ProDemoPage.previewIsLabelledAsExample`).
    static let exampleRoute: [CGPoint] = [
        CGPoint(x: 0.06, y: 0.18), CGPoint(x: 0.20, y: 0.30),
        CGPoint(x: 0.30, y: 0.28), CGPoint(x: 0.42, y: 0.46),
        CGPoint(x: 0.55, y: 0.52), CGPoint(x: 0.64, y: 0.72),
        CGPoint(x: 0.78, y: 0.78), CGPoint(x: 0.94, y: 0.88)
    ]

    /// Две точки и дорога между ними — вписанная поездка.
    static let manualRoute: [CGPoint] = [
        CGPoint(x: 0.10, y: 0.22), CGPoint(x: 0.28, y: 0.34),
        CGPoint(x: 0.46, y: 0.36), CGPoint(x: 0.62, y: 0.56),
        CGPoint(x: 0.82, y: 0.74)
    ]

    /// Заглушка на случай, если снимок ещё не досчитался.
    ///
    /// Нужна одному месту — экрану «Ты в PRO»: покупка может пройти раньше,
    /// чем приедет маршрут из базы, и поздравление обязано показаться. Имя
    /// настоящие, остальное пусто: превью покажет профиль без чисел, а не
    /// нули. Аватар приходит параметром, а не берётся умолчанием: второе
    /// умолчание рядом с `SettingsManager.avatarEmoji` однажды разошлось бы
    /// с первым.
    static func placeholder(name: String, emoji: String) -> ProDemoData {
        ProDemoData(name: name,
                    avatarEmoji: emoji,
                    trips: 0,
                    distanceMetres: 0,
                    vehicleTitle: nil,
                    route: [])
    }

    /// Координаты трека → единичное пространство коробки превью.
    ///
    /// Чистая функция и под тестом, потому что ошибка здесь не падает, а
    /// РИСУЕТ: вырожденная рамка (все точки на одной широте) даёт деление на
    /// ноль, и маршрут либо исчезает, либо уезжает за край. Пропорция НЕ
    /// сохраняется нарочно — коробка 180 pt, и маршрут в ней должен быть
    /// виден, а не быть географически точным.
    static func unitPoints(from coordinates: [CLLocationCoordinate2D]) -> [CGPoint] {
        guard coordinates.count > 1 else { return [] }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        let spanLat = maxLat - minLat
        let spanLon = maxLon - minLon
        // Прямая дорога строго с запада на восток даёт нулевую широтную
        // рамку — такой маршрут кладётся посередине, а не делится на ноль.
        let x: (Double) -> Double = spanLon > 0 ? { ($0 - minLon) / spanLon } : { _ in 0.5 }
        let y: (Double) -> Double = spanLat > 0 ? { ($0 - minLat) / spanLat } : { _ in 0.5 }
        return coordinates.map { CGPoint(x: x($0.longitude), y: y($0.latitude)) }
    }
}

// MARK: - Сбор

extension ProDemoData {
    /// Собрать снимок — ОДНА дверь на два вызывающих: витрину и контекстное
    /// предложение.
    ///
    /// Половина работы обязана идти на главном актёре (`@Published` у
    /// `SettingsManager` и `AuthService`), половина — вне него
    /// (`fetchTripsForMap` поднимает превью всей библиотеки; на зрелой это
    /// десятки тысяч точек, то самое «App Hanging ≥ 2 с» 0.8.0). Разделить их
    /// правильно можно один раз, и здесь это сделано один раз.
    @MainActor
    static func current(lang: LanguageManager.Language) async -> ProDemoData {
        let name = currentName(lang: lang)
        let emoji = SettingsManager.shared.avatarEmoji
        let vehicle = currentVehicleTitle()
        return await Task.detached(priority: .userInitiated) {
            // Прямо у репозитория, а не через `TripManager`: тот не синглтон и
            // живёт у `MapViewModel`, до которого с витрины, открытой из
            // гаража или из настроек, не дотянуться.
            let repository = CoreDataTripRepository()
            let stats = repository.fetchTripStats()
            let route = repository.fetchTripsForMap().first?.previewCoordinates ?? []
            return ProDemoData(
                name: name,
                avatarEmoji: emoji,
                trips: stats.count,
                distanceMetres: stats.totalDistance,
                vehicleTitle: vehicle,
                route: unitPoints(from: route))
        }.value
    }

    /// Имя человека — то же, что в шапке «Я». Своего правила у платной части
    /// нет нарочно: превью обещает ЕГО профиль, и имя в обещании обязано
    /// совпадать с именем на экране, откуда он пришёл.
    @MainActor
    static func currentName(lang: LanguageManager.Language) -> String {
        let name = AuthService.shared.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? AppStrings.meGuestName(lang) : name
    }

    /// Как человек называет свою машину.
    ///
    /// Сначала имя, которое он дал сам, потом марка с моделью из каталога.
    /// `nil` — гараж пуст, и это состояние 3: карточка показывает силуэт с
    /// подписью, а не пустой прямоугольник. Берётся ВЕСЬ гараж, включая
    /// архивные: вопрос здесь «как это будет выглядеть у меня», а не «на что
    /// писать следующую поездку».
    @MainActor
    static func currentVehicleTitle() -> String? {
        guard let vehicle = SettingsManager.shared.vehicles.first else { return nil }
        let own = vehicle.name.trimmingCharacters(in: .whitespaces)
        if !own.isEmpty { return own }
        let catalogue = "\(vehicle.make) \(vehicle.model)"
            .trimmingCharacters(in: .whitespaces)
        return catalogue.isEmpty ? nil : catalogue
    }
}
