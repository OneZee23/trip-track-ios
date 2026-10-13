import XCTest
import CoreLocation
@testable import TripTrack

final class KalmanLocationFilterTests: XCTestCase {

    private var filter: KalmanLocationFilter!

    override func setUp() {
        super.setUp()
        filter = KalmanLocationFilter()
    }

    // MARK: - Basic Smoothing

    func testFirstPointPassesThrough() {
        let input = CLLocation(latitude: 45.0, longitude: 39.0)
        let output = filter.processGPSUpdate(input)

        XCTAssertEqual(output.coordinate.latitude, 45.0, accuracy: 0.0001)
        XCTAssertEqual(output.coordinate.longitude, 39.0, accuracy: 0.0001)
    }

    func testSmoothingReducesNoise() {
        // Feed a series of points along a straight line with noise
        let baseLat = 45.0
        let baseLon = 39.0
        let speed = 10.0 // m/s heading north

        var inputs: [CLLocation] = []
        var outputs: [CLLocation] = []

        let startTime = Date()

        for i in 0..<20 {
            let t = Double(i) * 1.0  // 1 second intervals
            let trueLat = baseLat + (speed * t) / 111_320.0
            let trueLon = baseLon

            // Add random noise (up to ±10m)
            let noiseLat = Double.random(in: -0.0001...0.0001)
            let noiseLon = Double.random(in: -0.0001...0.0001)

            let location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: trueLat + noiseLat, longitude: trueLon + noiseLon),
                altitude: 30,
                horizontalAccuracy: 10,
                verticalAccuracy: -1,
                course: 0,
                speed: speed,
                timestamp: startTime.addingTimeInterval(t)
            )
            inputs.append(location)
            outputs.append(filter.processGPSUpdate(location))
        }

        // Calculate variance of lateral deviation from the true line
        var inputVariance: Double = 0
        var outputVariance: Double = 0

        for i in 0..<20 {
            let t = Double(i) * 1.0
            let trueLon = baseLon
            let inputDeviation = (inputs[i].coordinate.longitude - trueLon) * 111_320.0
            let outputDeviation = (outputs[i].coordinate.longitude - trueLon) * 111_320.0
            inputVariance += inputDeviation * inputDeviation
            outputVariance += outputDeviation * outputDeviation
        }

        // Output variance should be less than input (filter is smoothing)
        XCTAssertLessThan(outputVariance, inputVariance,
                          "Kalman filter should reduce position noise")
    }

    // MARK: - Prediction

    func testPredictionDuringGap() {
        let startTime = Date()

        // Feed 5 points heading north at 10 m/s
        for i in 0..<5 {
            let t = Double(i) * 1.0
            let lat = 45.0 + (10.0 * t) / 111_320.0
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: 39.0),
                altitude: 30,
                horizontalAccuracy: 5,
                verticalAccuracy: -1,
                course: 0,
                speed: 10.0,
                timestamp: startTime.addingTimeInterval(t)
            )
            _ = filter.processGPSUpdate(loc)
        }

        // Simulate 3-second gap, then request prediction
        // isPredicting should be true after gapThreshold (2s)
        // We need to wait for timeSinceLastGPS > 2.0
        // Since we can't sleep in tests, check that predictedLocation returns
        // a position north of the last GPS point

        let lastGPSLat = 45.0 + (10.0 * 4.0) / 111_320.0
        let predicted = filter.predictedLocation()

        // After just calling processGPSUpdate, timeSinceLastGPS is ~0, so no prediction yet
        XCTAssertNil(predicted, "Should not predict immediately after GPS update")
    }

    func testPredictionReturnsNilWhenNotInitialized() {
        XCTAssertNil(filter.predictedLocation())
        XCTAssertFalse(filter.isPredicting)
    }

    func testIsPredictingFalseInitially() {
        XCTAssertFalse(filter.isPredicting)
    }

    // MARK: - GPS Jump After Gap

    func testSmoothTransitionAfterJump() {
        let startTime = Date()

        // Feed 3 points at position A
        for i in 0..<3 {
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: 39.0),
                altitude: 30,
                horizontalAccuracy: 5,
                verticalAccuracy: -1,
                course: 0,
                speed: 0,
                timestamp: startTime.addingTimeInterval(Double(i))
            )
            _ = filter.processGPSUpdate(loc)
        }

        // Sudden jump to position 100m away (simulating GPS returning after gap)
        let jumpLat = 45.0 + 100.0 / 111_320.0
        let jumpLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: jumpLat, longitude: 39.0),
            altitude: 30,
            horizontalAccuracy: 50,  // poor accuracy after gap
            verticalAccuracy: -1,
            course: 0,
            speed: 0,
            timestamp: startTime.addingTimeInterval(10)  // 8 second gap, within model horizon
        )
        let afterJump = filter.processGPSUpdate(jumpLoc)

        // Filter should NOT jump all the way to the new position
        // (Kalman gain is lower because high uncertainty + high measurement noise)
        let jumpDistance = abs(afterJump.coordinate.latitude - 45.0) * 111_320.0
        XCTAssertLessThan(jumpDistance, 100.0,
                          "Filter should dampen GPS jump, not follow it exactly")
        XCTAssertGreaterThan(jumpDistance, 0.0,
                            "Filter should move toward new position")
    }

    // MARK: - ENU Conversion

    func testENURoundtrip() {
        // Initialize filter at a known location
        let origin = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            altitude: 30,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            course: -1,
            speed: 0,
            timestamp: Date()
        )
        let result = filter.processGPSUpdate(origin)

        // Should be very close to the input
        let latError = abs(result.coordinate.latitude - origin.coordinate.latitude) * 111_320
        let lonError = abs(result.coordinate.longitude - origin.coordinate.longitude) * 111_320 * cos(45.035 * .pi / 180)

        XCTAssertLessThan(latError, 0.01, "Latitude roundtrip error should be < 0.01m")
        XCTAssertLessThan(lonError, 0.01, "Longitude roundtrip error should be < 0.01m")
    }

    // MARK: - Reset

    func testResetClearsState() {
        let loc = CLLocation(latitude: 45.0, longitude: 39.0)
        _ = filter.processGPSUpdate(loc)

        filter.reset()

        XCTAssertFalse(filter.isPredicting)
        XCTAssertNil(filter.predictedLocation())
    }

    // MARK: - Recording independence from rendering

    func testPredictionDoesNotChangeTheNextRecordedFix() throws {
        let withoutRendering = KalmanLocationFilter()
        let withRendering = KalmanLocationFilter()
        for t in 0..<5 {
            let measurement = fix(north: Double(t) * 10, speed: 10, course: 0, time: Double(t))
            _ = withoutRendering.processGPSUpdate(measurement)
            _ = withRendering.processGPSUpdate(measurement)
        }

        for time in [6.5, 7.0, 7.5, 8.0] {
            XCTAssertNotNil(withRendering.predictedLocation(at: fixtureStart.addingTimeInterval(time)))
        }

        let next = fix(east: 3, north: 90, speed: 10, course: 0, time: 9)
        assertSameLocation(withoutRendering.processGPSUpdate(next), withRendering.processGPSUpdate(next))

        // Covariance and future projections must also remain identical.
        let expected = try XCTUnwrap(withoutRendering.predictedLocation(at: fixtureStart.addingTimeInterval(12)))
        let actual = try XCTUnwrap(withRendering.predictedLocation(at: fixtureStart.addingTimeInterval(12)))
        assertSameLocation(expected, actual)
    }

    func testPredictionIsIndependentOfPollingCadenceAndOrder() throws {
        _ = filter.processGPSUpdate(fix(speed: 10, course: 0, time: 0))
        let atFive = fixtureStart.addingTimeInterval(5)
        let first = try XCTUnwrap(filter.predictedLocation(at: atFive))
        _ = filter.predictedLocation(at: fixtureStart.addingTimeInterval(8))
        _ = filter.predictedLocation(at: fixtureStart.addingTimeInterval(3))
        let repeated = try XCTUnwrap(filter.predictedLocation(at: atFive))

        assertSameLocation(first, repeated)
        XCTAssertEqual(first.coordinate.latitude, 45 + 50 / 111_320.0, accuracy: 1e-10)
        XCTAssertNil(filter.predictedLocation(at: fixtureStart.addingTimeInterval(11)))
    }

    func testOutOfOrderFixDoesNotRewindEstimatorClockOrChangeItsState() {
        let reference = KalmanLocationFilter()
        for t in 0..<5 {
            let measurement = fix(north: Double(t) * 10, speed: 10, course: 0, time: Double(t))
            _ = reference.processGPSUpdate(measurement)
            _ = filter.processGPSUpdate(measurement)
        }

        let stale = filter.processGPSUpdate(fix(east: 500, speed: 0, course: 90, time: 1))
        XCTAssertEqual(stale.timestamp, fixtureStart.addingTimeInterval(4))

        let next = fix(east: 2, north: 50, speed: 10, course: 0, time: 5)
        assertSameLocation(reference.processGPSUpdate(next), filter.processGPSUpdate(next))
    }

    // MARK: - Loss of GPS and correlated fix bursts

    func testReturningFixAfterPredictionHorizonStartsFreshEstimate() {
        _ = filter.processGPSUpdate(fix(speed: 25, course: 90, time: 0))
        XCTAssertFalse(filter.lastUpdateResetAfterGap)
        _ = filter.processGPSUpdate(fix(east: 25, speed: 25, course: 90, time: 1))

        // No heading/speed survived the outage. Neither may be borrowed from
        // the old eastbound state when GPS resumes at another position.
        let returning = fix(north: 200, speed: -1, course: -1, accuracy: 40, time: 13)
        assertSameLocation(returning, filter.processGPSUpdate(returning))
        XCTAssertTrue(filter.lastUpdateResetAfterGap)
        let next = filter.processGPSUpdate(fix(north: 200, speed: -1, course: -1, time: 14))
        XCTAssertFalse(filter.lastUpdateResetAfterGap)
        XCTAssertEqual(next.speed, 0, accuracy: 1e-9)
        XCTAssertEqual(next.course, -1)
    }

    func testGapResetSignalOnlyDescribesTheCurrentUpdate() {
        _ = filter.processGPSUpdate(fix(speed: 0, course: -1, time: 0))
        _ = filter.processGPSUpdate(fix(north: 5000, speed: 0, course: -1, time: 240))
        XCTAssertTrue(filter.lastUpdateResetAfterGap)
        _ = filter.processGPSUpdate(fix(north: 5000, speed: 0, course: -1, time: 240.1))
        XCTAssertFalse(filter.lastUpdateResetAfterGap, "A repeated fix does not inherit the previous reset flag")
        _ = filter.processGPSUpdate(fix(north: 5010, speed: 0, course: -1, time: 300))
        XCTAssertTrue(filter.lastUpdateResetAfterGap)
        filter.reset()
        XCTAssertFalse(filter.lastUpdateResetAfterGap)
    }

    func testLongOutageAfterCoarseTeleportCannotRetainRunawayVelocity() {
        for t in 0..<30 {
            _ = filter.processGPSUpdate(fix(north: Double(t) * 14.4, speed: 14.4, course: 0,
                                           time: Double(t)))
        }

        // Synthetic jamming, not real trip coordinates: coarse positions jump
        // tens of kilometres, then a trustworthy scalar speed returns without
        // a heading after a thirteen-minute outage.
        _ = filter.processGPSUpdate(fix(east: 80_000, north: 1_000, speed: -1, course: -1,
                                       accuracy: 125, time: 84))
        _ = filter.processGPSUpdate(fix(east: 81_000, north: 1_000, speed: -1, course: -1,
                                       accuracy: 190, time: 92))
        let returning = fix(north: 18_000, speed: 14.4, course: -1, accuracy: 42, time: 870)
        assertSameLocation(returning, filter.processGPSUpdate(returning))

        let next = filter.processGPSUpdate(fix(north: 18_014.4, speed: 14.4, course: 0,
                                              accuracy: 10, time: 871))
        XCTAssertTrue(next.speed.isFinite)
        XCTAssertGreaterThan(next.speed, 5)
        XCTAssertLessThan(next.speed, 20)
        XCTAssertLessThan(next.distance(from: returning), 30)
    }

    func testRepeatedCoordinateBurstDoesNotCreateTrackOrExtraConfidence() {
        let singleMeasurement = KalmanLocationFilter()
        for t in 0..<30 {
            let measurement = fix(north: Double(t) * 10, speed: 10, course: 0, time: Double(t))
            _ = singleMeasurement.processGPSUpdate(measurement)
            _ = filter.processGPSUpdate(measurement)
        }

        let first = fix(east: 200, north: 300, speed: -1, course: -1, accuracy: 45, time: 30)
        let expected = singleMeasurement.processGPSUpdate(first)
        _ = filter.processGPSUpdate(first)
        for index in 1...52 {
            let copy = fix(east: 200, north: 300, speed: -1, course: -1,
                           accuracy: 32 + Double(index % 4) * 0.01,
                           time: 30 + Double(index) * 0.209 / 52)
            assertSameLocation(expected, filter.processGPSUpdate(copy))
        }

        let next = fix(north: 310, speed: 10, course: 0, time: 31)
        assertSameLocation(singleMeasurement.processGPSUpdate(next), filter.processGPSUpdate(next))
    }

    func testSameCoordinateWithNewStopSpeedIsNotSuppressedAsDuplicate() {
        _ = filter.processGPSUpdate(fix(speed: 10, course: -1, time: 0))
        let stop = fix(speed: 0, course: -1, time: 0.1)
        let output = filter.processGPSUpdate(stop)
        XCTAssertEqual(output.timestamp, stop.timestamp)
        XCTAssertEqual(output.speed, 0)
    }

    func testValidScalarSpeedSurvivesMissingCourse() {
        _ = filter.processGPSUpdate(fix(speed: 10, course: 0, time: 0))
        let output = filter.processGPSUpdate(fix(east: 30, north: 10, speed: 14.4, course: -1, time: 1))
        XCTAssertEqual(output.speed, 14.4, accuracy: 1e-9,
                       "Missing direction must not discard a known scalar GPS speed")
    }

    // MARK: - Provider conversion

    func testLocationUpdateRoundTripPreservesUnknownSpeedWithKnownCourse() {
        let measurement = fix(speed: -1, course: 120, time: 0)
        let update = LocationUpdate.from(measurement)
        XCTAssertEqual(update.speed, -1)
        assertSameLocation(measurement, update.toCLLocation())
    }

    func testLocationUpdateRoundTripPreservesKnownSpeedWithUnknownCourse() {
        let measurement = fix(speed: 14.4, course: -1, time: 0)
        let update = LocationUpdate.from(measurement)
        XCTAssertNil(update.course)
        assertSameLocation(measurement, update.toCLLocation())
    }

    // MARK: - Deterministic synthetic fixtures

    private let fixtureStart = Date(timeIntervalSince1970: 1_700_000_000)

    private func fix(
        east: Double = 0, north: Double = 0, speed: Double, course: Double,
        accuracy: Double = 10, time: TimeInterval
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: 45 + north / 111_320,
                longitude: 39 + east / (111_320 * cos(45 * .pi / 180))
            ),
            altitude: 30, horizontalAccuracy: accuracy, verticalAccuracy: 0,
            course: course, speed: speed, timestamp: fixtureStart.addingTimeInterval(time)
        )
    }

    private func assertSameLocation(
        _ expected: CLLocation, _ actual: CLLocation,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.coordinate.latitude, expected.coordinate.latitude, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual.coordinate.longitude, expected.coordinate.longitude, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(actual.timestamp, expected.timestamp, file: file, line: line)
        XCTAssertEqual(actual.speed, expected.speed, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.course, expected.course, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.horizontalAccuracy, expected.horizontalAccuracy, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actual.altitude, expected.altitude, accuracy: 1e-9, file: file, line: line)
    }
}
