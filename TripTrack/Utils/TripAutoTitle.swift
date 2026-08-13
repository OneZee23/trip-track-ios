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
    private static let enFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()
    private static let ruFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    static func generate(for date: Date?, language: LanguageManager.Language) -> String {
        guard let date else { return language == .ru ? "Поездка" : "Trip" }
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
        let en = enFormatter.string(from: startDate)
        let ruDotted = ruFormatter.string(from: startDate)
        let ru = ruDotted.replacingOccurrences(of: ".", with: "")
        return title == en || title == ru || title == ruDotted
    }

    static func localized(_ title: String?, startDate: Date, language: LanguageManager.Language) -> String? {
        guard let title, !title.isEmpty else { return title }
        let en = enFormatter.string(from: startDate)
        let ruDotted = ruFormatter.string(from: startDate)
        let ru = ruDotted.replacingOccurrences(of: ".", with: "")
        guard title == en || title == ru || title == ruDotted else { return title }
        return string(from: startDate, language: language)
    }

    private static func string(from date: Date, language: LanguageManager.Language) -> String {
        if language == .ru {
            // ru_RU "MMM" renders «авг.» — the canon is dotless.
            return ruFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
        }
        return enFormatter.string(from: date)
    }
}
