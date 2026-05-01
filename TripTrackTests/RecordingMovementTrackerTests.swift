import XCTest
@testable import TripTrack

final class RecordingMovementTrackerTests: XCTestCase {

    func testFirstSampleSeedsBaselineAndReturnsFalse() {
        var t = RecordingMovementTracker()
        let now = Date()
        XCTAssertFalse(t.record(currentDistance: 0, now: now))
        XCTAssertEqual(t.lastDistanceMeters, 0)
        XCTAssertEqual(t.lastChangeTime, now)
    }

    func testGrowthBelowThresholdDoesNotReset() {
        var t = RecordingMovementTracker()
        let t0 = Date()
        t.record(currentDistance: 0, now: t0)
        let t1 = t0.addingTimeInterval(60)
        // Below threshold (default 100m) — clock keeps ticking
        XCTAssertFalse(t.record(currentDistance: 50, now: t1))
        XCTAssertEqual(t.lastDistanceMeters, 0, "baseline must not move on sub-threshold growth")
        XCTAssertEqual(t.lastChangeTime, t0, "change time must not advance on sub-threshold growth")
    }

    func testGrowthAtOrAboveThresholdResetsBaseline() {
        var t = RecordingMovementTracker()
        let t0 = Date()
        t.record(currentDistance: 0, now: t0)
        let t1 = t0.addingTimeInterval(30)
        XCTAssertTrue(t.record(currentDistance: AutoTripPolicy.meaningfulMovementDistance, now: t1))
        XCTAssertEqual(t.lastDistanceMeters, AutoTripPolicy.meaningfulMovementDistance)
        XCTAssertEqual(t.lastChangeTime, t1)
    }

    func testIsStaleReturnsFalseBeforeAnyRecord() {
        let t = RecordingMovementTracker()
        XCTAssertFalse(t.isStale(threshold: 60))
    }

    func testIsStaleFalseInsideWindow() {
        var t = RecordingMovementTracker()
        let t0 = Date()
        t.record(currentDistance: 0, now: t0)
        XCTAssertFalse(t.isStale(threshold: 600, now: t0.addingTimeInterval(599)))
    }

    func testIsStaleTrueOutsideWindow() {
        var t = RecordingMovementTracker()
        let t0 = Date()
        t.record(currentDistance: 0, now: t0)
        XCTAssertTrue(t.isStale(threshold: 600, now: t0.addingTimeInterval(601)))
    }

    func testRecordingMovementDuringStaleWindowResetsStaleness() {
        var t = RecordingMovementTracker()
        let t0 = Date()
        t.record(currentDistance: 0, now: t0)
        // 9.5 min later — still not stale
        let t1 = t0.addingTimeInterval(570)
        XCTAssertFalse(t.isStale(threshold: 600, now: t1))
        // Move the car — clock resets at this moment
        t.record(currentDistance: AutoTripPolicy.meaningfulMovementDistance, now: t1)
        // 9.5 min after that — still not stale
        let t2 = t1.addingTimeInterval(570)
        XCTAssertFalse(t.isStale(threshold: 600, now: t2))
    }

    func testExtendWindowBumpsClockOnly() {
        var t = RecordingMovementTracker()
        let t0 = Date()
        t.record(currentDistance: 250, now: t0)
        let t1 = t0.addingTimeInterval(900)
        t.extendWindow(to: t1)
        XCTAssertEqual(t.lastChangeTime, t1)
        // Distance baseline must NOT change — extendWindow is for "user said
        // continue", not for "we saw movement"
        XCTAssertEqual(t.lastDistanceMeters, 250)
    }

    func testResetClearsBaselineAndTime() {
        var t = RecordingMovementTracker()
        t.record(currentDistance: 500, now: Date())
        t.reset()
        XCTAssertNil(t.lastDistanceMeters)
        XCTAssertNil(t.lastChangeTime)
        XCTAssertFalse(t.isStale(threshold: 60))
    }

    func testRecordAfterResetSeedsFreshBaseline() {
        var t = RecordingMovementTracker()
        let t0 = Date()
        t.record(currentDistance: 5000, now: t0)
        t.reset()
        let t1 = t0.addingTimeInterval(120)
        // First post-reset call must NOT report movement (it's just seeding)
        XCTAssertFalse(t.record(currentDistance: 5000, now: t1))
        XCTAssertEqual(t.lastChangeTime, t1)
    }
}
