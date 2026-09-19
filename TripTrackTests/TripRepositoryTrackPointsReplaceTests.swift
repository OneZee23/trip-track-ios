import XCTest
import CoreData
@testable import TripTrack

/// `TripEntity.trackPoints` is an ORDERED relationship (`NSOrderedSet`), not
/// `NSSet`. `applyRemoteTrip` used to cast it straight to
/// `Set<TrackPointEntity>` — a cast that always fails and returns `nil` — so
/// the "delete existing points before writing the server's" branch never
/// ran. Local points from before the pull piled up alongside the server's
/// replacement set instead of being replaced by it.
final class TripRepositoryTrackPointsReplaceTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var tripId: UUID!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        tripId = UUID()
        trip.id = tripId
        trip.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        trip.endDate = trip.startDate!.addingTimeInterval(3_600)
        trip.isPrivate = true
        trip.syncStatus = SyncStatus.synced.rawValue

        for i in 0..<2 {
            let tp = TrackPointEntity(context: ctx)
            tp.id = UUID()
            tp.latitude = 45
            tp.longitude = 38 + Double(i)
            tp.timestamp = trip.startDate!.addingTimeInterval(Double(i) * 10)
            tp.trip = trip
        }
        try? ctx.save()
    }

    /// See «Ловушки» in CLAUDE.md: fields not nilled in tearDown outlive the
    /// test and can trip up an unrelated class later in the run.
    override func tearDown() {
        repo = nil
        pc = nil
        tripId = nil
        super.tearDown()
    }

    private func payload(trackPoints: [TrackPointPayload]?) -> TripSyncPayload {
        TripSyncPayload(
            id: tripId, title: "t", description: nil,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            distance: 1_000, maxSpeed: 20, averageSpeed: 15, fuelUsed: 0, elevation: 0,
            maxAltitude: nil, drivingTime: nil, stoppedTime: nil, region: nil,
            isPrivate: true, vehicleId: nil, fuelCurrency: nil, previewPolyline: nil,
            badgesJson: nil, xpEarned: 0,
            conflictVersion: 1, lastModifiedAt: Date(),
            serverCreatedAt: Date(), trackPoints: trackPoints, photos: nil)
    }

    func testServerTrackPointsReplaceLocalOnes() {
        let newPoint = TrackPointPayload(
            id: UUID(), latitude: 46, longitude: 39, altitude: 0, speed: 0,
            course: -1, horizontalAccuracy: 5, timestamp: Date(), isInterpolated: false)

        repo.applyRemoteTrip(payload(trackPoints: [newPoint]))

        guard let entity = repo.fetchEntity(id: tripId) else {
            return XCTFail("поездка не нашлась")
        }
        let points = entity.trackPoints?.array as? [TrackPointEntity] ?? []
        XCTAssertEqual(points.count, 1, "старые точки обязаны быть удалены, а не накоплены")
        XCTAssertEqual(points.first?.id, newPoint.id)
    }

    /// Pull delta omits track points entirely — local ones must survive.
    func testMissingTrackPointsKeyKeepsLocalPoints() {
        repo.applyRemoteTrip(payload(trackPoints: nil))

        guard let entity = repo.fetchEntity(id: tripId) else {
            return XCTFail("поездка не нашлась")
        }
        let points = entity.trackPoints?.array as? [TrackPointEntity] ?? []
        XCTAssertEqual(points.count, 2, "отсутствие ключа не должно трогать локальные точки")
    }
}
