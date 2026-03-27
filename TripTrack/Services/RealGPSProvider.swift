import Foundation
import CoreLocation
import Combine

/// Провайдер реального GPS
class RealGPSProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let locationSubject = PassthroughSubject<LocationUpdate, Never>()

    private(set) var currentLocation: LocationUpdate?

    var locationPublisher: AnyPublisher<LocationUpdate, Never> {
        locationSubject.eraseToAnyPublisher()
    }

    private let maxAccuracy: Double = 100.0 // meters
    private let maxSpeedMs: Double = 83.3 // ~300 km/h
    private let maxLocationAge: TimeInterval = 10.0 // seconds

    /// Whether we're actively recording a trip (used to force-resume if iOS pauses updates)
    var isRecording = false

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
    }

    /// High-accuracy mode for active trip recording
    func setRecordingMode() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5.0
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
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
        print("⚠️ iOS paused location updates (isRecording: \(isRecording))")
        if isRecording {
            // Force resume — we must keep tracking during an active trip
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        print("✅ iOS resumed location updates")
    }
    
    private func isValidLocation(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxAccuracy else {
            return false
        }
        
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < maxLocationAge else {
            return false
        }
        
        let speed = max(0, location.speed)
        if speed > maxSpeedMs {
            return false
        }
        
        return true
    }
}
