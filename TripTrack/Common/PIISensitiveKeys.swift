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
        // Координаты дома (0.6.6). Хранятся только в UserDefaults и на
        // сервер не уезжают вовсе, поэтому в диагностику попасть сейчас
        // неоткуда — имена стоят здесь ЗАРАНЕЕ. Домашний адрес человека
        // это худшее, что можно случайно приложить к отчёту об ошибке, и
        // цена страховки — две строки.
        "homeLatitude", "homeLongitude",
        // Хеш «устройство + приложение», который Sentry считает от
        // Apple `identifierForVendor` и кладёт в контекст `app` КАЖДОГО
        // события — сам, без единой нашей строки. Рядом в том же событии
        // лежит `user.id`, то есть пара «кто» + «с какой установки»
        // склеивается без нашего участия. Своей чистки у SDK для этого
        // поля нет: имя пришло из его собственного контекста, а не из
        // нашего payload'а, поэтому строка нужна здесь.
        "device_app_hash",
    ]

    /// Совпадение по ИМЕНИ, а не по точному ключу: в UserDefaults те же
    /// поля лежат с префиксом (`com.triptrack.settings.homeLatitude`), и
    /// строгое равенство пропустило бы ровно тот дамп настроек, ради
    /// которого имена сюда и вписаны. Регистр не важен — сервер и SDK
    /// пишут ключи по-разному.
    static func matches(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return all.contains { name in
            let n = name.lowercased()
            return lowered == n || lowered.hasSuffix("." + n) || lowered.hasSuffix("_" + n)
        }
    }
}
