import XCTest
@testable import TripTrack

/// Экспорт — записанный трек: догадок в нём нет, а у грубой точки честная
/// точность GPS (спека §2.4).
final class ExportSkipsFillTests: XCTestCase {
    private let points = [
        TrackPoint(latitude: 45.0, longitude: 38.0, horizontalAccuracy: 8,
                   timestamp: Date(timeIntervalSince1970: 0)),
        TrackPoint(latitude: 45.1, longitude: 38.1, speed: -1, horizontalAccuracy: -1,
                   timestamp: Date(timeIntervalSince1970: 5), isInterpolated: true),
        TrackPoint(latitude: 45.2, longitude: 38.2, horizontalAccuracy: 120,
                   timestamp: Date(timeIntervalSince1970: 10)),
    ]

    func testGPXHasNoFilledPoints() {
        let gpx = GPXExporter.gpx(for: Trip(), points: points)
        XCTAssertEqual(gpx.components(separatedBy: "<trkpt").count - 1, 2)
        XCTAssertFalse(gpx.contains("45.100000"))
    }

    func testCSVHasNoFilledPointsAndKeepsRawAccuracy() {
        let csv = CSVExporter.csv(for: Trip(), points: points)
        XCTAssertEqual(csv.split(separator: "\n").count, 3)   // заголовок + две точки
        XCTAssertTrue(csv.contains(",120.000000"))
    }
}
