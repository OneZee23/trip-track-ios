import Foundation
import OSLog

enum DebugLogExporter {
    /// Pulls recent log entries from the system log store for the TripTrack subsystem,
    /// writes them to a .txt file in a temp directory, returns the URL.
    /// Caller can then present via ShareLink.
    ///
    /// WARNING: logs may contain trip data (dates, regions, pending counts).
    /// UI must warn the user before sharing.
    static func exportRecentLogs(hoursBack: TimeInterval = 24) async throws -> URL {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let since = store.position(date: Date().addingTimeInterval(-hoursBack * 3600))

        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.triptrack")
        let entries = try store.getEntries(at: since, matching: predicate)

        var lines: [String] = []
        lines.append("TripTrack debug log export")
        lines.append("generated: \(ISO8601DateFormatter().string(from: Date()))")
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
