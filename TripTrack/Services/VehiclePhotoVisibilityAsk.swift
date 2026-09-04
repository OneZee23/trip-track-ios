import Foundation

/// Задавали ли уже вопрос «показывать фотографии этой машины другим».
///
/// Один раз на машину. Не на человека: у одной машины снимки могут быть
/// безобидными, у другой — двор с номером и подъездом, и решение это разное.
///
/// Правило то же, что у `VisibilityNoticeLatch`: **отсутствие записи означает
/// «не спрашивали»**. Ошибиться можно только в одну сторону — лишний вопрос
/// раздражает, пропущенный оставляет человека в уверенности, что снимки видны,
/// когда они не видны (или наоборот).
enum VehiclePhotoVisibilityAsk {
    private static let key = "com.triptrack.vehicle.photoVisibilityAsked"

    static func wasAsked(_ vehicleId: UUID,
                         _ defaults: UserDefaults = .standard) -> Bool {
        asked(defaults).contains(vehicleId.uuidString)
    }

    static func markAsked(_ vehicleId: UUID,
                          _ defaults: UserDefaults = .standard) {
        var ids = asked(defaults)
        ids.insert(vehicleId.uuidString)
        defaults.set(Array(ids), forKey: key)
    }

    /// Машину удалили — забываем и вопрос. Иначе новая машина с тем же
    /// идентификатором (восстановление из бэкапа, синк) не спросит ничего.
    static func forget(_ vehicleId: UUID,
                       _ defaults: UserDefaults = .standard) {
        var ids = asked(defaults)
        ids.remove(vehicleId.uuidString)
        defaults.set(Array(ids), forKey: key)
    }

    private static func asked(_ defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
