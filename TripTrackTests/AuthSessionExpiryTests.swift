import XCTest
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

    override func setUp() async throws {
        TokenStore.shared.set(accessToken: "dead-access", refreshToken: "dead-refresh")
        try? KeychainHelper.saveString("true", for: kIsSignedIn)
        try? KeychainHelper.saveString("Тестовый Водитель", for: kUserName)
        try? KeychainHelper.saveString("apple-user-1", for: kUserIdentifier)
        SyncQueue.shared.clearAll()
    }

    override func tearDown() async throws {
        TokenStore.shared.clear()
        KeychainHelper.delete(key: kIsSignedIn)
        KeychainHelper.delete(key: kUserName)
        KeychainHelper.delete(key: kUserIdentifier)
        KeychainHelper.delete(key: kSessionExpired)
        SyncQueue.shared.clearAll()
    }

    func testSessionExpiredDropsTokensButKeepsEverythingElse() {
        let cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        SyncQueue.shared.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))

        AuthService.shared.sessionExpired()

        // Session state: signed out + flagged for re-login, tokens gone.
        XCTAssertFalse(AuthService.shared.isSignedIn)
        XCTAssertTrue(AuthService.shared.needsReauth)
        XCTAssertNil(TokenStore.shared.accessToken)
        XCTAssertNil(TokenStore.shared.refreshToken)
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
}
