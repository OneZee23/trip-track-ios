import XCTest
import CoreData
@testable import TripTrack

final class RecordingFinishPreviewTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    func testShortTripRequiresBothDistanceAndTimeBelowTheExistingThresholds() {
        XCTAssertEqual(reason(499.999, 119.999, 10), .tooShort)
        XCTAssertNil(reason(500, 119.999, 10))
        XCTAssertNil(reason(499.999, 120, 10))
        XCTAssertNil(reason(500, 120, 10))
    }

    func testSlowTripUsesStrictSpeedAndDurationBoundaries() {
        XCTAssertNil(reason(1000, 180, 0))
        XCTAssertEqual(reason(1000, 180.001, 14.999 / 3.6), .noDrivingSpeed)
        XCTAssertNil(reason(1000, 180.001, 15 / 3.6))
        XCTAssertNil(reason(1000, 300, 20 / 3.6))
    }

    func testEveryReasonMatchesTheExistingFinalTripRoute() {
        let samples: [(Double, Double, Double)] = [
            (0, 2, 0), (499, 119, 10), (500, 119, 10), (499, 120, 10),
            (0, 180, 0), (1000, 181, 0), (1000, 181, 15 / 3.6),
            (10000, 900, 25)
        ]
        for (distance, duration, speed) in samples {
            let trip = Trip(startDate: start, endDate: start.addingTimeInterval(duration),
                            distance: distance, maxSpeed: speed)
            let preview = preview(id: trip.id, distance: distance, duration: duration, speed: speed)
            XCTAssertEqual(preview.discardReason != nil, trip.isJunk)
            XCTAssertEqual(preview.discardReason != nil, TripWorldEntry.route(for: trip) == .discardJunk)
        }
    }

    func testCrossingATimeBoundaryRequiresANewConfirmation() {
        let id = UUID()
        let short = preview(id: id, distance: 100, duration: 119, speed: 0)
        let save = preview(id: id, distance: 100, duration: 120, speed: 0)
        let slow = preview(id: id, distance: 100, duration: 181, speed: 0)
        XCTAssertFalse(short.confirmsSameOutcome(as: save))
        XCTAssertFalse(save.confirmsSameOutcome(as: slow), "A previous Save tap must never accept a new discard")
        XCTAssertFalse(short.confirmsSameOutcome(as: slow), "The new reason also needs to be shown")
    }

    func testOrdinaryProgressDoesNotRequireRepeatedConfirmation() {
        let id = UUID()
        XCTAssertTrue(preview(id: id, distance: 1000, duration: 200, speed: 10)
            .confirmsSameOutcome(as: preview(id: id, distance: 1100, duration: 205, speed: 12)))
        XCTAssertTrue(preview(id: id, distance: 0, duration: 2, speed: 0)
            .confirmsSameOutcome(as: preview(id: id, distance: 0, duration: 5, speed: 0)))
        XCTAssertFalse(preview(id: UUID(), distance: 0, duration: 2, speed: 0)
            .confirmsSameOutcome(as: preview(id: UUID(), distance: 0, duration: 2, speed: 0)))
    }

    private func reason(_ distance: Double, _ duration: Double, _ speed: Double) -> TripJunkClassifier.Reason? {
        TripJunkClassifier.reason(distanceMeters: distance, durationSeconds: duration, maxSpeedMS: speed)
    }

    private func preview(id: UUID, distance: Double, duration: Double, speed: Double) -> RecordingFinishPreview {
        RecordingFinishPreview(tripID: id, endDate: start.addingTimeInterval(duration),
                               distance: distance, duration: duration, maxSpeed: speed)
    }
}

