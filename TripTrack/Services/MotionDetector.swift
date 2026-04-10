import Foundation
import CoreMotion

final class MotionDetector {
    private let motionManager = CMMotionActivityManager()
    private let motionQueue = OperationQueue()

    var onAutomotiveDetected: (() -> Void)?
    var onAutomotiveEnded: (() -> Void)?

    private var isAutomotive = false

    init() {
        motionQueue.maxConcurrentOperationCount = 1
    }

    // MARK: - Live Updates (foreground)

    func startLiveUpdates() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        motionManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
            guard let self, let activity else { return }
            guard activity.confidence == .high else { return }

            Task { @MainActor in
                if activity.automotive && !self.isAutomotive {
                    self.isAutomotive = true
                    self.onAutomotiveDetected?()
                } else if !activity.automotive && self.isAutomotive {
                    self.isAutomotive = false
                    self.onAutomotiveEnded?()
                }
            }
        }
    }

    func stopLiveUpdates() {
        motionManager.stopActivityUpdates()
        isAutomotive = false
    }

    // MARK: - Historical Query (background wake)

    /// Query last N seconds for automotive activity. Works after any wake event.
    func queryRecentAutomotive(seconds: TimeInterval = 300, completion: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            completion(false)
            return
        }

        let now = Date()
        let from = now.addingTimeInterval(-seconds)

        motionManager.queryActivityStarting(from: from, to: now, to: motionQueue) { activities, error in
            guard let activities, error == nil else {
                Task { @MainActor in completion(false) }
                return
            }

            let automotiveDetected = activities.contains {
                $0.automotive && $0.confidence == .high
            }

            Task { @MainActor in completion(automotiveDetected) }
        }
    }

    // MARK: - Authorization

    static var isAuthorized: Bool {
        CMMotionActivityManager.authorizationStatus() == .authorized
    }

    private static var authManager: CMMotionActivityManager?

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            completion(false)
            return
        }
        let manager = CMMotionActivityManager()
        authManager = manager // retain until callback
        let now = Date()
        manager.queryActivityStarting(from: now.addingTimeInterval(-1), to: now, to: .main) { _, error in
            authManager = nil
            let authorized = (error == nil) || CMMotionActivityManager.authorizationStatus() == .authorized
            completion(authorized)
        }
    }
}
