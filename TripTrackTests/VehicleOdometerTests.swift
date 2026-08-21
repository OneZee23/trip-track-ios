import XCTest
import CoreData
@testable import TripTrack

/// A vehicle's odometer used to be a pure accumulator: `+= trip.distanceKm`
/// once, at the moment a trip finished, and never touched again. Nothing
/// recomputed it, so every later change to the trips underneath it drifted the
/// number further from the truth.
///
/// A real user found it the obvious way: he moved a trip from one car to
/// another and the kilometres stayed on the first one. The same flaw is why his
/// garage read 950 km across four cars while his library held 131 trips — the
/// trips came back from the server, the odometers did not follow.
final class VehicleOdometerTests: XCTestCase {
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

    @discardableResult
    private func makeVehicle(odometerKm: Double = 0) -> VehicleEntity {
        let v = VehicleEntity(context: pc.container.viewContext)
        v.id = UUID()
        v.name = "Car"
        v.odometerKm = odometerKm
        v.vehicleLevel = 1
        return v
    }

    @discardableResult
    private func makeTrip(km: Double, vehicle: VehicleEntity?) -> TripEntity {
        let t = TripEntity(context: pc.container.viewContext)
        t.id = UUID()
        t.startDate = Date()
        t.endDate = Date()
        t.distance = km * 1000          // the column is metres
        t.vehicleId = vehicle?.id
        t.syncStatus = SyncStatus.synced.rawValue
        return t
    }

    // MARK: - The reported bug

    func testMovingATripToAnotherCarMovesItsKilometres() {
        let a = makeVehicle()
        let b = makeVehicle()
        let trip = makeTrip(km: 300, vehicle: a)
        repo.recomputeOdometers(forVehicles: [a.id!, b.id!])
        XCTAssertEqual(a.odometerKm, 300, accuracy: 0.001)
        XCTAssertEqual(b.odometerKm, 0, accuracy: 0.001)

        repo.updateVehicle(for: trip.id!, vehicleId: b.id!)

        XCTAssertEqual(a.odometerKm, 0, accuracy: 0.001, "kilometres must leave the old car")
        XCTAssertEqual(b.odometerKm, 300, accuracy: 0.001, "and arrive at the new one")
    }

    /// Detaching a trip from every car empties the old one without crediting
    /// anybody.
    func testClearingTheVehicleTakesTheKilometresAway() {
        let a = makeVehicle()
        let trip = makeTrip(km: 120, vehicle: a)
        repo.recomputeOdometers(forVehicles: [a.id!])
        XCTAssertEqual(a.odometerKm, 120, accuracy: 0.001)

        repo.updateVehicle(for: trip.id!, vehicleId: nil)

        XCTAssertEqual(a.odometerKm, 0, accuracy: 0.001)
    }

    func testLevelFollowsTheRecomputedOdometer() {
        let a = makeVehicle()
        makeTrip(km: 250, vehicle: a)      // level 2 starts at 100 km, level 3 at 300

        repo.recomputeOdometers(forVehicles: [a.id!])

        XCTAssertEqual(a.odometerKm, 250, accuracy: 0.001)
        XCTAssertEqual(Int(a.vehicleLevel), VehicleLevelSystem.level(for: 250))
    }

    // MARK: - Deletion

    /// A deleted trip must stop counting. Soft delete hides the trip from the
    /// user, so its kilometres have to leave the odometer at the same moment.
    func testDeletingATripSubtractsItsKilometres() {
        let a = makeVehicle()
        let keep = makeTrip(km: 100, vehicle: a)
        let drop = makeTrip(km: 400, vehicle: a)
        drop.serverCreatedAt = Date()      // forces the soft-delete path
        repo.recomputeOdometers(forVehicles: [a.id!])
        XCTAssertEqual(a.odometerKm, 500, accuracy: 0.001)

        repo.deleteTrip(id: drop.id!)

        XCTAssertEqual(a.odometerKm, 100, accuracy: 0.001)
        XCTAssertNotNil(repo.fetchEntity(id: keep.id!))
    }

    // MARK: - Recovery

    /// The state a real user was left in: trips restored from the server,
    /// odometers still holding whatever they had accumulated before the loss.
    func testGlobalRecomputeFixesDriftedOdometers() {
        let a = makeVehicle(odometerKm: 341)
        let b = makeVehicle(odometerKm: 301)
        makeTrip(km: 1000, vehicle: a)
        makeTrip(km: 500, vehicle: a)
        makeTrip(km: 800, vehicle: b)

        repo.recomputeAllVehicleOdometers()

        XCTAssertEqual(a.odometerKm, 1500, accuracy: 0.001)
        XCTAssertEqual(b.odometerKm, 800, accuracy: 0.001)
    }

    /// Safety rail. If the library is empty the odometers are not evidence of
    /// drift — they are the only surviving record. Zeroing them there would
    /// repeat the very mistake this release exists to fix.
    func testGlobalRecomputeDoesNothingWhenThereAreNoTrips() {
        let a = makeVehicle(odometerKm: 341)

        repo.recomputeAllVehicleOdometers()

        XCTAssertEqual(a.odometerKm, 341, accuracy: 0.001)
    }

    /// A car nobody has driven yet reads zero — but only when other trips
    /// prove the library is really there.
    func testACarWithNoTripsReadsZeroOnceTheLibraryExists() {
        let driven = makeVehicle(odometerKm: 0)
        let idle = makeVehicle(odometerKm: 999)
        makeTrip(km: 200, vehicle: driven)

        repo.recomputeAllVehicleOdometers()

        XCTAssertEqual(driven.odometerKm, 200, accuracy: 0.001)
        XCTAssertEqual(idle.odometerKm, 0, accuracy: 0.001)
    }

    /// An unfinished recording has no distance worth counting yet.
    func testAnInProgressRecordingIsNotCounted() {
        let a = makeVehicle()
        makeTrip(km: 100, vehicle: a)
        let recording = makeTrip(km: 50, vehicle: a)
        recording.endDate = nil

        repo.recomputeAllVehicleOdometers()

        XCTAssertEqual(a.odometerKm, 100, accuracy: 0.001)
    }
}
