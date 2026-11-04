import Foundation

struct PrivacySettings: Equatable {
    var edgeMetres: Int?
    var filmingManual: Bool
    var filmingAuto: Bool

    static let defaults = PrivacySettings(edgeMetres: nil, filmingManual: false, filmingAuto: true)

    static func load(defaults: UserDefaults = .standard) -> PrivacySettings {
        let edge = defaults.object(forKey: "privacy.edgeMetres") as? Int
        let manual = defaults.object(forKey: "filming.manual") as? Bool ?? false
        let automatic = defaults.object(forKey: "filming.auto") as? Bool ?? true
        return PrivacySettings(edgeMetres: edge, filmingManual: manual, filmingAuto: automatic)
    }

    func save(defaults: UserDefaults = .standard) {
        let previousEdge = defaults.object(forKey: "privacy.edgeMetres") as? Int
        let previousManual = defaults.object(forKey: "filming.manual") as? Bool ?? false
        let previousAutomatic = defaults.object(forKey: "filming.auto") as? Bool ?? true
        if let edgeMetres { defaults.set(edgeMetres, forKey: "privacy.edgeMetres") }
        else { defaults.removeObject(forKey: "privacy.edgeMetres") }
        defaults.set(filmingManual, forKey: "filming.manual")
        defaults.set(filmingAuto, forKey: "filming.auto")
        if previousEdge != edgeMetres { NotificationCenter.default.post(name: .privacyEdgeChanged, object: nil) }
        if previousManual != filmingManual || previousAutomatic != filmingAuto {
            NotificationCenter.default.post(name: .filmingSettingsChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let privacyEdgeChanged = Notification.Name("privacyEdgeChanged")
    static let filmingSettingsChanged = Notification.Name("filmingSettingsChanged")
}
