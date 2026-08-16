import XCTest
import CoreData
@testable import TripTrack

/// `applyRemoteSettings` used to assign every field unconditionally.
///
/// That was survivable only because the delta cursor hid it: the server rarely
/// sent the settings row back. 0.6.1 removes that accident — the store-identity
/// stamp forces one full pull on every device, and the backend applies its
/// `last_modified_at > since` filter only `if (since)`, so a full pull ALWAYS
/// carries settings. Without a merge, the upgrade would have rolled back XP,
/// level, streak, theme and language for the entire fleet on the same day.
final class RemoteSettingsMergeTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    override func tearDown() {
        repo = nil
        pc = nil
        super.tearDown()
    }

    private func makeLocal(xp: Int64, level: Int32, best: Int32, modified: Date) -> UserSettingsEntity {
        let e = UserSettingsEntity(context: pc.container.viewContext)
        e.id = UUID()
        e.profileXP = xp
        e.profileLevel = level
        e.bestStreak = best
        e.lastModifiedAt = modified
        return e
    }

    private func payload(
        id: UUID, xp: Int, level: Int, best: Int, modified: Date,
        theme: String = "dark", language: String = "ru"
    ) -> SettingsSyncPayload {
        SettingsSyncPayload(
            id: id, avatarEmoji: "😎", themeMode: theme, language: language,
            distanceUnit: "km", volumeUnit: "liters", fuelConsumption: 7.8,
            fuelPrice: 56, fuelCurrency: "€", selectedVehicleId: nil,
            profileLevel: level, profileXp: xp, currentStreak: 0, bestStreak: best,
            lastTripDate: nil, conflictVersion: 1, lastModifiedAt: modified)
    }

    /// The exact shape of the incident, in reverse: a server row that is behind
    /// must not drag the phone's progress down to meet it.
    func testServerNeverLowersProgress() {
        let local = makeLocal(xp: 5000, level: 12, best: 9, modified: Date())
        repo.applyRemoteSettings(
            payload(id: local.id!, xp: 0, level: 1, best: 0,
                    modified: Date().addingTimeInterval(-3600)))

        XCTAssertEqual(local.profileXP, 5000)
        XCTAssertEqual(local.profileLevel, 12)
        XCTAssertEqual(local.bestStreak, 9)
    }

    /// Monotonic means monotonic — a genuinely ahead server still wins.
    func testServerRaisesProgressWhenItIsAhead() {
        let local = makeLocal(xp: 100, level: 2, best: 1, modified: Date().addingTimeInterval(-3600))
        repo.applyRemoteSettings(
            payload(id: local.id!, xp: 9000, level: 20, best: 30, modified: Date()))

        XCTAssertEqual(local.profileXP, 9000)
        XCTAssertEqual(local.profileLevel, 20)
        XCTAssertEqual(local.bestStreak, 30)
    }

    /// Preferences are not progress: newest write wins, and a stale row loses.
    func testStalePreferencesAreIgnored() {
        let local = makeLocal(xp: 0, level: 1, best: 0, modified: Date())
        local.themeMode = "light"
        local.language = "en"

        repo.applyRemoteSettings(
            payload(id: local.id!, xp: 0, level: 1, best: 0,
                    modified: Date().addingTimeInterval(-3600),
                    theme: "dark", language: "ru"))

        XCTAssertEqual(local.themeMode, "light")
        XCTAssertEqual(local.language, "en")
    }

    func testFreshPreferencesAreApplied() {
        let local = makeLocal(xp: 0, level: 1, best: 0, modified: Date().addingTimeInterval(-3600))
        local.themeMode = "light"
        local.language = "en"

        repo.applyRemoteSettings(
            payload(id: local.id!, xp: 0, level: 1, best: 0, modified: Date(),
                    theme: "dark", language: "ru"))

        XCTAssertEqual(local.themeMode, "dark")
        XCTAssertEqual(local.language, "ru")
    }

    /// Rewriting the local settings id from a STALE server row is what
    /// silently re-points `localUserId` — the identity every entity is stamped
    /// with. It may only move when the row it came from is the fresher one.
    func testStaleServerRowDoesNotRewriteTheLocalIdentity() {
        let local = makeLocal(xp: 0, level: 1, best: 0, modified: Date())
        let originalId = local.id!

        repo.applyRemoteSettings(
            payload(id: UUID(), xp: 0, level: 1, best: 0,
                    modified: Date().addingTimeInterval(-3600)))

        XCTAssertEqual(local.id, originalId)
    }

    /// First sync on a device that has never had a settings row: nothing local
    /// to protect, so the server row is adopted whole.
    func testAFirstEverSettingsRowIsAdoptedWhole() {
        let serverId = UUID()
        repo.applyRemoteSettings(
            payload(id: serverId, xp: 4200, level: 11, best: 7,
                    modified: Date().addingTimeInterval(-86_400)))

        let req: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        let saved = try? pc.container.viewContext.fetch(req).first
        XCTAssertEqual(saved?.id, serverId)
        XCTAssertEqual(saved?.profileXP, 4200)
    }
}
