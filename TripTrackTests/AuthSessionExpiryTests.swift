import XCTest
import AuthenticationServices
import UIKit
@testable import TripTrack

/// Soft session expiry (`AuthService.sessionExpired()`): a dead session must
/// ask for a fresh sign-in WITHOUT the destructive sign-out cascade — the
/// 2026-08-23 incident wiped the sync queue, disabled Cloud Sync, and left
/// trip #100 stranded on the phone. Never log a user out of their own data.
@MainActor
final class AuthSessionExpiryTests: XCTestCase {

    // Mirrors of AuthService's private keychain keys (stable API surface).
    private let kUserName = "com.triptrack.auth.userName"
    private let kUserIdentifier = "com.triptrack.auth.userIdentifier"
    private let kIsSignedIn = "com.triptrack.auth.isSignedIn"
    private let kSessionExpired = "com.triptrack.auth.sessionExpired"

    private var savedOps: KeychainOps!

    override func setUp() async throws {
        savedOps = KeychainHelper.ops
        TokenStore.shared.set(accessToken: "dead-access", refreshToken: "dead-refresh")
        try? KeychainHelper.saveString("true", for: kIsSignedIn)
        try? KeychainHelper.saveString("Тестовый Водитель", for: kUserName)
        try? KeychainHelper.saveString("apple-user-1", for: kUserIdentifier)
        KeychainHelper.delete(key: kSessionExpired)
        SyncQueue.shared.clearAll()
        // Поднять сессию в память: `userIdentifier` и `isSignedIn` живут в
        // синглтоне, а keychain мы засеяли только что.
        AuthService.shared.loadFromKeychain()
    }

    override func tearDown() async throws {
        KeychainHelper.ops = savedOps
        savedOps = nil
        AuthService.shared.isProtectedDataAvailableOverride = nil
        TokenStore.shared.clear()
        KeychainHelper.delete(key: kIsSignedIn)
        KeychainHelper.delete(key: kUserName)
        KeychainHelper.delete(key: kUserIdentifier)
        KeychainHelper.delete(key: kSessionExpired)
        SyncQueue.shared.clearAll()
        AuthService.shared.loadFromKeychain()
    }

