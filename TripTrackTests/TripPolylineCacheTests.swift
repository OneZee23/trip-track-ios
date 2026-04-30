import XCTest
import CoreLocation
@testable import TripTrack

/// Polyline encoding precision and `previewCache` invalidation.
/// Existing `PolylineTests.swift` covers the basic round-trip; this file
/// extends with edge cases that move along with the new preview cache.
final class TripPolylineCacheTests: XCTestCase {

    // MARK: - encode/decode edge cases

    func testEncodeEmptyArrayProducesEmptyData() {
        XCTAssertEqual(Trip.encodePolyline([]).count, 0)
    }

    func testDecodeEmptyArrayRoundTrip() {
        let decoded = Trip.decodePolyline(Trip.encodePolyline([]))
        XCTAssertTrue(decoded.isEmpty)
    }

    func testSinglePointRoundTrip() {
        let original = [CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)]
        let decoded = Trip.decodePolyline(Trip.encodePolyline(original))
        XCTAssertEqual(decoded.count, 1)
        // Float32 has ~7 decimal digits of precision. Worst case at lat 55°
        // is ~1m for latitude, ~0.5m for longitude. 1e-4 deg ≈ 11m, so 1e-4
        // is a safe accuracy bound that catches gross encoding bugs.
        XCTAssertEqual(decoded[0].latitude, original[0].latitude, accuracy: 1e-4)
        XCTAssertEqual(decoded[0].longitude, original[0].longitude, accuracy: 1e-4)
    }

    func testLargePolylineRoundTrip() {
        // 1000 points should serialize to exactly 8000 bytes (4 lat + 4 lon).
        let original = (0..<1000).map { i in
            CLLocationCoordinate2D(
                latitude: 55.0 + Double(i) * 0.0001,
                longitude: 37.0 + Double(i) * 0.0001
            )
        }
        let data = Trip.encodePolyline(original)
        XCTAssertEqual(data.count, 8000)
        let decoded = Trip.decodePolyline(data)
        XCTAssertEqual(decoded.count, 1000)
        // Spot check first/middle/last
        for idx in [0, 500, 999] {
            XCTAssertEqual(decoded[idx].latitude, original[idx].latitude, accuracy: 1e-4)
            XCTAssertEqual(decoded[idx].longitude, original[idx].longitude, accuracy: 1e-4)
        }
    }

    func testFloat32PrecisionAtRealLatLon() {
        // Pick a coord with ~6 decimal digits — the resolution we care about
        // for visualizing a route. After Float32 round-trip, error must be
        // small enough to be invisible at any zoom that fits a city block.
        let original = [CLLocationCoordinate2D(latitude: 55.755826, longitude: 37.617299)]
        let decoded = Trip.decodePolyline(Trip.encodePolyline(original))
        // Float32 lat error at 55° ≈ 1m ≈ 9e-6 deg. Use 1e-5 with margin.
        XCTAssertEqual(decoded[0].latitude, original[0].latitude, accuracy: 1e-5)
        XCTAssertEqual(decoded[0].longitude, original[0].longitude, accuracy: 1e-5)
    }

    // MARK: - decode malformed data

    func testDecodeOddByteCountRejected() {
        // 7 bytes is not a multiple of 8 → invalid.
        XCTAssertTrue(Trip.decodePolyline(Data([1, 2, 3, 4, 5, 6, 7])).isEmpty)
    }

    func testDecodeFourBytesRejected() {
        // Exactly half a coord (4 bytes < 8) → must reject, not return half a coord.
        XCTAssertTrue(Trip.decodePolyline(Data([1, 2, 3, 4])).isEmpty)
    }

    // MARK: - previewCache invalidation

    func testPreviewCoordinatesUseCacheOnSecondCall() {
        // Build a Trip with previewPolyline set. The first access populates
        // the cache; second access should return the same coords.
        let coords = [
            CLLocationCoordinate2D(latitude: 55.7, longitude: 37.6),
            CLLocationCoordinate2D(latitude: 55.8, longitude: 37.7),
        ]
        let polyline = Trip.encodePolyline(coords)
        let trip = Trip(
            id: UUID(),
            startDate: Date(),
            previewPolyline: polyline
        )
        let first = trip.previewCoordinates
        let second = trip.previewCoordinates
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(first[0].latitude, second[0].latitude)
    }

    func testInvalidatePreviewCacheForcesRecompute() {
        // Round-trip after invalidation should still return correct coords.
        // We can't directly observe cache hits, but we can verify that
        // calling invalidate then accessing again returns the right shape.
        let coords = [
            CLLocationCoordinate2D(latitude: 55.7, longitude: 37.6),
            CLLocationCoordinate2D(latitude: 55.8, longitude: 37.7),
            CLLocationCoordinate2D(latitude: 55.9, longitude: 37.8),
        ]
        let id = UUID()
        let trip = Trip(
            id: id,
            startDate: Date(),
            previewPolyline: Trip.encodePolyline(coords)
        )
        _ = trip.previewCoordinates // populate cache
        Trip.invalidatePreviewCache(for: id)
        let after = trip.previewCoordinates
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(after[2].latitude, 55.9, accuracy: 1e-4)
    }

    func testPreviewCoordinatesFallsBackToTrackPointsWhenNoPolyline() {
        // No previewPolyline → returns trackPoints' coordinates directly.
        let trip = Trip(
            id: UUID(),
            startDate: Date(),
            trackPoints: [
                TrackPoint(latitude: 55.7, longitude: 37.6),
                TrackPoint(latitude: 55.8, longitude: 37.7),
            ]
        )
        let coords = trip.previewCoordinates
        XCTAssertEqual(coords.count, 2)
        XCTAssertEqual(coords[0].latitude, 55.7)
        XCTAssertEqual(coords[1].longitude, 37.7)
    }
}
