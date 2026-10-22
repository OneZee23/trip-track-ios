import XCTest
@testable import TripTrack

@MainActor
final class ProfileJournalRulesTests: XCTestCase {
    private var settings: SettingsManager!
    private var saved: [String: Any] = [:]
    private let keys = ["com.triptrack.settings.profileBio", "profileBioDirty", "profilePinnedTrips", "pinnedTripsDirty"]

    override func setUp() async throws {
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        settings = SettingsManager(persistenceController: PersistenceController(inMemory: true))
        settings.wipeProfileJournal()
    }
    override func tearDown() async throws {
        for key in keys { UserDefaults.standard.set(saved[key], forKey: key) }
        settings = nil
    }

    func testBioDirtyProtectsUnsentEditThenAcceptsServer() {
        settings.applyRemoteJournal(bio: "Remote", pinnedTripIds: nil)
        XCTAssertEqual(settings.profileBio, "Remote")
        XCTAssertFalse(settings.profileBioDirty)
        settings.profileBio = "Local"
        XCTAssertTrue(settings.profileBioDirty)
        settings.applyRemoteJournal(bio: "Stale", pinnedTripIds: nil)
        XCTAssertEqual(settings.profileBio, "Local")
        settings.profileBioDirty = false
        settings.applyRemoteJournal(bio: nil, pinnedTripIds: nil)
        XCTAssertEqual(settings.profileBio, "Local", "Old server must not clear a bio")
        settings.applyRemoteJournal(bio: nil, pinnedTripIds: nil, bioProvided: true)
        XCTAssertEqual(settings.profileBio, "", "Explicit server null clears")
        XCTAssertFalse(settings.profileBioDirty)
    }

    func testPinnedLimitOrderAndUnpin() {
        let ids = (0..<4).map { _ in UUID() }
        for id in ids.prefix(3) { XCTAssertTrue(settings.togglePinnedTrip(id)) }
        XCTAssertFalse(settings.togglePinnedTrip(ids[3]))
        XCTAssertEqual(settings.pinnedTripIds, Array(ids.prefix(3)))
        XCTAssertTrue(settings.togglePinnedTrip(ids[1]))
        XCTAssertTrue(settings.togglePinnedTrip(ids[3]))
        XCTAssertEqual(settings.pinnedTripIds, [ids[0], ids[2], ids[3]])
        settings.applyRemoteJournal(bio: nil, pinnedTripIds: [])
        XCTAssertEqual(settings.pinnedTripIds.count, 3, "Dirty list wins over remote")
    }

    func testPrivateAndUnfinishedTripsAreDroppedButMissingOnesStay() {
        let trips = (0..<3).map { _ in Trip(endDate: Date(), isPrivate: false) }
        for trip in trips { settings.togglePinnedTrip(trip.id) }
        var privateTrip = trips[1]
        privateTrip.isPrivate = true
        // trips[2] is not in this phone's library at all (no cloud library,
        // or the pull has not arrived): absence is not proof of anything.
        settings.reconcilePinnedTrips([trips[0], privateTrip])
        XCTAssertEqual(settings.pinnedTripIds, [trips[0].id, trips[2].id])
        var unfinished = trips[0]
        unfinished.endDate = nil
        settings.reconcilePinnedTrips([unfinished])
        XCTAssertEqual(settings.pinnedTripIds, [trips[2].id])
        XCTAssertTrue(settings.pinnedTripsDirty)
    }

    func testAnEmptyLibraryKeepsPinsFromAnotherPhone() {
        let remote = [UUID(), UUID()]
        settings.applyRemoteJournal(bio: nil, pinnedTripIds: remote)
        settings.reconcilePinnedTrips([])
        XCTAssertEqual(settings.pinnedTripIds, remote)
        XCTAssertFalse(settings.pinnedTripsDirty)
    }

    func testCleanRemotePinnedOrderAndWipe() {
        let ids = (0..<4).map { _ in UUID() }
        settings.applyRemoteJournal(bio: "About", pinnedTripIds: ids)
        XCTAssertEqual(settings.pinnedTripIds, Array(ids.prefix(3)))
        XCTAssertFalse(settings.pinnedTripsDirty)
        settings.wipeProfileJournal()
        XCTAssertTrue(settings.pinnedTripIds.isEmpty)
        XCTAssertEqual(settings.profileBio, "")
        XCTAssertFalse(settings.profileBioDirty)
    }
}
