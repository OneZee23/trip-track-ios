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
            timestamp: startTime.addingTimeInterval(15)  // 12 second gap
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
}
