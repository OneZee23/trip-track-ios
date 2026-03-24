import XCTest
@testable import TripTrack

final class TripTrackTests: XCTestCase {

    func testTripInitialization() {
        let trip = Trip()
        XCTAssertNotNil(trip.id)
        XCTAssertTrue(trip.isActive)
        XCTAssertEqual(trip.distance, 0)
        XCTAssertEqual(trip.maxSpeed, 0)
    }

    func testTripDuration() {
        let start = Date().addingTimeInterval(-3600) // 1 hour ago
        let end = Date()
        let trip = Trip(startDate: start, endDate: end, distance: 50000)
        XCTAssertEqual(trip.duration, 3600, accuracy: 1)
        XCTAssertEqual(trip.distanceKm, 50)
        XCTAssertFalse(trip.isActive)
    }

    func testTrackPointFromLocation() {
        let point = TrackPoint(latitude: 55.7558, longitude: 37.6173, altitude: 150, speed: 16.7)
        XCTAssertEqual(point.latitude, 55.7558)
        XCTAssertEqual(point.longitude, 37.6173)
        XCTAssertEqual(point.speedKmh, 16.7 * 3.6, accuracy: 0.1)
    }

    func testTripFormattedDuration() {
        let start = Date()
        let end = start.addingTimeInterval(5025) // 1h 23m 45s
        let trip = Trip(startDate: start, endDate: end)
        XCTAssertEqual(trip.formattedDuration, "1:23:45")
    }

    func testPersistenceControllerPreview() {
        let controller = PersistenceController.preview
        XCTAssertNotNil(controller.container)
    }

    func testTripEquatable_sameTrip() {
        let id = UUID()
        let date = Date()
        let trip1 = Trip(id: id, startDate: date, distance: 1000, title: "Test")
        let trip2 = Trip(id: id, startDate: date, distance: 1000, title: "Test")
        XCTAssertEqual(trip1, trip2)
    }

    func testTripEquatable_differentTitle() {
        let id = UUID()
        let date = Date()
        let trip1 = Trip(id: id, startDate: date, title: "A")
        let trip2 = Trip(id: id, startDate: date, title: "B")
        XCTAssertNotEqual(trip1, trip2)
    }

    func testTripEquatable_ignoresTrackPoints() {
        let id = UUID()
        let date = Date()
        let point = TrackPoint(latitude: 55.0, longitude: 37.0)
        let trip1 = Trip(id: id, startDate: date)
        let trip2 = Trip(id: id, startDate: date, trackPoints: [point])
        XCTAssertEqual(trip1, trip2, "Equatable should ignore trackPoints for performance")
    }
}
