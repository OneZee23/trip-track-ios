import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

@MainActor
final class ManualTripSyncImportTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var tripId: UUID!
    private var owner: UUID?

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        tripId = UUID()
        owner = UUID()
    }

    override func tearDown() {
        owner = nil
        tripId = nil
        repo = nil
        pc = nil
        super.tearDown()
    }

    private func payload(points: [TrackPointPayload]? = nil, version: Int = 1,
                         source: TripOrigin? = .manual, id: UUID? = nil) -> TripSyncPayload {
        TripSyncPayload(
            id: id ?? tripId, title: "Web trip", description: nil,
            startDate: start, endDate: start.addingTimeInterval(600),
            distance: 1_111, maxSpeed: 1.8517, averageSpeed: 1.8517,
            fuelUsed: 0, elevation: 0, maxAltitude: nil, drivingTime: 600,
            stoppedTime: 0, region: nil, isPrivate: true, vehicleId: nil,
            fuelCurrency: nil, previewPolyline: nil, badgesJson: "[]", xpEarned: 0,
            conflictVersion: version, lastModifiedAt: start.addingTimeInterval(900),
            serverCreatedAt: start.addingTimeInterval(900), trackPoints: points,
            photos: nil, source: source, energyMode: "electric")
    }

    private func points(latitude: Double = 45.01) -> [TrackPointPayload] {
        [TrackPointPayload(id: UUID(), latitude: 45, longitude: 39,
                           altitude: 0, speed: 1.8517, course: 0,
                           horizontalAccuracy: -1, timestamp: start, isInterpolated: false),
         TrackPointPayload(id: UUID(), latitude: latitude, longitude: 39,
                           altitude: 0, speed: 1.8517, course: 0,
                           horizontalAccuracy: -1, timestamp: start.addingTimeInterval(600),
                           isInterpolated: false)]
    }

    private func importSummary() {
        repo.applyRemoteTrip(payload())
        repo.flushPendingApplies()
    }

    private func loader(fetch: @escaping (UUID) async throws -> TripSyncPayload,
                        afterLoad: @escaping (UUID) async -> Void = { _ in }) -> ManualTripTrackLoader {
        ManualTripTrackLoader(repository: repo, accountId: { [weak self] in self?.owner },
                              fetch: fetch, afterLoad: afterLoad)
    }

    func testFirstPullClassifiesManualSourceAndPreservesNoRewardRule() {
        importSummary()
        let trip = repo.fetchTripDetail(id: tripId)
        XCTAssertEqual(trip?.source, .manual)
        XCTAssertEqual(trip?.rewardKm, 0)
        XCTAssertEqual(trip?.energyMode, .electric)
        XCTAssertEqual(repo.fetchEntity(id: tripId)?.syncStatus, SyncStatus.synced.rawValue)
    }

    func testExistingUnsyncedOriginAndEnergyChoiceSurviveAConflictPull() throws {
        importSummary()
        let entity = try XCTUnwrap(repo.fetchEntity(id: tripId))
        entity.source = TripOrigin.recorded.rawValue
        entity.energyMode = TripEnergyMode.fuel.rawValue
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        repo.applyRemoteTrip(payload(version: 2))
        XCTAssertEqual(entity.source, TripOrigin.recorded.rawValue)
        XCTAssertEqual(entity.energyMode, TripEnergyMode.fuel.rawValue)
    }

    func testHydratesNegativeAccuracyPointsWithoutReplacingMetadataPhotosOrCheckpoints() async throws {
        importSummary()
        let entity = try XCTUnwrap(repo.fetchEntity(id: tripId))
        entity.title = "Local display title"
        let photo = TripPhotoEntity(context: pc.container.viewContext)
        photo.id = UUID(); photo.filename = "retained.jpg"; photo.timestamp = start
        photo.uploadStatus = 2; photo.trip = entity
        let checkpoint = TripCheckpointEntity(context: pc.container.viewContext)
        checkpoint.id = UUID(); checkpoint.timestamp = start; checkpoint.name = "Keep me"
        checkpoint.trip = entity
        try pc.container.viewContext.save()
        let remote = payload(points: points())
        var processed: [UUID] = []
        let subject = loader(fetch: { _ in remote }, afterLoad: { processed.append($0) })

        let trip = await subject.loadIfNeeded(id: tripId)

        XCTAssertEqual(trip?.trackPoints.count, 2)
        XCTAssertEqual(trip?.trackPoints.map(\.horizontalAccuracy), [-1, -1])
        XCTAssertTrue(trip?.trackPoints.allSatisfy(\.countsForDistance) ?? false)
        XCTAssertEqual(trip?.trackPoints.last?.latitude, 45.01)
        XCTAssertEqual(trip?.title, "Local display title")
        XCTAssertEqual(entity.photos?.count, 1)
        XCTAssertEqual(entity.checkpoints?.count, 1)
        XCTAssertEqual(entity.syncStatus, SyncStatus.synced.rawValue)
        XCTAssertEqual(entity.lastModifiedAt, remote.lastModifiedAt)
        XCTAssertTrue(entity.isTrackProcessed)
        XCTAssertEqual(processed, [tripId!])
    }

    func testNeverFetchesAgainWhenManualTrackAlreadyExists() async {
        repo.applyRemoteTrip(payload(points: points()))
        repo.flushPendingApplies()
        var calls = 0
        let subject = loader(fetch: { _ in calls += 1; return self.payload(points: self.points()) })
        let result = await subject.loadIfNeeded(id: tripId)
        XCTAssertNil(result)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(repo.fetchTripDetail(id: tripId)?.trackPoints.count, 2)
    }

    func testRefusesLateResponseAfterAccountSwitch() async {
        importSummary()
        let remote = payload(points: points())
        let subject = loader(fetch: { _ in self.owner = UUID(); return remote })
        let result = await subject.loadIfNeeded(id: tripId)
        XCTAssertNil(result)
        XCTAssertEqual(repo.fetchTripDetail(id: tripId)?.trackPoints.count, 0)
    }

    func testRefusesLateResponseAfterLocalEditDeletionOrNewerPull() async throws {
        for change in 0..<3 {
            tripId = UUID()
            importSummary()
            let remote = payload(points: points())
            let id = tripId!
            let subject = loader(fetch: { _ in
                let entity = self.repo.fetchEntity(id: id)!
                switch change {
                case 0:
                    entity.syncStatus = SyncStatus.pendingUpload.rawValue
                    entity.title = "Changed while fetching"
                case 1: entity.syncStatus = SyncStatus.pendingDelete.rawValue
                default: entity.conflictVersion = 2
                }
                return remote
            })
            let result = await subject.loadIfNeeded(id: id)
            XCTAssertNil(result)
            XCTAssertEqual(repo.fetchTripDetail(id: id)?.trackPoints.count, 0)
        }
    }

    func testRejectsForeignRecordedInvalidOrExcessiveGeometryWithoutPartialWrites() async {
        for change in 0..<5 {
            tripId = UUID()
            importSummary()
            let track = points()
            let remote: TripSyncPayload
            switch change {
            case 0: remote = payload(points: track, id: UUID())
            case 1: remote = payload(points: track, source: .recorded)
            case 2: remote = payload(points: points(latitude: 91))
            case 3: remote = payload(points: [track[0], track[0]])
            default:
                remote = payload(points: Array(repeating: track[0], count: ManualTripTrackLoader.maximumPoints + 1))
            }
            var aftermath = false
            let subject = loader(fetch: { _ in remote }, afterLoad: { _ in aftermath = true })
            let result = await subject.loadIfNeeded(id: tripId)
            XCTAssertNil(result)
            XCTAssertEqual(repo.fetchTripDetail(id: tripId)?.trackPoints.count, 0)
            XCTAssertFalse(aftermath)
        }
    }

    func testNetworkFailureKeepsSummaryAndAllowsNextOpeningToRetry() async {
        importSummary()
        var calls = 0
        let remote = payload(points: points())
        let subject = loader(fetch: { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            return remote
        })
        let first = await subject.loadIfNeeded(id: tripId)
        XCTAssertNil(first)
        XCTAssertEqual(repo.fetchTripDetail(id: tripId)?.distance, 1_111)
        let retry = await subject.loadIfNeeded(id: tripId)
        XCTAssertEqual(retry?.trackPoints.count, 2)
        XCTAssertEqual(calls, 2)
    }

    func testEditingAnUnhydratedManualSummaryDoesNotEraseTheServerTrack() throws {
        importSummary()
        let entity = try XCTUnwrap(repo.fetchEntity(id: tripId))
        entity.title = "Edited before opening"
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        let trip = try XCTUnwrap(repo.fetchTripDetail(id: tripId))
        let upload = TripSyncPayload(trip: trip, entity: entity, zone: nil)
        XCTAssertNil(upload.trackPoints, "Missing local geometry must not become an explicit deletion")
        XCTAssertEqual(upload.title, "Edited before opening")
        XCTAssertEqual(upload.source, .manual)
    }

    func testLoadedManualTrackInsidePrivacyZoneStillSendsExplicitDeletion() throws {
        repo.applyRemoteTrip(payload(points: points()))
        repo.flushPendingApplies()
        let entity = try XCTUnwrap(repo.fetchEntity(id: tripId))
        let trip = try XCTUnwrap(repo.fetchTripDetail(id: tripId))
        let upload = TripSyncPayload(trip: trip, entity: entity,
            zone: (centre: CLLocationCoordinate2D(latitude: 45, longitude: 39), radius: 5_000))
        XCTAssertNotNil(upload.trackPoints)
        XCTAssertEqual(upload.trackPoints?.count, 0)
    }

    func testCancelledScreenCannotAdoptALateTrack() async {
        importSummary()
        let remote = payload(points: points())
        let subject = loader(fetch: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return remote
        })
        let id = tripId!
        let task = Task { await subject.loadIfNeeded(id: id) }
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(repo.fetchTripDetail(id: id)?.trackPoints.count, 0)
    }
}
