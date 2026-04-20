import Foundation

enum APIError: Error, Equatable {
    case userNotAuth
    case invalidAppleToken(String)
    case invalidRefreshToken
    case conflictDetected(serverVersion: Int?, serverLastModifiedAt: Date?)
    case validationFailed(String)
    case tooManyRequests
    case tripNotFound
    case vehicleNotFound
    case photoNotFound
    case unknownServer(code: String, message: String)
    case network(URLError)
    case decoding(String)
    case invalidHTTPStatus(Int)
    case transport(String)

    static func from(code: String, message: String, serverVersion: Int?, serverLastModifiedAt: Date?) -> APIError {
        switch code {
        case "USER_NOT_AUTH":          return .userNotAuth
        case "INVALID_APPLE_TOKEN":    return .invalidAppleToken(message)
        case "INVALID_REFRESH_TOKEN":  return .invalidRefreshToken
        case "CONFLICT_DETECTED":      return .conflictDetected(serverVersion: serverVersion, serverLastModifiedAt: serverLastModifiedAt)
        case "VALIDATION_FAILED":      return .validationFailed(message)
        case "TOO_MANY_REQUESTS":      return .tooManyRequests
        case "TRIP_NOT_FOUND":         return .tripNotFound
        case "VEHICLE_NOT_FOUND":      return .vehicleNotFound
        case "PHOTO_NOT_FOUND":        return .photoNotFound
        default:                        return .unknownServer(code: code, message: message)
        }
    }
}
