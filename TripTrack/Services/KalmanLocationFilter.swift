import Foundation
import CoreLocation

/// Kalman filter for GPS smoothing and position prediction during signal gaps.
///
/// Uses a constant-velocity model in local ENU (East-North-Up) coordinates.
/// State vector: [east, north, velocityEast, velocityNorth]
final class KalmanLocationFilter {

    // MARK: - Public State

    /// Seconds since last GPS update
    var timeSinceLastGPS: TimeInterval {
        guard let t = lastGPSTime else { return .infinity }
        return Date().timeIntervalSince(t)
    }

    /// Whether we are actively predicting (GPS gap, within timeout)
    var isPredicting: Bool {
        guard lastGPSTime != nil, isInitialized else { return false }
        let elapsed = timeSinceLastGPS
        return elapsed > gpsGapThreshold && elapsed <= predictionTimeout
    }

    // MARK: - Configuration

    /// Minimum gap before we start predicting (seconds)
    private let gpsGapThreshold: TimeInterval = 2.0

    /// Maximum prediction duration without GPS (seconds)
    private let predictionTimeout: TimeInterval = 10.0

    /// Process noise acceleration (m/s²) — tuned for automotive
    private let processNoiseAccel: Double = 2.0

    // MARK: - Internal State

    private var isInitialized = false
    private var lastGPSTime: Date?
    private var lastPredictionTime: Date?

    // ENU origin (first GPS point)
    private var originLat: Double = 0
    private var originLon: Double = 0
    private var cosOriginLat: Double = 1

    // State vector [east, north, vE, vN]
    private var x: [Double] = [0, 0, 0, 0]

    // Covariance matrix P (4x4, stored as flat array row-major)
    private var P: [Double] = Array(repeating: 0, count: 16)

    // Last known altitude and course (passed through, not filtered)
    private var lastAltitude: Double = 0
    private var lastCourse: Double = -1

    // MARK: - Public Interface

    /// Process a GPS measurement. Returns a smoothed location.
    func processGPSUpdate(_ location: CLLocation) -> CLLocation {
        let now = location.timestamp

        if !isInitialized {
            initialize(with: location)
            lastGPSTime = now
            return location
        }

        let dt = now.timeIntervalSince(lastGPSTime ?? now)
        guard dt > 0 else {
            lastGPSTime = now
            return filteredLocation(timestamp: now)
        }

        // Predict step (advance state to current time)
        predict(dt: dt)

        // Convert measurement to ENU
        let (measE, measN) = latLonToENU(lat: location.coordinate.latitude,
                                          lon: location.coordinate.longitude)

        // Measurement noise from horizontal accuracy
        let accuracy = max(location.horizontalAccuracy, 1.0)
        let R = accuracy * accuracy  // variance in meters²

        // Update step (correct state with GPS measurement)
        update(measE: measE, measN: measN, R: R)

        // Also use GPS speed + course to correct velocity if available
        if location.speed >= 0 && location.course >= 0 {
            let speedMps = location.speed
            let courseRad = location.course * .pi / 180.0
            let vE = speedMps * sin(courseRad)
            let vN = speedMps * cos(courseRad)
            // Velocity update with moderate trust
            let Rv = max(accuracy * 0.5, 1.0)  // velocity noise
            let Rv2 = Rv * Rv
            updateVelocity(vE: vE, vN: vN, Rv2: Rv2)
        }

        lastGPSTime = now
        lastPredictionTime = nil
        lastAltitude = location.altitude
        if location.course >= 0 { lastCourse = location.course }

        return filteredLocation(timestamp: now)
    }

    /// Get predicted location during GPS gap. Returns nil if timeout exceeded or not initialized.
    func predictedLocation() -> CLLocation? {
        guard isInitialized, isPredicting else { return nil }

        let now = Date()
        let lastRef = lastPredictionTime ?? lastGPSTime ?? now
        let dt = now.timeIntervalSince(lastRef)
        guard dt > 0 else { return nil }

        predict(dt: dt)
        lastPredictionTime = now

        return filteredLocation(timestamp: now)
    }

    /// Reset all state (call when starting a new recording)
    func reset() {
        isInitialized = false
        lastGPSTime = nil
        lastPredictionTime = nil
        x = [0, 0, 0, 0]
        P = Array(repeating: 0, count: 16)
        lastAltitude = 0
        lastCourse = -1
    }

    // MARK: - Initialization

