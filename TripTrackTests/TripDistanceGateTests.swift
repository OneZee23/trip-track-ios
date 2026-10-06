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
        // Порог записан в СИ вместе со сплитом: 50 км/ч — это 13.9 м/с.
        XCTAssertLessThan(trip.movingAverageSpeedMS, 50 / 3.6,
                          "Teleport segment must not inflate the moving average")
    }

    func testExplicitPauseExcludesPlausibleMissingJourneyButKeepsBothRecordedLegs() {
        let samples = [sample(0, 0), sample(10, 1),
                       sample(5010, 121, segment: 1), sample(5020, 122, segment: 1)]
        XCTAssertEqual(TripDistanceGate.totalDistance(samples), 20, accuracy: 0.1)
    }

    func testSparseGPSWithoutPauseStillCountsTheBridge() {
        let samples = [sample(0, 0), sample(10, 1), sample(5010, 121), sample(5020, 122)]
        XCTAssertEqual(TripDistanceGate.totalDistance(samples), 5020, accuracy: 10)
    }

    func testPauseResetsAnchorBeforeMinimumDistanceCheck() {
        let samples = [sample(0, 0), sample(4, 1, segment: 1), sample(8, 2, segment: 1),
                       sample(10, 3, segment: 1)]
        XCTAssertEqual(TripDistanceGate.totalDistance(samples), 6, accuracy: 0.1)
    }

    func testShortExplicitPauseIsExcludedFromMovementTimeAndDistance() {
        func point(_ north: Double, _ seconds: Double) -> TrackPoint {
            let c = TrackTestKit.coordinate(east: 0, north: north)
            return TrackPoint(latitude: c.latitude, longitude: c.longitude, speed: 10,
                              timestamp: TrackTestKit.epoch.addingTimeInterval(seconds))
        }
        var trip = Trip(startDate: TrackTestKit.epoch,
                        endDate: TrackTestKit.epoch.addingTimeInterval(13),
                        trackPoints: [point(0, 0), point(10, 1), point(110, 12), point(120, 13)])
        trip.recordingBreaks = [TrackTestKit.epoch.addingTimeInterval(12)]
        XCTAssertEqual(trip.measuredPoints.map(\.recordingSegmentIndex), [0, 0, 1, 1])
        XCTAssertEqual(trip.drivingTime, 2, accuracy: 0.01)
        XCTAssertEqual(trip.stoppedTime, 0, accuracy: 0.01)
        XCTAssertEqual(trip.movingAverageSpeedMS, 10, accuracy: 0.1)
    }

    // MARK: - Maximum supported by recorded measurements

    func testMaximumKeepsAValidSpeedFromTheFirstRecordedPoint() {
        let samples = [sample(0, 0, speed: 25), sample(100, 5, speed: 0)]
        XCTAssertEqual(TripDistanceGate.maximumRecordedSpeed(samples), 25)
    }

    func testLongGPSGapWithStoppedArrivalStillProvesTheTripWasMoving() {
        let samples = [sample(0, 0, speed: 0), sample(5000, 240, speed: 0)]
        XCTAssertEqual(TripDistanceGate.maximumRecordedSpeed(samples), 5000 / 240.0, accuracy: 0.1)
        XCTAssertEqual(samples.last?.speed, 0, "The maximum lower bound must not rewrite arrival speed")
    }

    func testLongGPSGapUsesPlausibleDisplacementWhenSpeedsAreUnknownOrCorrupt() {
        let samples = [sample(0, 0, speed: -1), sample(5000, 240, speed: 1000)]
        XCTAssertEqual(TripDistanceGate.maximumRecordedSpeed(samples), 5000 / 240.0, accuracy: 0.1)
    }

    func testMaximumDoesNotInferTravelDuringAnExplicitPause() {
        let samples = [sample(0, 0, speed: 0), sample(5000, 240, segment: 1, speed: 0)]
        XCTAssertEqual(TripDistanceGate.maximumRecordedSpeed(samples), 0)
    }

    func testMaximumIgnoresImpossibleJumpRatherThanClampingToTheSpeedCeiling() {
        let samples = [sample(0, 0, speed: -1), sample(5000, 11, speed: 1000)]
        XCTAssertEqual(TripDistanceGate.maximumRecordedSpeed(samples), 0)
    }

    func testDenseGeometryDoesNotInventAMaximumWhenSpeedWasNotMeasured() {
        let samples = [sample(0, 0, speed: -1), sample(100, 10, speed: -1)]
        XCTAssertEqual(TripDistanceGate.maximumRecordedSpeed(samples), 0)
    }

    func testNonFiniteAndUnknownSpeedsAreNotRecords() {
        let samples = [sample(0, 0, speed: .nan), sample(0, 1, speed: .infinity),
                       sample(0, 2, speed: -1)]
        XCTAssertEqual(TripDistanceGate.maximumRecordedSpeed(samples), 0)
    }

    private func sample(_ north: Double, _ seconds: Double, segment: Int = 0,
                        speed: Double? = nil) -> TripDistanceGate.Sample {
        let c = TrackTestKit.coordinate(east: 0, north: north)
        return .init(latitude: c.latitude, longitude: c.longitude,
                     timestamp: TrackTestKit.epoch.addingTimeInterval(seconds), recordingSegmentIndex: segment,
                     speed: speed)
    }
}
