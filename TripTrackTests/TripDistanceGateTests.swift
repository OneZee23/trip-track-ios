import XCTest
@testable import TripTrack

/// Locks in the distance/stat gate that decides whether a GPS segment counts —
/// the logic behind the v0.5.7 "0 km in the taiga" fix. Pure (no CoreData), so
/// it's a deterministic regression net for tomorrow's real inter-city drive.
final class TripDistanceGateTests: XCTestCase {

    // MARK: Implied-speed gate (dt > 0)

    func testHighwaySegmentCounts() {
        // ~100 km/h: 28 m over 1 s. Well under the 83 m/s ceiling.
        XCTAssertTrue(TripDistanceGate.isPlausibleSegment(meters: 28, dt: 1))
    }

    func testSparseGpsDeadZoneBridgeCounts() {
        // THE fix: 5 km covered over 2 minutes in a dead zone (tunnel / taiga) is
        // ~42 m/s (~150 km/h) — implausibly long for the OLD 1 km absolute cap,
        // but a perfectly sane SPEED, so it must still count toward distance.
        XCTAssertTrue(TripDistanceGate.isPlausibleSegment(meters: 5000, dt: 120))
    }

    func testTeleportJumpRejected() {
        // 5 km in 1 s = 5000 m/s — a GPS multipath / dropout snap-back. Rejected.
        XCTAssertFalse(TripDistanceGate.isPlausibleSegment(meters: 5000, dt: 1))
    }

    func testSpeedCeilingBoundary() {
        // Exactly 83 m/s counts (<=); just over does not.
        XCTAssertTrue(TripDistanceGate.isPlausibleSegment(meters: 83, dt: 1))
        XCTAssertFalse(TripDistanceGate.isPlausibleSegment(meters: 83.01, dt: 1))
    }

    func testSlowStationaryDriftStillCounts() {
        // Documents CURRENT behavior (deferred audit #6): slow engine-on multipath
        // drift (3 m over 2 s ≈ 1.5 m/s) is BELOW the ceiling, so it is counted.
        // If #6 is ever addressed with a dwell guard, this expectation changes.
        XCTAssertTrue(TripDistanceGate.isPlausibleSegment(meters: 3, dt: 2))
    }

    // MARK: Absolute-cap fallback (no usable dt)

    func testNoTimestampFallbackUnderCapCounts() {
        XCTAssertTrue(TripDistanceGate.isPlausibleSegment(meters: 999, dt: 0))
    }

    func testNoTimestampFallbackAtOrOverCapRejected() {
        XCTAssertFalse(TripDistanceGate.isPlausibleSegment(meters: 1000, dt: 0))
        XCTAssertFalse(TripDistanceGate.isPlausibleSegment(meters: 1500, dt: 0))
    }

    func testNegativeDtUsesAbsoluteCap() {
        // Clock skew / out-of-order fix (dt <= 0) → fall back to the distance cap,
        // matching the pre-extraction behavior (the `> 0` guard failed → else cap).
        XCTAssertTrue(TripDistanceGate.isPlausibleSegment(meters: 500, dt: -5))
        XCTAssertFalse(TripDistanceGate.isPlausibleSegment(meters: 1500, dt: -5))
    }

    // MARK: - movementSplit (the gate applied inside Trip's moving-average)

    /// A realistic mixed track — moving, idle, a >60 s gap, and a GPS teleport —
    /// drives Trip.movementSplit. drivingTime/stoppedTime are exact dt sums; the
    /// moving average must NOT be inflated by the teleport segment (the gate
    /// excludes it), which is exactly the "these numbers look wrong" class of bug.
    func testMovementSplitExcludesTeleportFromMovingAverage() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func pt(_ dLon: Double, _ sec: TimeInterval, speed: Double) -> TrackPoint {
            TrackPoint(latitude: 55.0, longitude: 37.0 + dLon,
                       speed: speed, timestamp: t0.addingTimeInterval(sec))
        }
        let points = [
            pt(0.000,   0, speed: 20),  // ─┐ moving (72 km/h)
            pt(0.001,  10, speed: 20),  // ─┘ drv += 10, ~64 m
            pt(0.001,  20, speed: 0),   //    avg 36 km/h → still "moving", 0 m
            pt(0.001,  30, speed: 0),   //    avg 0 → STOPPED, stp += 10
            pt(0.002, 200, speed: 20),  //    170 s gap from prev → EXCLUDED
            pt(0.100, 210, speed: 20),  //    ~6.3 km in 10 s → TELEPORT → EXCLUDED
        ]
        let trip = Trip(startDate: t0, endDate: t0.addingTimeInterval(210), trackPoints: points)

        XCTAssertEqual(trip.drivingTime, 20, accuracy: 0.01,
                       "Two <=60s moving segments; gap + teleport excluded")
        XCTAssertEqual(trip.stoppedTime, 10, accuracy: 0.01,
                       "One idle (speed 0) segment")
        // Real moving avg here is ~12 km/h. WITHOUT the gate the 6.3 km teleport
        // would be added → ~1000+ km/h. So a low value proves the gate held.
        XCTAssertLessThan(trip.movingAverageSpeedKmh, 50,
                          "Teleport segment must not inflate the moving average")
    }
}
