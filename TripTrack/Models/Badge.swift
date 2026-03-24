import SwiftUI

enum BadgeCategory: String, CaseIterable {
    case distance
    case exploration
    case special
    case streaks

    func titleRu() -> String {
        switch self {
        case .distance:    return "Дистанция"
        case .exploration: return "Исследование"
        case .special:     return "Особые"
        case .streaks:     return "Серии"
        }
    }

    func titleEn() -> String {
        switch self {
        case .distance:    return "Distance"
        case .exploration: return "Exploration"
        case .special:     return "Special"
        case .streaks:     return "Streaks"
        }
    }

    func title(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? titleRu() : titleEn()
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
    let checkUnlocked: (BadgeStats) -> Bool

    init(id: String, titleRu: String, titleEn: String,
         descriptionRu: String, descriptionEn: String,
         icon: String, color: Color,
         category: BadgeCategory = .distance,
         isHidden: Bool = false,
         isRepeatable: Bool = false,
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
        self.checkUnlocked = checkUnlocked
    }

    func title(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? titleRu : titleEn
    }

    func description(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? descriptionRu : descriptionEn
    }
}

extension Badge: Equatable, Hashable {
    static func == (lhs: Badge, rhs: Badge) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
