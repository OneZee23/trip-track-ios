import Foundation

/// Reddit-style placeholder name generator. Used when Apple Sign In didn't
/// return `fullName` (e.g. re-sign-in after delete-account, or hide-my-email
/// + minimal scope) so the user lands on something humane like
/// "Быстрый Путешественник 42" instead of `null`. They can still rename
/// themselves any time via the profile header.
///
/// Word lists are road-trip themed to fit the product voice — adjectives
/// nudge toward driving qualities, nouns toward travelers / explorers.
enum RandomDisplayName {
    static func generate(language: LanguageManager.Language) -> String {
        let pool = (language == .ru) ? ruPool : enPool
        let adj = pool.adjectives.randomElement() ?? ""
        let noun = pool.nouns.randomElement() ?? ""
        let suffix = Int.random(in: 10...9999)
        return "\(adj) \(noun) \(suffix)"
    }

    /// Whether `name` looks like one we generated — three tokens, last is a
    /// 2–4 digit number, first matches one of our seed adjectives. Lets the
    /// UI flag the name as a placeholder ("tap to change") so users on a
    /// fresh device don't end up thinking "Дерзкий Гонщик 472" is their
    /// permanent identity.
    static func isPlaceholder(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count == 3 else { return false }
        guard Int(parts[2]) != nil else { return false }
        let firstWord = String(parts[0])
        return ruPool.adjectives.contains(firstWord) || enPool.adjectives.contains(firstWord)
    }

    private struct Pool {
        let adjectives: [String]
        let nouns: [String]
    }

    private static let ruPool = Pool(
        adjectives: [
            "Быстрый", "Смелый", "Ловкий", "Дерзкий", "Хитрый",
            "Зоркий", "Мудрый", "Шустрый", "Тихий", "Лихой",
            "Гордый", "Светлый", "Бодрый", "Крепкий", "Острый",
        ],
        nouns: [
            "Водитель", "Путешественник", "Странник", "Кочевник", "Гонщик",
            "Картограф", "Навигатор", "Путник", "Турист", "Капитан",
            "Исследователь", "Дрифтер", "Райдер", "Покоритель", "Скиталец",
        ]
    )

    private static let enPool = Pool(
        adjectives: [
            "Swift", "Bold", "Nimble", "Daring", "Sly",
            "Sharp", "Wise", "Quick", "Quiet", "Wild",
            "Steady", "Bright", "Lucky", "Cool", "Brave",
        ],
        nouns: [
            "Driver", "Traveler", "Wanderer", "Nomad", "Racer",
            "Mapper", "Navigator", "Voyager", "Tourist", "Captain",
            "Explorer", "Drifter", "Rider", "Roamer", "Pathfinder",
        ]
    )
}
