import SwiftUI

// MARK: - Units

enum DistanceUnit: String, CaseIterable {
    case km = "km"
    case miles = "miles"

    var label: String {
        switch self {
        case .km: return "km"
        case .miles: return "mi"
        }
    }

    var labelFull: (ru: String, en: String) {
        switch self {
        case .km: return ("Километры", "Kilometers")
        case .miles: return ("Мили", "Miles")
        }
    }
}

enum VolumeUnit: String, CaseIterable {
    case liters = "liters"
    case gallons = "gallons"

    var label: String {
        switch self {
        case .liters: return "L"
        case .gallons: return "gal"
        }
    }

    var labelFull: (ru: String, en: String) {
        switch self {
        case .liters: return ("Литры", "Liters")
        case .gallons: return ("Галлоны", "Gallons")
        }
    }

    var consumptionLabel: (ru: String, en: String) {
        switch self {
        case .liters: return ("л/100км", "L/100km")
        case .gallons: return ("mpg", "mpg")
        }
    }
}

enum FuelCurrency: String, CaseIterable {
    case rub = "₽"
    case usd = "$"
    case eur = "€"
    case gbp = "£"
    case uah = "₴"
    case kzt = "₸"
    case tryLira = "₺"
    case inr = "₹"
    case cny = "¥"
    case brl = "R$"

    var symbol: String { rawValue }

    static let storageKey = "fuelCurrency"
    static let defaultSymbol = "€"

    /// Current global fuel currency symbol from UserDefaults.
    static var current: String {
        UserDefaults.standard.string(forKey: storageKey) ?? defaultSymbol
    }
}

// MARK: - Driver Profile

enum DriverRank: String, CaseIterable {
    case novice        // 1-4
    case driver        // 5-9
    case traveler      // 10-14
    case explorer      // 15-19
    case navigator     // 20-24
    case trucker       // 25-29
    case legend        // 30-39
    case pioneer       // 40-49
    case nomad         // 50-59
    case conqueror     // 60-69
    case cartographer  // 70-79
    case odysseus      // 80-89
    case roadSpirit    // 90-99
    case eternal       // 100-110

    var levelRange: ClosedRange<Int> {
        switch self {
        case .novice:       return 1...4
        case .driver:       return 5...9
        case .traveler:     return 10...14
        case .explorer:     return 15...19
        case .navigator:    return 20...24
        case .trucker:      return 25...29
        case .legend:       return 30...39
        case .pioneer:      return 40...49
        case .nomad:        return 50...59
        case .conqueror:    return 60...69
        case .cartographer: return 70...79
        case .odysseus:     return 80...89
        case .roadSpirit:   return 90...99
        case .eternal:      return 100...110
        }
    }

    var icon: String {
        switch self {
        case .novice:       return "car.fill"
        case .driver:       return "steeringwheel"
        case .traveler:     return "compass.drawing"
        case .explorer:     return "map.fill"
        case .navigator:    return "helm"
        case .trucker:      return "star.fill"
        case .legend:       return "flame.fill"
        case .pioneer:      return "signpost.right.fill"
        case .nomad:        return "tent.fill"
        case .conqueror:    return "flag.2.crossed.fill"
        case .cartographer: return "map.circle.fill"
        case .odysseus:     return "sailboat.fill"
        case .roadSpirit:   return "sparkles"
        case .eternal:      return "infinity"
        }
    }

    /// Warm "heat ramp" — cool-grey at the start deepening to oxblood at the top,
    /// so a higher rank always reads as hotter/deeper. Matches the Figma v0.6 spec.
    var color: Color {
        switch self {
        case .novice:       return Color(red: 0.486, green: 0.510, blue: 0.557)
        case .driver:       return Color(red: 0.690, green: 0.475, blue: 0.235)
        case .traveler:     return Color(red: 0.808, green: 0.604, blue: 0.180)
        case .explorer:     return Color(red: 0.882, green: 0.627, blue: 0.090)
        case .navigator:    return Color(red: 0.933, green: 0.506, blue: 0.129)
        case .trucker:      return Color(red: 0.922, green: 0.353, blue: 0.118)
        case .legend:       return Color(red: 0.847, green: 0.243, blue: 0.082)
        case .pioneer:      return Color(red: 0.784, green: 0.180, blue: 0.106)
        case .nomad:        return Color(red: 0.706, green: 0.129, blue: 0.129)
        case .conqueror:    return Color(red: 0.612, green: 0.106, blue: 0.157)
        case .cartographer: return Color(red: 0.518, green: 0.102, blue: 0.196)
        case .odysseus:     return Color(red: 0.435, green: 0.086, blue: 0.184)
        case .roadSpirit:   return Color(red: 0.345, green: 0.075, blue: 0.157)
        case .eternal:      return Color(red: 0.259, green: 0.063, blue: 0.129)
        }
    }

