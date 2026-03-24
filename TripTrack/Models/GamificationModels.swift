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
}

// MARK: - Driver Profile

enum DriverRank: String, CaseIterable {
    case novice      // 1-4
    case driver      // 5-9
    case traveler    // 10-14
    case explorer    // 15-19
    case navigator   // 20-24
    case trucker     // 25-29
    case legend      // 30

    var levelRange: ClosedRange<Int> {
        switch self {
        case .novice:    return 1...4
        case .driver:    return 5...9
        case .traveler:  return 10...14
        case .explorer:  return 15...19
        case .navigator: return 20...24
        case .trucker:   return 25...29
        case .legend:    return 30...30
        }
    }

    var icon: String {
        switch self {
        case .novice:    return "car.fill"
        case .driver:    return "steeringwheel"
        case .traveler:  return "compass.drawing"
        case .explorer:  return "map.fill"
        case .navigator: return "helm"
        case .trucker:   return "star.fill"
        case .legend:    return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .novice:    return .gray
        case .driver:    return Color(red: 205/255, green: 127/255, blue: 50/255)  // bronze
        case .traveler:  return Color(red: 192/255, green: 192/255, blue: 192/255) // silver
        case .explorer:  return Color(red: 255/255, green: 215/255, blue: 0/255)   // gold
        case .navigator: return Color(red: 180/255, green: 210/255, blue: 230/255) // platinum
        case .trucker:   return Color(red: 185/255, green: 242/255, blue: 255/255) // diamond
        case .legend:    return AppTheme.accent
        }
    }

    func titleRu() -> String {
        switch self {
        case .novice:    return "Новичок"
        case .driver:    return "Водитель"
        case .traveler:  return "Путешественник"
        case .explorer:  return "Исследователь"
        case .navigator: return "Штурман"
        case .trucker:   return "Дальнобойщик"
        case .legend:    return "Легенда дорог"
        }
    }

    func titleEn() -> String {
        switch self {
        case .novice:    return "Novice"
        case .driver:    return "Driver"
        case .traveler:  return "Traveler"
        case .explorer:  return "Explorer"
        case .navigator: return "Navigator"
        case .trucker:   return "Trucker"
        case .legend:    return "Road Legend"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? titleRu() : titleEn()
    }

    static func from(level: Int) -> DriverRank {
        allCases.first { $0.levelRange.contains(level) } ?? .novice
    }
}

// MARK: - Level Thresholds (30 levels)

enum LevelSystem {
    /// XP required to reach each level (index 0 = level 1, etc.)
    static let thresholds: [Int] = [
        0,       // Level 1:  0 XP
        50,      // Level 2:  50 XP
        150,     // Level 3:  150 XP
        300,     // Level 4:  300 XP
        500,     // Level 5:  500 XP
        800,     // Level 6:  800 XP
        1_200,   // Level 7:  1,200 XP
        1_700,   // Level 8:  1,700 XP
        2_300,   // Level 9:  2,300 XP
        3_000,   // Level 10: 3,000 XP
        4_000,   // Level 11: 4,000 XP
        5_200,   // Level 12: 5,200 XP
        6_600,   // Level 13: 6,600 XP
        8_200,   // Level 14: 8,200 XP
        10_000,  // Level 15: 10,000 XP
        12_000,  // Level 16: 12,000 XP
        14_500,  // Level 17: 14,500 XP
        17_000,  // Level 18: 17,000 XP
        19_500,  // Level 19: 19,500 XP
        22_000,  // Level 20: 22,000 XP
        25_000,  // Level 21: 25,000 XP
        28_500,  // Level 22: 28,500 XP
        32_000,  // Level 23: 32,000 XP
        35_500,  // Level 24: 35,500 XP
        39_000,  // Level 25: 39,000 XP
        43_000,  // Level 26: 43,000 XP
        48_000,  // Level 27: 48,000 XP
        53_000,  // Level 28: 53,000 XP
        58_000,  // Level 29: 58,000 XP
        63_000,  // Level 30: 63,000 XP
    ]

    static let maxLevel = 30

    static func level(for xp: Int) -> Int {
        var lvl = 1
        for i in 1..<thresholds.count {
            if xp >= thresholds[i] {
                lvl = i + 1
            } else {
                break
            }
        }
        return min(lvl, maxLevel)
    }

    static func xpForLevel(_ level: Int) -> Int {
        guard level >= 1, level <= maxLevel else { return 0 }
        return thresholds[level - 1]
    }

    static func xpForNextLevel(_ level: Int) -> Int {
        guard level < maxLevel else { return thresholds[maxLevel - 1] }
        return thresholds[level]
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
