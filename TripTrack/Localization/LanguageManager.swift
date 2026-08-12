import SwiftUI

final class LanguageManager: ObservableObject {
    enum Language: String, CaseIterable {
        case en, ru
    }

    static var currentLanguage: Language {
        Language(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .en
    }

    @Published var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            // Re-register notification categories with updated language
            NotificationManager.shared.reregisterCategories()
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = Language(rawValue: saved) {
            self.language = lang
        } else {
            // Detect from system language
            let preferred = Locale.preferredLanguages.first ?? "en"
            let detected: Language = preferred.hasPrefix("ru") ? .ru : .en
            self.language = detected
            // `didSet` does not run for assignments made inside `init`, so the
            // detected language never reached UserDefaults — and everything
            // that reads it from there instead of from this object (the Live
            // Activity, the Dynamic Island, the widget extension) fell back to
            // English. A Russian phone that never opened the language picker
            // recorded its trips under an English lock-screen card.
            UserDefaults.standard.set(detected.rawValue, forKey: "appLanguage")
        }
    }
}
