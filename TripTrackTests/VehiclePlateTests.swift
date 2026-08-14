import XCTest
@testable import TripTrack

/// Coverage for `VehiclePlate` — the free-text plate field. The research
/// behind it says every serious product takes plates as plain text, so these
/// tests are mostly about what must NOT happen: no masks, no country guessing,
/// no helpful rewriting.
final class VehiclePlateTests: XCTestCase {

    // MARK: - What survives

    func testKeepsRussianPlate() {
        XCTAssertEqual(VehiclePlate.normalized("А 123 БВ 77"), "А 123 БВ 77")
    }

    func testKeepsLatinAndSeparators() {
        XCTAssertEqual(VehiclePlate.normalized("AB-12 CDE"), "AB-12 CDE")
        XCTAssertEqual(VehiclePlate.normalized("B.1234"), "B.1234")
    }

    /// Any alphabet, not just the two we happen to design for.
    func testKeepsOtherScripts() {
        XCTAssertEqual(VehiclePlate.normalized("京A88888"), "京A88888")
        XCTAssertEqual(VehiclePlate.normalized("ΑΒ 1234"), "ΑΒ 1234")
    }

    // MARK: - What does not

    func testDropsEmoji() {
        XCTAssertEqual(VehiclePlate.normalized("А123БВ🚗🔥"), "А123БВ")
    }

    func testDropsPunctuationThatIsNotAPlateSeparator() {
        XCTAssertEqual(VehiclePlate.normalized("A/B*12#3"), "AB123")
    }

    func testTrimsEdgesButKeepsInnerSpacing() {
        XCTAssertEqual(VehiclePlate.normalized("  А 123 БВ  "), "А 123 БВ")
    }

    func testCapsLength() {
        let long = String(repeating: "A", count: 40)
        XCTAssertEqual(VehiclePlate.normalized(long).count, VehiclePlate.maxLength)
    }

    // MARK: - What must never happen

    /// Cyrillic А and Latin A look identical and are different strings. A
    /// "helpful" transliteration would silently rewrite someone's Russian
    /// plate into a Latin one. Fails if anyone adds lookalike folding.
    func testDoesNotTransliterateLookalikeLetters() {
        let cyrillic = "АВЕКМНОРСТУХ"
        XCTAssertEqual(VehiclePlate.normalized(cyrillic), cyrillic)
        XCTAssertNotEqual(VehiclePlate.normalized("А"), "A")
    }

    /// No mask means no reformatting: whatever spacing someone types is what
    /// they meant, including none at all.
    func testDoesNotImposeFormatting() {
        XCTAssertEqual(VehiclePlate.normalized("А123БВ77"), "А123БВ77")
        XCTAssertEqual(VehiclePlate.normalized("1234"), "1234")
    }

    /// An empty plate is an ordinary, valid state — the field is optional.
    func testEmptyStaysEmpty() {
        XCTAssertEqual(VehiclePlate.normalized(""), "")
        XCTAssertEqual(VehiclePlate.normalized("   "), "")
        XCTAssertEqual(VehiclePlate.normalized("🚗"), "")
    }
}
