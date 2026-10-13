import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

@MainActor
final class RoadHistoryCountTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private let route = [
        CLLocationCoordinate2D(latitude: 40.123, longitude: 20.123),
        CLLocationCoordinate2D(latitude: 40.243, longitude: 20.243),
    ]

    func testCompletionUsesAllRestoredPreviewsInsteadOfLocalRoadCounter() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let manager = RoadCollectionManager(persistenceController: persistence)
        let current = trip(previewOnly: false)
        _ = manager.processTrip(current, history: [])
        let road = try XCTUnwrap(context.fetch(RoadEntity.fetchRequest()).first)
        road.timesDriven = 22

        for _ in 0..<120 {
            let entity = TripEntity(context: context)
            entity.id = UUID()
            entity.startDate = date
            entity.endDate = date.addingTimeInterval(1200)
            entity.distance = 15_000
            entity.maxSpeed = 25
            entity.previewPolyline = Trip.encodePolyline(route)
            entity.source = TripOrigin.recorded.rawValue
            entity.confirmation = TripConfirmation.confirmed.rawValue
            entity.syncStatus = SyncStatus.synced.rawValue
            entity.serverCreatedAt = date
        }
        try context.save()
        let history = CoreDataTripRepository(persistenceController: persistence).fetchAllTrips()
        XCTAssertEqual(history.count, 120)
        XCTAssertTrue(history.allSatisfy { $0.trackPoints.isEmpty && $0.isOnServer })

        let completion = try XCTUnwrap(manager.processTrip(current, history: history))
        XCTAssertEqual(completion.timesDriven, 121)
        XCTAssertFalse(completion.isNew)
        // Existing collection progression is not rebuilt or awarded again.
        XCTAssertEqual(road.timesDriven, 23)
        XCTAssertEqual(manager.processTrip(current, history: history)?.timesDriven, 121)
    }

    func testRestoredHistoryIsRecognizedWithoutAnyLocalRoadCollection() throws {
        let persistence = PersistenceController(inMemory: true)
        let manager = RoadCollectionManager(persistenceController: persistence)
        let completion = try XCTUnwrap(manager.processTrip(trip(previewOnly: false),
                                                          history: [trip(), trip()]))
        XCTAssertEqual(completion.timesDriven, 3)
        XCTAssertFalse(completion.isNew)
    }

    func testCurrentTripAndPublicPrivateCopiesCountOnceByID() {
        let current = trip()
        let prior = trip()
        var publicCopy = prior
        publicCopy.isPrivate = false
        publicCopy.isOnServer = true
        let history = [current, prior, publicCopy, current]
        XCTAssertEqual(SimilarRecordedTrips.count(for: current, in: history), 2)
        XCTAssertEqual(SimilarRecordedTrips.count(for: current, in: Array(history.reversed())), 2)
        XCTAssertEqual(SimilarRecordedTrips.count(for: current, in: [prior]), 2)
    }

    func testSparseSyncedPreviewMatchesDenseRecordingAndReverseDirection() {
        let dense = (0...240).map { index in
            CLLocationCoordinate2D(latitude: 40.123 + Double(index) * 0.0005,
                                   longitude: 20.123 + Double(index) * 0.0005)
        }
        let current = trip(coordinates: dense, previewOnly: false)
        let reverse = trip(coordinates: Array(route.reversed()))
        XCTAssertEqual(SimilarRecordedTrips.count(for: current, in: [trip(), reverse]), 3)
    }

    func testUnknownGeometryDraftManualAndUnfinishedTripsDoNotInflateCount() {
        let current = trip()
        var missing = trip()
        missing.previewPolyline = nil
        var draft = trip()
        draft.confirmation = .draft
        var manual = trip()
        manual.source = .manual
        var active = trip()
        active.endDate = nil
        var junk = trip()
        junk.distance = 10
        junk.endDate = junk.startDate.addingTimeInterval(10)
        let history = [missing, draft, manual, active, junk, trip()]
        XCTAssertEqual(SimilarRecordedTrips.count(for: current, in: history), 2)
    }

    func testSameEndpointsDoNotCountACompletelyDifferentRoute() {
        let detour = trip(coordinates: [route[0],
                                       CLLocationCoordinate2D(latitude: 40.123, longitude: 20.9),
                                       CLLocationCoordinate2D(latitude: 40.243, longitude: 20.9),
                                       route[1]])
        XCTAssertEqual(SimilarRecordedTrips.count(for: trip(), in: [detour]), 1)
        var longer = trip()
        longer.distance *= 3
        XCTAssertEqual(SimilarRecordedTrips.count(for: trip(), in: [longer]), 1)
    }

    func testKnownRecordingGapsAreNotJoinedForSimilarity() {
        let current = trip()
        var paused = trip()
        paused.recordingBreaks = [date.addingTimeInterval(60)]
        var signalGap = trip(previewOnly: false)
        signalGap.trackPoints[1] = TrackPoint(latitude: route[1].latitude,
                                             longitude: route[1].longitude,
                                             timestamp: date.addingTimeInterval(120))
        var interpolated = trip(previewOnly: false)
        interpolated.trackPoints[1] = TrackPoint(latitude: route[1].latitude,
                                                longitude: route[1].longitude,
                                                timestamp: date.addingTimeInterval(1),
                                                isInterpolated: true)
        XCTAssertEqual(SimilarRecordedTrips.count(for: current, in: [paused, signalGap, interpolated]), 1)
        XCTAssertEqual(SimilarRecordedTrips.count(for: paused, in: [current]), 0)
        XCTAssertEqual(SimilarRecordedTrips.count(for: signalGap, in: [current]), 0)
    }

    func testAntimeridianRouteUsesTheShortCrossing() {
        let crossing = [CLLocationCoordinate2D(latitude: 40.123, longitude: 179.9),
                        CLLocationCoordinate2D(latitude: 40.123, longitude: -179.9)]
        let denseCrossing = [crossing[0],
                             CLLocationCoordinate2D(latitude: 40.123, longitude: 180),
                             crossing[1]]
        XCTAssertEqual(SimilarRecordedTrips.count(for: trip(coordinates: crossing),
                                                 in: [trip(coordinates: Array(denseCrossing.reversed()))]), 2)
    }

    func testInvalidCoordinatesDoNotTurnIntoMatchingGridCells() {
        let invalid = trip(coordinates: [route[0],
                                        CLLocationCoordinate2D(latitude: .nan, longitude: 20)])
        XCTAssertEqual(SimilarRecordedTrips.count(for: trip(), in: [invalid]), 1)
        XCTAssertEqual(SimilarRecordedTrips.count(for: invalid, in: [trip()]), 0)
    }

    private func trip(coordinates: [CLLocationCoordinate2D]? = nil, previewOnly: Bool = true) -> Trip {
        let coordinates = coordinates ?? route
        return Trip(startDate: date, endDate: date.addingTimeInterval(1200),
                    distance: 15_000, maxSpeed: 25,
                    trackPoints: previewOnly ? [] : coordinates.enumerated().map { index, coordinate in
                        TrackPoint(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                   speed: 15, timestamp: date.addingTimeInterval(Double(index)))
                    },
                    previewPolyline: previewOnly ? Trip.encodePolyline(coordinates) : nil)
    }
}
