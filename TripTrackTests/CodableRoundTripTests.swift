import XCTest
@testable import TripTrack

final class CodableRoundTripTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - TrackPoint

    func testTrackPointRoundTrip() throws {
        let point = TrackPoint(
            latitude: 55.7558, longitude: 37.6173,
            altitude: 150, speed: 16.7, course: 90,
            horizontalAccuracy: 5.0, timestamp: Date(timeIntervalSince1970: 1700000000),
            isInterpolated: true
        )
        let data = try encoder.encode(point)
        let decoded = try decoder.decode(TrackPoint.self, from: data)

        XCTAssertEqual(decoded.id, point.id)
        XCTAssertEqual(decoded.latitude, point.latitude)
        XCTAssertEqual(decoded.longitude, point.longitude)
        XCTAssertEqual(decoded.altitude, point.altitude)
        XCTAssertEqual(decoded.speed, point.speed)
        XCTAssertEqual(decoded.course, point.course)
        XCTAssertEqual(decoded.horizontalAccuracy, point.horizontalAccuracy)
        XCTAssertEqual(decoded.timestamp, point.timestamp)
        XCTAssertEqual(decoded.isInterpolated, point.isInterpolated)
    }

    // MARK: - TripPhoto

    func testTripPhotoRoundTrip() throws {
        let photo = TripPhoto(
            id: UUID(),
            filename: "abc123/photo.jpg",
            caption: "Nice view",
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
        let data = try encoder.encode(photo)
        let decoded = try decoder.decode(TripPhoto.self, from: data)

        XCTAssertEqual(decoded.id, photo.id)
        XCTAssertEqual(decoded.filename, photo.filename)
        XCTAssertEqual(decoded.caption, photo.caption)
        XCTAssertEqual(decoded.timestamp, photo.timestamp)
    }

    func testTripPhotoNilCaption() throws {
        let photo = TripPhoto(id: UUID(), filename: "test.jpg", caption: nil, timestamp: Date())
        let data = try encoder.encode(photo)
        let decoded = try decoder.decode(TripPhoto.self, from: data)
        XCTAssertNil(decoded.caption)
    }

    // MARK: - Vehicle

    func testVehicleRoundTrip() throws {
        let vehicle = Vehicle(
            name: "Tesla Model 3",
            avatarEmoji: "pixel_car_blue",
            odometerKm: 15000,
            level: 3,
            stickers: [.flag100km, .mountain],
            createdAt: Date(timeIntervalSince1970: 1700000000),
            cityConsumption: 0, highwayConsumption: 0, fuelPrice: 0
        )
        let data = try encoder.encode(vehicle)
        let decoded = try decoder.decode(Vehicle.self, from: data)

        XCTAssertEqual(decoded.id, vehicle.id)
        XCTAssertEqual(decoded.name, vehicle.name)
        XCTAssertEqual(decoded.avatarEmoji, vehicle.avatarEmoji)
        XCTAssertEqual(decoded.odometerKm, vehicle.odometerKm)
        XCTAssertEqual(decoded.level, vehicle.level)
        XCTAssertEqual(decoded.stickers, vehicle.stickers)
        XCTAssertEqual(decoded.createdAt, vehicle.createdAt)
    }

    // MARK: - Trip

    func testTripRoundTrip() throws {
        let point = TrackPoint(latitude: 55.7558, longitude: 37.6173, altitude: 150, speed: 16.7)
        let photo = TripPhoto(id: UUID(), filename: "trip/photo.jpg", caption: "Test", timestamp: Date())
        let polyline = Trip.encodePolyline([point.coordinate])

        let trip = Trip(
            startDate: Date(timeIntervalSince1970: 1700000000),
            endDate: Date(timeIntervalSince1970: 1700003600),
            distance: 45200, maxSpeed: 33.3, averageSpeed: 12.6,
            trackPoints: [point], photos: [photo],
            title: "Moscow → Tula", tripDescription: "Weekend trip",
            fuelUsed: 5.2, elevation: 320,
            region: "Tula Oblast", isPrivate: true,
            vehicleId: UUID(), fuelCurrency: "RUB",
            previewPolyline: polyline,
            earnedBadgeIds: ["first_trip", "century"]
        )

        let data = try encoder.encode(trip)
        let decoded = try decoder.decode(Trip.self, from: data)

        XCTAssertEqual(decoded.id, trip.id)
        XCTAssertEqual(decoded.startDate, trip.startDate)
        XCTAssertEqual(decoded.endDate, trip.endDate)
        XCTAssertEqual(decoded.distance, trip.distance)
        XCTAssertEqual(decoded.maxSpeed, trip.maxSpeed)
        XCTAssertEqual(decoded.averageSpeed, trip.averageSpeed)
        XCTAssertEqual(decoded.trackPoints.count, 1)
        XCTAssertEqual(decoded.photos.count, 1)
        XCTAssertEqual(decoded.title, trip.title)
        XCTAssertEqual(decoded.tripDescription, trip.tripDescription)
        XCTAssertEqual(decoded.fuelUsed, trip.fuelUsed)
        XCTAssertEqual(decoded.elevation, trip.elevation)
        XCTAssertEqual(decoded.region, trip.region)
        XCTAssertEqual(decoded.isPrivate, trip.isPrivate)
        XCTAssertEqual(decoded.vehicleId, trip.vehicleId)
        XCTAssertEqual(decoded.fuelCurrency, trip.fuelCurrency)
        XCTAssertEqual(decoded.previewPolyline, trip.previewPolyline)
        XCTAssertEqual(decoded.earnedBadgeIds, trip.earnedBadgeIds)
    }

    func testTripMinimalRoundTrip() throws {
        let trip = Trip(startDate: Date(timeIntervalSince1970: 1700000000))
        let data = try encoder.encode(trip)
        let decoded = try decoder.decode(Trip.self, from: data)

        XCTAssertEqual(decoded.id, trip.id)
        XCTAssertNil(decoded.endDate)
        XCTAssertNil(decoded.title)
        XCTAssertTrue(decoded.trackPoints.isEmpty)
        XCTAssertTrue(decoded.photos.isEmpty)
    }
}
