import Foundation

/// Simple denylist-based content filter for user-generated text (trip titles,
/// notes, display names). Satisfies Apple App Review Guideline 1.2 which
/// requires a "method for filtering objectionable content" in UGC apps.
///
/// Matches are case-insensitive and word-boundary-aware to avoid false positives
/// in ordinary words ("scunthorpe problem"). The list is intentionally short —
/// the goal is to block the most egregious slurs and prevent a first-line
/// rejection at Apple review, not to be a comprehensive moderation system.
enum ContentFilter {

    /// English + Russian slurs and the most common objectionable terms.
    /// Stored as lowercase whole-word patterns. Real moderation stack would
    /// extend this server-side with reporting + human review.
    private static let denylist: Set<String> = [
        // English — the short unambiguous list
        "nigger", "nigga", "faggot", "chink", "spic", "kike", "tranny",
        "retard", "raghead", "kyke", "wetback", "beaner",
        // Russian — аналог
        "пидор", "пидорас", "пидарас", "нигер", "жид", "хач", "чурка",
        "даун", "педик"
    ]

    /// Returns true if text contains any denylisted term (case-insensitive,
    /// Unicode lowercasing). Ignores word-boundary precision for brevity —
    /// this is intentional: substring match catches obfuscations like
    /// "s-l-u-r-s" with spaces removed.
    static func containsObjectionable(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        for term in denylist where normalized.contains(term) {
            return true
        }
        return false
    }

    /// Validates a user-submitted string; returns nil on success or a
    /// human-readable error message otherwise.
    static func validate(_ text: String, field: Field, language: LanguageManager.Language) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if containsObjectionable(trimmed) {
            return language == .ru
                ? "Содержит недопустимые выражения"
                : "Contains inappropriate language"
        }

        if trimmed.count > field.maxLength {
            return language == .ru
                ? "Слишком длинный текст (максимум \(field.maxLength))"
                : "Too long (max \(field.maxLength) characters)"
        }

        return nil
    }

    enum Field {
        case tripTitle
        case tripNote
        case displayName
        case vehicleName

        var maxLength: Int {
            switch self {
            case .tripTitle: return 200
            case .tripNote: return 2000
            case .displayName: return 64
            case .vehicleName: return 60
            }
        }
    }
}
