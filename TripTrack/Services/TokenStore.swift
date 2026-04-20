import Foundation

final class TokenStore {
    static let shared = TokenStore()

    private enum Keys {
        static let accessToken  = "com.triptrack.auth.accessToken"
        static let refreshToken = "com.triptrack.auth.refreshToken"
        static let accountId    = "com.triptrack.auth.accountId"
    }

    var accessToken: String? { KeychainHelper.loadString(key: Keys.accessToken) }
    var refreshToken: String? { KeychainHelper.loadString(key: Keys.refreshToken) }
    var accountId: UUID? { KeychainHelper.loadString(key: Keys.accountId).flatMap(UUID.init) }

    func set(accessToken: String, refreshToken: String) {
        try? KeychainHelper.saveString(accessToken, for: Keys.accessToken)
        try? KeychainHelper.saveString(refreshToken, for: Keys.refreshToken)
    }

    func setAccountId(_ id: UUID) {
        try? KeychainHelper.saveString(id.uuidString, for: Keys.accountId)
    }

    func clear() {
        _ = KeychainHelper.delete(key: Keys.accessToken)
        _ = KeychainHelper.delete(key: Keys.refreshToken)
        _ = KeychainHelper.delete(key: Keys.accountId)
    }
}
