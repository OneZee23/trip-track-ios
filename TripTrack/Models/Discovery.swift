import Foundation
import CoreLocation
import CryptoKit

/// Что именно нашлось на треке.
///
/// `rawValue` — КОЛОНКА в базе (`DiscoveryEntity.kind`) и половина ключа, из
/// которого выводится `id` находки. Менять нельзя никогда: переименование
/// сделает каждую уже поставленную печать чужой, а найденное заново —
/// дубликатом рядом со старым.
enum DiscoveryKind: String, Codable {
    /// Авторский секрет из бандла: место, о котором знает автор, а человек
    /// узнаёт, только проехав мимо.
    case secret
    /// Автоматическая загадка по открытым данным: маяк, перевал, мост.
    case riddle
    /// Веха собственной географии: первый регион, самая восточная точка.
    case milestone
}

/// Символ на медальоне печати.
///
/// `rawValue` — колонка в базе (`DiscoveryEntity.symbol`) и поле на проводе:
/// менять нельзя, у уже найденного символ лежит строкой. Семнадцать первых
/// значений — ещё и имена SF-символов: ими печать рисовалась до волны 5, и
/// сегодня они остались ЗАПАСНЫМ вариантом, если гравюры не оказалось в
/// бандле. `komsomolsky` добавлен в 0.7.0 аддитивно (`"seal.komsomolsky"` —
/// имени SF с такой строкой не существует, и это нормально: у него есть
/// гравюра).
///
/// Рисует символ `SealPainter` по `assetName`, а не по `rawValue`: имя набора
/// гравюр обязано быть стабильным именем кейса, а не строкой контракта с
/// сервером, в которой стоят точки.
enum SealSymbol: String, Codable, CaseIterable {
    case pass = "mountain.2"
    case lighthouse = "light.beacon.max"
    case border = "flag.2.crossed"
    case ferry = "ferry"
    case dam = "water.waves"
    case bridge = "road.lanes"
    case viewpoint = "binoculars"
    case observatory = "telescope"
    case seaRoad = "water.waves.and.arrow.down"
    case extreme = "arrow.up.left.and.arrow.down.right"
    case centre = "scope"
    case tripoint = "triangle"
    case region = "map"
    case altitude = "mountain.2.fill"
    case night = "moon.stars"
    case country = "globe"
    case generic = "seal"
    /// Первый авторский секрет — «Знак Комсомольского» (спека §6). Гравюра
    /// своя; `rawValue` аддитивен и с сервером согласован.
    case komsomolsky = "seal.komsomolsky"

    /// Имя набора гравюр в `Assets.xcassets`.
    var assetName: String { "seal_" + caseName }

    /// Имя кейса — руками, а не рефлексией: `switch` исчерпывающий нарочно,
    /// поэтому восемнадцатый символ не соберётся, пока ему не нарисовали
    /// гравюру и не назвали её.
    private var caseName: String {
        switch self {
        case .pass:        return "pass"
        case .lighthouse:  return "lighthouse"
        case .border:      return "border"
        case .ferry:       return "ferry"
        case .dam:         return "dam"
        case .bridge:      return "bridge"
        case .viewpoint:   return "viewpoint"
        case .observatory: return "observatory"
        case .seaRoad:     return "seaRoad"
        case .extreme:     return "extreme"
        case .centre:      return "centre"
        case .tripoint:    return "tripoint"
        case .region:      return "region"
        case .altitude:    return "altitude"
        case .night:       return "night"
        case .country:     return "country"
        case .generic:     return "generic"
        case .komsomolsky: return "komsomolsky"
        }
    }
}

/// Веха собственной географии.
///
/// `rawValue` — первая часть ключа находки (`"<milestone>:<regionId|iso|yyyy-MM-dd>"`),
/// то есть он входит в `id`. Менять нельзя: после переименования уже
/// отмеченная веха нашлась бы второй раз.
enum Milestone: String, Codable, CaseIterable {
    case firstRegion
    case easternmost
    case westernmost
    case northernmost
    case southernmost
    case above2000
    case belowSea
    case threeRegionsDay
    case countryBorder
    case nightPass
}

/// Находка — то, что телефон нашёл на записанном треке ПОСЛЕ финиша.
///
/// Секрет, загадка или веха: печать на «Атласе», строка на экране итогов.
/// Живёт только на телефоне (сервер — волна 3), поэтому `id` обязан быть
/// функцией от содержимого, а не случайным: два телефона одного человека,
/// независимо разобрав один и тот же трек, обязаны поставить ОДНУ печать, а
/// не две. Тот же приём, что у `Place.id(forCell:)`.
struct Discovery: Identifiable, Equatable, Codable {
    /// UUID v5 от `(kind, key)`. Выводится всегда — см. `id(kind:key:)`.
    let id: UUID
    let kind: DiscoveryKind
    /// Что именно нашлось: `secretId` | `riddleId` | `"<milestone>:<regionId|iso|yyyy-MM-dd>"`.
    let key: String
    /// Поездка, на треке которой находка случилась ПЕРВЫЙ раз.
    let tripId: UUID
    let coordinate: CLLocationCoordinate2D
    let foundAt: Date
    let symbol: SealSymbol
    /// Загадка — имя объекта из бандла; веха — `nil` (печатается по ключу);
    /// секрет — `nil` до раскрытия (в каталоге лежат только хэши, без названий).
    let title: String?
    /// История секрета. Приходит ТОЛЬКО с `/secrets/reveal` — в каталоге её
    /// нет нарочно: текст, лежащий на телефоне до находки, и есть вскрытый
    /// секрет.
    let story: String?
    /// Подтверждена ли находка сервером: трек поездки лежит на сервере и
    /// проходит через `reach`. Без Cloud Sync остаётся `false` навсегда — и
    /// это не поломка, а отсутствие того, чем подтверждать.
    let verified: Bool
    /// Сколько человек нашли это же. `nil` — «не спрашивали»: без Cloud Sync
    /// счётчика не существует, и показывать вместо него ноль нельзя.
    let finders: Int?
    /// Имя первооткрывателя — только если его профиль публичный; иначе `nil`
    /// при непустом `firstFinderAt`.
    let firstFinderName: String?
    let firstFinderAt: Date?
    /// `few | tens | hundreds | many` — СТРОКОЙ, а не enum: редкость считает
    /// сервер, и незнакомое слово обязано доехать до базы целым, а не
    /// обнулиться при разборе. Показывающий экран сам решает, что делать с
    /// неизвестным ему значением.
    let rarity: String?

