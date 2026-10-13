import Foundation

extension AppStrings {
    static func profileDetailsGroup(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileDetailsGroup", ru: "Личные данные", en: "Personal details")
    }
    static func profileAppearanceGroup(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileAppearanceGroup", ru: "Оформление", en: "Appearance")
    }
    static func profileProgressGroup(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileProgressGroup", ru: "В пути", en: "On the road")
    }
    static func proTryYourStyle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "proTryYourStyle", ru: "Примерить оформление", en: "Try your new look")
    }
}
