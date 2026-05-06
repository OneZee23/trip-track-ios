import Foundation
import OSLog

final class APILogger {
    private let logger = Logger(subsystem: "com.triptrack", category: "api")

    // We deliberately log in Release too — TestFlight crashes need observability,
    // and `redact()` strips tokens from response bodies. Request bodies don't
    // include access/refresh tokens (they're in headers), so request body
    // logging is safe. Without this gate the recent prod USER_NOT_AUTH cascade
    // was invisible to anything but server-side logs.
    func log(request: URLRequest, bodyPreview: String?) {
        let method = request.httpMethod ?? "?"
        let path = request.url?.path ?? "?"
        logger.notice("→ \(method) \(path) body=\(bodyPreview ?? "-", privacy: .public)")
    }

    func log(response: URLResponse, data: Data, duration: TimeInterval) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let preview = redact(String(data: data.prefix(2048), encoding: .utf8) ?? "")
        logger.notice("← [\(status)] (\(Int(duration * 1000))ms) \(preview, privacy: .public)")
    }

    private func redact(_ s: String) -> String {
        // Greedy whitelist of "private" JSON fields. Approach: every quoted
        // value of a sensitive field is replaced with `***`. Sensitive fields
        // include not just auth tokens but also PII (email, displayName),
        // server-issued presigned URLs (whoever sees them gets the photo
        // until expiry), APNs tokens, and refresh tokens.
        // Earlier blacklist-only redaction missed presigned R2 URLs and
        // user emails that were appearing in /auth/login response bodies
        // and /social/feed reactor lists. TestFlight feedback bundles can
        // ship sysdiagnose containing these logs — privacy-first means we
        // never let those values land in OSLog.
        let sensitiveFields = [
            "refreshToken", "accessToken", "identityToken",
            "apnsToken", "deviceToken",
            "email", "userEmail",
            "displayName", "userName",
            "thumbnailUrl", "originalUrl", "remoteUrl", "url"
        ]
        var redacted = s
        for field in sensitiveFields {
            let pattern = #""\#(field)"\s*:\s*"[^"]*""#
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: "\"\(field)\":\"***\"",
                options: .regularExpression
            )
        }
        return redacted
    }
}
