import Foundation
import CoreLocation

/// Тип автоматической загадки.
///
/// `rawValue` — колонка в `Riddles.json` и половина `Riddle.id`, менять
/// нельзя: у человека на телефоне уже лежат решённые находки с этим ключом.
///
/// Загадки собирает `Tools/build_secrets.py` из открытых данных (OSM ODbL,
/// Wikidata CC0) и кладёт в бандл открытым текстом — в отличие от авторских
/// секретов, от которых в бандле только хеш ячейки.
enum RiddleType: String, Codable, CaseIterable {
    case pass, lighthouse, border, ferry, dam, bridge, viewpoint, observatory,
         seaRoad, extreme, centre, tripoint

    /// Насколько близко надо проехать, чтобы загадка засчиталась.
    ///
    /// Три ступени, и они про ТОЧНОСТЬ ТОЧКИ, а не про щедрость: перевал и
    /// мост — это сама дорога, мимо них не проехать (300 м); маяк и смотровая
    /// стоят в стороне от проезда (600 м); крайняя точка страны, центр и
    /// трипойнт — координата условная, её ставили по карте (1000 м).
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

/// Одна загадка бандла: точка, до которой можно доехать.
///
/// Имя (`name`) — это ДАННЫЕ, а не строка интерфейса: оно приходит из OSM
/// `name:en` или транслитерируется тем же правилом, что имена городов в
/// атласе, и показывается только ПОСЛЕ решения. Текст самой загадки живёт в
/// `AppStrings.riddleLine(_:type:)` и переведён на все тринадцать языков.
struct Riddle: Identifiable, Codable, Equatable {
    let id: String                          // "<type>:<geohash7>"
    let type: RiddleType
    let coordinate: CLLocationCoordinate2D
    let name: String
    let regionId: String?                   // ISO 3166-2 из атласа, может не быть

    /// Ключи — те же короткие имена, что пишет скрипт: бандл с 12 типами
    /// точек должен влезать в сотни килобайт, а не в мегабайты.
    private enum CodingKeys: String, CodingKey {
        case id, type = "t", coordinate = "c", name = "n", regionId = "r"
    }

    init(id: String, type: RiddleType, coordinate: CLLocationCoordinate2D,
         name: String, regionId: String?) {
        self.id = id
        self.type = type
        self.coordinate = coordinate
        self.name = name
        self.regionId = regionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(RiddleType.self, forKey: .type)
        let pair = try container.decode([Double].self, forKey: .coordinate)
        guard pair.count == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .coordinate, in: container,
                debugDescription: "coordinate must be [lat, lon]")
        }
        coordinate = CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        name = (try container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        regionId = try container.decodeIfPresent(String.self, forKey: .regionId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode([coordinate.latitude, coordinate.longitude], forKey: .coordinate)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(regionId, forKey: .regionId)
    }

    static func == (lhs: Riddle, rhs: Riddle) -> Bool {
        lhs.id == rhs.id && lhs.type == rhs.type && lhs.name == rhs.name
            && lhs.regionId == rhs.regionId
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Круг на карте вместо булавки: точку загадки человеку не показывают.
struct RiddleHint: Equatable {
    let riddle: Riddle
    let circleCenter: CLLocationCoordinate2D
    let radiusMeters: Double

    static func == (lhs: RiddleHint, rhs: RiddleHint) -> Bool {
        lhs.riddle == rhs.riddle && lhs.radiusMeters == rhs.radiusMeters
            && lhs.circleCenter.latitude == rhs.circleCenter.latitude
            && lhs.circleCenter.longitude == rhs.circleCenter.longitude
    }
}

/// Откуда берутся загадки. Сегодня — бандл; волна 3 добавит серверную
/// реализацию за тем же протоколом, и ни один матчер об этом не узнает.
protocol RiddleCatalog {
    func all() -> [Riddle]
    /// Загадки, до которых поездка могла дотянуться: `cells` — geohash-5
    /// ячейки трека. Предфильтр тот же, что у мест (`PlaceMatcher.isCandidate`):
    /// своя ячейка плюс восемь соседних, потому что точка у края ячейки
    /// ближе к соседней, чем к своему центру.
    func candidates(near cells: Set<String>) -> [Riddle]
}

/// `Riddles.json` из бандла приложения.
///
/// Файл собран `Tools/build_secrets.py` из OSM (ODbL) и Wikidata (CC0); сам
/// извлечённый набор — производная база, а не «произведение», поэтому он и
/// скрипт публикуются под ODbL отдельно от кода приложения.
final class BundleRiddleCatalog: RiddleCatalog {
    static let shared = BundleRiddleCatalog()

    private let riddles: [Riddle]
    /// geohash-5 ячейка → индексы загадок в ней.
    private let byCell: [String: [Int]]

    /// `url` опционален, а не `!`, по той же причине, по которой
    /// `RegionAtlas` перебирает бандлы: под `xcodebuild test` код приложения
    /// грузится из дилиба, чей бандл — не `Bundle.main`. Нет файла — пустой
    /// каталог и строка в логе; карта без загадок хуже карты с ними, но
    /// падение приложения хуже обеих.
    init(url: URL? = BundleRiddleCatalog.bundledURL()) {
        guard let url else {
            print("[RiddleCatalog] Riddles.json not found in any bundle")
            riddles = []
            byCell = [:]
            return
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            print("[RiddleCatalog] cannot read \(url.lastPathComponent)")
            riddles = []
            byCell = [:]
            return
        }
        let parsed: [Riddle]
        do {
            parsed = try JSONDecoder().decode(Payload.self, from: data).riddles
        } catch {
            print("[RiddleCatalog] decode failed: \(error)")
            riddles = []
            byCell = [:]
            return
        }
        riddles = parsed
        var index: [String: [Int]] = [:]
        for (offset, riddle) in parsed.enumerated() {
            let cell = GeohashEncoder.encode(latitude: riddle.coordinate.latitude,
                                             longitude: riddle.coordinate.longitude,
                                             precision: 5)
            index[cell, default: []].append(offset)
        }
        byCell = index
    }

    func all() -> [Riddle] { riddles }

    func candidates(near cells: Set<String>) -> [Riddle] {
        guard !cells.isEmpty, !riddles.isEmpty else { return [] }
        var wanted = cells
        for cell in cells {
            for neighbour in GeohashEncoder.neighbors(of: cell) { wanted.insert(neighbour) }
        }
        var offsets = Set<Int>()
        for cell in wanted {
            guard let bucket = byCell[cell] else { continue }
            offsets.formUnion(bucket)
        }
        return offsets.sorted().map { riddles[$0] }
    }

    static func bundledURL() -> URL? {
        var candidates = [Bundle(for: BundleRiddleCatalog.self), Bundle.main]
        candidates.append(contentsOf: Bundle.allBundles)
        candidates.append(contentsOf: Bundle.allFrameworks)
        for bundle in candidates {
            if let url = bundle.url(forResource: "Riddles", withExtension: "json") {
                return url
            }
        }
        return nil
    }

    private struct Payload: Decodable {
        let riddles: [Riddle]
    }
}
