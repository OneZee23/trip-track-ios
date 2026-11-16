import XCTest
@testable import TripTrack

/// The lock screen card's pause button says what it showed.
///
/// ActivityKit spaces out updates in the background, so after a pause made on
/// the screen, in CarPlay or on the watch the card can still show «Пауза».
/// The button used to toggle: pressed on such a card, it resumed the trip the
/// person had just paused, and the next stereo or inactivity rule was free to
/// end it. The owner's car test of 7 Nov 2026 resumed at 17:40:48 without a
/// clear source; this closes one of the ways it could have happened.
final class PauseIntentDecisionTests: XCTestCase {

    func testPauseOnARunningTripPauses() {
        XCTAssertTrue(PauseIntentDecision.shouldToggle(target: true, isPaused: false))
    }

    func testResumeOnAPausedTripResumes() {
        XCTAssertTrue(PauseIntentDecision.shouldToggle(target: false, isPaused: true))
    }

    func testPauseOnALaggingCardKeepsThePause() {
        XCTAssertFalse(PauseIntentDecision.shouldToggle(target: true, isPaused: true))
    }

    func testResumeOnALaggingCardDoesNotPause() {
        XCTAssertFalse(PauseIntentDecision.shouldToggle(target: false, isPaused: false))
    }

    /// A card started by a build before 0.9.4 survives the update with a
    /// parameterless button, and that button must still work.
    func testAnOldCardStillToggles() {
        XCTAssertTrue(PauseIntentDecision.shouldToggle(target: nil, isPaused: false))
        XCTAssertTrue(PauseIntentDecision.shouldToggle(target: nil, isPaused: true))
    }

    /// The intent the cards are drawn with carries the target, and its
    /// handler passes it on unchanged.
    @MainActor
    func testTheIntentHandsItsTargetToTheApp() async throws {
        var received: [Bool?] = []
        let handler = TripIntentHandler.shared
        let previous = handler.onPause
        defer { handler.onPause = previous }
        handler.onPause = { received.append($0) }

        _ = try await PauseTripIntent(pause: true).perform()
        _ = try await PauseTripIntent(pause: false).perform()
        _ = try await PauseTripIntent().perform()

        XCTAssertEqual(received, [true, false, nil])
    }
}
