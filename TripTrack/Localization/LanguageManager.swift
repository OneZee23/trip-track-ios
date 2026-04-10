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
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = Language(rawValue: saved) {
            self.language = lang
        } else {
            // Detect from system language
            let preferred = Locale.preferredLanguages.first ?? "en"
            self.language = preferred.hasPrefix("ru") ? .ru : .en
        }
    }
}
