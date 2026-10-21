import Foundation

enum APIEndpoint {
    static let login         = "/auth/login"
    static let refresh       = "/auth/refresh"
    static let logout        = "/auth/logout"
    static let deleteAccount = "/auth/delete-account"
    static let profileUpdate = "/auth/profile-update"
    static let deviceToken   = "/auth/device-token"
    static let authMe        = "/auth/me"

    static let tripUpsert = "/trips/upsert"
    static let tripDetail = "/trips/detail"
    static let tripDelete = "/trips/delete"

    static let vehicleUpsert = "/vehicles/upsert"
    /// Весь гараж аккаунта одним ответом. `/vehicles/detail` не существует и не
    /// нужен: машин у человека единицы, а строка — это имя, пробег и горстка
    /// флагов. Спрашивается там же, где список путешествий, — при разрешении
    /// конфликта загрузки.
    static let vehicleList = "/vehicles/list"
    static let vehicleDelete = "/vehicles/delete"

    static let journeyUpsert = "/journeys/upsert"
    /// Весь список путешествий аккаунта. У путешествия нет `/detail`, как у
    /// поездки, и он не нужен: строка — это имя, две даты и горстка id, так
    /// что список из десятка таких дешевле одного трека. Спрашивается он в
    /// одном месте — при разрешении конфликта загрузки.
    static let journeyList = "/journeys/list"
    static let journeyDelete = "/journeys/delete"

    static let settingsUpsert = "/settings/upsert"

    static let photoUpload = "/photos/upload"
    static let photoURL    = "/photos/url"
    static let photoDelete = "/photos/delete"
    // Фотографии машины (0.6.4). Отдельные маршруты, а не `/photos/*` с
    // необязательным vehicleId: там вся проверка доступа построена вокруг
    // поездки и попутчиков, а у машины владелец ровно один.
    static let vehiclePhotoUpload = "/vehicles/photos/upload"
    static let vehiclePhotoDelete = "/vehicles/photos/delete"
    static let vehiclePhotoMain   = "/vehicles/photos/main"
    static let vehiclePhotoList   = "/vehicles/photos/list"

