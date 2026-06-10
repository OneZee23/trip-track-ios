import XCTest
import CoreData
@testable import TripTrack

/// Coverage for the v0.5.7 vehicle fixes:
///  * `CoreDataTripRepository.updateVehicle` reassigns / clears a saved trip's
///    vehicle, advances `lastModifiedAt`, and follows the same pendingUpload
///    flip rules as `updateTitle`/`updateNotes`.
///  * `TripManager.startTrip` carries the chosen vehicle into the in-memory
///    `activeTrip` — previously dropped, so the recording UI / any
///    `activeTrip.vehicleId` consumer saw nil.
@MainActor
final class VehicleAssignmentTests: XCTestCase {
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
        SettingsManager.shared.cloudSyncEnabled = false
        super.tearDown()
    }

    @discardableResult
    private func insertTrip(isPrivate: Bool = true,
                            syncStatus: SyncStatus = .synced,
                            vehicleId: UUID? = nil) -> UUID {
        let ctx = pc.container.viewContext
        let entity = TripEntity(context: ctx)
        let id = UUID()
        entity.id = id
        entity.userId = SettingsManager.shared.localUserId
        entity.startDate = Date()
        entity.endDate = Date().addingTimeInterval(600)
        entity.isPrivate = isPrivate
        entity.syncStatus = syncStatus.rawValue
        entity.vehicleId = vehicleId
        entity.lastModifiedAt = Date(timeIntervalSince1970: 0)
        try? ctx.save()
        return id
    }

    private func entity(_ id: UUID) -> TripEntity? {
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? pc.container.viewContext.fetch(req).first
    }

    // MARK: - updateVehicle

    func testUpdateVehicle_assignsVehicleId() {
        let id = insertTrip(vehicleId: nil)
        let car = UUID()
        repo.updateVehicle(for: id, vehicleId: car)
        XCTAssertEqual(repo.fetchTripDetail(id: id)?.vehicleId, car)
    }

    func testUpdateVehicle_clearsVehicleId() {
        let id = insertTrip(vehicleId: UUID())
        repo.updateVehicle(for: id, vehicleId: nil)
        XCTAssertNil(repo.fetchTripDetail(id: id)?.vehicleId)
    }

    func testUpdateVehicle_advancesLastModified() {
        let id = insertTrip(vehicleId: nil)
        repo.updateVehicle(for: id, vehicleId: UUID())
        let after = entity(id)?.lastModifiedAt ?? .distantPast
        XCTAssertGreaterThan(after, Date(timeIntervalSince1970: 0))
    }

    func testUpdateVehicle_publicTrip_flipsPendingUpload() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(isPrivate: false, syncStatus: .synced)
        repo.updateVehicle(for: id, vehicleId: UUID())
        XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.pendingUpload.rawValue)
    }

    func testUpdateVehicle_privateTripSyncOff_doesNotFlipPendingUpload() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(isPrivate: true, syncStatus: .synced)
        repo.updateVehicle(for: id, vehicleId: UUID())
        XCTAssertEqual(entity(id)?.syncStatus, SyncStatus.synced.rawValue)
    }

    // MARK: - startTrip carries the vehicle into activeTrip

    func testStartTrip_populatesActiveTripVehicleId() {
        let manager = TripManager(locationManager: LocationManager(),
                                  persistenceController: pc)
        let car = UUID()
        manager.startTrip(vehicleId: car)
        XCTAssertEqual(manager.activeTrip?.vehicleId, car)
    }
}
