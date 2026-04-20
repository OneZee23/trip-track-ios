import Foundation

struct LoginRequest: Codable {
    let identityToken: String
    let localUserId: String
    let deviceName: String?
}

struct AccountDTO: Codable {
    let id: UUID
    let displayName: String?
    let email: String?
    let avatarEmoji: String
}

struct LoginResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let account: AccountDTO
    let isNewAccount: Bool
}

struct RefreshRequest: Codable {
    let refreshToken: String
}

struct RefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

struct EmptyRequest: Codable {}
struct EmptyResponse: Codable {}
