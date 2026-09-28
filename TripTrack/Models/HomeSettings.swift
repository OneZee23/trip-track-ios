import CoreLocation
import Foundation

/// Дом и приватная зона вокруг него (0.8.2, доска макета A7 «Вид карты»).
///
/// **Дом задаётся ТОЛЬКО руками** — решение владельца 27 сентября. Вывод из
/// истории ночёвок у нас есть (`JourneySuggester.home`), но он отвечает на
/// другой вопрос — «одна ли это история» — и ошибается в пользу работы; а
/// здесь цена ошибки не досада, а обрезанный не тот кусок чужого трека или
/// необрезанный свой двор. Поэтому точку ставит человек.
///
/// Живёт только на телефоне: ни в `SettingsSyncPayload`, ни в CoreData, ни на
/// сервере. Метка «видно только тебе» — это буквально так, а не подпись.
struct HomeSettings: Equatable, Codable {

    /// Радиус приватной зоны — ТРИ СТУПЕНИ, а не ползунок.
    ///
    /// Число обязано быть предсказуемым: его видно кругом на карте, и человек
    /// сверяет его глазами с собственным двором. Ползунок дал бы точность,
    /// которую не с чем сверить, а одно зашитое число кому-то мало, а кому-то
    /// полгорода. `rawValue` — метры, и он лежит в `UserDefaults`: менять
    /// нельзя.
    enum Radius: Int, CaseIterable, Codable {
        case yard = 200
        case block = 500
        case district = 1000
    }

    var latitude: Double?
    var longitude: Double?
    var radius: Radius = .block
    /// Показывать метку дома на СВОЁМ атласе.
    var showsOnMap = true
    /// Обрезать трек публичных поездок внутри зоны.
    ///
    /// По умолчанию ВЫКЛЮЧЕНО, и это не малодушие: включение переотправляет
    /// все уже опубликованные поездки обрезанными, а такую работу нельзя
    /// заводить самому — её заводит человек, нажав тумблер.
    var trimsPublicTracks = false

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isSet: Bool { coordinate != nil }

    /// Зона, которая РАБОТАЕТ прямо сейчас: точка есть и обрезка включена.
    ///
    /// Одно свойство вместо двух проверок по месту — иначе где-нибудь
    /// проверят только флаг и обрежут по нулевой координате в Гвинейском
    /// заливе.
    var activeZone: (centre: CLLocationCoordinate2D, radius: Double)? {
        guard trimsPublicTracks, let coordinate else { return nil }
        return (coordinate, Double(radius.rawValue))
    }

    // MARK: Хранение

    private static let defaultsKey = "home.settings"

    static func load(defaults: UserDefaults = .standard) -> HomeSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func wipe(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

extension Notification.Name {
    /// Дом или зона изменились так, что УЖЕ ОТПРАВЛЕННЫЕ публичные треки
    /// перестали быть верными: включили обрезку, передвинули точку, сменили
    /// радиус.
    ///
    /// Уведомлением, а не прямым вызовом: лист настройки ничего не знает про
    /// очередь синка, а переотправка ничего не знает про лист. Их связывает
    /// одна строка, и заводится она ровно там, где меняется зона.
    static let homePrivacyZoneChanged = Notification.Name("homePrivacyZoneChanged")
}
