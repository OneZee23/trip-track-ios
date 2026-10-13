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
    var accountIdRead: KeychainRead { KeychainHelper.read(key: Keys.accountId) }

    /// Трёхзначное чтение для тех, кто по отсутствию токена принимает решение
    /// о судьбе сессии. `nil` из обычного геттера значит И «токена нет», И
    /// «keychain сейчас не читается» — а это разные вещи: во втором случае
    /// сессия жива, просто телефон не разблокирован после перезагрузки.
    var refreshTokenRead: KeychainRead { KeychainHelper.read(key: Keys.refreshToken) }
    var accessTokenRead: KeychainRead { KeychainHelper.read(key: Keys.accessToken) }

    func set(accessToken: String, refreshToken: String) {
        try? KeychainHelper.saveString(accessToken, for: Keys.accessToken)
        try? KeychainHelper.saveString(refreshToken, for: Keys.refreshToken)
    }

    func setAccountId(_ id: UUID) {
        try? KeychainHelper.saveString(id.uuidString, for: Keys.accountId)
    }

    /// Мягкая смерть сессии: протухший access уходит, refresh ОСТАЁТСЯ.
    /// Сервер держит осиротевший токен к повтору 30 суток, и удачный рефреш
    /// потом поднимает сессию молча. Полная чистка — только по кнопке
    /// человека, удалению аккаунта и бану (`clear()`).
    func clearAccessToken() {
        _ = KeychainHelper.delete(key: Keys.accessToken)
    }

    func clear() {
        _ = KeychainHelper.delete(key: Keys.accessToken)
        _ = KeychainHelper.delete(key: Keys.refreshToken)
        _ = KeychainHelper.delete(key: Keys.accountId)
    }
}
