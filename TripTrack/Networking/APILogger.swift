import Foundation
import OSLog

final class APILogger {
    private let logger = Logger(subsystem: "com.triptrack", category: "api")

    // We deliberately log in Release too — TestFlight crashes need observability,
    // and `redact()` strips tokens from BOTH directions. The old comment here
    // said request bodies carry no tokens because tokens travel in headers —
    // that was false for the two calls that matter most: `/auth/refresh` sends
    // the refresh token in its JSON body and `/auth/login` sends Apple's
    // identity token. Until 17 Sep 2026 the owner's exported debug log carried
    // live, ten-year refresh tokens in plain text (`triptrack-log-*.txt`).
    // Without this gate the recent prod USER_NOT_AUTH cascade was invisible to
    // anything but server-side logs.
    func log(request: URLRequest, bodyPreview: String?) {
        let method = request.httpMethod ?? "?"
        let path = request.url?.path ?? "?"
        let preview = bodyPreview.map { Self.preview(of: $0) } ?? "-"
        logger.notice("→ \(method) \(path) body=\(preview, privacy: .public)")
    }

    /// Сколько символов тела запроса попадает в журнал. Ответ давно режется
    /// до 2 КБ (ниже), а запрос шёл ЦЕЛИКОМ: `APIClient` — `@MainActor`, и
    /// `redact` гонял ~25 регулярок по всему телу на главном потоке. Поездка
    /// на 76 000 точек — 6,8 МБ, и запись одного запроса в журнал держала
    /// экран секундами (Sentry APPLE-IOS-8; `APILoggerCostTests`: 2,4 с на
    /// Mac). Для диагностики хватает начала: путь, ключи, первые точки.
    static let previewLimit = 2048

    /// Текст начала тела, не раскодируя его целиком. Срез по байтам может
    /// разрезать многобайтовый символ: такой хвост отбрасывается
    /// (`decoding:` заменил бы его знаком �, что для журнала тоже годится,
    /// но размер тела в подписи берётся из полной длины).
    static func previewText(of data: Data) -> String? {
        guard data.count > previewLimit * 4 else { return String(data: data, encoding: .utf8) }
        let head = String(decoding: data.prefix(previewLimit * 4), as: UTF8.self)
        return String(head.prefix(previewLimit + 256)) + "…[\(data.count) bytes]"
    }

    /// Начало тела, вычищенное. Режем ДО `redact`, а не после — иначе цена
    /// остаётся прежней. Секрет, разрезанный на границе, не утекает:
    /// `redact` сначала чистит запас в 256 символов за границей, и только
    /// потом строка обрезается окончательно.
    static func preview(of body: String) -> String {
        guard body.count > previewLimit else { return redact(body) }
        let head = redact(String(body.prefix(previewLimit + 256)))
        return String(head.prefix(previewLimit)) + "…[\(body.utf8.count) bytes]"
    }

    func log(response: URLResponse, data: Data, duration: TimeInterval) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let preview = Self.redact(String(data: data.prefix(2048), encoding: .utf8) ?? "")
        logger.notice("← [\(status)] (\(Int(duration * 1000))ms) \(preview, privacy: .public)")
    }

    /// Internal, not private: the request-body path above and `APILoggerRedactionTests`
    /// both need it — a leak in either direction is the same leak.
    static func redact(_ s: String) -> String {
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