    func titleRu() -> String {
        switch self {
        case .novice:       return "Новичок"
        case .driver:       return "Водитель"
        case .traveler:     return "Путешественник"
        case .explorer:     return "Исследователь"
        case .navigator:    return "Штурман"
        case .trucker:      return "Дальнобойщик"
        case .legend:       return "Легенда дорог"
        case .pioneer:      return "Первопроходец"
        case .nomad:        return "Кочевник"
        case .conqueror:    return "Покоритель дорог"
        case .cartographer: return "Хранитель карт"
        case .odysseus:     return "Одиссей"
        case .roadSpirit:   return "Дух странствий"
        case .eternal:      return "Вечный странник"
        }
    }

    func titleEn() -> String {
        switch self {
        case .novice:       return "Beginner"
        case .driver:       return "Driver"
        case .traveler:     return "Traveler"
        case .explorer:     return "Explorer"
        case .navigator:    return "Navigator"
        case .trucker:      return "Trucker"
        case .legend:       return "Road Legend"
        case .pioneer:      return "Trailblazer"
        case .nomad:        return "Nomad"
        case .conqueror:    return "Road Conqueror"
        case .cartographer: return "Cartographer"
        case .odysseus:     return "Odysseus"
        case .roadSpirit:   return "Spirit of Journeys"
        case .eternal:      return "Eternal Wanderer"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? titleRu() : titleEn()
    }

    static func from(level: Int) -> DriverRank {
        allCases.first { $0.levelRange.contains(level) } ?? .novice
    }
}

// MARK: - Level Thresholds (110 levels)

enum LevelSystem {
    static let maxLevel = 110

    /// XP to reach levels 1–30 — FROZEN. These match the original 30-level system
    /// so existing players (whose level is recomputed from stored XP) never drop.
    private static let baseThresholds: [Int] = [
        0, 50, 150, 300, 500, 800, 1_200, 1_700, 2_300, 3_000,
        4_000, 5_200, 6_600, 8_200, 10_000, 12_000, 14_500, 17_000, 19_500, 22_000,
        25_000, 28_500, 32_000, 35_500, 39_000, 43_000, 48_000, 53_000, 58_000, 63_000,
    ]

    /// XP needed to reach `level`. L1–30 use the frozen table above; L31–110 follow a
    /// steepening curve — the per-level increment grows by 600 XP each level, continuing
    /// smoothly from L30 (L31 +5 600 … L110 +52 400). Closed form, n = level − 30:
    /// threshold = 63 000 + 5 000·n + 300·n·(n + 1).
    /// Anchors: L40 ≈ 146k · L50 ≈ 289k · L70 ≈ 755k · L100 ≈ 1.90M · L110 ≈ 2.41M XP.
    static func xpForLevel(_ level: Int) -> Int {
        guard level >= 1 else { return 0 }
        if level <= 30 { return baseThresholds[level - 1] }
        let n = min(level, maxLevel) - 30
        return 63_000 + 5_000 * n + 300 * n * (n + 1)
    }

    static func level(for xp: Int) -> Int {
        var lvl = 1
        var l = 2
        while l <= maxLevel {
            if xp >= xpForLevel(l) { lvl = l } else { break }
            l += 1
        }
        return lvl
    }

    static func xpForNextLevel(_ level: Int) -> Int {
        guard level < maxLevel else { return xpForLevel(maxLevel) }
        return xpForLevel(level + 1)
    }

