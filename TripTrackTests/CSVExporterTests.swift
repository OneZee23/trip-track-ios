import XCTest
@testable import TripTrack

final class CSVExporterTests: XCTestCase {

    private static let start = Date(timeIntervalSince1970: 1_700_000_000) // UTC

    private func point(
        lat: Double, lon: Double, altitude: Double = 0, speed: Double = 0,
        course: Double = -1, horizontalAccuracy: Double = 0, offset: TimeInterval = 0
    ) -> TrackPoint {
        TrackPoint(
            latitude: lat, longitude: lon, altitude: altitude, speed: speed,
            course: course, horizontalAccuracy: horizontalAccuracy,
            timestamp: Self.start.addingTimeInterval(offset)
        )
    }

    private func trip(title: String? = "Krasnodar → Sochi") -> Trip {
        Trip(startDate: Self.start, title: title)
    }

    // MARK: - Header

    func testHeaderIsExact() {
        let xml = CSVExporter.csv(for: trip(), points: [])
        let firstLine = xml.components(separatedBy: "\n").first
        XCTAssertEqual(
            firstLine,
            "timestamp,latitude,longitude,altitude_m,speed_mps,course_deg,horizontal_accuracy_m"
        )
    }

    // MARK: - Row count

    func testRowCountIsPointsPlusHeader() {
        let points = (0..<12).map { point(lat: 45.0, lon: 39.0, offset: TimeInterval($0) * 10) }
        let csv = CSVExporter.csv(for: trip(), points: points)
        XCTAssertEqual(csv.components(separatedBy: "\n").count, 13)
    }

    // MARK: - Locale independence

    func testCoordinatesUseADotUnderRussianLocale() {
        let points = [point(lat: 45.123456, lon: 39.654321)]
        let csv = CSVExporter.csv(for: trip(), points: points)
        XCTAssertTrue(csv.contains("45.123456"), csv)
        XCTAssertTrue(csv.contains("39.654321"), csv)
        XCTAssertFalse(csv.contains("45,123456"), "comma decimal separator leaked into CSV")
    }

    // MARK: - Empty fields for unknown values

    func testUnknownSpeedIsEmptyField() {
        let p = point(lat: 45, lon: 39, speed: -1)
        let csv = CSVExporter.csv(for: trip(), points: [p])
        let row = csv.components(separatedBy: "\n")[1]
        let fields = row.components(separatedBy: ",")
        XCTAssertEqual(fields.count, 7, row)
        XCTAssertEqual(fields[4], "", row) // speed_mps
    }

    func testUnknownCourseIsEmptyField() {
        let p = point(lat: 45, lon: 39, course: -1)
        let csv = CSVExporter.csv(for: trip(), points: [p])
        let row = csv.components(separatedBy: "\n")[1]
        let fields = row.components(separatedBy: ",")
        XCTAssertEqual(fields[5], "", row) // course_deg
    }

    func testZeroAltitudeIsEmptyField() {
        let p = point(lat: 45, lon: 39, altitude: 0)
        let csv = CSVExporter.csv(for: trip(), points: [p])
        let row = csv.components(separatedBy: "\n")[1]
        let fields = row.components(separatedBy: ",")
        XCTAssertEqual(fields[3], "", row) // altitude_m
    }

    func testKnownValuesArePrinted() {
        let p = point(lat: 45, lon: 39, altitude: 88, speed: 12.5, course: 270, horizontalAccuracy: 5)
        let csv = CSVExporter.csv(for: trip(), points: [p])
        let row = csv.components(separatedBy: "\n")[1]
        let fields = row.components(separatedBy: ",")
        XCTAssertEqual(fields[3], "88.000000", row)
        XCTAssertEqual(fields[4], "12.500000", row)
        XCTAssertEqual(fields[5], "270.000000", row)
        XCTAssertEqual(fields[6], "5.000000", row)
    }

    // MARK: - Ordering

    func testRowsAreOrderedByTime() {
        let later = point(lat: 45.2, lon: 39.2, offset: 120)
        let earlier = point(lat: 45.1, lon: 39.1, offset: 0)
        let csv = CSVExporter.csv(for: trip(), points: [later, earlier])
        let firstIndex = csv.range(of: "45.100000")!.lowerBound
        let secondIndex = csv.range(of: "45.200000")!.lowerBound
        XCTAssertLessThan(firstIndex, secondIndex, "later point printed before the earlier one")
    }

    // MARK: - Time is UTC

    func testTimeIsUTCISO8601() {
        let csv = CSVExporter.csv(for: trip(), points: [point(lat: 1, lon: 1)])
        // 1_700_000_000 UTC = 2023-11-14T22:13:20Z
        XCTAssertTrue(csv.contains("2023-11-14T22:13:20Z"), csv)
    }

    // MARK: - Empty track

    func testEmptyTrackHasOnlyHeader() {
        let csv = CSVExporter.csv(for: trip(), points: [])
        XCTAssertEqual(csv.components(separatedBy: "\n").count, 1)
        XCTAssertEqual(
            csv,
            "timestamp,latitude,longitude,altitude_m,speed_mps,course_deg,horizontal_accuracy_m"
        )
    }

    // MARK: - No thousands separators

    func testNoCommaInsideNumericValues() {
        // A trip in the tens-of-thousands of metres altitude range would be
        // the first place a grouping separator could sneak in.
        let p = point(lat: 45, lon: 39, altitude: 12_345, speed: 1_234.5)
        let csv = CSVExporter.csv(for: trip(), points: [p])
        let row = csv.components(separatedBy: "\n")[1]
        // Exactly 6 commas: 7 fields, no extras from a formatted number.
        XCTAssertEqual(row.filter { $0 == "," }.count, 6, row)
    }
}
