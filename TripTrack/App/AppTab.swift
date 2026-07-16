import Foundation

/// Single source of truth for the five top-level tabs (6.1.0 redesign
/// navigation). Replaces the previous hardcoded `Int` indices. Backed by a
/// stable `String` rawValue so it persists cleanly via `@AppStorage`.
enum AppTab: String, CaseIterable, Hashable {
    case home, maps, record, groups, profile

    /// Storage key for the new enum-backed selection. A NEW key (not the
    /// legacy "selectedTab") so an old `Int` value can never be misread as
    /// a `String` rawValue — migration moves the value across explicitly.
    static let storageKey = "selectedTabV2"
    static let legacyStorageKey = "selectedTab"

    /// Maps the pre-6.1.0 `Int` tab index to its 6.1.0 tab.
    /// Old order was: 0 = Feed, 1 = Record, 2 = Regions.
    static func fromLegacyIndex(_ index: Int) -> AppTab {
        switch index {
        case 0: return .home    // Feed → Home
        case 1: return .record  // Record → Record
        case 2: return .maps    // Regions → Maps
        default: return .home
        }
    }

    /// One-time migration: if the new key is unset but a legacy `Int`
    /// selection exists, translate it. Fresh installs (no legacy key) are
    /// left untouched so the `@AppStorage` default (.home) applies.
    static func migrateLegacySelectedTabIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: storageKey) == nil else { return }
        guard defaults.object(forKey: legacyStorageKey) != nil else { return }
        let legacy = defaults.integer(forKey: legacyStorageKey)
        defaults.set(fromLegacyIndex(legacy).rawValue, forKey: storageKey)
    }
}
