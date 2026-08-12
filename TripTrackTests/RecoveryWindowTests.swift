import XCTest
@testable import TripTrack

/// What happens when the app dies mid-recording — battery, memory pressure,
/// force-quit, reboot — and you open it again.
///
/// Both extremes are wrong, and the app has now been at each of them. Always
/// resuming silently (pre-6.1.0) kept a trip you abandoned hours ago quietly
/// recording. Always asking (6.1.0 as shipped) put a modal in front of someone
/// who crashed at a traffic light and is still driving. The canon calls for a
/// hybrid, and the window is the whole of it.
final class RecoveryWindowTests: XCTestCase {

    func testCrashSecondsAgoResumesWithoutAsking() {
        XCTAssertTrue(isFresh(secondsAgo: 5))
        XCTAssertTrue(isFresh(secondsAgo: 60))
    }

    /// The person is at a light, or a petrol station, or stuck in traffic —
    /// still on the same drive.
    func testCrashMinutesAgoStillResumesWithoutAsking() {
        XCTAssertTrue(isFresh(secondsAgo: 5 * 60))
        XCTAssertTrue(isFresh(secondsAgo: 14 * 60 + 59))
    }

    /// Past the window the answer stops being obvious, so it becomes a
    /// question instead of a guess.
    func testOlderThanTheWindowAsks() {
        XCTAssertFalse(isFresh(secondsAgo: 15 * 60 + 1))
        XCTAssertFalse(isFresh(secondsAgo: 60 * 60))
        XCTAssertFalse(isFresh(secondsAgo: 5 * 3600))
    }

    /// Fifteen minutes is a judgement call, but it has to stay in the range
    /// where «still driving» is the likely reading. A window of an hour would
    /// silently resume abandoned trips; one of a minute would ask constantly.
    func testWindowStaysInDefensibleRange() {
        XCTAssertGreaterThanOrEqual(TripManager.silentResumeWindow, 5 * 60)
        XCTAssertLessThanOrEqual(TripManager.silentResumeWindow, 30 * 60)
    }

    /// Anything past the restorable age is not offered at all — neither
    /// resumed nor asked about — so the two thresholds must not cross.
    func testSilentWindowSitsInsideTheRestorableAge() {
        XCTAssertLessThan(TripManager.silentResumeWindow, 6 * 3600)
    }

    private func isFresh(secondsAgo: TimeInterval) -> Bool {
        secondsAgo < TripManager.silentResumeWindow
    }
}
