import XCTest
@testable import TripTrack

final class FilmingModeStateTests: XCTestCase {
    func testManualModeStaysActiveWithoutCapture() {
        XCTAssertTrue(FilmingModeState(manual: true, automatic: true, isCaptured: false).isActive)
    }

    func testAutomaticModeTracksCaptureState() {
        XCTAssertFalse(FilmingModeState(manual: false, automatic: true, isCaptured: false).isActive)
        XCTAssertTrue(FilmingModeState(manual: false, automatic: true, isCaptured: true).isActive)
    }

    func testDisabledAutomaticModeDoesNotFollowCapture() {
        XCTAssertFalse(FilmingModeState(manual: false, automatic: false, isCaptured: true).isActive)
    }

    func testManualModeRemainsActiveAfterCaptureStops() {
        XCTAssertTrue(FilmingModeState(manual: true, automatic: false, isCaptured: false).isActive)
    }
}
