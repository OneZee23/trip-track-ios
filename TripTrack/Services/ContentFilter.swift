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

    /// Strips zero-width, bidi-override, and other invisible Unicode chars
    /// that two users could exploit to appear identical in the UI. Also
    /// collapses internal whitespace runs and trims edges. Safe to apply
    /// silently — the resulting string is what the user "actually intended".
    /// Specifically targeted at display-name input; trip titles tolerate
    /// trailing whitespace less aggressively but follow the same rules.
    static func sanitize(_ text: String) -> String {
        // Zero-width / format / bidi-control / line-separator chars. These
        // never carry semantic meaning in a display name and let attackers
        // mint visually-identical "different" names. Stripping > replacing
        // because they have no rendering anyway.
        let stripped = text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x200B...0x200F: return false  // ZWSP/ZWJ/LRM/RLM
            case 0x202A...0x202E: return false  // bidi override (LRE/RLE/PDF/LRO/RLO)
            case 0x2060...0x206F: return false  // word-joiner / invisible operators
            case 0xFEFF:          return false  // BOM
            case 0x180E:          return false  // Mongolian vowel separator (deprecated, abused as ZWSP)
            default: return true
            }
        }
        let cleaned = String(String.UnicodeScalarView(stripped))
        // Collapse internal whitespace runs to a single space + trim edges.
        // `whitespacesAndNewlines` covers regular space, tab, NBSP, and
        // line breaks — pasted-from-Word names regularly have NBSP.
        let collapsed = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }

    /// Validates a user-submitted string; returns nil on success or a
    /// human-readable error message otherwise. For display names, also
    /// enforces anti-abuse rules: mixed-script tokens (homoglyph attacks),
    /// repeated-character runs, and punctuation floods.
    static func validate(_ text: String, field: Field, language: LanguageManager.Language) -> String? {
        let isRu = language == .ru
        let cleaned = sanitize(text)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.count > field.maxLength {
            return isRu
                ? "Слишком длинный текст (максимум \(field.maxLength))"
                : "Too long (max \(field.maxLength) characters)"
        }

        if containsObjectionable(cleaned) {
            return isRu
                ? "Содержит недопустимые выражения"
                : "Contains inappropriate language"
        }

        // Display-name-specific anti-abuse. Other fields (trip titles,
        // notes) accept arbitrary mixed-script / punctuation because they
        // describe a thing, not an identity.
        if field == .displayName {
            if let err = validateDisplayNameAbuse(cleaned, isRu: isRu) {
                return err
            }
        }

        return nil
    }

    /// Display-name-only checks. All applied AFTER `sanitize` so we don't
    /// trip on whitespace artefacts the user didn't author.
    private static func validateDisplayNameAbuse(_ text: String, isRu: Bool) -> String? {
        // Must contain at least one letter — pure punctuation/digit names
        // ("123", "....", "!@#$") are rejected as identity-free.
        let hasLetter = text.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .uppercaseLetter ||
            scalar.properties.generalCategory == .lowercaseLetter ||
            scalar.properties.generalCategory == .titlecaseLetter ||
            scalar.properties.generalCategory == .otherLetter ||
            scalar.properties.generalCategory == .modifierLetter
        }
        if !hasLetter {
            return isRu ? "Должно быть хотя бы одно слово" : "Must contain at least one letter"
        }

        // 5+ identical characters in a row — `aaaaaa` spam pattern.
        if hasRepeatedRun(text, threshold: 5) {
            return isRu
                ? "Слишком много повторов одного символа"
                : "Too many repeated characters"
        }

        // 4+ non-letter non-digit chars in a row — `....!@#$` punctuation flood.
        if hasPunctuationFlood(text, threshold: 4) {
            return isRu
                ? "Слишком много знаков подряд"
                : "Too many symbols in a row"
        }

        // Homoglyph guard — Latin and Cyrillic letters in the same name
        // component (split by space + common name separators). `Иван Smith`
        // is fine (separate tokens); `Тwitter` (Cyrillic Т + Latin witter)
        // is rejected because that's the impersonation vector.
        let separators = CharacterSet(charactersIn: " -.,'’/_")
        let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
        for token in tokens {
            if hasMixedScript(token) {
                return isRu
                    ? "Латиница и кириллица в одном слове недопустимы"
                    : "Mixing Latin and Cyrillic in one word isn't allowed"
            }
        }

        return nil
    }

    private static func hasRepeatedRun(_ text: String, threshold: Int) -> Bool {
        var run = 1
        var prev: Character?
        for ch in text {
            if let p = prev, p == ch {
                run += 1
                if run >= threshold { return true }
            } else {
                run = 1
            }
            prev = ch
        }
        return false
    }

    private static func hasPunctuationFlood(_ text: String, threshold: Int) -> Bool {
        var run = 0
        for ch in text {
            let isLetterOrDigit = ch.isLetter || ch.isNumber || ch == " "
            if isLetterOrDigit {
                run = 0
            } else {
                run += 1
                if run >= threshold { return true }
            }
        }
        return false
    }

    /// True if `token` has letters from BOTH Latin and Cyrillic blocks.
    /// Digits, punctuation, and combining marks are script-neutral and
    /// don't count toward either side.
    private static func hasMixedScript(_ token: String) -> Bool {
        var hasLatin = false
        var hasCyrillic = false
        for scalar in token.unicodeScalars {
            // Latin: basic + Latin-1 supplement + Extended-A + Extended-B + IPA
            if (0x0041...0x005A).contains(scalar.value) ||
               (0x0061...0x007A).contains(scalar.value) ||
               (0x00C0...0x024F).contains(scalar.value) {
                hasLatin = true
            }
            // Cyrillic: basic + supplement + extended-A + extended-B
            else if (0x0400...0x04FF).contains(scalar.value) ||
                    (0x0500...0x052F).contains(scalar.value) ||
                    (0x2DE0...0x2DFF).contains(scalar.value) ||
                    (0xA640...0xA69F).contains(scalar.value) {
                hasCyrillic = true
            }
            if hasLatin && hasCyrillic { return true }
        }
        return false
    }

    enum Field {
        case tripTitle
        case tripNote
        case displayName
        case vehicleName
        case comment

        var maxLength: Int {
            switch self {
            case .tripTitle: return 200
            case .tripNote: return 2000
            // Matches the comments backend contract (text 1..500).
            case .comment: return 500
            // Match the server's `@MaxLength(30)` on `displayName` —
            // previously 64 here would let `ContentFilter.validate` accept
            // 30–64 char names that the server then rejected with a
            // generic 400. Single binding constraint avoids drift.
            case .displayName: return 30
            case .vehicleName: return 60
            }
        }
    }
}
