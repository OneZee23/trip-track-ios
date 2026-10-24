import Foundation

struct Drive2Link: Equatable {
    let url: URL
    let make: String
    let model: String

    init?(_ input: String) {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            input.range(
                of: #"^https?://[^/?#:]+(?:[/?#]|$)"#,
                options: [.regularExpression, .caseInsensitive]) != nil,
            let parts = URLComponents(string: input),
            let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = parts.host?.lowercased(),
            ["drive2.ru", "www.drive2.ru", "m.drive2.ru", "drive2.com", "www.drive2.com"].contains(host),
            parts.user == nil, parts.password == nil, parts.port == nil,
            let match = parts.percentEncodedPath.range(
                of: #"^/r/[a-z0-9_-]+/[a-z0-9_-]+/[0-9]+(?:/.*)?$"#, options: .regularExpression),
            match == parts.percentEncodedPath.startIndex..<parts.percentEncodedPath.endIndex
        else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/")
        make = String(path[1])
        model = String(path[2])
        let normalizedHost = host.hasSuffix(".com") ? "www.drive2.com" : "www.drive2.ru"
        guard let normalized = URL(string: "https://\(normalizedHost)/r/\(make)/\(model)/\(path[3])/"),
            normalized.absoluteString.count <= 200
        else { return nil }
        url = normalized
    }
}

/// Кому приглашение «Привязать бортжурнал DRIVE2» стоит прямо на странице
/// машины.
///
/// DRIVE2 — сервис русскоязычный, и за пределами СНГ его почти не знают.
/// Пустая строка второй под шапкой показывала немцу или бразильцу незнакомое
/// имя на самом видном месте (владелец, 23 окт 2026: «не сильно выпячивать,
/// у меня иностранная аудитория тоже есть»). Остальным привязка доступна из
/// «…» на странице машины, а УЖЕ привязанная ссылка видна всем: это то, что
/// человек сам положил в свой гараж.
///
/// Решают язык приложения ИЛИ регион телефона: русский в Германии и немецкий
/// интерфейс в Казахстане — оба вероятные читатели DRIVE2.
enum Drive2Audience {
    static let languages: Set<LanguageManager.Language> = [.ru, .uk, .kk]
    static let regions: Set<String> = ["RU", "BY", "KZ"]

    static func invitesOnPage(language: LanguageManager.Language, region: String?) -> Bool {
        languages.contains(language) || region.map { regions.contains($0.uppercased()) } == true
    }

    static func invitesOnPage(language: LanguageManager.Language) -> Bool {
        invitesOnPage(language: language, region: Locale.current.region?.identifier)
    }
}