    /// Каталог секретов (0.7.0) — ПУБЛИЧНЫЙ маршрут: ни аккаунта, ни личных
    /// данных, одни усечённые хеши. `version` пустой не шлём вовсе: пустая
    /// строка на сервере значит «версии нет», и лишний параметр только сбивал
    /// бы с толку в логах.
    /// Удалённая конфигурация (0.9.0): флаги, минимальная версия, объявления.
    /// Публичная, без тела; `version` — то, что телефон уже знает.
    static func appConfig(version: String?) -> String {
        guard let version, !version.isEmpty else { return "/app/config" }
        let escaped = version.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) ?? version
        return "/app/config?version=\(escaped)"
    }
    /// Каталог по имени (0.9.0): `riddles`, `vehicles`. Тот же JSON, что
    /// лежит в бандле, — сервер отдаёт его целиком с хешем версии.
    static func remoteCatalog(_ name: String, version: String?) -> String {
        let base = "/app/catalog/\(name)"
        guard let version, !version.isEmpty else { return base }
        let escaped = version.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) ?? version
        return "\(base)?version=\(escaped)"
    }
    static func secretsCatalog(version: String?) -> String {
        guard let version, !version.isEmpty else { return "/secrets/catalog" }
        let escaped = version.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) ?? version
        return "/secrets/catalog?version=\(escaped)"
    }
    /// Раскрытие находки — уже с аккаунтом: история, счётчик, первооткрыватель.
    static let secretsReveal = "/secrets/reveal"
    /// «Стереть мои данные с сервера» для находок: один запрос вместо цикла —
    /// заявок у человека бывают сотни, и у сервера нет удаления по одной.
    static let secretsForgetAll = "/secrets/forget-all"

    /// «Плюс» (0.8.0). `attach` — привязка подписанной транзакции к аккаунту,
    /// `status` — что сервер о ней думает. Оба под JWT: подписка личная.
    static let plusAttach = "/plus/attach"
    static let plusStatus = "/plus/status"

    static let syncPull = "/sync/pull"
    static let syncPush = "/sync/push"
    static let syncManifest = "/sync/manifest"

    static let socialFeed       = "/social/feed"
    static let socialFollow     = "/social/follow"
    static let socialUnfollow   = "/social/unfollow"
    static let socialFollowers  = "/social/followers"
    static let socialFollowing  = "/social/following"
    static let socialReact      = "/social/react"
    static let socialUnreact    = "/social/unreact"
    static let socialShare      = "/social/share"
    static let socialSearch     = "/social/search"
    static let socialSuggested  = "/social/suggested"
    static let socialBlock      = "/social/block"
    static let socialUnblock    = "/social/unblock"
    static let socialBlocked    = "/social/blocked"
    static let socialReport     = "/social/report"
    static let socialReactions  = "/social/reactions"
    static let socialTrip       = "/social/trip"
    static let socialTripPhotos = "/social/trip/photos"
    static let socialComment       = "/social/comment"
    static let socialComments      = "/social/comments"
    static let socialCommentDelete = "/social/comment/delete"
    /// Чужое путешествие — шапка и плечи, одним ответом (0.6.8).
    static let socialJourney       = "/social/journey"
    /// Шаринг чужого путешествия — тот же ответ, что у `socialShare`
    /// (`SocialShareResponse`).
    static let socialShareJourney  = "/social/share-journey"

    /// Clubs waitlist — guest-callable, keyed by the device's local user id.
    static let groupsWaitlist      = "/groups/waitlist"
    static let groupsWaitlistJoin  = "/groups/waitlist/join"
    static let groupsWaitlistLeave = "/groups/waitlist/leave"

    static let notificationsFeed        = "/notifications/feed"
    static let notificationsUnreadCount = "/notifications/unread-count"
    static let notificationsMarkRead    = "/notifications/mark-read"

    /// Админка (0.9.0) — сервер пускает только `is_admin` (`ADMIN_ONLY`).
    static let adminSummary            = "/admin/summary"
    static let adminSubscriptions      = "/admin/subscriptions"
    static let adminEvents             = "/admin/events"
    static let adminFlags              = "/admin/flags"
    static let adminFlag               = "/admin/flag"

    static let notificationPrefsGet     = "/auth/notification-prefs/get"
    static let notificationPrefsUpdate  = "/auth/notification-prefs/update"

    static let companionsList          = "/companions/list"
    static let companionsCandidates    = "/companions/candidates"
    static let companionsInvite        = "/companions/invite"
    static let companionsRespond       = "/companions/respond"
    static let companionsRemove        = "/companions/remove"
    static let companionsInvitePreview = "/companions/invite-preview"
    static let companionsMyTrips       = "/companions/my-trips"

    static func userProfile(_ id: String) -> String { "/users/\(id)/profile" }
    /// Гараж другого человека (0.6.4) — только открытые машины.
    static func userGarage(_ id: String) -> String { "/users/\(id)/garage" }
    /// Одна машина чужого человека. Скрытая отвечает как несуществующая —
    /// ответ не должен подтверждать, что она есть.
    static func userVehicle(_ id: String, _ vehicleId: String) -> String {
        "/users/\(id)/vehicles/\(vehicleId)"
    }
    /// Все публичные поездки аккаунта с геометрией — источник чужой карты (0.6.3).
    /// Курсор по формату совпадает с лентой: `${startDate.toISOString()}|${id}`,
    /// поэтому его надо процентно экранировать (в нём есть `|` и `:`).
    static func userTrips(_ id: String, cursor: String? = nil, limit: Int? = nil,
                          vehicleId: String? = nil) -> String {
        var query: [String] = []
        if let limit { query.append("limit=\(limit)") }
        if let vehicleId { query.append("vehicleId=\(vehicleId)") }
        if let cursor, !cursor.isEmpty {
            let escaped = cursor.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics) ?? cursor
            query.append("cursor=\(escaped)")
        }
        let base = "/users/\(id)/trips"
        return query.isEmpty ? base : "\(base)?\(query.joined(separator: "&"))"
    }

    /// Карточки поездок профиля постранично (0.9.1) — продолжение десяти
    /// `recentTrips`, та же форма, что у ленты, тот же курсор.
    static func userProfileTrips(_ id: String, cursor: String? = nil, limit: Int? = nil) -> String {
        var query: [String] = []
        if let limit { query.append("limit=\(limit)") }
        if let cursor, !cursor.isEmpty {
            let escaped = cursor.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics) ?? cursor
            query.append("cursor=\(escaped)")
        }
        let base = "/users/\(id)/profile-trips"
        return query.isEmpty ? base : "\(base)?\(query.joined(separator: "&"))"
    }

    /// Курсор ленты для поездки — точь-в-точь `encodeFeedCursor` сервера:
    /// `toISOString()` (UTC, миллисекунды) и id в нижнем регистре. Сервер
    /// сравнивает кортеж `(start_date, id)` в базе, где uuid строчный, — и
    /// продолжить список с последней карточки профиля можно без лишнего
    /// запроса.
    static func feedCursor(startDate: Date, id: UUID) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return "\(f.string(from: startDate))|\(id.uuidString.lowercased())"
    }

    /// Список путешествий чужого профиля (0.6.8) — та же курсорная форма,
    /// что у `userTrips`.
    static func userJourneys(_ id: String, cursor: String? = nil, limit: Int? = nil) -> String {
        var query: [String] = []
        if let limit { query.append("limit=\(limit)") }
        if let cursor, !cursor.isEmpty {
            let escaped = cursor.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics) ?? cursor
            query.append("cursor=\(escaped)")
        }
        let base = "/users/\(id)/journeys"
        return query.isEmpty ? base : "\(base)?\(query.joined(separator: "&"))"
    }
}
