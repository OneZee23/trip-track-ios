import XCTest
import CoreData
@testable import TripTrack

/// The back-fills latch a UserDefaults flag when they are done. On the launch
/// that lost a real user's store they ran against zero rows, concluded there
/// was nothing to count, and latched anyway — so even once his 107 trips came
/// home, level and fog would have stayed at zero permanently. The flag said the
/// work was finished, and nothing ever reconsiders.
///
/// Latching on "I found nothing" records an accident as a decision.
final class BackfillLatchTests: XCTestCase {
    private var defaults: UserDefaults!
    private var pc: PersistenceController!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "backfill-\(UUID().uuidString)")
        pc = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        defaults = nil
        pc = nil
        super.tearDown()
    }

    private func makeSettings() -> UserSettingsEntity {
        let e = UserSettingsEntity(context: pc.container.viewContext)
        e.id = UUID()
        return e
    }

    private func trip(km: Double, region: String? = nil) -> Trip {
        Trip(startDate: Date(), endDate: Date(), distance: km * 1000, region: region)
    }

    // MARK: - Gamification

    func testGamificationBackfillDoesNotLatchOnAnEmptyLibrary() {
        let gm = GamificationManager(persistenceController: pc, defaults: defaults)
        let settings = makeSettings()

        gm.backfillIfNeeded(trips: [], settingsEntity: settings)

        XCTAssertFalse(defaults.bool(forKey: GamificationManager.backfillKey),
                       "an empty library means 'not yet', not 'nothing to do'")
    }

    /// The half that proves the fix matters: after the library comes back, the
    /// level actually gets computed.
    func testGamificationBackfillRunsAfterTheLibraryComesBack() {
        let gm = GamificationManager(persistenceController: pc, defaults: defaults)
        let settings = makeSettings()

        gm.backfillIfNeeded(trips: [], settingsEntity: settings)
        gm.backfillIfNeeded(trips: [trip(km: 120, region: "Bavaria")], settingsEntity: settings)

        XCTAssertGreaterThan(settings.profileXP, 0)
        XCTAssertTrue(defaults.bool(forKey: GamificationManager.backfillKey))
    }

    /// The change must not amount to deleting the latch: a second run on a
    /// profile that already has XP must not double it.
    func testGamificationBackfillStillLatchesAfterRealWork() {
        let gm = GamificationManager(persistenceController: pc, defaults: defaults)
        let settings = makeSettings()

        gm.backfillIfNeeded(trips: [trip(km: 120)], settingsEntity: settings)
        let afterFirst = settings.profileXP
        XCTAssertGreaterThan(afterFirst, 0)

        gm.backfillIfNeeded(trips: [trip(km: 120)], settingsEntity: settings)
        XCTAssertEqual(settings.profileXP, afterFirst)
    }

    // MARK: - Territory

    func testTerritoryBackfillDoesNotLatchWithoutTrackPoints() {
        let tm = TerritoryManager(persistenceController: pc, defaults: defaults)

        tm.backfillIfNeeded()

        XCTAssertFalse(defaults.bool(forKey: TerritoryManager.backfillKey),
                       "no points yet is not the same as no territory")
    }

    func testTerritoryBackfillLatchesOncePointsExist() {
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        trip.id = UUID()
        trip.startDate = Date()
        trip.endDate = Date()
        for i in 0..<3 {
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            p.latitude = 55.75 + Double(i) * 0.01
            p.longitude = 37.61 + Double(i) * 0.01
            p.timestamp = Date()
            p.trip = trip
        }

        let tm = TerritoryManager(persistenceController: pc, defaults: defaults)
        tm.backfillIfNeeded()

        XCTAssertTrue(defaults.bool(forKey: TerritoryManager.backfillKey))
    }
}
