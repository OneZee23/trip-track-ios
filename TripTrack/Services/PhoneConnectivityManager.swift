import Foundation
import WatchConnectivity

/// iPhone-side WCSession glue for the Watch companion.
///
/// Architecture: the iPhone is the single source of truth for trip state
/// (recording lives entirely in `TripManager` / `MapViewModel`). This
/// class:
///   1. Publishes state snapshots to the Watch via
///      `updateApplicationContext` — latest-wins, low-power, survives
///      app suspension.
///   2. Receives start/stop/pause/resume messages from the Watch and
///      routes them to `MapViewModel.toggleRecording()` /
///      `togglePause()`.
///
/// MapViewModel installs a weak reference at init time so commands
/// from the wrist hit the same control surface as on-screen taps.
/// No second `CLLocationManager` on the Watch — GPS-on-wrist would
/// double battery cost AND introduce sample-rate / source conflicts.
final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()

    weak var mapViewModel: MapViewModel?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Snapshot push to the paired Watch. Safe to call rapid-fire from
    /// the location-update callback — `updateApplicationContext` is
    /// debounced by WatchConnectivity and only the latest dict reaches
    /// the watch. Skipped silently when no watch is paired or the
    /// session isn't activated yet (cold-launch race).
    func publish(
        isRecording: Bool,
        isPaused: Bool,
        speedKmh: Double,
        distanceKm: Double,
        elapsedSeconds: Int
    ) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        let payload: [String: Any] = [
            "isRecording": isRecording,
            "isPaused": isPaused,
            "speedKmh": speedKmh,
            "distanceKm": distanceKm,
            "elapsedSeconds": elapsedSeconds,
        ]
        try? session.updateApplicationContext(payload)
    }

    // MARK: - WCSessionDelegate (called on the WC delivery queue, not main)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // iOS-only callback when the active watch is switched (e.g. user
        // pairs a new device). Re-activate to keep the channel open.
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        DispatchQueue.main.async { [weak self] in
            self?.route(action: action)
        }
    }

    @MainActor
    private func route(action: String) {
        guard let vm = mapViewModel else { return }
        switch action {
        case "start":
            if !vm.isRecording { vm.toggleRecording() }
        case "stop":
            if vm.isRecording { vm.toggleRecording() }
        case "pause":
            if vm.isRecording, !vm.isPaused { vm.togglePause(source: .watch) }
        case "resume":
            if vm.isRecording, vm.isPaused { vm.togglePause(source: .watch) }
        default:
            break
        }
    }
}
