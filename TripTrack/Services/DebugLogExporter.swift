import Foundation
import OSLog

enum DebugLogExporter {
    /// Maximum retention window. Anything older than this is never included in exports,
    /// regardless of how long iOS still holds the underlying OS logs.
    static let maxRetentionHours: TimeInterval = 48

    /// Default export window (full retention).
    static let defaultHoursBack: TimeInterval = 48

    /// One journal line for the on-screen log view (DebugLogsView). Kept
    /// deliberately tiny — date/level/category/message — so the UI never
    /// grows a dependency on OSLogEntry internals.
    struct LogEntryRow: Identifiable {
        let id = UUID()
        let date: Date
        let level: OSLogEntryLog.Level
        let category: String
        let message: String
    }

    /// In-app journal feed: the newest `limit` TripTrack log lines from the
    /// last `hoursBack` hours, oldest-first (newest-last). Same store +
    /// subsystem predicate as the export path (shared `logEntries` helper);
    /// `async` because the OSLogStore read is slow — call it off the main
    /// actor and show a loader meanwhile.
    static func recentEntries(hoursBack: Double = 2, limit: Int = 100) async throws -> [LogEntryRow] {
        let window = min(max(hoursBack, 0.25), maxRetentionHours)
        var rows: [LogEntryRow] = []
        for entry in try logEntries(hoursBack: window) {
            guard let log = entry as? OSLogEntryLog else { continue }
            rows.append(LogEntryRow(
                date: log.date,
                level: log.level,
                category: log.category,
                message: log.composedMessage
            ))
        }
        if rows.count > limit {
            rows.removeFirst(rows.count - limit)
        }
        return rows
    }

    /// Shared OSLogStore + TripTrack-subsystem predicate setup used by both
    /// `exportRecentLogs` and `recentEntries`. Returns entries oldest-first.
    private static func logEntries(hoursBack: TimeInterval) throws -> AnySequence<OSLogEntry> {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date().addingTimeInterval(-hoursBack * 3600))
        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.triptrack")
        return AnySequence(try store.getEntries(at: since, matching: predicate))
    }

    /// Pulls recent log entries from the system log store for the TripTrack subsystem,
    /// writes them to a .txt file in a temp directory, returns the URL.
    /// Caller can then present via ShareLink.
    ///
    /// `hoursBack` is clamped to [1, 48]. Older exports in the temp dir are purged first
    /// so we never accumulate stale debug files on-device.
    ///
    /// WARNING: logs may contain trip data (dates, regions, pending counts).
    /// UI must warn the user before sharing.
    static func exportRecentLogs(hoursBack: TimeInterval = defaultHoursBack) async throws -> URL {
        let window = min(max(hoursBack, 1), maxRetentionHours)

        // Clean up any prior exports first — we only ever need the latest.
        purgeOldExports()

        let entries = try logEntries(hoursBack: window)

        let identity = await MainActor.run { () -> (localUserId: String, accountId: String, signedIn: Bool, syncEnabled: Bool) in
            let local = SettingsManager.shared.localUserId.uuidString
            let acc = TokenStore.shared.accountId?.uuidString ?? "(not signed in)"
            return (local, acc, AuthService.shared.isSignedIn, SettingsManager.shared.cloudSyncEnabled)
        }

        var lines: [String] = []
        lines.append("=== TripTrack debug log ===")
        lines.append("generated:     \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("window:        last \(Int(window))h")
        lines.append("")
        lines.append("--- app ---")
        lines.append("bundle_id:     \(Bundle.main.bundleIdentifier ?? "?")")
        lines.append("version:       \(DeviceInfo.appVersion) (build \(DeviceInfo.buildNumber))")
        lines.append("device:        \(DeviceInfo.description)")
        lines.append("")
        lines.append("--- identity ---")
        lines.append("local_user_id: \(identity.localUserId)")
        lines.append("account_id:    \(identity.accountId)")
        lines.append("signed_in:     \(identity.signedIn)")
        lines.append("sync_enabled:  \(identity.syncEnabled)")
        lines.append("")
        // Startup milestones persist across process death (OSLog does not), so a
        // launch HANG is diagnosable after the user force-quits and relaunches:
        // `previous_launch` is the run before this one — if it hung, its trace
        // ends at the milestone it stalled after.
        lines.append("--- startup trace ---")
        lines.append("previous_launch: \(StartupTrace.previousTrace ?? "(none)")")
        lines.append("current_launch:  \(StartupTrace.currentTrace ?? "(none)")")
        lines.append("")
        lines.append("--- log entries ---")

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            let ts = fmt.string(from: log.date)
            let level = shortLevel(log.level)
            lines.append("[\(ts)] [\(level)] [\(log.subsystem)/\(log.category)] \(log.composedMessage)")
        }

        let data = lines.joined(separator: "\n").data(using: .utf8) ?? Data()
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("triptrack-log-\(Int(Date().timeIntervalSince1970)).txt")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Deletes any `triptrack-log-*.txt` files from the temp dir.
    /// We only ever need the most recent export — old ones just waste storage.
    private static func purgeOldExports() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in items where name.hasPrefix("triptrack-log-") && name.hasSuffix(".txt") {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private static func shortLevel(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "UNDEF"
        }
    }
}

private enum DeviceInfo {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
    static var description: String {
        #if canImport(UIKit)
        let device = UIDevice.current
        return "\(device.model) iOS \(device.systemVersion)"
        #else
        return "unknown"
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
