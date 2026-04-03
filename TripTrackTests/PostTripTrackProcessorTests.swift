import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

final class PostTripTrackProcessorTests: XCTestCase {

    private var persistenceController: PersistenceController!
    private var processor: PostTripTrackProcessor!

    override func setUp() {
        super.setUp()
        persistenceController = PersistenceController.preview
        processor = PostTripTrackProcessor(persistenceController: persistenceController)
    }

    // MARK: - Helpers

    private func createTrip(
        points: [(lat: Double, lon: Double, speed: Double, course: Double, timestamp: Date)],
        endDate: Date? = Date()
    ) -> UUID {
        let context = persistenceController.container.viewContext
        let trip = TripEntity(context: context)
        let tripId = UUID()
        trip.id = tripId
        trip.startDate = points.first?.timestamp ?? Date()
        trip.endDate = endDate
        trip.distance = 0
        trip.maxSpeed = 0
        trip.averageSpeed = 0

        for p in points {
            let point = TrackPointEntity(context: context)
            point.id = UUID()
            point.latitude = p.lat
            point.longitude = p.lon
            point.altitude = 30
            point.speed = p.speed
            point.course = p.course
            point.horizontalAccuracy = 5
            point.timestamp = p.timestamp
            point.isInterpolated = false
            point.trip = trip
        }

        persistenceController.save()
        return tripId
    }

    private func fetchTrackPoints(tripId: UUID) -> [TrackPointEntity] {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
        guard let trip = try? context.fetch(request).first,
              let points = trip.trackPoints?.array as? [TrackPointEntity] else {
            return []
        }
        return points.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }

    private func fetchTrip(tripId: UUID) -> TripEntity? {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
        return try? context.fetch(request).first
    }

    // MARK: - Gap Interpolation

    func testShortGapIsInterpolated() async {
        let t0 = Date()
        let tripId = createTrip(points: [
            (lat: 45.0, lon: 39.0, speed: 10, course: 0, timestamp: t0),
            (lat: 45.0001, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(1)),
            // 10 second gap
            (lat: 45.001, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(11)),
            (lat: 45.0011, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(12)),
        ])

        await processor.processTrip(tripId)

        // Interpolated points are NOT saved to CoreData (only used for preview polyline)
        let points = fetchTrackPoints(tripId: tripId)
        let interpolated = points.filter { $0.isInterpolated }
        XCTAssertEqual(interpolated.count, 0, "Interpolated points should not be persisted")

        // But preview polyline should be generated (non-nil)
        let trip = fetchTrip(tripId: tripId)
        XCTAssertNotNil(trip?.previewPolyline, "Preview polyline should be generated with interpolation")
        XCTAssertTrue(trip!.isTrackProcessed)
    }

    func testNoGapNoInterpolation() async {
        let t0 = Date()
        let tripId = createTrip(points: [
            (lat: 45.0, lon: 39.0, speed: 10, course: 0, timestamp: t0),
            (lat: 45.0001, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(1)),
            (lat: 45.0002, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(2)),
            (lat: 45.0003, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(3)),
        ])

        await processor.processTrip(tripId)

        let points = fetchTrackPoints(tripId: tripId)
        let interpolated = points.filter { $0.isInterpolated }

        XCTAssertEqual(interpolated.count, 0, "No gaps = no interpolated points")
    }

    func testLargeGapNotInterpolated() async {
        let t0 = Date()
        // Gap > 5km — should not interpolate
        let tripId = createTrip(points: [
            (lat: 45.0, lon: 39.0, speed: 10, course: 0, timestamp: t0),
            (lat: 45.001, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(1)),
            // 60 second gap, position 10km away
            (lat: 45.1, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(61)),
            (lat: 45.101, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(62)),
        ])

        await processor.processTrip(tripId)

        let points = fetchTrackPoints(tripId: tripId)
        let interpolated = points.filter { $0.isInterpolated }

        XCTAssertEqual(interpolated.count, 0, "Gaps > 5km should not be interpolated")
    }

    // MARK: - Idempotency

    func testProcessTripIsIdempotent() async {
        let t0 = Date()
        let tripId = createTrip(points: [
            (lat: 45.0, lon: 39.0, speed: 10, course: 0, timestamp: t0),
            (lat: 45.001, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(10)),
        ])

        await processor.processTrip(tripId)
        let countAfterFirst = fetchTrackPoints(tripId: tripId).count

        await processor.processTrip(tripId)
        let countAfterSecond = fetchTrackPoints(tripId: tripId).count

        XCTAssertEqual(countAfterFirst, countAfterSecond,
                       "Processing twice should not add more points")
    }

    // MARK: - Stats & Polyline

    func testStatsRecalculated() async {
        let t0 = Date()
        let tripId = createTrip(points: [
            (lat: 45.0, lon: 39.0, speed: 10, course: 0, timestamp: t0),
            // 10 second gap
            (lat: 45.001, lon: 39.0, speed: 20, course: 0, timestamp: t0.addingTimeInterval(10)),
        ], endDate: t0.addingTimeInterval(10))

        await processor.processTrip(tripId)

        let trip = fetchTrip(tripId: tripId)
        XCTAssertNotNil(trip)
        XCTAssertTrue(trip!.isTrackProcessed)
        XCTAssertGreaterThan(trip!.distance, 0, "Distance should be recalculated")
    }

    func testPreviewPolylineRegenerated() async {
        let t0 = Date()
        let tripId = createTrip(points: [
            (lat: 45.0, lon: 39.0, speed: 10, course: 0, timestamp: t0),
            (lat: 45.001, lon: 39.0, speed: 10, course: 0, timestamp: t0.addingTimeInterval(10)),
        ])

        // Clear existing polyline
        let trip = fetchTrip(tripId: tripId)
        trip?.previewPolyline = nil
        persistenceController.save()

        await processor.processTrip(tripId)

        let updatedTrip = fetchTrip(tripId: tripId)
        XCTAssertNotNil(updatedTrip?.previewPolyline, "Preview polyline should be regenerated")
    }

    // MARK: - Course Interpolation

    func testProcessedTripHasPreviewPolyline() async {
        let t0 = Date()
        let tripId = createTrip(points: [
            (lat: 45.0, lon: 39.0, speed: 10, course: 340, timestamp: t0),
            (lat: 45.0001, lon: 39.0, speed: 10, course: 350, timestamp: t0.addingTimeInterval(1)),
            // 6 second gap
            (lat: 45.001, lon: 39.0001, speed: 10, course: 10, timestamp: t0.addingTimeInterval(7)),
            (lat: 45.0011, lon: 39.0002, speed: 10, course: 20, timestamp: t0.addingTimeInterval(8)),
        ])

        await processor.processTrip(tripId)

        let trip = fetchTrip(tripId: tripId)
        XCTAssertNotNil(trip?.previewPolyline, "Trip with gaps should have preview polyline after processing")
        XCTAssertTrue(trip!.isTrackProcessed)

        // No interpolated points saved
        let points = fetchTrackPoints(tripId: tripId)
        let interpolated = points.filter { $0.isInterpolated }
        XCTAssertEqual(interpolated.count, 0)
    }
}
