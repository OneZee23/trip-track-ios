import Foundation

enum AppConfig {
    static var apiBaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: raw) else {
            #if DEBUG
            return URL(string: "http://localhost:3003")!
            #else
            fatalError("API_BASE_URL missing in Info.plist")
            #endif
        }
        return url
    }

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Sentry project DSN. Empty = SDK no-op (dev / simulator builds).
    /// Sourced from Info.plist (`SENTRY_DSN`), wired via Local.xcconfig
    /// per build config.
    static var sentryDSN: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Legal URLs

    static func privacyPolicyURL(_ lang: LanguageManager.Language) -> URL {
        let base = "https://onezee23.github.io/trip-track-ios"
        let path = lang == .ru ? "/privacy-policy-ru.html" : "/privacy-policy.html"
        return URL(string: base + path)!
    }

    static func termsURL(_ lang: LanguageManager.Language) -> URL {
        let base = "https://onezee23.github.io/trip-track-ios"
        let path = lang == .ru ? "/terms-ru.html" : "/terms.html"
        return URL(string: base + path)!
    }
}
