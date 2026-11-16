import XCTest
@testable import TripTrack

/// A name that needs two lines splits at the space that balances them, so no
/// word is ever broken by letter (owner, 5 Nov 2026).
final class ProfileHeroNameTests: XCTestCase {
    func testTwoWordsSplitAtTheSpace() throws {
        let lines = try XCTUnwrap(ProfileHeroCard.nameLines("Ярослав Подзаборовский"))
        XCTAssertEqual(lines.0, "Ярослав")
        XCTAssertEqual(lines.1, "Подзаборовский")
    }

    func testThreeWordsSplitWhereTheLinesAreClosest() throws {
        let lines = try XCTUnwrap(ProfileHeroCard.nameLines("Анна Мария Петрова"))
        XCTAssertEqual(lines.0, "Анна Мария")
        XCTAssertEqual(lines.1, "Петрова")
    }

    func testOneWordHasNoSplit() {
        XCTAssertNil(ProfileHeroCard.nameLines("Vixor66"))
    }
}
