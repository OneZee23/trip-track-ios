import Foundation
import CoreLocation
import Combine
import OSLog

/// GPS diagnostics log. Flows into `DebugLogExporter` (subsystem `com.triptrack`)
/// so a user can export it and hand it over to debug field issues — e.g. "GPS
/// dropped in the taiga": the periodic summaries + reject reasons show whether
/// fixes stopped arriving, or arrived but were gated out for poor accuracy.
/// `.notice`/`.error` are persisted (exported); `.debug` is live-Console only.
private let gpsLog = Logger(subsystem: "com.triptrack", category: "gps")

/// Провайдер реального GPS
class RealGPSProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let locationSubject = PassthroughSubject<LocationUpdate, Never>()

    // MARK: GPS diagnostics (rolling window, summarized into the log)
    private var diagWindowStart = Date()
    private var diagFixes = 0
    private var diagAccepted = 0
    private var diagRejAccuracy = 0
    private var diagRejStale = 0
    private var diagRejSpeed = 0
    private var diagRejInvalid = 0
    private var diagAccMin = Double.greatestFiniteMagnitude
    private var diagAccMax = 0.0
    private var diagAccSum = 0.0
    private var lastAcceptedAt: Date?
    private var diagMaxGap: TimeInterval = 0
    /// Emit a rolling summary at most this often (seconds), driven by fix arrival.
    private let diagSummaryInterval: TimeInterval = 30

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
        gpsLog.notice("mode=IDLE accuracy=100m distanceFilter=50m bg=off")
    }

    /// High-accuracy mode for active trip recording
    func setRecordingMode() {
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5.0
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        gpsLog.notice("mode=RECORDING accuracy=bestForNavigation distanceFilter=5m bg=on auth=\(self.authString, privacy: .public)")

        // GPS needs ~2 seconds to recalibrate after accuracy change
        isWarmingUp = true
        warmUpTimer?.invalidate()
        warmUpTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.isWarmingUp = false
            gpsLog.notice("warm-up ended — fixes now eligible for recording")
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        resetDiagnostics()
        gpsLog.notice("start updating — recording=\(self.isRecording) auth=\(self.authString, privacy: .public)")
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        gpsLog.notice("stop updating")
    }

    /// Human-readable authorization state for the logs.
    private var authString: String {
        switch manager.authorizationStatus {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            let decision = evaluate(location)
            recordDiagnostics(location, decision)
            guard case .accept = decision else { continue }

            let update = LocationUpdate.from(location)
            currentLocation = update
            locationSubject.send(update)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError).map { String(describing: $0.code) } ?? "?"
        gpsLog.error("didFailWithError code=\(code, privacy: .public) — \(error.localizedDescription, privacy: .public)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        // iOS auto-paused updates — a PRIME "GPS отвалился" cause, so log it
        // loudly. During an active trip we force-resume so the track doesn't die.
        gpsLog.notice("iOS PAUSED updates (recording=\(self.isRecording)) — \(self.isRecording ? "force-resuming" : "left idle", privacy: .public)")
        if isRecording {
            manager.startUpdatingLocation()
        }
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        gpsLog.notice("iOS RESUMED updates")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        gpsLog.notice("authorization → \(self.authString, privacy: .public)")
        // Surface denial to the UI (Record idle → «Нет доступа к геолокации»).
        // iOS calls this delegate on CLLocationManager creation too, so the
        // initial state propagates without extra plumbing.
        let denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        NotificationCenter.default.post(name: .locationAuthDenied, object: denied)
    }

    // MARK: - Validity + diagnostics

    private enum FixDecision: Equatable { case accept; case reject(String) }

    /// Single place that decides whether a raw CL fix is usable, returning the
    /// reject REASON so diagnostics can attribute drops (esp. the taiga case).
    private func evaluate(_ location: CLLocation) -> FixDecision {
        guard location.horizontalAccuracy >= 0 else { return .reject("invalid") }
        // Accuracy ceiling during recording (65m; idle 100m). Both this gate and
        // TripManager's must move together. This is where heavy-canopy / remote
        // fixes get dropped — the summary below makes that visible.
        let accuracyLimit = isRecording ? 65.0 : maxAccuracy
        guard location.horizontalAccuracy <= accuracyLimit else { return .reject("accuracy") }
        // Reject stale cached positions.
        let age = -location.timestamp.timeIntervalSinceNow
        guard age < maxLocationAge else { return .reject("stale") }
        // We intentionally KEEP fixes with unknown speed (speed < 0) — valid in
        // the taiga; speed only feeds the drift filter, which ignores unknowns.
        let speed = max(0, location.speed)
        if speed > maxSpeedMs { return .reject("speed") }
        return .accept
    }

    private func isValidLocation(_ location: CLLocation) -> Bool { evaluate(location) == .accept }

    private func resetDiagnostics() {
        diagWindowStart = Date()
        diagFixes = 0; diagAccepted = 0
        diagRejAccuracy = 0; diagRejStale = 0; diagRejSpeed = 0; diagRejInvalid = 0
        diagAccMin = .greatestFiniteMagnitude; diagAccMax = 0; diagAccSum = 0
        diagMaxGap = 0
    }

    /// Per-fix accounting + a rolling `.notice` summary every ~30 s. The summary
    /// is the compact, exportable picture of GPS health: how many fixes arrived,
    /// how many were accepted vs gated out and why, the accuracy distribution,
    /// and the largest gap between accepted fixes. Per-fix lines are `.debug`
    /// (live Console only) to avoid drowning the exported log.
    private func recordDiagnostics(_ location: CLLocation, _ decision: FixDecision) {
        let now = Date()
        diagFixes += 1
        let acc = location.horizontalAccuracy
        if acc >= 0 {  // accuracy distribution over ALL valid-accuracy fixes
            diagAccMin = min(diagAccMin, acc); diagAccMax = max(diagAccMax, acc); diagAccSum += acc
        }

        switch decision {
        case .accept:
            diagAccepted += 1
            if let last = lastAcceptedAt {
                let gap = now.timeIntervalSince(last)
                diagMaxGap = max(diagMaxGap, gap)
                if gap >= 20 {
                    gpsLog.notice("accepted fix after \(Int(gap))s gap (acc=\(Int(acc))m) — dead stretch ended")
                }
            }
            lastAcceptedAt = now
            gpsLog.debug("fix ACCEPT acc=\(Int(acc))m spd=\(String(format: "%.1f", max(0, location.speed)))m/s")
        case .reject(let reason):
            switch reason {
            case "accuracy": diagRejAccuracy += 1
            case "stale": diagRejStale += 1
            case "speed": diagRejSpeed += 1
            default: diagRejInvalid += 1
            }
            gpsLog.debug("fix REJECT(\(reason, privacy: .public)) acc=\(Int(acc))m age=\(String(format: "%.1f", -location.timestamp.timeIntervalSinceNow))s")
        }

        if now.timeIntervalSince(diagWindowStart) >= diagSummaryInterval {
            let validAcc = diagFixes - diagRejInvalid
            let avg = validAcc > 0 ? Int(diagAccSum / Double(validAcc)) : 0
            let minStr = diagAccMin == .greatestFiniteMagnitude ? "-" : "\(Int(diagAccMin))"
            let win = Int(now.timeIntervalSince(diagWindowStart))
            gpsLog.notice("summary \(win)s: fixes=\(self.diagFixes) accepted=\(self.diagAccepted) rejected=\(self.diagFixes - self.diagAccepted)(acc:\(self.diagRejAccuracy) stale:\(self.diagRejStale) spd:\(self.diagRejSpeed) inv:\(self.diagRejInvalid)) acc[min/avg/max]=\(minStr)/\(avg)/\(Int(self.diagAccMax))m maxGapAccepted=\(Int(self.diagMaxGap))s rec=\(self.isRecording) warmup=\(self.isWarmingUp)")
            resetDiagnostics()
        }
    }
}
