import XCTest
@testable import TripTrack

final class DriverRankTests: XCTestCase {

    func testNoviceEnglishTitle() {
        XCTAssertEqual(DriverRank.novice.titleEn(), "Beginner")
    }

    func testNoviceRussianTitle() {
        XCTAssertEqual(DriverRank.novice.titleRu(), "Новичок")
    }

    func testAllRanksHaveTitles() {
        for rank in DriverRank.allCases {
            XCTAssertFalse(rank.titleEn().isEmpty)
            XCTAssertFalse(rank.titleRu().isEmpty)
        }
    }

    func testRankFromLevel() {
        XCTAssertEqual(DriverRank.from(level: 1), .novice)
        XCTAssertEqual(DriverRank.from(level: 5), .driver)
        XCTAssertEqual(DriverRank.from(level: 10), .traveler)
        XCTAssertEqual(DriverRank.from(level: 15), .explorer)
        XCTAssertEqual(DriverRank.from(level: 20), .navigator)
        XCTAssertEqual(DriverRank.from(level: 25), .trucker)
        XCTAssertEqual(DriverRank.from(level: 30), .legend)
    }

    func testLegendIsHighestRank() {
        XCTAssertEqual(DriverRank.allCases.last, .legend)
        XCTAssertEqual(DriverRank.from(level: 30), .legend)
    }

    func testRankTitleLocalization() {
        let rank = DriverRank.novice
        XCTAssertEqual(rank.title(.en), "Beginner")
        XCTAssertEqual(rank.title(.ru), "Новичок")
    }
}
