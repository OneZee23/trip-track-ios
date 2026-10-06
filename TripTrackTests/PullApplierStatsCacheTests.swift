import XCTest
import CoreData
@testable import TripTrack

/// Exercise the real pull boundary: a trip/photo edit must reach the next
/// cached library read even when count and newest start date are unchanged.
/// PullApplier uses the shared store, so only this test's unique rows are
/// created and removed; no account settings, files or other trips are reset.
@MainActor
final class PullApplierStatsCacheTests: XCTestCase {
    private var repo: CoreDataTripRepository!
    private var applier: PullApplier!
    private var tripId: UUID!
    private var photoId: UUID!
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        try await super.setUp()
        StatsCache.invalidate()
        repo = CoreDataTripRepository()
        applier = PullApplier()
        tripId = UUID()
        photoId = UUID()
        applier.apply(response(trips: [tripPayload(title: "Before pull")]))
    }

    override func tearDown() async throws {
        // Release fields even if fetching or saving the cleanup fails.
        defer {
            StatsCache.invalidate()
            applier = nil
            repo = nil
            tripId = nil
            photoId = nil
        }
        let context = PersistenceController.shared.container.viewContext
        if let photoId {
            let request: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", photoId as CVarArg)
            for entity in try context.fetch(request) { context.delete(entity) }
        }
        if let tripId, let entity = repo?.fetchEntity(id: tripId) {
            context.delete(entity)
        }
        try context.save()
        try await super.tearDown()
    }

    func testRemoteTripEditReachesCachedLibraryWithoutChangingCountOrDate() async throws {
        let before = try await cachedTrip()
        let count = repo.fetchTripCount()
        let lastDate = repo.fetchLastTripDate()
        XCTAssertEqual(before.title, "Before pull")
        XCTAssertTrue(before.isPrivate)
        XCTAssertEqual(before.xpEarned, 10)

        applier.apply(response(trips: [tripPayload(
            title: "From the other phone", isPrivate: false, xp: 250,
            region: "Krasnodar Krai", version: 2)]))

        XCTAssertEqual(repo.fetchTripCount(), count)
        XCTAssertEqual(repo.fetchLastTripDate(), lastDate)
        let after = try await cachedTrip()
        XCTAssertEqual(after.title, "From the other phone")
        XCTAssertFalse(after.isPrivate)
        XCTAssertEqual(after.xpEarned, 250)
        XCTAssertEqual(after.region, "Krasnodar Krai")
    }

    func testPhotoOnlyPullRefreshesPhotoMetadataWithoutChangingTripKeys() async throws {
        applier.apply(response(photos: [photoPayload(caption: "Before pull")]))
        let before = try await cachedTrip()
        let count = repo.fetchTripCount()
        let lastDate = repo.fetchLastTripDate()
        XCTAssertEqual(before.photos.first?.caption, "Before pull")

        applier.apply(response(photos: [photoPayload(caption: "From the other phone")]))

        XCTAssertEqual(repo.fetchTripCount(), count)
        XCTAssertEqual(repo.fetchLastTripDate(), lastDate)
        let after = try await cachedTrip()
        XCTAssertEqual(after.photos.map(\.id), [photoId!])
        XCTAssertEqual(after.photos.first?.caption, "From the other phone")
    }

    func testPhotoOnlyDeletionRemovesPhotoFromCachedTrip() async throws {
        applier.apply(response(photos: [photoPayload(caption: "Will be removed")]))
        let before = try await cachedTrip()
        let count = repo.fetchTripCount()
        let lastDate = repo.fetchLastTripDate()
        XCTAssertEqual(before.photos.count, 1)

        applier.apply(response(deletedPhotos: [photoId]))

        XCTAssertEqual(repo.fetchTripCount(), count)
        XCTAssertEqual(repo.fetchLastTripDate(), lastDate)
        let after = try await cachedTrip()
        XCTAssertTrue(after.photos.isEmpty)
    }

    func testEmptyPullPreservesWarmLibraryCache() async throws {
        let before = await readCachedLibrary()
        let count = repo.fetchTripCount()
        let lastDate = repo.fetchLastTripDate()
        XCTAssertTrue(before.contains { $0.id == tripId })

        applier.apply(response())

        let cached = try XCTUnwrap(StatsCache.tripsIfValid(
            currentCount: count, currentLastDate: lastDate),
            "An empty pull must not force the whole library to be fetched again")
        XCTAssertEqual(cached.map(\.id), before.map(\.id))
        XCTAssertEqual(cached.first { $0.id == tripId }?.title, "Before pull")
    }

    /// Same cache-hit/fresh-background-read path as profile aggregates,
    /// without constructing a view or posting a UI notification.
    private func readCachedLibrary() async -> [Trip] {
        let count = repo.fetchTripCount()
        let lastDate = repo.fetchLastTripDate()
        if let cached = StatsCache.tripsIfValid(currentCount: count, currentLastDate: lastDate) {
            return cached
        }
        let trips = await repo.fetchAllTripsAsync()
        StatsCache.update(trips: trips, count: count, lastDate: lastDate)
        return trips
    }

    private func cachedTrip() async throws -> Trip {
        let trips = await readCachedLibrary()
        return try XCTUnwrap(trips.first { $0.id == tripId })
    }

    private func tripPayload(
        title: String, isPrivate: Bool = true, xp: Int = 10,
        region: String? = nil, version: Int = 1
    ) -> TripSyncPayload {
        TripSyncPayload(
            id: tripId, title: title, description: nil,
            startDate: start, endDate: start.addingTimeInterval(3_600),
            distance: 10_000, maxSpeed: 20, averageSpeed: 15, fuelUsed: 0, elevation: 0,
            maxAltitude: nil, drivingTime: nil, stoppedTime: nil, region: region,
            isPrivate: isPrivate, vehicleId: nil, fuelCurrency: nil, previewPolyline: nil,
            badgesJson: nil, xpEarned: xp, conflictVersion: version,
            lastModifiedAt: start.addingTimeInterval(Double(version) * 7_200),
            serverCreatedAt: start, trackPoints: nil, photos: nil)
    }

    private func photoPayload(caption: String) -> PhotoSyncPayload {
        PhotoSyncPayload(
            id: photoId, tripId: tripId, filename: "\(photoId.uuidString).jpg",
            caption: caption, timestamp: start.addingTimeInterval(600),
            remoteUrl: nil, thumbnailUrl: nil, sortOrder: 0,
            uploadStatus: PhotoUploadStatus.uploaded.rawValue,
            lastModifiedAt: start.addingTimeInterval(7_200))
    }

    private func response(
        trips: [TripSyncPayload] = [], photos: [PhotoSyncPayload] = [],
        deletedPhotos: [UUID] = []
    ) -> SyncPullResponse {
        SyncPullResponse(
            trips: .init(upserted: trips, deleted: []),
            vehicles: .init(upserted: [], deleted: []),
            photos: .init(upserted: photos, deleted: deletedPhotos),
            settings: nil, serverTime: "2026-10-02T06:00:00.000Z", ownedCounts: nil,
            journeys: nil, discoveries: nil)
    }
}
