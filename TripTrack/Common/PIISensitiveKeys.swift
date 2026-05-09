import Foundation

/// Single source of truth for "what counts as a sensitive field name in
/// TripTrack". Used by both `APILogger.redact` (regex-blanks the value of
/// any matching JSON field) and `SentryService.scrub` (recursively
/// nukes the value anywhere in the event payload).
///
/// Both consumers traverse different shapes (raw JSON string vs. nested
/// dict), so the *scrub functions* legitimately differ — but the *list*
/// is identical and changes to it should land in one place.
enum PIISensitiveKeys {
    /// Field names whose values are PII / credentials and must never
    /// reach OSLog, Sentry, or any other diagnostic surface.
    static let all: Set<String> = [
        // Auth tokens
        "refreshToken", "accessToken", "identityToken",
        "apnsToken", "deviceToken",
        "password", "jwt",
        // Apple Sign-In nonce (raw, before SHA256 → backend)
        "nonce", "rawNonce",
        // Contact / identity
        "email", "userEmail",
        "displayName", "userName",
        // Server-issued presigned URLs — whoever sees them sees the
        // photo until expiry.
        "thumbnailUrl", "originalUrl", "remoteUrl", "url",
    ]
}
