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
    /// Главный снимок для списка гаража — presigned-ссылка на миниатюру.
    /// `nil` — либо фотографий нет, либо владелец их не открыл; различать эти
    /// два случая снаружи не нужно и не положено.
    let mainPhoto: String?
    /// Пусто и когда снимков нет, и когда владелец закрыл ось «фотографии»:
    /// сервер их в этом случае просто не присылает, и различать эти два случая
    /// зрителю не положено.
    let photos: [PublicVehiclePhoto]?
    /// Фон карточки — косметика «Плюса» (0.8.0). Сервер присылает её только
    /// у аккаунта с живой подпиской, поэтому клиент здесь ничего не
    /// перепроверяет: пришла строка — красим, не пришла — обычная карточка.
    /// Незнакомую разбирает `VehicleCardStyle.from`.
    var cardStyle: String? = nil

    var tripPhotos: [PublicGarageTripPhoto]? = nil
    var drive2Url: String? = nil
    var modTags: [String]? = nil
    var paintFinish: String? = nil
    var mods: [PublicVehicleMod]? = nil
    var catalogModelId: String? = nil
    var catalogGenerationId: String? = nil
    var catalogVariantId: String? = nil

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

extension PublicVehicle {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        avatarEmoji = try c.decode(String.self, forKey: .avatarEmoji)
        avatarStyle = (try? c.decodeIfPresent(String.self, forKey: .avatarStyle)) ?? nil
        vehicleType = (try? c.decodeIfPresent(String.self, forKey: .vehicleType)) ?? nil
        make = (try? c.decodeIfPresent(String.self, forKey: .make)) ?? nil
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? nil
        year = (try? c.decodeIfPresent(Int.self, forKey: .year)) ?? nil
        bodyType = (try? c.decodeIfPresent(String.self, forKey: .bodyType)) ?? nil
        level = try c.decode(Int.self, forKey: .level)
        odometerKm = try c.decode(Double.self, forKey: .odometerKm)
        about = (try? c.decodeIfPresent(String.self, forKey: .about)) ?? nil
        isArchived = (try? c.decodeIfPresent(Bool.self, forKey: .isArchived)) ?? nil
        soldAt = (try? c.decodeIfPresent(Date.self, forKey: .soldAt)) ?? nil
        plate = (try? c.decodeIfPresent(String.self, forKey: .plate)) ?? nil
        mapVisible = (try? c.decodeIfPresent(Bool.self, forKey: .mapVisible)) ?? nil
        photosVisible = (try? c.decodeIfPresent(Bool.self, forKey: .photosVisible)) ?? nil
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
        mainPhoto = (try? c.decodeIfPresent(String.self, forKey: .mainPhoto)) ?? nil
        photos = (try? c.decodeIfPresent([PublicVehiclePhoto].self, forKey: .photos)) ?? nil
        cardStyle = (try? c.decodeIfPresent(String.self, forKey: .cardStyle)) ?? nil
        tripPhotos = try? c.decodeIfPresent([PublicGarageTripPhoto].self, forKey: .tripPhotos)
        drive2Url = (try? c.decodeIfPresent(String.self, forKey: .drive2Url)) ?? nil
        modTags = (try? c.decodeIfPresent([String].self, forKey: .modTags)) ?? nil
        paintFinish = (try? c.decodeIfPresent(String.self, forKey: .paintFinish)) ?? nil
        mods = (try? c.decodeIfPresent([PublicVehicleMod].self, forKey: .mods)) ?? nil
        catalogModelId = (try? c.decodeIfPresent(String.self, forKey: .catalogModelId)) ?? nil
        catalogGenerationId = (try? c.decodeIfPresent(String.self, forKey: .catalogGenerationId)) ?? nil
        catalogVariantId = (try? c.decodeIfPresent(String.self, forKey: .catalogVariantId)) ?? nil
    }
}

struct PublicGarageTripPhoto: Codable, Hashable, Identifiable {
    let id: UUID
    let url: String?
    let thumbUrl: String?
    let timestamp: Date
}
