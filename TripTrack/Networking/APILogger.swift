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
        // Whitelist-driven JSON value scrub. The list lives in
        // `PIISensitiveKeys.all` so SentryService and any future
        // diagnostic surface scrub the same field names by default —
        // earlier blacklist-only redaction missed presigned R2 URLs
        // and user emails appearing in /auth/login + /social/feed
        // bodies that ended up inside TestFlight sysdiagnose bundles.
        var redacted = s
        for field in PIISensitiveKeys.all {
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
