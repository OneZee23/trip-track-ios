import Foundation
import OSLog

/// Cold-launch milestone tracer. Two jobs:
///  1. Emit timed `[startup]` `.notice` lines so a normal export shows the launch
///     timeline (where time went).
///  2. Persist the timeline to UserDefaults so a LAUNCH HANG is still
///     diagnosable. `OSLogStore` is scoped to the current process, so when the
///     user force-quits a hung launch and relaunches, the hung process's OSLog
///     is gone — but its last persisted trace survives and shows the milestone
///     it stalled after. The exporter prints both the previous and current trace.
enum StartupTrace {
    /// Process start. Lazily evaluated on first `mark`, so t+ is relative to the
    /// first milestone (close enough to process launch for diagnosis).
    private static let t0 = Date()
    private static let log = Logger(subsystem: "com.triptrack", category: "startup")

    private static let currentKey = "com.triptrack.launchTrace.current"
    private static let previousKey = "com.triptrack.launchTrace.previous"

    private static var started = false
    private static var lines: [String] = []

    /// Record a launch milestone. Cheap; safe to call on the main actor.
    static func mark(_ step: String) {
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        if !started {
            started = true
            // Preserve the prior launch's final trace before starting a new one —
            // if that launch hung, its trace ends at the stall point.
            let prior = UserDefaults.standard.string(forKey: currentKey) ?? ""
            if !prior.isEmpty { UserDefaults.standard.set(prior, forKey: previousKey) }
            lines = []
        }
        lines.append("+\(ms)ms \(step)")
        log.notice("startup +\(ms)ms \(step, privacy: .public)")
        UserDefaults.standard.set(lines.joined(separator: " | "), forKey: currentKey)
    }

    /// The previous launch's trace (the one that may have hung). Nil on first run.
    static var previousTrace: String? {
        let t = UserDefaults.standard.string(forKey: previousKey)
        return (t?.isEmpty == false) ? t : nil
    }

    /// This launch's trace so far.
    static var currentTrace: String? {
        let t = UserDefaults.standard.string(forKey: currentKey)
        return (t?.isEmpty == false) ? t : nil
    }
}
