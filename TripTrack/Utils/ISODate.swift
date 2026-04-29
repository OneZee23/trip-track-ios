import Foundation

/// Thread-safe ISO-8601 (RFC 3339) date parsing pinned to UTC.
///
/// `ISO8601DateFormatter` looks like the right tool but has two real-world
/// problems that bit us in production:
///   1. Under Swift concurrency it intermittently parsed `Z`-suffixed
///      timestamps as device-local time, dropping the wall-clock by one
///      timezone offset — observable in the social feed as a "3 hours ago"
///      reaction in MSK that was actually placed seconds earlier.
///   2. Combining `.withInternetDateTime` and `.withFractionalSeconds` on
///      the same instance has historically had off-by-one behaviour on
///      different iOS versions.
///
/// Switching to plain `DateFormatter` with an explicit format string and
/// `en_US_POSIX` locale eliminates both issues — it's the boilerplate Apple
/// itself recommends for parsing fixed-format timestamps.
enum ISODate {
    /// Parses a server timestamp. Accepts both fractional-seconds and
    /// non-fractional variants, and any form of timezone designator (`Z`,
    /// `+0000`, `+03:00`). Returns `nil` if the input doesn't match either
    /// pattern — caller decides how to surface that.
    static func parse(_ value: String) -> Date? {
        if let date = withMs.date(from: value) { return date }
        if let date = withoutMs.date(from: value) { return date }
        return nil
    }

    /// Serializes a Date as an ISO-8601 UTC string with millisecond precision
    /// (e.g. `2026-04-29T08:33:35.049Z`). Symmetric with what we accept on
    /// the way in, and what the NestJS server emits.
    static func format(_ date: Date) -> String {
        return withMs.string(from: date)
    }

    // `XXXXX` = ISO 8601 timezone with colon and Z support (`Z` or `+03:00`).
    // `en_US_POSIX` is the canonical locale for fixed-format date parsing —
    // immune to user locale changes (`Calendar.gregorian` matters too on
    // some non-Gregorian regions).
    private static let withMs: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private static let withoutMs: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()
}