@MainActor
final class RecordingFinishManagerTests: XCTestCase {
    /// A parked tail and stale live statistics used to let a seemingly valid
    /// recording become junk only after stopTrip recalculated it. The dialog
    /// must see the final numbers before it makes a promise.
    func testPreviewUsesTheSameTrimAndOdometerAsFinishingWithoutMutatingRecording() async throws {
        let pc = PersistenceController(inMemory: true)
        // This test exercises finish-time statistics, not the external
        // geocoder or cloud sync. Keep naming local and wait for it before
        // releasing the in-memory store used by its MainActor task.
        let previousEnqueueAuthorization = SyncEnqueuer.isAuthorizedToEnqueue
        SyncEnqueuer.isAuthorizedToEnqueue = { false }
        defer { SyncEnqueuer.isAuthorizedToEnqueue = previousEnqueueAuthorization }
        let cachedLocality = "Recording preview fixture"
        let cachedStart = GeocodeCacheEntity(context: pc.container.viewContext)
        cachedStart.geohash5 = GeohashEncoder.encode(latitude: 45, longitude: 38, precision: 5)
        cachedStart.locality = cachedLocality
        cachedStart.cachedAt = Date()
        try pc.container.viewContext.save()

        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: nil)
        let entity = try XCTUnwrap(pc.container.viewContext.fetch(TripEntity.fetchRequest()).first)
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        entity.startDate = start
        entity.distance = 90_000
        entity.maxSpeed = 90
        let samples: [(Double, Double, Double)] = [(0, 45, 10), (30, 45.001, 10), (110, 45.001, 0)]
        for (seconds, latitude, speed) in samples {
            let point = TrackPointEntity(context: pc.container.viewContext)
            point.id = UUID()
            point.timestamp = start.addingTimeInterval(seconds)
            point.latitude = latitude
            point.longitude = 38
            point.speed = speed
            point.horizontalAccuracy = 8
            point.trip = entity
            entity.addToTrackPoints(point)
        }
        manager.isPaused = true

        let preview = try XCTUnwrap(manager.recordingFinishPreview(now: start.addingTimeInterval(300)))

        XCTAssertEqual(preview.endDate, start.addingTimeInterval(30))
        XCTAssertEqual(preview.duration, 30)
        XCTAssertLessThan(preview.distance, 500)
        XCTAssertEqual(preview.maxSpeed, 10)
        XCTAssertEqual(preview.discardReason, .tooShort)
        XCTAssertNil(entity.endDate, "Opening/cancelling the question must not finish the trip")
        XCTAssertEqual(entity.distance, 90_000, "Preview is read-only")
        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(manager.isPaused, "Returning to the recording must preserve Pause")

        let named = expectation(description: "Cached trip naming completed")
        let titleObservation = entity.observe(\.title, options: [.new]) { _, change in
            if (change.newValue ?? nil) == cachedLocality { named.fulfill() }
        }
        defer { titleObservation.invalidate() }

        let completed = try XCTUnwrap(manager.stopTrip(suggestedEndDate: preview.endDate))
        XCTAssertEqual(completed.endDate, preview.endDate)
        XCTAssertEqual(completed.distance, preview.distance, accuracy: 0.0001)
        XCTAssertEqual(completed.maxSpeed, preview.maxSpeed)
        XCTAssertEqual(completed.isJunk, preview.discardReason != nil)
        XCTAssertNil(manager.recordingFinishPreview(), "There must be no stale question after stopping")
        await fulfillment(of: [named], timeout: 2)
        XCTAssertEqual(entity.title, cachedLocality)
        await RawFixLog.shared.remove(tripId: completed.id)
        withExtendedLifetime((manager, pc)) {}
    }

    func testEmptyRecordingPreviewUsesTheSameTimeClampAsStop() throws {
        let pc = PersistenceController(inMemory: true)
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: nil)
        let start = try XCTUnwrap(manager.activeTrip?.startDate)
        let preview = try XCTUnwrap(manager.recordingFinishPreview(now: start.addingTimeInterval(-10)))
        XCTAssertEqual(preview.duration, 0)
        XCTAssertEqual(preview.endDate, start)
        XCTAssertEqual(preview.discardReason, .tooShort)
        _ = manager.stopTrip(suggestedEndDate: preview.endDate)
    }
}
