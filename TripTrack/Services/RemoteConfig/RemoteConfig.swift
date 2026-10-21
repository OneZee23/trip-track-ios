import Foundation

/// Удалённая конфигурация (0.9.0) — то, что меняется без новой версии и без
/// ревью: флаги, минимальная версия, объявления. Владелец 13 окт 2026: «чтобы
/// по тысяче раз не выпускать и не ждать ревью».
///
/// Формат — ответ `GET /app/config` (`trip-track-backend`,
/// `src/modules/app-config`). Сервер уже отбросил всё кривое, но телефон
/// второй раз не доверяет никому: незнакомое поле и незнакомый флаг
/// пропускаются, а не роняют разбор.
struct RemoteConfig: Codable, Equatable {
    var flags: [String: Bool] = [:]
    var update: UpdatePolicy = UpdatePolicy()
    var announcements: [Announcement] = []

    struct UpdatePolicy: Codable, Equatable {
        /// Ниже — карточка «Обновите приложение», её можно закрыть.
        var recommended: String?
        /// Ниже — та же карточка без крестика. Приложение при этом работает.
        var required: String?
        var message: LocalizedText?
    }

    struct Announcement: Codable, Equatable, Identifiable {
        enum Placement: String, Codable { case feed, me }
        let id: String
        let placement: Placement
        let title: LocalizedText
        let body: LocalizedText
        var action: Action?
        var startsAt: Date?
        var endsAt: Date?
        var minVersion: String?
        var maxVersion: String?

        struct Action: Codable, Equatable {
            let label: LocalizedText
            let url: URL
        }
    }

    /// Текст на языках приложения; `en` обязателен и им откатывается всё.
    struct LocalizedText: Codable, Equatable {
        let values: [String: String]

        init(_ values: [String: String]) { self.values = values }

        init(from decoder: Decoder) throws {
            values = try decoder.singleValueContainer().decode([String: String].self)
            guard let en = values["en"], !en.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "localized text without en"))
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(values)
        }

        func text(_ language: LanguageManager.Language) -> String {
            values[language.rawValue] ?? values["en"] ?? ""
        }
    }

    init() {}

    /// Терпимый разбор: одно кривое объявление не отменяет остальные, а
    /// незнакомое место показа (`placement` из будущей версии) — пропускается.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flags = (try? c.decode([String: Bool].self, forKey: .flags)) ?? [:]
        update = (try? c.decode(UpdatePolicy.self, forKey: .update)) ?? UpdatePolicy()
        var list: [Announcement] = []
        if var items = try? c.nestedUnkeyedContainer(forKey: .announcements) {
            while !items.isAtEnd {
                if let item = try? items.decode(Announcement.self) { list.append(item) }
                else { _ = try? items.decode(Skip.self) }
            }
        }
        announcements = list
    }

    private struct Skip: Decodable {}
    private enum CodingKeys: String, CodingKey { case flags, update, announcements }
}

extension RemoteConfig {
    /// Нужно ли обновиться приложению этой версии. `nil` — не нужно.
    func updateNeed(appVersion: String) -> UpdateNeed? {
        if let required = update.required, AppVersion.compare(appVersion, required) < 0 { return .required }
        if let recommended = update.recommended, AppVersion.compare(appVersion, recommended) < 0 { return .recommended }
        return nil
    }

    enum UpdateNeed: Equatable { case recommended, required }

    /// Объявления для места показа, отобранные по датам и версии приложения.
    func announcements(for placement: Announcement.Placement, appVersion: String, now: Date) -> [Announcement] {
        announcements.filter { a in
            guard a.placement == placement else { return false }
            if let start = a.startsAt, now < start { return false }
            if let end = a.endsAt, now > end { return false }
            if let min = a.minVersion, AppVersion.compare(appVersion, min) < 0 { return false }
            if let max = a.maxVersion, AppVersion.compare(appVersion, max) > 0 { return false }
            return true
        }
    }
}

/// «0.9.0» < «0.10.0» — по числам, не по строке.
enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let d = (i < pa.count ? pa[i] : 0) - (i < pb.count ? pb[i] : 0)
            if d != 0 { return d < 0 ? -1 : 1 }
        }
        return 0
    }
}
