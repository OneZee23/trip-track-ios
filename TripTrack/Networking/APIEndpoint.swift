import Foundation

enum APIEndpoint {
    static let login   = "/auth/login"
    static let refresh = "/auth/refresh"
    static let logout  = "/auth/logout"

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
}
