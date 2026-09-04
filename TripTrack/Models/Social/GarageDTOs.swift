import Foundation

/// Чужой гараж и чужая машина (0.6.4).
///
/// Отдельные типы, а не переиспользование `Vehicle`: у локальной машины есть
/// то, чего чужому знать не положено (расход, цена топлива, ручной пробег), и
/// декодировать чужой ответ в неё значило бы завести поля, которые всегда
/// пустые, и однажды случайно их показать.
///
/// Всё, что может быть скрыто, приходит опциональным. `nil` тут значит «этого
/// вам не отдали», а не «этого нет» — и экран обязан различать: скрытое
/// исчезает целиком, без плашки «скрыто».
struct PublicVehicle: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let avatarEmoji: String
    let avatarStyle: String?
    let vehicleType: String?
    let make: String?
    let model: String?
    let year: Int?
    let bodyType: String?
    let level: Int
    let odometerKm: Double
    let about: String?
    let isArchived: Bool?
    let soldAt: Date?
    /// `nil` — владелец не открыл номер. По номеру находят имя и адрес,
    /// поэтому сервер его в таком случае просто не присылает.
    let plate: String?
    /// Что зритель имеет право открыть дальше. Клиент по ним решает, рисовать
    /// ли карту и фотографии, а не гадает по пустому ответу.
    let mapVisible: Bool?
    let photosVisible: Bool?
    let createdAt: Date?
    /// Пусто и когда снимков нет, и когда владелец закрыл ось «фотографии»:
    /// сервер их в этом случае просто не присылает, и различать эти два случая
    /// зрителю не положено.
    let photos: [PublicVehiclePhoto]?

    /// «Toyota Land Cruiser 200 · 2014 · внедорожник» — подпись под именем.
    /// `nil`, когда паспорт не заполнен: подпись из одной точки хуже её
    /// отсутствия.
    func modelLine(_ l: LanguageManager.Language) -> String? {
        var parts: [String] = []
        let makeModel = [make ?? "", model ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        if !makeModel.isEmpty { parts.append(makeModel) }
        if let year, year > 0 { parts.append(String(year)) }
        if let bodyType, !bodyType.isEmpty {
            parts.append(AppStrings.avatarStyleName(l, style: bodyType).lowercased(l))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var isSold: Bool { soldAt != nil }
}

/// Снимок чужой машины: ссылки уже подписанные и живут около часа, поэтому
/// кэшировать их дольше экрана бессмысленно.
struct PublicVehiclePhoto: Codable, Identifiable, Hashable {
    let id: UUID
    let url: String?
    let thumbUrl: String?
    let isMain: Bool

    /// Крупная, если доехала; иначе миниатюра — лучше мелко, чем пусто.
    var best: URL? { URL(string: url ?? thumbUrl ?? "") }
    var thumb: URL? { URL(string: thumbUrl ?? url ?? "") }
}

struct PublicGarageResponse: Codable {
    let vehicles: [PublicVehicle]
}
