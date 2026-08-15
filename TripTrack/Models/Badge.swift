import SwiftUI

enum BadgeCategory: String, CaseIterable {
    case distance
    case exploration
    case special
    case streaks
    case exclusive

    func titleRu() -> String {
        switch self {
        case .distance:    return "Дистанция"
        case .exploration: return "Исследование"
        case .special:     return "Особые"
        case .streaks:     return "Серии"
        case .exclusive:   return "Эксклюзив"
        }
    }

    func titleEn() -> String {
        switch self {
        case .distance:    return "Distance"
        case .exploration: return "Exploration"
        case .special:     return "Special"
        case .streaks:     return "Streaks"
        case .exclusive:   return "Exclusive"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        AppStrings.tr(lang, "badgeCategory.\(rawValue)", ru: titleRu(), en: titleEn())
    }
}

// MARK: - Rarity

/// How rare a badge is. Authored per-badge as a baseline, but overridden by the
/// live global unlock share when the backend reports it (Steam-style dynamic
/// rarity — the fewer people who have it, the rarer it reads).
enum BadgeRarity: Int, CaseIterable, Comparable {
    case common
    case uncommon
    case rare
    case epic
    case legendary
    /// Not a rarity tier — a special class for time-limited / gifted badges
    /// (early tester, yearly veteran). Authored only; never derived from `%`.
    case exclusive

