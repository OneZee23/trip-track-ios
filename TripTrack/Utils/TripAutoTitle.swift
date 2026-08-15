import Foundation

/// Auto-generated trip titles are the formatted start date («5 Aug, 17:41»)
/// stamped at save time with whatever locale the RECORDING device had, and
/// stored verbatim — so a RU app happily shows an EN title. Two duties:
///
///   * `generate` — new auto-titles follow the APP language, not the system
///     locale («5 авг, 17:41» when the app runs in Russian).
///   * `localized` — legacy stored titles are re-rendered on display when
///     (and only when) they exactly match the trip's own start date in one
///     of the known auto formats. Real user-typed titles can never match a
///     full formatted date string, so they pass through untouched.
enum TripAutoTitle {
    private static let formatters = LocalizedDateFormatter.patterns("d MMM, HH:mm")
    private static var enFormatter: DateFormatter { formatters[.en]! }
    private static var ruFormatter: DateFormatter { formatters[.ru]! }

    static func generate(for date: Date?, language: LanguageManager.Language) -> String {
        guard let date else { return AppStrings.tripTitle(language) }
        return string(from: date, language: language)
    }

    /// Whether this title is one the app stamped on, not one a person typed.
    ///
    /// The detail screen has a rule — a NAMED trip gets «14 ИЮНЯ · КРАСНОДАР.
    /// КРАЙ» over its name, an unnamed one gets «14 ИЮНЯ» over its region —
    /// and the rule was right, but every trip has a title, because saving
    /// stamps the date as one. So the screen printed the same date three
    /// times: pixel line, heading, and the chip below. Auto-titles are a
    /// formatted start date and nothing else, which is exactly what
    /// `localized` already recognises.
    static func isAuto(_ title: String?, startDate: Date) -> Bool {
        guard let title, !title.isEmpty else { return false }
        return autoForms(startDate).contains(title)
    }

    /// Every string the app could have stamped on a trip started at this
    /// moment — one per language, plus the dotted form the abbreviated months
    /// carry before `string(from:)` strips the period.
    private static func autoForms(_ startDate: Date) -> Set<String> {
        var forms: Set<String> = []
        for lang in LanguageManager.Language.allCases {
            guard let dotted = formatters[lang]?.string(from: startDate) else { continue }
            forms.insert(dotted)
            forms.insert(dotted.replacingOccurrences(of: ".", with: ""))
        }
        return forms
    }

    static func localized(_ title: String?, startDate: Date, language: LanguageManager.Language) -> String? {
        guard let title, !title.isEmpty else { return title }
        guard autoForms(startDate).contains(title) else { return title }
        return string(from: startDate, language: language)
    }

    private static func string(from date: Date, language: LanguageManager.Language) -> String {
        let raw = formatters[language]?.string(from: date) ?? ""
        // ru_RU "MMM" renders «авг.» — the canon is dotless. Other languages
        // abbreviate with a period too («14 Aug.»), and the same rule reads
        // right there, so it is applied to all of them rather than to RU alone.
        return raw.replacingOccurrences(of: ".", with: "")
    }
}
