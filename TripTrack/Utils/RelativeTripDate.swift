import Foundation

/// Strava-style relative date string for feed cards. Threshold table:
///
///   < 1 min                       Just now / Только что
///   < 1 hour, same day            5 min ago / 5 мин назад
///   same calendar day             Today at 14:30 / Сегодня в 14:30
///   previous calendar day         Yesterday at 14:30 / Вчера в 14:30
///   2–6 days ago                  3 days ago / 3 дня назад
///   ≥ 7 days, same year           12 Apr / 12 апр.
///   different year                12 Apr 2025 / 12 апр. 2025
///
/// Calendar-day boundaries are used (not 24h offsets) so a trip ended at 23:50
/// flips to "Yesterday" at the next 00:00, not 24 hours later. Russian
/// plural forms are handled locally — `RelativeDateTimeFormatter` mostly
/// gets it right, but its output is inconsistent enough across iOS versions
/// that hand-rolling matches the rest of the app's localization style.
enum RelativeTripDate {
    /// Reference time is injected for testability — production callers pass
    /// `Date()`. Locale defaults to `language`'s region.
    static func string(
        from date: Date,
        now: Date = Date(),
        language: LanguageManager.Language
    ) -> String {
        let calendar = Calendar.current
        let secondsAgo = max(0, Int(now.timeIntervalSince(date)))

        if secondsAgo < 60 {
            return AppStrings.relativeTripDateJustNow(language)
        }

        // `Calendar.isDateInToday`/`isDateInYesterday` compare to the
        // SYSTEM clock, not the injected `now` — that broke unit tests
        // anchored to a fixed epoch and would also misclassify in the
        // unlikely-but-real case where the user's device clock drifts
        // mid-session. Use `isDate(_:inSameDayAs:)` against `now` for
        // the "today" branch and a manual day-1 calc for "yesterday" so
        // both honor the caller-supplied reference time.
        if calendar.isDate(date, inSameDayAs: now) {
            if secondsAgo < 3600 {
                let m = secondsAgo / 60
                return AppStrings.relTimeMinutesAgo(language, m)
            }
            return AppStrings.relTimeTodayAt(language, timeString(date, language: language))
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return AppStrings.relTimeYesterdayAt(language, timeString(date, language: language))
        }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days >= 2, days <= 6 {
            return daysAgo(days, language: language)
        }

        return absoluteDate(date, now: now, language: language, calendar: calendar)
    }

    /// Plural agreement lives in `AppStrings.nounDays` now, so «2 дня назад»
    /// and „vor 2 Tagen" come from the same table as every other counted day.
    private static func daysAgo(_ days: Int, language: LanguageManager.Language) -> String {
        AppStrings.relTimeDaysAgo(language, days)
    }

    private static func timeString(_ date: Date, language: LanguageManager.Language) -> String {
        timeFormatters[language]?.string(from: date) ?? ""
    }

    private static func absoluteDate(
        _ date: Date, now: Date,
        language: LanguageManager.Language,
        calendar: Calendar
    ) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let table = sameYear ? dateNoYearFormatters : dateFullFormatters
        let s = table[language]?.string(from: date) ?? ""
        // ru_RU "MMM" renders «апр.» — the Figma meta canon is dotless
        // («12 апр · Карелия»).
        return language == .ru ? s.replacingOccurrences(of: ".", with: "") : s
    }

    // MARK: - Cached formatters
    //
    // One per language rather than a pair of hand-written ru/en ones: a
    // `DateFormatter` is expensive to build and these are hit once per feed
    // card. Built from `Language.locale`, so a new language needs no code here.

    private static let timeFormatters = formatters(pattern: "HH:mm")
    private static let dateNoYearFormatters = formatters(pattern: "d MMM")
    private static let dateFullFormatters = formatters(pattern: "d MMM yyyy")

    private static func formatters(pattern: String) -> [LanguageManager.Language: DateFormatter] {
        var map: [LanguageManager.Language: DateFormatter] = [:]
        for lang in LanguageManager.Language.allCases {
            let f = DateFormatter()
            f.locale = lang.locale
            f.dateFormat = pattern
            map[lang] = f
        }
        return map
    }
}
