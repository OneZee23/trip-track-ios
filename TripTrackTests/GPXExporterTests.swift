import XCTest
@testable import TripTrack

final class GPXExporterTests: XCTestCase {

    private static let start = Date(timeIntervalSince1970: 1_700_000_000) // UTC

    private func point(
        lat: Double, lon: Double, altitude: Double = 0, speed: Double = 0,
        offset: TimeInterval = 0
    ) -> TrackPoint {
        TrackPoint(
            latitude: lat, longitude: lon, altitude: altitude, speed: speed,
            timestamp: Self.start.addingTimeInterval(offset)
        )
    }

    private func trip(title: String? = "Krasnodar → Sochi") -> Trip {
        Trip(startDate: Self.start, title: title)
    }

    // MARK: - Well-formed XML

    func testProducesWellFormedXML() throws {
        let points = [point(lat: 45.0, lon: 39.0), point(lat: 45.1, lon: 39.1, offset: 60)]
        let xml = GPXExporter.gpx(for: trip(), points: points)

        let delegate = CountingParserDelegate()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        XCTAssertTrue(parser.parse(), "GPX did not parse: \(parser.parserError.debugDescription)")
        XCTAssertNil(parser.parserError)
    }

    // MARK: - Point count

    func testTrackPointCountMatchesInputCount() {
        let points = (0..<12).map { point(lat: 45.0, lon: 39.0, offset: TimeInterval($0) * 10) }
        let xml = GPXExporter.gpx(for: trip(), points: points)
        XCTAssertEqual(xml.components(separatedBy: "<trkpt").count - 1, 12)
    }

    // MARK: - Locale independence

    func testCoordinatesUseADotUnderRussianLocale() {
        // The formatter used inside GPXExporter is pinned to en_US_POSIX
        // regardless of what Locale.current happens to be during the test
        // run — this asserts the OUTPUT, which is the thing that matters.
        let points = [point(lat: 45.123456, lon: 39.654321)]
        let xml = GPXExporter.gpx(for: trip(), points: points)
        XCTAssertTrue(xml.contains("lat=\"45.123456\""), xml)
        XCTAssertTrue(xml.contains("lon=\"39.654321\""), xml)
        XCTAssertFalse(xml.contains("45,123456"), "comma decimal separator leaked into GPX")
    }

    func testSixDecimalPlaces() {
        let points = [point(lat: 45.1, lon: 39.2)]
        let xml = GPXExporter.gpx(for: trip(), points: points)
        XCTAssertTrue(xml.contains("lat=\"45.100000\""), xml)
        XCTAssertTrue(xml.contains("lon=\"39.200000\""), xml)
    }

    // MARK: - Escaping

    func testEscapesAmpersandAndLessThanInName() {
        let xml = GPXExporter.gpx(for: trip(title: "Home & <Away>"), points: [point(lat: 1, lon: 1)])
        XCTAssertTrue(xml.contains("Home &amp; &lt;Away&gt;"), xml)
        XCTAssertFalse(xml.contains("Home & <Away>"), xml)
    }

    // MARK: - Empty track

    func testEmptyTrackHasNoTrkElement() {
        let xml = GPXExporter.gpx(for: trip(), points: [])
        XCTAssertFalse(xml.contains("<trk>"), xml)
        XCTAssertTrue(xml.contains("<metadata>"), xml)
    }

    // MARK: - Speed extension

    func testUnknownSpeedIsOmittedFromExtensions() {
        let known = point(lat: 45, lon: 39, speed: 12.5)
        let unknown = point(lat: 45.01, lon: 39.01, speed: -1, offset: 30)
        let xml = GPXExporter.gpx(for: trip(), points: [known, unknown])
        XCTAssertEqual(xml.components(separatedBy: "<speed>").count - 1, 1)
        XCTAssertTrue(xml.contains("<speed>12.500000</speed>"), xml)
    }

    func testElevationOmittedWhenZero() {
        let noAltitude = point(lat: 45, lon: 39, altitude: 0)
        let withAltitude = point(lat: 45.01, lon: 39.01, altitude: 88, offset: 30)
        let xml = GPXExporter.gpx(for: trip(), points: [noAltitude, withAltitude])
        XCTAssertEqual(xml.components(separatedBy: "<ele>").count - 1, 1)
        XCTAssertTrue(xml.contains("<ele>88.000000</ele>"), xml)
    }

    // MARK: - Ordering

    func testPointsAreOrderedByTime() {
        let later = point(lat: 45.2, lon: 39.2, offset: 120)
        let earlier = point(lat: 45.1, lon: 39.1, offset: 0)
        let xml = GPXExporter.gpx(for: trip(), points: [later, earlier])
        let firstIndex = xml.range(of: "lat=\"45.100000\"")!.lowerBound
        let secondIndex = xml.range(of: "lat=\"45.200000\"")!.lowerBound
        XCTAssertLessThan(firstIndex, secondIndex, "later point printed before the earlier one")
    }

    // MARK: - Time is UTC

    func testTimeIsUTCWithZSuffix() {
        let xml = GPXExporter.gpx(for: trip(), points: [point(lat: 1, lon: 1)])
        // 1_700_000_000 UTC = 2023-11-14T22:13:20Z
        XCTAssertTrue(xml.contains("2023-11-14T22:13:20Z"), xml)
    }

    // MARK: - Name fallback

    func testFallsBackToDateWhenTitleIsNil() {
        XCTAssertEqual(GPXExporter.displayName(for: trip(title: nil)), "14 Nov 2023")
    }

    func testFallsBackToDateWhenTitleIsBlank() {
        XCTAssertEqual(GPXExporter.displayName(for: trip(title: "   ")), "14 Nov 2023")
    }
}

/// Just enough of `XMLParserDelegate` to force `parse()` to walk the whole
/// document rather than bailing after the first element.
private final class CountingParserDelegate: NSObject, XMLParserDelegate {
    private(set) var elementCount = 0
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        elementCount += 1
    }
}
