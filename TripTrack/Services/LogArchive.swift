import Foundation
import OSLog

/// The journal that survives a relaunch.
///
/// `OSLogStore(scope: .currentProcessIdentifier)` — the only scope an App
/// Store app may read — holds the CURRENT process only. Close the app and
/// every line is gone, which is exactly what a bug report needs and never has:
/// «человек перезаходит в приложение и они у него исчезают».
///
/// So we keep our own copy. Everything the app logs under `com.triptrack` is
/// swept out of the system store into a plain text file per day, and the
/// journal (and the export) read those files back. A sweep runs at launch,
/// every couple of minutes while the app is in front, and — the one that
/// matters — the moment it goes to the background, which is the last thing
/// that happens before most kills.
///
/// Files older than `retentionDays` are deleted on every sweep, so the archive
/// is bounded by time as well as by the per-sweep size cap below.
actor LogArchive {
    static let shared = LogArchive()

    /// A week of history. Long enough to cover «случилось пару дней назад»,
    /// short enough that the folder stays a few megabytes.
    static let retentionDays = 7

    /// Bytes one day's file may reach before older lines are dropped from its
    /// head. A runaway debug loop must not fill the user's disk.
    private static let maxBytesPerDay = 3 * 1024 * 1024

    private static let lastSweptKey = "logArchive.lastEntryDate"

    /// The periodic sweep loop, started once per process. `.task` can re-fire
    /// when its view is re-mounted (the onboarding flag flipping is enough),
    /// and every re-fire would leave another loop running for the rest of the
    /// session.
    private var isPeriodicSweepRunning = false

    /// Sweeps now, then every two minutes for the life of the process.
    func startPeriodicSweep() {
        sweep()
        guard !isPeriodicSweepRunning else { return }
        isPeriodicSweepRunning = true
        Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await LogArchive.shared.sweep()
            }
        }
    }

    private let fm = FileManager.default

    private var directory: URL? {
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Logs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Sweep

    /// Moves everything logged since the last sweep into today's file.
    ///
    /// Cheap to call often: the store read is bounded by the last sweep's
    /// timestamp, so a sweep two minutes after the previous one reads two
    /// minutes of log.
    func sweep() {
        prune()
        guard let dir = directory else { return }

        let last = UserDefaults.standard.object(forKey: Self.lastSweptKey) as? Double
        // First sweep of a fresh install: take the whole window the system
        // store can still answer for rather than nothing.
        let since = last.map { Date(timeIntervalSince1970: $0) }
            ?? Date().addingTimeInterval(-DebugLogExporter.maxRetentionHours * 3600)

        var newest = since
        var byDay: [String: [String]] = [:]
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: since)
            let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.triptrack")
            for entry in try store.getEntries(at: position, matching: predicate) {
                guard let log = entry as? OSLogEntryLog else { continue }
                // `position(date:)` is a seek, not a filter — it can hand back
                // the entry just before the mark. Skipping what we already
                // wrote is what keeps a line from appearing twice per sweep.
                guard log.date > since else { continue }
                if log.date > newest { newest = log.date }
                byDay[Self.dayKey(log.date), default: []].append(Self.line(from: log))
            }
        } catch {
            // Nothing readable (simulator quirks, store unavailable) — leave
            // the mark where it was and try again next sweep.
            return
        }

        for (day, lines) in byDay {
            append(lines, toDay: day, in: dir)
        }
        UserDefaults.standard.set(newest.timeIntervalSince1970, forKey: Self.lastSweptKey)
    }

    private func append(_ lines: [String], toDay day: String, in dir: URL) {
        let url = dir.appendingPathComponent("triptrack-\(day).log")
        let text = lines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }

        // Trim from the HEAD if the day ran long: the tail is the part a bug
        // report is about.
        if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > Self.maxBytesPerDay,
           let existing = try? String(contentsOf: url, encoding: .utf8) {
            let kept = existing.split(separator: "\n", omittingEmptySubsequences: false)
            let half = kept.suffix(kept.count / 2).joined(separator: "\n")
            try? half.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    /// Deletes day files past the retention window.
    private func prune() {
        guard let dir = directory,
              let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.retentionDays, to: Date()
        ) ?? Date()
        let cutoffKey = Self.dayKey(cutoff)
        for name in names where name.hasPrefix("triptrack-") && name.hasSuffix(".log") {
            let day = name
                .replacingOccurrences(of: "triptrack-", with: "")
                .replacingOccurrences(of: ".log", with: "")
            // Day keys are ISO `yyyy-MM-dd`, so string order IS date order.
            if day < cutoffKey {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    // MARK: - Read back

    /// Archived lines, oldest first, as raw text — what the export file needs.
    func archivedText(days: Int = retentionDays) -> String {
        guard let dir = directory,
              let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return "" }
        let wanted = Self.dayKeys(days: days)
        let files = names
            .filter { $0.hasPrefix("triptrack-") && $0.hasSuffix(".log") }
            .filter { name in wanted.contains(where: { name.contains($0) }) }
            .sorted()
        return files
            .compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }
            .joined()
    }

    /// Archived lines parsed back into journal rows, oldest first.
    func archivedRows(days: Int = retentionDays) -> [DebugLogExporter.LogEntryRow] {
        archivedText(days: days)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Self.row(from: String($0)) }
    }

    // MARK: - Line format
    //
    // `[2026-08-14T21:03:11.482+03:00] [ERROR] [com.triptrack/social.profile] text`
    // — the same shape the export file has always used, so an archived line
    // and a live one are indistinguishable in a report.

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func line(from log: OSLogEntryLog) -> String {
        // Newlines inside a message would break the one-line-per-entry parse.
        let message = log.composedMessage.replacingOccurrences(of: "\n", with: "⏎")
        return "[\(stamp.string(from: log.date))] [\(level(log.level))] [\(log.subsystem)/\(log.category)] \(message)"
    }

    private static func row(from line: String) -> DebugLogExporter.LogEntryRow? {
        guard line.hasPrefix("["),
              let dateEnd = line.firstIndex(of: "]") else { return nil }
        let dateText = String(line[line.index(after: line.startIndex)..<dateEnd])
        guard let date = stamp.date(from: dateText) else { return nil }

        var rest = String(line[line.index(after: dateEnd)...])
            .trimmingCharacters(in: .whitespaces)
        var fields: [String] = []
        while rest.hasPrefix("["), let end = rest.firstIndex(of: "]"), fields.count < 2 {
            fields.append(String(rest[rest.index(after: rest.startIndex)..<end]))
            rest = String(rest[rest.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        }
        guard fields.count == 2 else { return nil }
        let category = fields[1].split(separator: "/").last.map(String.init) ?? fields[1]
        return DebugLogExporter.LogEntryRow(
            date: date,
            level: parseLevel(fields[0]),
            category: category,
            message: rest.replacingOccurrences(of: "⏎", with: "\n")
        )
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "UNDEF"
        }
    }

    private static func parseLevel(_ text: String) -> OSLogEntryLog.Level {
        switch text {
        case "DEBUG": return .debug
        case "INFO": return .info
        case "NOTICE": return .notice
        case "ERROR": return .error
        case "FAULT": return .fault
        default: return .undefined
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    private static func dayKeys(days: Int) -> [String] {
        (0..<max(1, days)).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date()).map(dayKey)
        }
    }
}
