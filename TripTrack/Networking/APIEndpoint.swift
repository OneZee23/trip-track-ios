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
    static let vehicleDelete = "/vehicles/delete"

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

    /// Clubs waitlist — guest-callable, keyed by the device's local user id.
    static let groupsWaitlist      = "/groups/waitlist"
    static let groupsWaitlistJoin  = "/groups/waitlist/join"
    static let groupsWaitlistLeave = "/groups/waitlist/leave"

    static let notificationsFeed        = "/notifications/feed"
    static let notificationsUnreadCount = "/notifications/unread-count"
    static let notificationsMarkRead    = "/notifications/mark-read"

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
}
