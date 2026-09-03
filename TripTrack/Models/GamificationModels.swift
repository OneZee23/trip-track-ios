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

    func labelFull(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .km: return AppStrings.tr(lang, "unitKilometersFull", ru: "Километры", en: "Kilometers")
        case .miles: return AppStrings.tr(lang, "unitMilesFull", ru: "Мили", en: "Miles")
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

    func labelFull(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .liters: return AppStrings.tr(lang, "unitLitersFull", ru: "Литры", en: "Liters")
        case .gallons: return AppStrings.tr(lang, "unitGallonsFull", ru: "Галлоны", en: "Gallons")
        }
    }

    var consumptionLabel: (ru: String, en: String) {
        switch self {
        case .liters: return ("л/100км", "L/100km")
        case .gallons: return ("mpg", "mpg")
        }
    }
}

/// Ordered as the picker shows them: the currencies this app's people actually
/// refuel in first, the rest after. Raw value is the symbol because that is
/// what gets persisted and printed next to a price.
enum FuelCurrency: String, CaseIterable {
    case rub = "₽"
    case usd = "$"
    case eur = "€"
    case kzt = "₸"
    case gel = "₾"
    case tryLira = "₺"
    case cny = "¥"
    case byn = "Br"
    case gbp = "£"
    case uah = "₴"
    case inr = "₹"
    case brl = "R$"

    var symbol: String { rawValue }

    /// ISO code, shown greyed next to the name.
    var code: String {
        switch self {
        case .rub:     return "RUB"
        case .usd:     return "USD"
        case .eur:     return "EUR"
        case .kzt:     return "KZT"
        case .gel:     return "GEL"
        case .tryLira: return "TRY"
        case .cny:     return "CNY"
        case .byn:     return "BYN"
        case .gbp:     return "GBP"
        case .uah:     return "UAH"
        case .inr:     return "INR"
        case .brl:     return "BRL"
        }
    }

    /// Foundation already carries every currency's name in every language we
    /// ship, so this is one line instead of twelve names × seven languages
    /// hand-written into the translation tables — and it stays right when a
    /// currency is added. The ISO code is the fallback if a locale has no name.
    func name(_ lang: LanguageManager.Language) -> String {
        lang.locale.localizedString(forCurrencyCode: code) ?? code
    }

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
        case .trucker:      return Color(red: 0.761, green: 0.271, blue: 0.169)
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
        AppStrings.tr(lang, "driverRank.\(self)", ru: titleRu(), en: titleEn())
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

// MARK: - Vehicle Levels

/// A vehicle's level is its mileage, counted.
///
/// It replaces a ten-rung ladder with named rungs ("Новая" … "Одометр ∞"). The
/// names were the problem: they promised a story the number could not keep, and
/// the tenth rung was a ceiling — a car that had earned "Одометр ∞" could never
/// earn anything again. There is no ceiling here, and no titles. The level is
/// the odometer read out loud, nothing more: it unlocks nothing, gates nothing,
/// and exists so a car has a record of its own.
///
/// Each step costs more than the last, in the simplest possible way: going from
/// level N to N+1 takes N × 100 km. First level is a hundred kilometres, the
/// tenth is a thousand, and the curve keeps opening without ever stopping.
enum VehicleLevelSystem {
    /// The first step, in km. Every later step is a multiple of it.
    static let stepKm: Double = 100

    /// Total distance needed to *be* at `level`.
    ///
    /// Summing the steps 1…L-1 gives 100 · (L-1)L/2, i.e. 50·L·(L-1):
    /// level 2 at 100 km, level 11 at 5 500 km, level 28 at 37 800 km.
    static func kmForLevel(_ level: Int) -> Double {
        guard level > 1 else { return 0 }
        let l = Double(level)
        return stepKm / 2 * l * (l - 1)
    }

    static func kmForNextLevel(_ level: Int) -> Double {
        kmForLevel(max(1, level) + 1)
    }

