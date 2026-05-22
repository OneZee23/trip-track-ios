import Foundation
import CoreMotion
import OSLog

private let motionLog = Logger(subsystem: "com.triptrack", category: "motion")

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
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionLog.notice("[motion.start.skip] reason=activity_unavailable")
            return
        }
        motionLog.notice("[motion.start_live]")

        motionManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
            guard let self, let activity else { return }
            guard activity.confidence == .high else {
                motionLog.debug("[motion.update.skip] reason=confidence_not_high confidence=\(self.confidenceString(activity.confidence), privacy: .public)")
                return
            }

            Task { @MainActor in
                if activity.automotive && !self.isAutomotive {
                    motionLog.notice("[motion.transition] from=\(self.activityKindString(prevAutomotive: false, activity: activity), privacy: .public) to=automotive confidence=high")
                    self.isAutomotive = true
                    self.onAutomotiveDetected?()
                } else if !activity.automotive && self.isAutomotive {
                    motionLog.notice("[motion.transition] from=automotive to=\(self.activityKindString(prevAutomotive: true, activity: activity), privacy: .public) confidence=high")
                    self.isAutomotive = false
                    self.onAutomotiveEnded?()
                }
            }
        }
    }

    private func confidenceString(_ c: CMMotionActivityConfidence) -> String {
        switch c {
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        @unknown default: return "undef"
        }
    }

    private func activityKindString(prevAutomotive: Bool, activity: CMMotionActivity) -> String {
        var kinds: [String] = []
        if activity.stationary { kinds.append("stationary") }
        if activity.walking { kinds.append("walking") }
        if activity.running { kinds.append("running") }
        if activity.cycling { kinds.append("cycling") }
        if activity.automotive { kinds.append("automotive") }
        if activity.unknown || kinds.isEmpty { kinds.append("unknown") }
        return kinds.joined(separator: "+")
    }

    func stopLiveUpdates() {
        motionLog.notice("[motion.stop_live] was_automotive=\(self.isAutomotive, privacy: .public)")
        motionManager.stopActivityUpdates()
        isAutomotive = false
    }

    // MARK: - Historical Query (background wake)

    /// Query last N seconds for automotive activity. Works after any wake event.
    func queryRecentAutomotive(seconds: TimeInterval = 300, completion: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionLog.notice("[motion.query_recent.skip] reason=activity_unavailable")
            completion(false)
            return
        }

        let now = Date()
        let from = now.addingTimeInterval(-seconds)
        motionLog.notice("[motion.query_recent.start] lookback_s=\(Int(seconds), privacy: .public)")

        motionManager.queryActivityStarting(from: from, to: now, to: motionQueue) { activities, error in
            guard let activities, error == nil else {
                motionLog.notice("[motion.query_recent.fail] error=\(error?.localizedDescription ?? "nil", privacy: .public)")
                Task { @MainActor in completion(false) }
                return
            }

            let automotiveDetected = activities.contains {
                $0.automotive && $0.confidence == .high
            }
            motionLog.notice("[motion.query_recent.result] activities_count=\(activities.count, privacy: .public) automotive_high_conf_found=\(automotiveDetected, privacy: .public)")

            Task { @MainActor in completion(automotiveDetected) }
        }
    }

    /// Find when automotive activity started (for trip start time recovery)
    func queryAutomotiveStartTime(completion: @escaping (Date?) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else {
            motionLog.notice("[motion.query_start.skip] reason=activity_unavailable")
            completion(nil)
            return
        }

        let now = Date()
        let from = now.addingTimeInterval(-600) // look back 10 minutes
        motionLog.notice("[motion.query_start.begin] lookback_s=600")

        motionManager.queryActivityStarting(from: from, to: now, to: motionQueue) { activities, error in
            guard let activities, error == nil else {
                motionLog.notice("[motion.query_start.fail] error=\(error?.localizedDescription ?? "nil", privacy: .public)")
                Task { @MainActor in completion(nil) }
                return
            }

            // Find the earliest automotive activity in the window
            let firstAutomotive = activities.first { $0.automotive && $0.confidence == .high }
            let startAgo = firstAutomotive.map { Int(now.timeIntervalSince($0.startDate)) }
            motionLog.notice("[motion.query_start.result] activities_count=\(activities.count, privacy: .public) found_automotive=\(firstAutomotive != nil, privacy: .public) start_s_ago=\(startAgo.map(String.init) ?? "nil", privacy: .public)")
            Task { @MainActor in completion(firstAutomotive?.startDate) }
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
