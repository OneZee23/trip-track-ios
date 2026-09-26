import XCTest
import CoreData
@testable import TripTrack

/// The production AuthService request, observed on the wire. The regression
/// was a valid POST carrying a new/stale phone's level 1 over an established
/// account, and earned XP reaching settings without ever reaching account.
@MainActor
final class ProfileProgressSyncTests: XCTestCase {
    private var pc: PersistenceController!
    private var settings: SettingsManager!
    private var defaults: UserDefaults!
    private var suite: String!
    private var session: URLSession!
    private var client: APIClient!
    private var savedKeychainService: String!
    private var savedNameLatch: Any?
    private var accountId: UUID!
    private let nameLatch = "com.triptrack.profile.syncConfirmed"
    private nonisolated(unsafe) static var profileBodies: [[String: Any]] = []

    override func setUp() async throws {
        try await super.setUp()
        _ = AuthService.shared
        savedKeychainService = KeychainHelper.service
        KeychainHelper.service = "com.triptrack.profile-progress-tests.\(UUID())"
        savedNameLatch = UserDefaults.standard.object(forKey: nameLatch)
        ProfileSyncLatch.markConfirmed()
        accountId = UUID()
        TokenStore.shared.setAccountId(accountId)
        TokenStore.shared.set(accessToken: "test-access", refreshToken: "test-refresh")
        try KeychainHelper.saveString("true", for: "com.triptrack.auth.isSignedIn")
        try KeychainHelper.saveString("Driver", for: "com.triptrack.auth.userName")
        try KeychainHelper.saveString("test-apple-id", for: "com.triptrack.auth.userIdentifier")
        AuthService.shared.loadFromKeychain()

        suite = "ProfileProgressSyncTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)
        pc = PersistenceController(inMemory: true)
        settings = SettingsManager(persistenceController: pc, unitStore: defaults, regionUnit: .km)
        MockURLProtocol.reset()
        Self.profileBodies = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        client = APIClient(session: session, tokenStore: TokenStore.shared)
    }

    override func tearDown() async throws {
        session?.invalidateAndCancel()
        session = nil
        client = nil
        MockURLProtocol.reset()
        Self.profileBodies = []
        TokenStore.shared.clear()
        for key in ["com.triptrack.auth.isSignedIn", "com.triptrack.auth.userName",
                    "com.triptrack.auth.userIdentifier"] {
            KeychainHelper.delete(key: key)
        }
        KeychainHelper.service = savedKeychainService
        if let savedNameLatch {
            UserDefaults.standard.set(savedNameLatch, forKey: nameLatch)
        } else {
            UserDefaults.standard.removeObject(forKey: nameLatch)
        }
        AuthService.shared.loadFromKeychain()
        settings = nil
        pc = nil
        defaults?.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        savedNameLatch = nil
        savedKeychainService = nil
        accountId = nil
        try await super.tearDown()
    }

    private func entity() throws -> UserSettingsEntity {
        let request: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        return try XCTUnwrap(pc.container.viewContext.fetch(request).first)
    }

    private func serve(level: Int = 1, xp: Int? = 0, invalidRead: Bool = false,
                       invalidWrite: Bool = false, readDelay: TimeInterval = 0) {
        let id = accountId.uuidString
        let xpField = xp.map { ",\"profileXp\":\($0)" } ?? ""
        let me = Data("{\"status\":\"ok\",\"payload\":{\"id\":\"\(id)\",\"isPublic\":true,\"profileLevel\":\(level)\(xpField)}}".utf8)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            if request.url!.path.hasSuffix("/auth/me") {
                if readDelay > 0 { Thread.sleep(forTimeInterval: readDelay) }
                return (response, invalidRead ? Data("[]".utf8) : me)
            }
            if request.url!.path.hasSuffix("/auth/profile-update"),
               let data = Self.bodyData(request),
               let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.profileBodies.append(body)
                if invalidWrite { return (response, Data("[]".utf8)) }
            }
            return (response, Data(#"{"status":"ok","payload":{}}"#.utf8))
        }
    }