    private func initialize(with location: CLLocation) {
        originLat = location.coordinate.latitude
        originLon = location.coordinate.longitude
        cosOriginLat = cos(originLat * .pi / 180.0)

        x = [0, 0, 0, 0]  // at origin, zero velocity

        // Initial speed from GPS if available
        if location.speed > 0 && location.course >= 0 {
            let courseRad = location.course * .pi / 180.0
            x[2] = location.speed * sin(courseRad)
            x[3] = location.speed * cos(courseRad)
        }

        // Initial covariance: moderate position uncertainty, high velocity uncertainty
        let posVar = max(location.horizontalAccuracy * location.horizontalAccuracy, 25.0)
        let velVar = 100.0  // 10 m/s uncertainty
        P = [
            posVar, 0,      0,      0,
            0,      posVar, 0,      0,
            0,      0,      velVar, 0,
            0,      0,      0,      velVar
        ]

        lastAltitude = location.altitude
        if location.course >= 0 { lastCourse = location.course }
        isInitialized = true
    }

    // MARK: - Kalman Predict

    private func predict(dt: Double) {
        // State prediction: x' = F * x
        // F = [1  0  dt  0 ]
        //     [0  1  0   dt]
        //     [0  0  1   0 ]
        //     [0  0  0   1 ]
        x[0] += x[2] * dt  // east += vE * dt
        x[1] += x[3] * dt  // north += vN * dt
        // velocity unchanged (constant-velocity model)

        // Covariance prediction: P' = F * P * F^T + Q
        // Process noise Q based on acceleration uncertainty
        let q = processNoiseAccel * processNoiseAccel
        let dt2 = dt * dt
        let dt3 = dt2 * dt / 2.0
        let dt4 = dt2 * dt2 / 4.0

        // P' = F*P*F^T (expand manually for 4x4)
        let p = P
        var pNew = Array(repeating: 0.0, count: 16)

        // Row 0: east
        pNew[0]  = p[0] + dt * (p[2] + p[8]) + dt2 * p[10]  // P[0,0]
        pNew[1]  = p[1] + dt * (p[3] + p[9]) + dt2 * p[11]  // P[0,1]
        pNew[2]  = p[2] + dt * p[10]                          // P[0,2]
        pNew[3]  = p[3] + dt * p[11]                          // P[0,3]

        // Row 1: north
        pNew[4]  = p[4] + dt * (p[6] + p[12]) + dt2 * p[14]
        pNew[5]  = p[5] + dt * (p[7] + p[13]) + dt2 * p[15]
        pNew[6]  = p[6] + dt * p[14]
        pNew[7]  = p[7] + dt * p[15]

        // Row 2: vE
        pNew[8]  = p[8] + dt * p[10]
        pNew[9]  = p[9] + dt * p[11]
        pNew[10] = p[10]
        pNew[11] = p[11]

        // Row 3: vN
        pNew[12] = p[12] + dt * p[14]
        pNew[13] = p[13] + dt * p[15]
        pNew[14] = p[14]
        pNew[15] = p[15]

        // Add process noise Q
        // Q = q * [dt⁴/4  0      dt³/2  0     ]
        //         [0       dt⁴/4  0      dt³/2 ]
        //         [dt³/2   0      dt²    0     ]
        //         [0       dt³/2  0      dt²   ]
        pNew[0]  += q * dt4
        pNew[5]  += q * dt4
        pNew[2]  += q * dt3;  pNew[8]  += q * dt3
        pNew[7]  += q * dt3;  pNew[13] += q * dt3
        pNew[10] += q * dt2
        pNew[15] += q * dt2

        P = pNew
    }

    // MARK: - Kalman Update (position)

