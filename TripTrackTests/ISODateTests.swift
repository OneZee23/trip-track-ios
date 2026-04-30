import XCTest
@testable import TripTrack

/// Regression coverage for `ISODate.parse`. The 3-hour timezone bug we hit
/// in production (server-stamped `Z` parsed as Moscow local) would have
/// failed `testZSuffixIsUTC` here.
final class ISODateTests: XCTestCase {

    // MARK: - Timezone designators

    func testZSuffixIsUTC() {
        // Fixture from the runSelfTest in production.
        let parsed = ISODate.parse("2026-04-29T08:33:35.049Z")
        XCTAssertNotNil(parsed)
        // 2026-04-29T08:33:35.049Z = 1777451615.049 epoch seconds.
        XCTAssertEqual(parsed!.timeIntervalSince1970, 1777451615.049, accuracy: 0.001)
    }

    func testPositiveOffsetWithColon() {
        // 11:33 +03:00 should equal 08:33Z. If the parser ignored the
        // offset, we'd get the same epoch as if `Z` was stamped.
        let withOffset = ISODate.parse("2026-04-29T11:33:35.049+03:00")
        let asUTC = ISODate.parse("2026-04-29T08:33:35.049Z")
        XCTAssertNotNil(withOffset)
        XCTAssertNotNil(asUTC)
        XCTAssertEqual(withOffset!.timeIntervalSince1970, asUTC!.timeIntervalSince1970, accuracy: 0.001)
    }

    func testNegativeOffsetWithColon() {
        // 03:33 -05:00 should equal 08:33Z.
        let withOffset = ISODate.parse("2026-04-29T03:33:35.049-05:00")
        let asUTC = ISODate.parse("2026-04-29T08:33:35.049Z")
        XCTAssertNotNil(withOffset)
        XCTAssertEqual(withOffset!.timeIntervalSince1970, asUTC!.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Fractional seconds variants

    func testNoFractionalSecondsZ() {
        let parsed = ISODate.parse("2026-04-29T08:33:35Z")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.timeIntervalSince1970, 1777451615, accuracy: 0.001)
    }

    func testNoFractionalSecondsWithOffset() {
        let parsed = ISODate.parse("2026-04-29T11:33:35+03:00")
        let expected = ISODate.parse("2026-04-29T08:33:35Z")
        XCTAssertNotNil(parsed)
        XCTAssertNotNil(expected)
        XCTAssertEqual(parsed!.timeIntervalSince1970, expected!.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Round-trip

    func testFormatProducesParseableString() {
        let original = Date(timeIntervalSince1970: 1777660415.049)
        let serialized = ISODate.format(original)
        // Server contract: must end with `Z`.
        XCTAssertTrue(serialized.hasSuffix("Z"), "Expected Z-suffix UTC, got: \(serialized)")
        let roundTripped = ISODate.parse(serialized)
        XCTAssertNotNil(roundTripped)
        XCTAssertEqual(roundTripped!.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Malformed input

    func testEmptyStringReturnsNil() {
        XCTAssertNil(ISODate.parse(""))
    }

    func testGarbageStringReturnsNil() {
        XCTAssertNil(ISODate.parse("not a date"))
    }

    func testDateOnlyReturnsNil() {
        // `2026-04-29` is not a full RFC-3339 timestamp.
        XCTAssertNil(ISODate.parse("2026-04-29"))
    }

    func testMissingTimezoneDesignatorReturnsNil() {
        // No `Z` and no offset — ambiguous, must reject.
        XCTAssertNil(ISODate.parse("2026-04-29T08:33:35.049"))
    }
}