    func testSessionExpiredDropsTokensButKeepsEverythingElse() {
        let cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        SyncQueue.shared.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))

        AuthService.shared.sessionExpired()

        // Session state: signed out + flagged for re-login, tokens gone.
        XCTAssertFalse(AuthService.shared.isSignedIn)
        XCTAssertTrue(AuthService.shared.needsReauth)
        XCTAssertNil(TokenStore.shared.accessToken)
        XCTAssertEqual(TokenStore.shared.refreshToken, "dead-refresh",
                       "refresh-токен переживает мягкую смерть: сервер держит его к повтору 30 суток")
        // The flag survives a relaunch.
        XCTAssertNotNil(KeychainHelper.loadString(key: kSessionExpired))

        // Everything the destructive sign-out used to nuke stays put.
        XCTAssertEqual(KeychainHelper.loadString(key: kUserName), "Тестовый Водитель",
                       "display name must survive session expiry")
        XCTAssertEqual(KeychainHelper.loadString(key: kUserIdentifier), "apple-user-1",
                       "Apple user id must survive session expiry")
        XCTAssertEqual(SettingsManager.shared.cloudSyncEnabled, cloudSyncBefore,
                       "Cloud Sync consent must survive session expiry")
        XCTAssertEqual(SyncQueue.shared.pendingCount, 1,
                       "pending sync ops must survive session expiry")
    }

    func testSessionExpiredIsIdempotent() {
        AuthService.shared.sessionExpired()
        AuthService.shared.sessionExpired() // second call must be a no-op

        XCTAssertTrue(AuthService.shared.needsReauth)
        XCTAssertNil(TokenStore.shared.accessToken)
    }

    /// Review finding: soft expiry preserves the previous user's sync queue,
    /// Cloud Sync consent, and identity — so a DIFFERENT Apple ID signing in
    /// afterwards must purge that state first, or user B inherits user A's
    /// pending uploads and consent.
    func testSignInWithDifferentAppleIdPurgesInheritedState() {
        let cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        defer { SettingsManager.shared.cloudSyncEnabled = cloudSyncBefore }
        SettingsManager.shared.cloudSyncEnabled = true
        SyncQueue.shared.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))

        AuthService.shared.prepareForIdentity("someone-else")

        XCTAssertEqual(SyncQueue.shared.pendingCount, 0, "previous user's queue must not drain into the new account")
        XCTAssertFalse(SettingsManager.shared.cloudSyncEnabled, "previous user's Cloud Sync consent must not carry over")
        XCTAssertNil(KeychainHelper.loadString(key: kUserName), "previous user's display name must not leak onto the new account")
    }

    func testSignInWithSameAppleIdKeepsState() {
        let cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        defer { SettingsManager.shared.cloudSyncEnabled = cloudSyncBefore }
        SettingsManager.shared.cloudSyncEnabled = true
        SyncQueue.shared.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))

        AuthService.shared.prepareForIdentity("apple-user-1") // same as setUp seeded

        XCTAssertEqual(SyncQueue.shared.pendingCount, 1, "same user re-signing in keeps their pending uploads")
        XCTAssertTrue(SettingsManager.shared.cloudSyncEnabled)
        XCTAssertEqual(KeychainHelper.loadString(key: kUserName), "Тестовый Водитель")
    }

    // MARK: - 0.7.0: приложение не разлогинивает человека само

    /// `INVALID_REFRESH_TOKEN` — это `sessionDeathHandler()`, то есть мягкая
    /// смерть. Она обязана оставить refresh-токен: сервер держит осиротевший
    /// токен к повтору 30 суток, и удачный рефреш поднимает сессию молча.
    func testInvalidRefreshTokenAsksForReauthButKeepsTheToken() {
        APIClient.shared.sessionDeathHandler()

        XCTAssertTrue(AuthService.shared.needsReauth)
        XCTAssertFalse(AuthService.shared.isSignedIn)
        XCTAssertEqual(TokenStore.shared.refreshToken, "dead-refresh")
        XCTAssertEqual(KeychainHelper.loadString(key: kUserIdentifier), "apple-user-1")
    }

    func testSuccessfulRefreshAfterSoftDeathRestoresSessionSilently() {
        AuthService.shared.sessionExpired()
        XCTAssertTrue(AuthService.shared.needsReauth)

        // Так делает APIClient после удачной ротации.
        TokenStore.shared.set(accessToken: "fresh-access", refreshToken: "fresh-refresh")
        APIClient.shared.sessionRecoveryHandler()

        XCTAssertTrue(AuthService.shared.isSignedIn, "сессия вернулась без единого нажатия")
        XCTAssertFalse(AuthService.shared.needsReauth)
        XCTAssertNotNil(KeychainHelper.loadString(key: kIsSignedIn))
        XCTAssertNil(KeychainHelper.loadString(key: kSessionExpired))
    }

    /// `.revoked` от Apple — мягкая смерть, а не выход. Проба креденшала это
    /// не решение человека, и цена ошибки несимметрична: карточка «Войти»
    /// против сноса очереди синка, consent и имени.
    func testRevokedAppleCredentialIsSoftNotASignOut() {
        SyncQueue.shared.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))

        AuthService.shared.applyCredentialState(.revoked)

        XCTAssertTrue(AuthService.shared.needsReauth)
        XCTAssertFalse(AuthService.shared.isSignedIn)
        XCTAssertEqual(KeychainHelper.loadString(key: kUserIdentifier), "apple-user-1",
                       "identity остаётся: выйти может только человек")
        XCTAssertEqual(KeychainHelper.loadString(key: kUserName), "Тестовый Водитель")
        XCTAssertEqual(SyncQueue.shared.pendingCount, 1)
        XCTAssertEqual(TokenStore.shared.refreshToken, "dead-refresh")
    }

    func testNotFoundAppleCredentialIsSoftEvenWithoutTokens() {
        TokenStore.shared.clear()

        AuthService.shared.applyCredentialState(.notFound)

        XCTAssertEqual(KeychainHelper.loadString(key: kUserIdentifier), "apple-user-1",
                       "dev-сборка законно видит .notFound у аккаунта, заведённого продовой")
        XCTAssertEqual(KeychainHelper.loadString(key: kUserName), "Тестовый Водитель")
    }

    /// Фоновый запуск по локации на телефоне, который перезагрузили и не
    /// разблокировали: keychain не читается. Сессия в памяти остаётся, а
    /// keychain перечитывается по уведомлению системы.
    func testKeychainUnavailableAtLaunchKeepsSessionAndReReadsLater() async throws {
        XCTAssertTrue(AuthService.shared.isSignedIn, "сессия поднята в setUp")

        var unavailable = savedOps!
        unavailable.copy = { _, _ in (errSecInteractionNotAllowed, nil) }
        KeychainHelper.ops = unavailable
        AuthService.shared.isProtectedDataAvailableOverride = { false }

        AuthService.shared.loadFromKeychain()

        XCTAssertTrue(AuthService.shared.isSignedIn, "недоступный keychain — не «сессии нет»")
        XCTAssertFalse(AuthService.shared.needsReauth)
        XCTAssertTrue(AuthService.shared.hydrationDeferred)

        KeychainHelper.ops = savedOps
        AuthService.shared.isProtectedDataAvailableOverride = nil
        NotificationCenter.default.post(
            name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(AuthService.shared.hydrationDeferred, "после разблокировки keychain перечитан")
        XCTAssertTrue(AuthService.shared.isSignedIn)
    }

    /// Единственный путь, который стирает ВСЁ, — кнопка человека. Сеть при
    /// этом не трогается: access-токена уже нет (мягкая смерть прошла), и
    /// `signOut` пропускает `/auth/logout`.
    func testUserSignOutClearsEverythingIncludingRefreshToken() async {
        AuthService.shared.sessionExpired()
        XCTAssertEqual(TokenStore.shared.refreshToken, "dead-refresh")

        await AuthService.shared.signOut()

        XCTAssertNil(TokenStore.shared.refreshToken, "по кнопке человека токен уходит")
        XCTAssertNil(TokenStore.shared.accessToken)
        XCTAssertNil(KeychainHelper.loadString(key: kUserIdentifier))
        XCTAssertNil(KeychainHelper.loadString(key: kUserName))
        XCTAssertNil(KeychainHelper.loadString(key: kSessionExpired))
        XCTAssertFalse(AuthService.shared.isSignedIn)
        XCTAssertFalse(AuthService.shared.needsReauth)
    }
}