    private func update(measE: Double, measN: Double, R: Double) {
        // H = [1 0 0 0] for east, [0 1 0 0] for north
        // Update east
        let Se = P[0] + R  // innovation covariance
        guard Se > 1e-10 else { return }
        let Ke0 = P[0] / Se
        let Ke1 = P[4] / Se
        let Ke2 = P[8] / Se
        let Ke3 = P[12] / Se

        let ye = measE - x[0]  // innovation
        x[0] += Ke0 * ye
        x[1] += Ke1 * ye
        x[2] += Ke2 * ye
        x[3] += Ke3 * ye

        // Update P for east measurement
        // P = (I - K*H) * P
        var pTemp = P
        for i in 0..<4 {
            let Ki: Double
            switch i {
            case 0: Ki = Ke0
            case 1: Ki = Ke1
            case 2: Ki = Ke2
            case 3: Ki = Ke3
            default: Ki = 0
            }
            for j in 0..<4 {
                pTemp[i * 4 + j] -= Ki * P[j]  // P[0, j] is first row
            }
        }
        P = pTemp

        // Update north
        let Sn = P[5] + R
        guard Sn > 1e-10 else { return }
        let Kn0 = P[1] / Sn
        let Kn1 = P[5] / Sn
        let Kn2 = P[9] / Sn
        let Kn3 = P[13] / Sn

        let yn = measN - x[1]
        x[0] += Kn0 * yn
        x[1] += Kn1 * yn
        x[2] += Kn2 * yn
        x[3] += Kn3 * yn

        pTemp = P
        for i in 0..<4 {
            let Ki: Double
            switch i {
            case 0: Ki = Kn0
            case 1: Ki = Kn1
            case 2: Ki = Kn2
            case 3: Ki = Kn3
            default: Ki = 0
            }
            for j in 0..<4 {
                pTemp[i * 4 + j] -= Ki * P[4 + j]  // second row of P (H for north)
            }
        }
        P = pTemp
    }

    // MARK: - Kalman Update (velocity)

    private func updateVelocity(vE: Double, vN: Double, Rv2: Double) {
        // H = [0 0 1 0] for vE
        let SvE = P[10] + Rv2
        guard SvE > 1e-10 else { return }
        let K0 = P[2] / SvE
        let K1 = P[6] / SvE
        let K2 = P[10] / SvE
        let K3 = P[14] / SvE

        let yv = vE - x[2]
        x[0] += K0 * yv
        x[1] += K1 * yv
        x[2] += K2 * yv
        x[3] += K3 * yv

        var pTemp = P
        for i in 0..<4 {
            let Ki: Double
            switch i {
            case 0: Ki = K0
            case 1: Ki = K1
            case 2: Ki = K2
            case 3: Ki = K3
            default: Ki = 0
            }
            for j in 0..<4 {
                pTemp[i * 4 + j] -= Ki * P[2 * 4 + j]
            }
        }
        P = pTemp

        // H = [0 0 0 1] for vN
        let SvN = P[15] + Rv2
        guard SvN > 1e-10 else { return }
        let Kn0 = P[3] / SvN
        let Kn1 = P[7] / SvN
        let Kn2 = P[11] / SvN
        let Kn3 = P[15] / SvN

        let yn = vN - x[3]
        x[0] += Kn0 * yn
        x[1] += Kn1 * yn
        x[2] += Kn2 * yn
        x[3] += Kn3 * yn

        pTemp = P
        for i in 0..<4 {
            let Ki: Double
            switch i {
            case 0: Ki = Kn0
            case 1: Ki = Kn1
            case 2: Ki = Kn2
            case 3: Ki = Kn3
            default: Ki = 0
            }
            for j in 0..<4 {
                pTemp[i * 4 + j] -= Ki * P[3 * 4 + j]
            }
        }
        P = pTemp
    }

    // MARK: - Coordinate Conversion

    private static let metersPerDegreeLat: Double = 111_320.0

    private func latLonToENU(lat: Double, lon: Double) -> (east: Double, north: Double) {
        let north = (lat - originLat) * Self.metersPerDegreeLat
        let east = (lon - originLon) * Self.metersPerDegreeLat * cosOriginLat
        return (east, north)
    }

    private func enuToLatLon(east: Double, north: Double) -> (lat: Double, lon: Double) {
        let lat = originLat + north / Self.metersPerDegreeLat
        let lon = originLon + east / (Self.metersPerDegreeLat * cosOriginLat)
        return (lat, lon)
    }

    // MARK: - Output

    private func filteredLocation(timestamp: Date) -> CLLocation {
        let (lat, lon) = enuToLatLon(east: x[0], north: x[1])

        // Compute estimated accuracy from covariance diagonal
        let posVariance = max(P[0], P[5])
        let estimatedAccuracy = sqrt(max(posVariance, 0))

        // Compute speed and course from velocity state
        let speed = sqrt(x[2] * x[2] + x[3] * x[3])
        let course: Double
        if speed > 0.5 {
            course = atan2(x[2], x[3]) * 180.0 / .pi
        } else {
            course = lastCourse
        }
        let normalizedCourse = course < 0 ? course + 360.0 : course

        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: lastAltitude,
            horizontalAccuracy: estimatedAccuracy,
            verticalAccuracy: -1,
            course: normalizedCourse,
            speed: speed,
            timestamp: timestamp
        )
    }
}