    static func progressToNextLevel(xp: Int, level: Int) -> Double {
        guard level < maxLevel else { return 1.0 }
        let currentThreshold = xpForLevel(level)
        let nextThreshold = xpForNextLevel(level)
        let range = nextThreshold - currentThreshold
        guard range > 0 else { return 1.0 }
        return Double(xp - currentThreshold) / Double(range)
    }
}

// MARK: - Vehicle Levels (10 levels)

enum VehicleLevelSystem {
    static let thresholds: [(level: Int, km: Double, titleRu: String, titleEn: String)] = [
        (1,  0,       "Новая",       "New"),
        (2,  100,     "Обкатка",     "Break-in"),
        (3,  500,     "Знакомая",    "Familiar"),
        (4,  1_000,   "Своя",        "Yours"),
        (5,  2_500,   "Напарник",    "Partner"),
        (6,  5_000,   "Ветеран",     "Veteran"),
        (7,  10_000,  "Боевой конь", "Warhorse"),
        (8,  25_000,  "Легенда",     "Legend"),
        (9,  50_000,  "Бессмертный", "Immortal"),
        (10, 100_000, "Одометр ∞",   "Odometer ∞"),
    ]

    static let maxLevel = 10

    static func level(for km: Double) -> Int {
        var lvl = 1
        for t in thresholds {
            if km >= t.km { lvl = t.level } else { break }
        }
        return lvl
    }

    static func kmForLevel(_ level: Int) -> Double {
        guard level >= 1, level <= maxLevel else { return 0 }
        return thresholds[level - 1].km
    }

    static func kmForNextLevel(_ level: Int) -> Double {
        guard level < maxLevel else { return thresholds[maxLevel - 1].km }
        return thresholds[level].km
    }

    static func progressToNext(km: Double, level: Int) -> Double {
        guard level < maxLevel else { return 1.0 }
        let current = kmForLevel(level)
        let next = kmForNextLevel(level)
        let range = next - current
        guard range > 0 else { return 1.0 }
        return min(1.0, (km - current) / range)
    }

    static func title(level: Int, lang: LanguageManager.Language) -> String {
        guard level >= 1, level <= maxLevel else { return "" }
        let t = thresholds[level - 1]
        return lang == .ru ? t.titleRu : t.titleEn
    }
}

// MARK: - Vehicle Stickers

enum VehicleSticker: String, CaseIterable, Codable {
    case flag100km       // First 100 km
    case route500km      // 500 km - first route line
    case bronzeFrame     // 1,000 km
    case silverFrame     // 2,500 km
    case goldenFrame     // 5,000 km
    case regionMap       // 10,000 km - region sticker
    case platinumFrame   // 25,000 km
    case mountain        // Trip with 1000m+ elevation gain
    case night           // Night trip (after 23:00)
    case winter          // Winter trip (Dec-Feb)

    var icon: String {
        switch self {
        case .flag100km:     return "flag.fill"
        case .route500km:    return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .bronzeFrame:   return "shield.fill"
        case .silverFrame:   return "shield.lefthalf.filled"
        case .goldenFrame:   return "crown.fill"
        case .regionMap:     return "map.fill"
        case .platinumFrame: return "star.circle.fill"
        case .mountain:      return "mountain.2.fill"
        case .night:         return "moon.stars.fill"
        case .winter:        return "snowflake"
        }
    }

    var color: Color {
        switch self {
        case .flag100km:     return AppTheme.accent
        case .route500km:    return AppTheme.blue
        case .bronzeFrame:   return Color(red: 205/255, green: 127/255, blue: 50/255)
        case .silverFrame:   return Color(red: 192/255, green: 192/255, blue: 192/255)
        case .goldenFrame:   return Color(red: 255/255, green: 215/255, blue: 0/255)
        case .regionMap:     return AppTheme.green
        case .platinumFrame: return Color(red: 180/255, green: 210/255, blue: 230/255)
        case .mountain:      return AppTheme.teal
        case .night:         return AppTheme.purple
        case .winter:        return AppTheme.blue
        }
    }

