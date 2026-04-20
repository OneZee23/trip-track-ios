import Foundation

enum APIEndpoint {
    static let login         = "/auth/login"
    static let refresh       = "/auth/refresh"
    static let logout        = "/auth/logout"
    static let deleteAccount = "/auth/delete-account"

    static let tripUpsert = "/trips/upsert"
    static let tripDetail = "/trips/detail"
    static let tripDelete = "/trips/delete"

    static let vehicleUpsert = "/vehicles/upsert"
    static let vehicleDelete = "/vehicles/delete"

    static let settingsUpsert = "/settings/upsert"

    static let photoUpload = "/photos/upload"
    static let photoURL    = "/photos/url"

    static let syncPull = "/sync/pull"
    static let syncPush = "/sync/push"

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

    static func userProfile(_ id: String) -> String { "/users/\(id)/profile" }
}
