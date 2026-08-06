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
            return language == .ru ? "только что" : "just now"
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
                return language == .ru
                    ? "\(m) мин назад"
                    : (m == 1 ? "1 min ago" : "\(m) min ago")
            }
            return language == .ru
                ? "Сегодня в \(timeString(date, language: language))"
                : "Today at \(timeString(date, language: language))"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return language == .ru
                ? "Вчера в \(timeString(date, language: language))"
                : "Yesterday at \(timeString(date, language: language))"
        }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days >= 2, days <= 6 {
            return daysAgo(days, language: language)
        }

        return absoluteDate(date, now: now, language: language, calendar: calendar)
    }

    private static func daysAgo(_ days: Int, language: LanguageManager.Language) -> String {
        if language == .ru {
            // Russian plural agreement: 1 → "день", 2-4 → "дня", 5-20 → "дней",
            // 21 → "день", 22-24 → "дня", 25-30 → "дней", etc. Days here is
            // always 2-6 so only the "дня" form fires, but keep the full
            // table so future callers (e.g. weeks/months) follow the rule.
            let mod10 = days % 10
            let mod100 = days % 100
            let word: String
            if mod100 >= 11 && mod100 <= 14 {
                word = "дней"
            } else if mod10 == 1 {
                word = "день"
            } else if (2...4).contains(mod10) {
                word = "дня"
            } else {
                word = "дней"
            }
            return "\(days) \(word) назад"
        } else {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }

    private static func timeString(_ date: Date, language: LanguageManager.Language) -> String {
        let f = language == .ru ? Self.ruTime : Self.enTime
        return f.string(from: date)
    }

    private static func absoluteDate(
        _ date: Date, now: Date,
        language: LanguageManager.Language,
        calendar: Calendar
    ) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let f: DateFormatter
        switch (language, sameYear) {
        case (.ru, true):  f = ruDateNoYear
        case (.ru, false): f = ruDateFull
        case (.en, true):  f = enDateNoYear
        case (.en, false): f = enDateFull
        }
        let s = f.string(from: date)
        // ru_RU "MMM" renders «апр.» — the Figma meta canon is dotless
        // («12 апр · Карелия»).
        return language == .ru ? s.replacingOccurrences(of: ".", with: "") : s
    }

    // MARK: - Cached formatters

    private static let ruTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let enTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let ruDateNoYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f
    }()
    private static let ruDateFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
    private static let enDateNoYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM"
        return f
    }()
    private static let enDateFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}
