import Foundation
import CoreLocation
import CryptoKit

// ВРЕМЕННЫЙ ФАЙЛ. Его пишет задача 2 волны 2 («бандл загадок, скрипт,
// каталоги»), и при слиянии веток контроллер этот файл УДАЛЯЕТ целиком.
//
// Здесь лежат ровно те типы, которые задача 3 (матчеры) потребляет, слово в
// слово по блоку «Task 2 → Interfaces (Produces)» плана
// `docs/superpowers/plans/2026-09-16-070-wave2-discoveries.md`. Ничего своего
// в этот файл добавлять нельзя: всё, что тут появится сверх блока, пропадёт
// вместе с ним. Протоколы каталогов (`RiddleCatalog`, `SecretCatalog`) сюда
// НЕ выписаны нарочно — матчеры про каталоги не знают, им приходят готовые
// списки.

/// Тип автоматической загадки.
enum RiddleType: String, Codable, CaseIterable {
    case pass, lighthouse, border, ferry, dam, bridge
    case viewpoint, observatory, seaRoad, extreme, centre, tripoint

    /// Насколько близко надо проехать, чтобы загадка считалась решённой.
    var reach: Double {
        switch self {
        case .pass, .border, .ferry, .dam, .bridge, .seaRoad: return 300
        case .lighthouse, .viewpoint, .observatory: return 600
        case .extreme, .centre, .tripoint: return 1000
        }
    }

    var symbol: SealSymbol {
        switch self {
        case .pass: return .pass
        case .lighthouse: return .lighthouse
        case .border: return .border
        case .ferry: return .ferry
        case .dam: return .dam
        case .bridge: return .bridge
        case .viewpoint: return .viewpoint
        case .observatory: return .observatory
        case .seaRoad: return .seaRoad
        case .extreme: return .extreme
        case .centre: return .centre
        case .tripoint: return .tripoint
        }
    }
}

/// Загадка из бандла: открытые данные, поэтому лежит открытым текстом.
struct Riddle: Identifiable, Codable, Equatable {
    /// `"<type>:<geohash7>"`.
    let id: String
    let type: RiddleType
    let coordinate: CLLocationCoordinate2D
    /// Имя объекта (транслитерация как в атласе) — для карточки после решения.
    let name: String
    /// ISO 3166-2 из атласа; `nil`, если точка вне атласа.
    let regionId: String?

    init(id: String, type: RiddleType, coordinate: CLLocationCoordinate2D, name: String, regionId: String? = nil) {
        self.id = id
        self.type = type
        self.coordinate = coordinate
        self.name = name
        self.regionId = regionId
    }

    static func == (lhs: Riddle, rhs: Riddle) -> Bool {
        lhs.id == rhs.id
            && lhs.type == rhs.type
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.name == rhs.name
            && lhs.regionId == rhs.regionId
    }

    private enum CodingKeys: String, CodingKey {
        case id, t, c, n, r
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pair = try container.decode([Double].self, forKey: .c)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            type: try container.decode(RiddleType.self, forKey: .t),
            coordinate: CLLocationCoordinate2D(latitude: pair.first ?? 0, longitude: pair.count > 1 ? pair[1] : 0),
            name: try container.decode(String.self, forKey: .n),
            regionId: try container.decodeIfPresent(String.self, forKey: .r)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .t)
        try container.encode([coordinate.latitude, coordinate.longitude], forKey: .c)
        try container.encode(name, forKey: .n)
        try container.encodeIfPresent(regionId, forKey: .r)
    }
}

/// Авторский секрет: в бандле лежат только усечённые хеши ячеек, ни координат,
/// ни названия.
struct SecretRecord: Codable, Equatable {
    let id: String
    let hashes: [UInt32]
    let reach: Double
    let symbol: SealSymbol
    /// Площадной секрет: достаточно попасть в любую его ячейку, `reach` не
    /// проверяется.
    let polygon: Bool

    init(id: String, hashes: [UInt32], reach: Double, symbol: SealSymbol, polygon: Bool = false) {
        self.id = id
        self.hashes = hashes
        self.reach = reach
        self.symbol = symbol
        self.polygon = polygon
    }
}

/// Усечение `SHA-256(salt ‖ geohash7)` до 32 бит.
enum SecretHash {
    /// Первые 4 байта дайджеста, big-endian.
    static func truncated(salt: String, geohash7: String) -> UInt32 {
        var data = Data(salt.utf8)
        data.append(contentsOf: Array(geohash7.utf8))
        let digest = Array(SHA256.hash(data: data))
        return (UInt32(digest[0]) << 24) | (UInt32(digest[1]) << 16) | (UInt32(digest[2]) << 8) | UInt32(digest[3])
    }
}