    /// Inverse of `kmForLevel` — the largest level whose threshold `km` clears.
    ///
    /// Solved directly rather than by looping, since there is no upper bound to
    /// loop to. The closed form can land a hair under an exact threshold in
    /// binary floating point (38 420 km is fine; 100 km is the kind of round
    /// number that bites), so the result is nudged against the thresholds it
    /// claims to sit between.
    static func level(for km: Double) -> Int {
        guard km > 0 else { return 1 }
        let estimate = (1 + (1 + 8 * km / stepKm).squareRoot()) / 2
        var level = max(1, Int(estimate.rounded(.down)))
        while kmForLevel(level + 1) <= km { level += 1 }
        while level > 1, kmForLevel(level) > km { level -= 1 }
        return level
    }

    /// How far along the current step the odometer stands, 0…1.
    static func progressToNext(km: Double, level: Int) -> Double {
        let current = kmForLevel(level)
        let next = kmForNextLevel(level)
        let range = next - current
        guard range > 0 else { return 0 }
        return min(1, max(0, (km - current) / range))
    }

    /// Kilometres still owed for the next level. Never nil — there is always
    /// a next level.
    static func kmToNextLevel(km: Double, level: Int) -> Double {
        max(0, kmForNextLevel(level) - km)
    }

    // MARK: - Colour by decade

    /// The level number changes colour every ten levels and holds from 100 on.
    ///
    /// Decades, not per-level shades: the point is that the colour reads as an
    /// era of the car's life, and a ramp that shifts every level would just look
    /// like noise. 20–29 is the brand orange because that is where a daily
    /// driver spends its middle years.
    static func color(for level: Int) -> Color {
        let decade = max(0, min(10, level / 10))
        return decadeColors[decade]
    }

    /// Index = decade (0 → levels 1–9, 1 → 10–19, …, 10 → 100 and above).
    ///
    /// Read straight off the «Уровень машины» canvas (1535:119), not sampled by
    /// eye. The ramp walks from grey through the brand orange into deepening
    /// reds, then violet, and lands on the app's own text colour — a hundred
    /// levels in, the number stops being a badge and becomes type again.
    private static let decadeColors: [Color] = [
        Color(red: 155/255, green: 155/255, blue: 165/255),  // 1–9    #9B9BA5 grey, still new
        Color(red: 160/255, green: 113/255, blue: 61/255),   // 10–19  #A0713D bronze
        AppTheme.accent,                                     // 20–29  #C2452B brand terracotta
        Color(red: 217/255, green: 58/255,  blue: 30/255),   // 30–39  #D93A1E
        Color(red: 180/255, green: 35/255,  blue: 24/255),   // 40–49  #B42318
        Color(red: 155/255, green: 30/255,  blue: 60/255),   // 50–59  #9B1E3C
        Color(red: 122/255, green: 31/255,  blue: 77/255),   // 60–69  #7A1F4D
        Color(red: 91/255,  green: 33/255,  blue: 96/255),   // 70–79  #5B2160
        Color(red: 74/255,  green: 30/255,  blue: 81/255),   // 80–89  #4A1E51
        Color(red: 51/255,  green: 32/255,  blue: 63/255),   // 90–99  #33203F
        Color(red: 30/255,  green: 30/255,  blue: 35/255),   // 100+   #1E1E23, and no further change
    ]
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

    func title(_ lang: LanguageManager.Language) -> String {
        AppStrings.tr(lang, "vehicleSticker.\(self)", ru: titleRu(), en: titleEn())
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
        AppStrings.tr(lang, "roadRarity.\(self)", ru: titleRu(), en: titleEn())
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
        AppStrings.tr(lang, "roadLevel.\(self)", ru: titleRu(), en: titleEn())
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
        AppStrings.tr(lang, "zoneStatus.\(self)", ru: titleRu(), en: titleEn())
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
