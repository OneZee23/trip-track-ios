import Foundation
import OSLog

enum DebugLogExporter {
    /// Maximum retention window. Anything older than this is never included in exports,
    /// regardless of how long iOS still holds the underlying OS logs.
    static let maxRetentionHours: TimeInterval = 48

    /// Default export window (full retention).
    static let defaultHoursBack: TimeInterval = 48

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

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date().addingTimeInterval(-window * 3600))

        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.triptrack")
        let entries = try store.getEntries(at: since, matching: predicate)

        var lines: [String] = []
        lines.append("TripTrack debug log export")
        lines.append("generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("window: last \(Int(window))h")
        lines.append("device: \(DeviceInfo.description)")
        lines.append("app: \(DeviceInfo.appVersion) (build \(DeviceInfo.buildNumber))")
        lines.append("")

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