    private nonisolated static func bodyData(_ request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    func testPersistedRewardsRepairAccountEvenWhenPublishedCacheAndNameLatchAreStale() async throws {
        let saved = try entity()
        saved.profileXP = 25_730
        saved.profileLevel = 21
        try pc.container.viewContext.save()
        XCTAssertEqual(settings.profileLevel, 1, "the profile screen has not reloaded")
        XCTAssertEqual(settings.profileXP, 0)
        serve()

        await AuthService.shared.syncProgressToServer(client: client, settings: settings)

        let body = try XCTUnwrap(Self.profileBodies.last)
        XCTAssertEqual(body["profileLevel"] as? Int, 21)
        XCTAssertEqual(body["profileXp"] as? Int, 25_730)
        XCTAssertNil(body["displayName"], "a reward retry must not replay old cosmetics")
        XCTAssertNil(body["avatarEmoji"])
        XCTAssertEqual(settings.profileLevel, 21)
        await AuthService.shared.syncProgressToServer(client: client, settings: settings)
        XCTAssertEqual(Self.profileBodies.count, 1, "an acknowledged snapshot is not pushed every foreground tick")

        saved.profileXP = 26_000
        await AuthService.shared.syncProgressToServer(client: client, settings: settings)
        XCTAssertEqual(Self.profileBodies.count, 2)
        XCTAssertEqual(Self.profileBodies.last?["profileXp"] as? Int, 26_000)
    }

    func testFreshPhoneReadsExistingAccountBeforeFullProfilePush() async throws {
        serve(level: 21, xp: 25_730)
        await AuthService.shared.syncProfileToServer(refreshFeedAfter: false, client: client, settings: settings)
        let body = try XCTUnwrap(Self.profileBodies.last)
        XCTAssertEqual(body["profileLevel"] as? Int, 21)
        XCTAssertEqual(body["profileXp"] as? Int, 25_730)
        XCTAssertEqual(try entity().profileXP, 25_730, "readback survives relaunch")
        XCTAssertEqual(try entity().profileLevel, 21)
        XCTAssertTrue(MockURLProtocol.recordedRequests.first?.url?.path.hasSuffix("/auth/me") == true)
    }

    func testEmptyPhoneNeverSendsAProgressResetAlongWithCosmetics() async throws {
        serve()
        await AuthService.shared.syncProfileToServer(refreshFeedAfter: false, client: client, settings: settings)
        let body = try XCTUnwrap(Self.profileBodies.last)
        XCTAssertNotNil(body["avatarEmoji"])
        for key in ["profileLevel", "profileXp", "currentStreak", "bestStreak"] {
            XCTAssertNil(body[key], key)
        }
    }

    func testOlderServerLevelWithoutXPKeepsXPUnknown() async throws {
        serve(level: 21, xp: nil)
        await AuthService.shared.syncProfileToServer(refreshFeedAfter: false, client: client, settings: settings)
        let body = try XCTUnwrap(Self.profileBodies.last)
        XCTAssertEqual(body["profileLevel"] as? Int, 21)
        XCTAssertNil(body["profileXp"], "zero must not clear XP absent from the old response")
        XCTAssertEqual(try entity().profileXP, 0, "do not manufacture threshold XP")
        XCTAssertEqual(try entity().profileLevel, 21)
    }

    func testFailedAccountReadOmitsProgressAndRetriesEvenAfterNameWasConfirmed() async throws {
        let saved = try entity()
        saved.profileXP = 200
        saved.profileLevel = 3
        serve(invalidRead: true)
        await AuthService.shared.syncProfileToServer(refreshFeedAfter: false, client: client, settings: settings)
        XCTAssertNil(try XCTUnwrap(Self.profileBodies.last)["profileLevel"])
        XCTAssertNil(Self.profileBodies.last?["profileXp"])

        serve(level: 21, xp: 25_730)
        await AuthService.shared.syncProgressToServer(client: client, settings: settings)
        XCTAssertEqual(Self.profileBodies.last?["profileLevel"] as? Int, 21)
        XCTAssertEqual(Self.profileBodies.last?["profileXp"] as? Int, 25_730)
    }

    func testRemoteProgressNeverLowersPersistedXPOrLevel() throws {
        let saved = try entity()
        saved.profileXP = 25_730
        saved.profileLevel = 21
        settings.applyRemoteProfileProgress(level: 1, xp: 0)
        XCTAssertEqual(saved.profileXP, 25_730)
        XCTAssertEqual(saved.profileLevel, 21)
    }

    func testFailedProgressWriteRetriesTheSameSnapshotUntilAcknowledged() async throws {
        let saved = try entity()
        saved.profileXP = 25_730
        saved.profileLevel = 21
        serve(invalidWrite: true)
        await AuthService.shared.syncProgressToServer(client: client, settings: settings)
        XCTAssertEqual(Self.profileBodies.count, 1)
        XCTAssertEqual(Self.profileBodies.last?["profileXp"] as? Int, 25_730)

        serve()
        await AuthService.shared.syncProgressToServer(client: client, settings: settings)
        XCTAssertEqual(Self.profileBodies.count, 2, "a failed POST must not acknowledge progress")
        XCTAssertEqual(Self.profileBodies.last?["profileXp"] as? Int, 25_730)
        XCTAssertEqual(Self.profileBodies.last?["profileLevel"] as? Int, 21)
        await AuthService.shared.syncProgressToServer(client: client, settings: settings)
        XCTAssertEqual(Self.profileBodies.count, 2, "only a successful POST closes the retry")
    }

    func testAccountSwitchDuringReadCannotApplyOrPushPreviousAccountsProgress() async throws {
        serve(level: 21, xp: 25_730, readDelay: 0.2)
        let task = Task {
            await AuthService.shared.syncProgressToServer(client: client, settings: settings)
        }
        // Let the old account's request reach the mock transport first.
        for _ in 0..<50 where MockURLProtocol.recordedRequests.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(MockURLProtocol.recordedRequests.isEmpty)
        TokenStore.shared.setAccountId(UUID())
        await task.value

        XCTAssertEqual(try entity().profileXP, 0)
        XCTAssertEqual(try entity().profileLevel, 1)
        XCTAssertTrue(Self.profileBodies.isEmpty)
    }
}