    func titleRu() -> String {
        switch self {
        case .flag100km:     return "Флажок старта"
        case .route500km:    return "Первый маршрут"
        case .bronzeFrame:   return "Бронзовая рамка"
        case .silverFrame:   return "Серебряная рамка"
        case .goldenFrame:   return "Золотая рамка"
        case .regionMap:     return "Карта регионов"
        case .platinumFrame: return "Платиновая рамка"
        case .mountain:      return "Горы"
        case .night:         return "Луна"
        case .winter:        return "Снежинка"
        }
    }

    func titleEn() -> String {
        switch self {
        case .flag100km:     return "Start Flag"
        case .route500km:    return "First Route"
        case .bronzeFrame:   return "Bronze Frame"
        case .silverFrame:   return "Silver Frame"
        case .goldenFrame:   return "Golden Frame"
        case .regionMap:     return "Region Map"
        case .platinumFrame: return "Platinum Frame"
        case .mountain:      return "Mountains"
        case .night:         return "Moon"
        case .winter:        return "Snowflake"
        }
    }
}

// MARK: - Road Rarity

enum RoadRarity: String, CaseIterable, Codable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var color: Color {
        switch self {
        case .common:    return .gray
        case .uncommon:  return AppTheme.green
        case .rare:      return AppTheme.blue
        case .epic:      return AppTheme.purple
        case .legendary: return AppTheme.accent
        }
    }

    func titleRu() -> String {
        switch self {
        case .common:    return "Обычная"
        case .uncommon:  return "Необычная"
        case .rare:      return "Редкая"
        case .epic:      return "Эпическая"
        case .legendary: return "Легендарная"
        }
    }

    func titleEn() -> String {
        switch self {
        case .common:    return "Common"
        case .uncommon:  return "Uncommon"
        case .rare:      return "Rare"
        case .epic:      return "Epic"
        case .legendary: return "Legendary"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? titleRu() : titleEn()
    }

    static func from(distanceKm: Double) -> RoadRarity {
        switch distanceKm {
        case ..<20:    return .common
        case 20..<100: return .uncommon
        case 100..<300: return .rare
        case 300..<1000: return .epic
        default:       return .legendary
        }
    }
}

// MARK: - Road Level

enum RoadLevel: Int, CaseIterable {
    case discovered = 1  // 1x
    case bronze = 2      // 3x
    case silver = 3      // 10x
    case gold = 4        // 25x
    case mastered = 5    // 50x

    var minDrives: Int {
        switch self {
        case .discovered: return 1
        case .bronze:     return 3
        case .silver:     return 10
        case .gold:       return 25
        case .mastered:   return 50
        }
    }

    var color: Color {
        switch self {
        case .discovered: return .gray
        case .bronze:     return Color(red: 205/255, green: 127/255, blue: 50/255)
        case .silver:     return Color(red: 192/255, green: 192/255, blue: 192/255)
        case .gold:       return Color(red: 255/255, green: 215/255, blue: 0/255)
        case .mastered:   return AppTheme.accent
        }
    }

    func titleRu() -> String {
        switch self {
        case .discovered: return "Открыта"
        case .bronze:     return "Бронза"
        case .silver:     return "Серебро"
        case .gold:       return "Золото"
        case .mastered:   return "Мастер"
        }
    }

    func titleEn() -> String {
        switch self {
        case .discovered: return "Discovered"
        case .bronze:     return "Bronze"
        case .silver:     return "Silver"
        case .gold:       return "Gold"
        case .mastered:   return "Mastered"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? titleRu() : titleEn()
    }

    static func from(timesDriven: Int) -> RoadLevel {
        if timesDriven >= 50 { return .mastered }
        if timesDriven >= 25 { return .gold }
        if timesDriven >= 10 { return .silver }
        if timesDriven >= 3 { return .bronze }
        return .discovered
    }

    var nextLevel: RoadLevel? {
        switch self {
        case .discovered: return .bronze
        case .bronze:     return .silver
        case .silver:     return .gold
        case .gold:       return .mastered
        case .mastered:   return nil
        }
    }
}

// MARK: - XP Breakdown

struct XPBreakdown {
    var base: Int = 0          // 1 XP per km
    var newRegionBonus: Int = 0
    var longTripBonus: Int = 0  // x2 for 200+ km
    var firstTripOfDay: Int = 0
    var regionDiscovery: Int = 0 // +50 per new region

