import Foundation
import WatchConnectivity
import Combine

/// Watch-side WCSession glue.
///
/// The watch app is intentionally a thin remote — it never starts its
/// own `CLLocationManager`, never persists trip state. All recording
/// runs on the phone; the watch (1) receives state snapshots via
/// `updateApplicationContext`, (2) sends start/stop/pause messages via
/// `sendMessage`. Single source of truth on the phone avoids
/// dual-recorder hazards (drift, conflicting saves on bad connectivity).
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var speedKmh: Double = 0
    @Published private(set) var distanceKm: Double = 0
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var isReachable = false
    @Published private(set) var lastError: String?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// Send a control command to the phone. `sendMessage` requires the
    /// phone to be reachable in foreground — for background queueing
    /// we'd use `transferUserInfo`, but trip control is a foreground
    /// action by design (user is looking at their wrist).
    func send(action: String) {
        guard WCSession.default.isReachable else {
            lastError = "phone unreachable"
            return
        }
        WCSession.default.sendMessage(["action": action], replyHandler: nil) { [weak self] err in
            DispatchQueue.main.async {
                self?.lastError = err.localizedDescription
            }
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            if let error { self.lastError = error.localizedDescription }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.applyContext(applicationContext) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { self.applyContext(message) }
    }

    private func applyContext(_ ctx: [String: Any]) {
        if let v = ctx["isRecording"] as? Bool { isRecording = v }
        if let v = ctx["isPaused"] as? Bool { isPaused = v }
        if let v = ctx["speedKmh"] as? Double { speedKmh = v }
        if let v = ctx["distanceKm"] as? Double { distanceKm = v }
        if let v = ctx["elapsedSeconds"] as? Int { elapsedSeconds = v }
    }
}
