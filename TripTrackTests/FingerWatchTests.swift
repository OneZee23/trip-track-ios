import XCTest
@testable import TripTrack

/// Pinching out to see more of the map kept opening whichever region the last
/// finger was over. Two fingers do not land or lift together, so the straggler
/// is a perfectly ordinary tap — short and barely moved — and the map obeyed
/// it.
final class FingerWatchTests: XCTestCase {

    func testOneFingerTapGoesThrough() {
        XCTAssertFalse(FingerWatch.shouldIgnoreTap(
            activeTouches: 1, secondsSinceMultiTouch: nil))
    }

    func testTapIsIgnoredWhileASecondFingerIsStillDown() {
        XCTAssertTrue(FingerWatch.shouldIgnoreTap(
            activeTouches: 2, secondsSinceMultiTouch: nil))
        XCTAssertTrue(FingerWatch.shouldIgnoreTap(
            activeTouches: 3, secondsSinceMultiTouch: 0.01))
    }

    /// The actual bug: both fingers are already up, so the touch count is
    /// clean, and the tap arrives in the gap between them lifting.
    func testTapIsIgnoredJustAfterATwoFingerGesture() {
        XCTAssertTrue(FingerWatch.shouldIgnoreTap(
            activeTouches: 1, secondsSinceMultiTouch: 0.05))
        XCTAssertTrue(FingerWatch.shouldIgnoreTap(
            activeTouches: 1, secondsSinceMultiTouch: FingerWatch.multiTouchGrace - 0.01))
    }

    /// …but the guard has to let go, or a pinch would leave the map dead to
    /// touch. A deliberate tap after a pinch is a normal thing to do.
    func testTapWorksAgainOnceTheGraceWindowPasses() {
        XCTAssertFalse(FingerWatch.shouldIgnoreTap(
            activeTouches: 1, secondsSinceMultiTouch: FingerWatch.multiTouchGrace + 0.01))
        XCTAssertFalse(FingerWatch.shouldIgnoreTap(
            activeTouches: 1, secondsSinceMultiTouch: 5))
    }

    /// The window is a compromise: long enough to cover two fingers lifting,
    /// short enough that it never feels like the map stopped responding.
    func testGraceWindowStaysInHumanRange() {
        XCTAssertGreaterThanOrEqual(FingerWatch.multiTouchGrace, 0.25)
        XCTAssertLessThanOrEqual(FingerWatch.multiTouchGrace, 0.6)
    }
}