    init(
        kind: DiscoveryKind,
        key: String,
        tripId: UUID,
        coordinate: CLLocationCoordinate2D,
        foundAt: Date,
        symbol: SealSymbol,
        title: String? = nil,
        story: String? = nil,
        verified: Bool = false,
        finders: Int? = nil,
        firstFinderName: String? = nil,
        firstFinderAt: Date? = nil,
        rarity: String? = nil
    ) {
        self.id = Discovery.id(kind: kind, key: key)
        self.kind = kind
        self.key = key
        self.tripId = tripId
        self.coordinate = coordinate
        self.foundAt = foundAt
        self.symbol = symbol
        self.title = title
        self.story = story
        self.verified = verified
        self.finders = finders
        self.firstFinderName = firstFinderName
        self.firstFinderAt = firstFinderAt
        self.rarity = rarity
    }

    /// Пространство имён находок TripTrack. НАВСЕГДА: от него зависят id на
    /// всех телефонах, и смена превратит каждую найденную печать в чужую.
    static let namespace = UUID(uuidString: "5a3c8b2e-7f10-4c6e-9d21-0e6b3a9f4c11")!

    /// UUID v5 (RFC 4122 §4.3) от `"<kind>:<key>"`: SHA-1 над байтами
    /// пространства имён и UTF-8 строки, биты версии и варианта — как в RFC.
    /// Совпадает с `uuid.uuid5` в Python, чем и заморожены векторы
    /// `DiscoveryIdentityTests`.
    ///
    /// Вид входит в строку, а не только ключ: `secret` и `riddle` живут в
    /// разных каталогах и однажды поделят одно имя.
    static func id(kind: DiscoveryKind, key: String) -> UUID {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array("\(kind.rawValue):\(key)".utf8))
        var b = Array(Insecure.SHA1.hash(data: data))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    // MARK: - Equatable

    /// Руками: `CLLocationCoordinate2D` не `Equatable`.
    static func == (lhs: Discovery, rhs: Discovery) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.key == rhs.key
            && lhs.tripId == rhs.tripId
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.foundAt == rhs.foundAt
            && lhs.symbol == rhs.symbol
            && lhs.title == rhs.title
            && lhs.story == rhs.story
            && lhs.verified == rhs.verified
            && lhs.finders == rhs.finders
            && lhs.firstFinderName == rhs.firstFinderName
            && lhs.firstFinderAt == rhs.firstFinderAt
            && lhs.rarity == rhs.rarity
    }

    // MARK: - Codable

    /// Руками по той же причине: координата не `Codable`, и на проводе она
    /// двумя числами.
    ///
    /// `id` печатается, но при разборе ИГНОРИРУЕТСЯ и выводится заново из
    /// `kind`/`key`: чужой или испорченный id разъехался бы с ключом, а
    /// выведенный сходится на любом телефоне по определению.
    private enum CodingKeys: String, CodingKey {
        case id, kind, key, tripId, latitude, longitude, foundAt, symbol, title, verified
        case story, finders, firstFinderName, firstFinderAt, rarity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decode(DiscoveryKind.self, forKey: .kind),
            key: try c.decode(String.self, forKey: .key),
            tripId: try c.decode(UUID.self, forKey: .tripId),
            coordinate: CLLocationCoordinate2D(
                latitude: try c.decode(Double.self, forKey: .latitude),
                longitude: try c.decode(Double.self, forKey: .longitude)
            ),
            foundAt: try c.decode(Date.self, forKey: .foundAt),
            symbol: try c.decode(SealSymbol.self, forKey: .symbol),
            title: try c.decodeIfPresent(String.self, forKey: .title),
            story: try c.decodeIfPresent(String.self, forKey: .story),
            verified: try c.decodeIfPresent(Bool.self, forKey: .verified) ?? false,
            finders: try c.decodeIfPresent(Int.self, forKey: .finders),
            firstFinderName: try c.decodeIfPresent(String.self, forKey: .firstFinderName),
            firstFinderAt: try c.decodeIfPresent(Date.self, forKey: .firstFinderAt),
            rarity: try c.decodeIfPresent(String.self, forKey: .rarity)
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(key, forKey: .key)
        try c.encode(tripId, forKey: .tripId)
        try c.encode(coordinate.latitude, forKey: .latitude)
        try c.encode(coordinate.longitude, forKey: .longitude)
        try c.encode(foundAt, forKey: .foundAt)
        try c.encode(symbol, forKey: .symbol)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(story, forKey: .story)
        try c.encode(verified, forKey: .verified)
        try c.encodeIfPresent(finders, forKey: .finders)
        try c.encodeIfPresent(firstFinderName, forKey: .firstFinderName)
        try c.encodeIfPresent(firstFinderAt, forKey: .firstFinderAt)
        try c.encodeIfPresent(rarity, forKey: .rarity)
    }
}
