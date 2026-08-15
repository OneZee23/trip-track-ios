import SwiftUI

final class LanguageManager: ObservableObject {
    /// The languages the interface exists in. Raw values are the ISO-639-1
    /// codes, and they double as the `appLanguage` UserDefaults value the
    /// extensions read — so `en`/`ru` must keep their spelling forever, or a
    /// phone that upgraded from 0.6.0 loses its choice.
    enum Language: String, CaseIterable {
        case en, ru, de, es, fr, it, pl
        // 0.6.2. `fil` and `pt` are the LANGUAGE subtags iOS reports for
        // Filipino and Brazilian Portuguese («fil-PH», «pt-BR»), which is what
        // `detect(from:)` matches on — the region lives in `locale` instead.
        case id, tr, fil, uk, kk, pt

        /// The locale every date, number and unit formatter must be built
        /// with. Hard-coding `ru_RU`/`en_US` at call sites is what made
        /// «14 мая» come out as «May 14» on a German phone; ask the language
        /// instead.
        var locale: Locale {
            switch self {
            case .en: return Locale(identifier: "en_US")
            case .ru: return Locale(identifier: "ru_RU")
            case .de: return Locale(identifier: "de_DE")
            case .es: return Locale(identifier: "es_ES")
            case .fr: return Locale(identifier: "fr_FR")
            case .it: return Locale(identifier: "it_IT")
            case .pl: return Locale(identifier: "pl_PL")
            case .id: return Locale(identifier: "id_ID")
            case .tr: return Locale(identifier: "tr_TR")
            case .fil: return Locale(identifier: "fil_PH")
            case .uk: return Locale(identifier: "uk_UA")
            case .kk: return Locale(identifier: "kk_KZ")
            // Brazil, not Portugal: that is the market this was added for, and
            // the two differ in vocabulary as well as in number format.
            case .pt: return Locale(identifier: "pt_BR")
            }
        }

        /// Every language names itself, in itself — the picker shows endonyms,
        /// because someone who only reads Polish cannot find "Polish".
        var endonym: String {
            switch self {
            case .en: return "English"
            case .ru: return "Русский"
            case .de: return "Deutsch"
            case .es: return "Español"
            case .fr: return "Français"
            case .it: return "Italiano"
            case .pl: return "Polski"
            case .id: return "Bahasa Indonesia"
            case .tr: return "Türkçe"
            case .fil: return "Filipino"
            case .uk: return "Українська"
            case .kk: return "Қазақша"
            case .pt: return "Português (Brasil)"
            }
        }

        /// The two-letter chip in the settings row. In the language's own
        /// script, so the chip and the name below it are not from two
        /// different alphabets.
        var badge: String {
            switch self {
            case .en: return "En"
            case .ru: return "Ру"
            case .de: return "De"
            case .es: return "Es"
            case .fr: return "Fr"
            case .it: return "It"
            case .pl: return "Pl"
            case .id: return "Id"
            case .tr: return "Tr"
            case .fil: return "Fi"
            case .uk: return "Ук"
            case .kk: return "Қа"
            case .pt: return "Pt"
            }
        }

        /// Picker order: the two languages the app was born in first, then the
        /// rest in the order they were added. `allCases` is declaration order
        /// and is not meant for display.
        static let displayOrder: [Language] = [
            .ru, .en, .de, .es, .fr, .it, .pl, .uk, .kk, .tr, .id, .fil, .pt,
        ]

        /// `Locale.preferredLanguages` gives BCP-47 tags — "de-DE", "pt-BR",
        /// "zh-Hans-CN". Match on the language subtag only, and walk the whole
        /// preference list: a phone set to Portuguese with Spanish second
        /// should land on Spanish rather than on English.
        static func detect(from preferred: [String]) -> Language {
            for tag in preferred {
                let code = tag.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
                if let match = Language(rawValue: code) { return match }
            }
            return .en
        }
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
            let detected = Language.detect(from: Locale.preferredLanguages)
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
