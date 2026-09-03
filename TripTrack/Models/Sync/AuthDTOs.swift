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
    /// Server's `account.show_on_public_map` (website-globe opt-in). Optional so
    /// decoding survives an older server that doesn't return it; when present it
    /// seeds the local toggle on sign-in (cross-device / fresh-install read-back).
    let showOnPublicMap: Bool?
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

/// `POST /auth/me` payload (`MeResponseDto` on the backend). The account page
/// needs `email` and `isPublic`; everything else is optional-decoded so the
/// struct survives older/newer server shapes without breaking the page.
/// A successful decode of this response is ALSO the capability signal that
/// the deployed server supports the account-privacy endpoints (F2 gating in
/// `CloudSyncView` — prod without `/auth/me` would silently fake-accept an
/// `isPublic` profile-update).
struct MeResponse: Codable {
    /// Видимость блоков публичного профиля (0.6.3). Опциональны: старый
    /// сервер этих ключей не шлёт, и их отсутствие означает «всё открыто».
    let countersPublic: Bool?
    let statsPublic: Bool?
    let mapPublic: Bool?
    let achievementsPublic: Bool?
    let id: UUID?
    let email: String?
    let displayName: String?
    let avatarEmoji: String?
    let profileBackground: String?
    let profileLevel: Int?
    let isPublic: Bool
    let showOnPublicMap: Bool?
    let notifyReactions: Bool?
    let notifyFollows: Bool?
    let notifyComments: Bool?
    let notifyWeeklyRecap: Bool?
    let createdAt: String?
}

struct EmptyRequest: Codable {}
struct EmptyResponse: Codable {}
