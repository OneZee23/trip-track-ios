import XCTest
import CoreLocation
@testable import TripTrack

final class PolylineTests: XCTestCase {

    func testEncodeDecodeRoundtrip() {
        let original = [
            CLLocationCoordinate2D(latitude: 45.03500, longitude: 38.97500),
            CLLocationCoordinate2D(latitude: 45.03600, longitude: 38.97600),
            CLLocationCoordinate2D(latitude: 45.03700, longitude: 38.97700),
        ]
        let data = Trip.encodePolyline(original)
        let decoded = Trip.decodePolyline(data)

        XCTAssertEqual(decoded.count, original.count)
        for (a, b) in zip(original, decoded) {
            // Float32 precision ~ 5-6 decimal digits
            XCTAssertEqual(a.latitude, b.latitude, accuracy: 0.001)
            XCTAssertEqual(a.longitude, b.longitude, accuracy: 0.001)
        }
    }

    func testEncodeDecodePreservesOrder() {
        let coords = (0..<20).map {
            CLLocationCoordinate2D(latitude: 45.0 + Double($0) * 0.01, longitude: 38.0 + Double($0) * 0.005)
        }
        let decoded = Trip.decodePolyline(Trip.encodePolyline(coords))

        XCTAssertEqual(decoded.count, 20)
        // Verify monotonically increasing latitude (order preserved)
        for i in 1..<decoded.count {
            XCTAssertGreaterThan(decoded[i].latitude, decoded[i - 1].latitude)
        }
    }

    func testDecodeEmptyData() {
        let decoded = Trip.decodePolyline(Data())
        XCTAssertTrue(decoded.isEmpty)
    }

    func testDecodeInvalidData() {
        // 5 bytes — not divisible by 8
        let decoded = Trip.decodePolyline(Data([1, 2, 3, 4, 5]))
        XCTAssertTrue(decoded.isEmpty)
    }
}