    static func < (lhs: BadgeRarity, rhs: BadgeRarity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Map a global unlock share (0–100) to a rarity tier.
    static func from(percent: Double) -> BadgeRarity {
        switch percent {
        case ..<1:   return .legendary
        case ..<5:   return .epic
        case ..<15:  return .rare
        case ..<40:  return .uncommon
        default:     return .common
        }
    }

    var color: Color {
        switch self {
        case .common:    return Color(red: 0.55, green: 0.57, blue: 0.60)
        case .uncommon:  return Color(red: 0.18, green: 0.68, blue: 0.35)
        case .rare:      return Color(red: 0.20, green: 0.55, blue: 0.90)
        case .epic:      return Color(red: 0.60, green: 0.35, blue: 0.80)
        case .legendary: return Color(red: 0.90, green: 0.65, blue: 0.10)
        case .exclusive: return Color(red: 0.86, green: 0.20, blue: 0.58) // special — vivid magenta
        }
    }

    func titleRu() -> String {
        switch self {
        case .common:    return "Обычная"
        case .uncommon:  return "Необычная"
        case .rare:      return "Редкая"
        case .epic:      return "Эпическая"
        case .legendary: return "Легендарная"
        case .exclusive: return "Особая"
        }
    }

    func titleEn() -> String {
        switch self {
        case .common:    return "Common"
        case .uncommon:  return "Uncommon"
        case .rare:      return "Rare"
        case .epic:      return "Epic"
        case .legendary: return "Legendary"
        case .exclusive: return "Special"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        AppStrings.tr(lang, "badgeRarity.\(self)", ru: titleRu(), en: titleEn())
    }
}

struct BadgeStats {
    let totalTrips: Int
    let totalDistanceKm: Double
    let maxSpeedKmh: Double
    let totalDurationHours: Double
    let uniqueRegions: Int
    let longestTripKm: Double
    let hasNightTrip: Bool
    // New fields
    let hasEarlyMorningTrip: Bool
    let hasLateNightTrip: Bool     // started after 23:00
    let maxAltitude: Double        // highest altitude in any track point
    let maxLatitude: Double        // for polar badge
    let maxElevationGainSingleTrip: Double
    let currentStreak: Int
    let bestStreak: Int
    let hasSingleTripMarathon: Bool // 42.2+ km
    let hasSingleTripIronButt: Bool // 500+ km
    let longestSingleTripDuration: TimeInterval
    let hasSundayTrip: Bool
    let hasWeekendWarrior: Bool    // 4 weekends in a row
    let hasWinterMountainTrip: Bool // Dec-Feb with elevation
    let hasSeaLevelTrip: Bool      // altitude <10m, >20km
    let countriesCount: Int
    // Fields for the 0.5.5 secret-badges pack.
    let hasAfterMidnightTrip: Bool   // started 00:00–03:59 — a step deeper than `hasLateNightTrip`
    let distinctMonthsWithTrips: Int // 1…12, calendar months in current year that have ≥1 trip
    let maxTripsOnSingleVehicle: Int // most trips on the same vehicle id — Carpool Karaoke
    let privateTripCount: Int        // count of `isPrivate == true` trips — Vault Keeper
}

struct Badge: Identifiable {
    let id: String
    let titleRu: String
    let titleEn: String
    let descriptionRu: String
    let descriptionEn: String
    let icon: String
    let color: Color
    let category: BadgeCategory
    let isHidden: Bool
    let isRepeatable: Bool
    /// Authored baseline rarity.
    let rarity: BadgeRarity
    /// Live global unlock share (0–100), set from the backend when available.
    /// When present it overrides `rarity` and feeds the "Получили X%" line.
    var globalUnlockPercent: Double?
    let checkUnlocked: (BadgeStats) -> Bool

    /// The rarity to actually show — dynamic global share if we have it, else authored.
    var displayRarity: BadgeRarity {
        if rarity == .exclusive { return .exclusive } // special class isn't %-ranked
        if let p = globalUnlockPercent { return BadgeRarity.from(percent: p) }
        return rarity
    }

    init(id: String, titleRu: String, titleEn: String,
         descriptionRu: String, descriptionEn: String,
         icon: String, color: Color,
         category: BadgeCategory = .distance,
         isHidden: Bool = false,
         isRepeatable: Bool = false,
         rarity: BadgeRarity = .common,
         globalUnlockPercent: Double? = nil,
         checkUnlocked: @escaping (BadgeStats) -> Bool) {
        self.id = id
        self.titleRu = titleRu
        self.titleEn = titleEn
        self.descriptionRu = descriptionRu
        self.descriptionEn = descriptionEn
        self.icon = icon
        self.color = color
        self.category = category
        self.isHidden = isHidden
        self.isRepeatable = isRepeatable
        self.rarity = rarity
        self.globalUnlockPercent = globalUnlockPercent
        self.checkUnlocked = checkUnlocked
    }

    /// The Russian and English wording stays inline in `BadgeDefinitions`,
    /// next to the rule that unlocks the badge — the other five languages come
    /// from the tables, keyed by the badge id. `TranslationsCoverageTests`
    /// checks that every id in `BadgeDefinitions` has a row.
    func title(_ lang: LanguageManager.Language) -> String {
        AppStrings.tr(lang, "badge.\(id).title", ru: titleRu, en: titleEn)
    }

    func description(_ lang: LanguageManager.Language) -> String {
        AppStrings.tr(lang, "badge.\(id).desc", ru: descriptionRu, en: descriptionEn)
    }

    // MARK: - Personal record

    /// Which number of the earning trip answers the badge's rule.
    ///
    /// Only single-trip badges have one. A cumulative badge («1 000 км
    /// суммарно») is not answered by the drive that happened to cross the
    /// line, and printing that drive's 12 км under it would read as the
    /// record — so those stay `nil`.
    enum RecordMetric {
        case tripDistance
        case tripMaxSpeed
        case tripDuration
        case tripElevationGain
        case tripMaxAltitude
    }

    var recordMetric: RecordMetric? {
        switch id {
        case "marathon_42", "marathon_100", "iron_butt", "highway_wolf":
            return .tripDistance
        case "speed_demon":
            return .tripMaxSpeed
        case "long_shift":
            return .tripDuration
        case "mountain_goat":
            return .tripElevationGain
        case "above_clouds":
            return .tripMaxAltitude
        default:
            return nil
        }
    }

    /// The personal number under the generic rule (Figma 117:1581) — «проедьте
    /// 42.2 км» is the badge, «47.3 км» is the memory. `nil` when the badge is
    /// not about a single drive, or when this trip carries no figure for it
    /// (a feed-adapted trip has no track points, so no altitude).
    func recordValue(for trip: Trip, language: LanguageManager.Language) -> String? {
        guard let recordMetric else { return nil }
        switch recordMetric {
        case .tripDistance:
            guard trip.distanceKm > 0 else { return nil }
            return "\(Self.oneDecimal(trip.distanceKm, language)) \(AppStrings.km(language))"
        case .tripMaxSpeed:
            guard trip.maxSpeedKmh > 0 else { return nil }
            return "\(Int(trip.maxSpeedKmh.rounded())) \(AppStrings.kmh(language))"
        case .tripDuration:
            guard trip.duration > 0 else { return nil }
            return trip.formattedDurationHuman(language)
        case .tripElevationGain:
            guard trip.elevation > 0 else { return nil }
            return Self.metres(trip.elevation, language)
        case .tripMaxAltitude:
            let peak = trip.trackPoints.map(\.altitude).max() ?? 0
            guard peak > 0 else { return nil }
            return Self.metres(peak, language)
        }
    }

    /// RU writes decimals with a comma, and the app's language is not the
    /// device's — a device on en_US showing the RU card still owes «47,3».
    private static func oneDecimal(_ value: Double, _ lang: LanguageManager.Language) -> String {
        let s = String(format: "%.1f", value)
        return s.replacingOccurrences(of: ".", with: AppStrings.decimalSeparator(lang))
    }

    private static func metres(_ value: Double, _ lang: LanguageManager.Language) -> String {
        "\(AppStrings.groupedNumber(Int(value.rounded()), lang)) \(AppStrings.unitMeters(lang))"
    }
}

extension Badge: Equatable, Hashable {
    static func == (lhs: Badge, rhs: Badge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
