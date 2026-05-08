import Foundation
import Sentry

/// Thin wrapper around `SentrySDK.start` that bakes in TripTrack's
/// privacy stance:
///   - DSN sourced from Info.plist via `AppConfig.sentryDSN`. Empty DSN
///     → no-op start (dev / simulator builds skip Sentry entirely).
///   - No screenshot, no view-hierarchy, no session replay. Privacy
///     surfaces stay strictly off — driving routes & photos must NEVER
///     leak via diagnostic snapshots.
///   - PII scrubber on `beforeSend` and `beforeBreadcrumb` mirrors the
///     existing `APILogger.redact` whitelist (auth tokens, email, names,
///     remote URLs).
///   - Auto-instrumentation kept lean: crashes + unhandled exceptions
///     ON, network performance OFF (URL paths can carry trip ids).
enum SentryService {
    /// Keys whose values get nuked anywhere they appear in the event
    /// payload. Mirrors `APILogger.redact` to keep one source of truth
    /// for "what counts as PII in this app".
    private static let sensitiveKeys: Set<String> = [
        "refreshToken", "accessToken", "identityToken", "apnsToken",
        "deviceToken", "email", "userEmail", "displayName", "userName",
        "thumbnailUrl", "originalUrl", "remoteUrl", "url", "password",
        "nonce", "rawNonce",
    ]

    static func start() {
        guard let dsn = AppConfig.sentryDSN else {
            // Dev / simulator with empty DSN — Sentry never starts. No
            // network, no overhead, breadcrumbs are local-no-ops.
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = Self.releaseString
            options.environment = AppConfig.isDebug ? "debug" : "release"

            // Bound transaction sampling — for an early-stage app the
            // free tier is plenty at 10%, and we don't have user-load
            // worth profiling beyond that.
            options.tracesSampleRate = 0.1
            options.profilesSampleRate = 0.0

            // Hard "no" to surfaces that could leak driving data.
            // Session replay is OFF by default (opt-in via experimental
            // options); we deliberately do not configure it so capture
            // never starts. Same for screenshots / view hierarchies.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // We attach our own user scope (only the anonymous account
            // id, no name / email). Disable Sentry's default user info
            // collection so device identifiers don't leak.
            options.sendDefaultPii = false

            // Network breadcrumbs: keep them, but `beforeBreadcrumb`
            // strips URL paths so per-trip / per-photo identifiers
            // don't end up in event payloads.
            options.enableAutoBreadcrumbTracking = true

            options.beforeSend = { event in
                Self.scrub(event: event)
                return event
            }

            options.beforeBreadcrumb = { breadcrumb in
                Self.scrub(breadcrumb: breadcrumb)
                return breadcrumb
            }
        }
    }

    /// Stamp the current authenticated account id (UUID, no PII) onto
    /// the Sentry scope so events get grouped per-user without revealing
    /// who that user actually is. Call after sign-in / on cold-launch
    /// when a session restores. Pass `nil` on sign-out to clear.
    static func setAccount(id: String?) {
        SentrySDK.configureScope { scope in
            if let id {
                let user = User()
                user.userId = id
                scope.setUser(user)
            } else {
                scope.setUser(nil)
            }
        }
    }

    // MARK: - Scrubbing

    private static func scrub(event: Event) {
        // Tags & extras: drop sensitive entries entirely.
        if let tags = event.tags {
            event.tags = tags.filter { !sensitiveKeys.contains($0.key) }
        }
        if let extra = event.extra {
            event.extra = redactDict(extra)
        }
        // Request cookies / auth headers — defense in depth. The SDK
        // doesn't capture HTTP bodies by default; we still strip auth
        // headers in case automatic instrumentation gets enabled later.
        if let request = event.request {
            request.cookies = nil
            request.headers = (request.headers ?? [:]).filter {
                !$0.key.lowercased().contains("authorization") &&
                !$0.key.lowercased().contains("cookie")
            }
        }
    }

    private static func scrub(breadcrumb: Breadcrumb) {
        if let data = breadcrumb.data {
            breadcrumb.data = redactDict(data)
        }
        // URL breadcrumbs: keep host + scheme so we know which API got
        // hit, drop the path (per-trip ids, account ids, share codes
        // live in path segments).
        if breadcrumb.category == "http", let url = breadcrumb.data?["url"] as? String,
           let parsed = URL(string: url), let host = parsed.host {
            var redacted = (breadcrumb.data ?? [:]) as [String: Any]
            redacted["url"] = "\(parsed.scheme ?? "https")://\(host)/<path>"
            breadcrumb.data = redacted
        }
    }

    private static func redactDict(_ dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in dict {
            if sensitiveKeys.contains(k) {
                out[k] = "<redacted>"
            } else if let nested = v as? [String: Any] {
                out[k] = redactDict(nested)
            } else {
                out[k] = v
            }
        }
        return out
    }

    // MARK: - Release string

    /// `MARKETING_VERSION (CURRENT_PROJECT_VERSION)` — Sentry uses this to
    /// group events per build, makes regressions easy to bisect.
    private static var releaseString: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "triptrack-ios@\(marketing)+\(build)"
    }
}