    var total: Int {
        base + newRegionBonus + longTripBonus + firstTripOfDay + regionDiscovery
    }
}

// MARK: - Trip Completion Data

struct TripCompletionData {
    let xpEarned: Int
    let xpBreakdown: XPBreakdown
    let previousLevel: Int
    let newLevel: Int
    let previousXP: Int
    let newXP: Int
    let previousRank: DriverRank
    let newRank: DriverRank
    let vehicleOdometerBefore: Double
    let vehicleOdometerAfter: Double
    let vehicleLevelBefore: Int
    let vehicleLevelAfter: Int
    let newBadges: [Badge]
    let repeatedBadgeCounts: [String: Int]
    let newStickers: [VehicleSticker]
    let currentStreak: Int
    var roadCard: RoadCompletionInfo?

    var didLevelUp: Bool { newLevel > previousLevel }
    var didRankUp: Bool { newRank != previousRank }
    var didVehicleLevelUp: Bool { vehicleLevelAfter > vehicleLevelBefore }
}

struct RoadCompletionInfo {
    let name: String
    let rarity: RoadRarity
    let level: RoadLevel
    let timesDriven: Int
    let isNew: Bool
}

// MARK: - Road Card (Swift struct)

struct RoadCard: Identifiable {
    let id: UUID
    var name: String
    var rarity: RoadRarity
    var level: RoadLevel
    var timesDriven: Int
    var distanceKm: Double
    var geohashSequence: [String]
    var firstDriven: Date
    var lastDriven: Date

    var nextLevelDrives: Int? {
        guard let next = level.nextLevel else { return nil }
        return next.minDrives
    }

    var progressToNextLevel: Double {
        guard let next = level.nextLevel else { return 1.0 }
        let current = level.minDrives
        let target = next.minDrives
        let range = target - current
        guard range > 0 else { return 1.0 }
        return Double(timesDriven - current) / Double(range)
    }
}

// MARK: - Zone Status (Geohash territories)

enum ZoneStatus: String, CaseIterable {
    case undiscovered
    case discovered   // 1+ tile
    case explored     // 5%
    case mapped       // 25%
    case conquered    // 50%
    case mastered     // 80%

    static func from(percentage: Double) -> ZoneStatus {
        switch percentage {
        case ..<0.001:  return .undiscovered
        case ..<0.05:   return .discovered
        case ..<0.25:   return .explored
        case ..<0.50:   return .mapped
        case ..<0.80:   return .conquered
        default:        return .mastered
        }
    }

    var color: Color {
        switch self {
        case .undiscovered: return .gray.opacity(0.3)
        case .discovered:   return .gray
        case .explored:     return Color(red: 205/255, green: 127/255, blue: 50/255)
        case .mapped:       return Color(red: 192/255, green: 192/255, blue: 192/255)
        case .conquered:    return Color(red: 255/255, green: 215/255, blue: 0/255)
        case .mastered:     return AppTheme.accent
        }
    }

    func titleRu() -> String {
        switch self {
        case .undiscovered: return "Неизвестна"
        case .discovered:   return "Обнаружена"
        case .explored:     return "Исследована"
        case .mapped:       return "Нанесена"
        case .conquered:    return "Покорена"
        case .mastered:     return "Освоена"
        }
    }

    func titleEn() -> String {
        switch self {
        case .undiscovered: return "Undiscovered"
        case .discovered:   return "Discovered"
        case .explored:     return "Explored"
        case .mapped:       return "Mapped"
        case .conquered:    return "Conquered"
        case .mastered:     return "Mastered"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? titleRu() : titleEn()
    }
}

struct ZoneCard: Identifiable {
    let id: String // geohash4
    var name: String
    var tileCount: Int
    var totalTiles: Int // approximate
    var status: ZoneStatus
    var firstVisited: Date?
    var percentage: Double {
        guard totalTiles > 0 else { return 0 }
        return Double(tileCount) / Double(totalTiles)
    }
}

struct TerritoryCard: Identifiable {
    let id: String // geohash3
    var name: String
    var zones: [ZoneCard]
    var discoveredZoneCount: Int {
        zones.filter { $0.status != .undiscovered }.count
    }
}
