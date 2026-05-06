import Foundation

struct LoginRequest: Codable {
    let identityToken: String
    let localUserId: String
    let deviceName: String?
    /// Raw nonce that the client previously sent SHA-256-hashed to Apple via
    /// `ASAuthorizationAppleIDRequest.nonce`. Backend SHA-256s this and
    /// compares against the JWT's `nonce` claim — mismatch = replay attempt.
    /// Optional in the encoder for backward-compat with older builds, but
    /// the backend will start enforcing presence after rollout.
    let nonce: String?
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
