import Foundation
import CoreLocation
import Combine

/// Провайдер реального GPS
class RealGPSProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let locationSubject = PassthroughSubject<LocationUpdate, Never>()

    private(set) var currentLocation: LocationUpdate?

    /// System-cached last known location (available without active updates).
    var cachedSystemLocation: CLLocation? { manager.location }

    var locationPublisher: AnyPublisher<LocationUpdate, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    private let maxAccuracy: Double = 100.0 // meters
    private let maxSpeedMs: Double = 83.3 // ~300 km/h
    private let maxLocationAge: TimeInterval = 10.0 // seconds

    /// Whether we're actively recording a trip (used to force-resume if iOS pauses updates)
    var isRecording = false

    /// GPS warm-up: first 2 seconds after mode switch produce unreliable data
    private(set) var isWarmingUp = false
    private var warmUpTimer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        setIdleMode()
    }

    private var isRunning = false

    /// Low-power mode for showing user position without recording
    func setIdleMode() {
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50.0
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        isWarmingUp = false
        warmUpTimer?.invalidate()
    }

    /// High-accuracy mode for active trip recording
    func setRecordingMode() {
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5.0
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true

        // GPS needs ~2 seconds to recalibrate after accuracy change
        isWarmingUp = true
        warmUpTimer?.invalidate()
        warmUpTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.isWarmingUp = false
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard isValidLocation(location) else { continue }

            let update = LocationUpdate.from(location)
            currentLocation = update
            locationSubject.send(update)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        if isRecording {
            // Force resume — we must keep tracking during an active trip
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {}

    private func isValidLocation(_ location: CLLocation) -> Bool {
        // Reject invalid accuracy
        guard location.horizontalAccuracy >= 0 else { return false }

        // Stricter accuracy threshold during recording
        let accuracyLimit = isRecording ? 50.0 : maxAccuracy
        guard location.horizontalAccuracy <= accuracyLimit else { return false }

        // Reject stale cached positions
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < maxLocationAge else { return false }

        // Reject unknown speed during recording
        if isRecording && location.speed < 0 { return false }

        // Reject unrealistic speed
        let speed = max(0, location.speed)
        if speed > maxSpeedMs { return false }

        return true
    }
}
