import Foundation
import CoreLocation
import UIKit

/// Журнал сырых фиксов поездки (спека §2.7): каждый фикс CoreLocation —
/// принятый и отброшенный, с причиной, — и отметки жизни процесса. Отвечает на
/// вопрос, на который лог сводок не отвечает: фиксов не было, или они были, но
/// их выбросили. Хранится 14 дней, уезжает в экспорт лога.
///
/// Строки несут своё время: вызовы приходят в актор отдельными задачами, и
/// строгого порядка между ними никто не обещает.
actor RawFixLog {
    static let shared = RawFixLog()
    static let defaultDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RawFixes", isDirectory: true)
    static let retentionDays = 14
    static let maxBytesPerTrip = 20 * 1024 * 1024
    static let header = "ts,lat,lon,acc,speed,course,alt,decision"

    private let directory: URL
    private var currentURL: URL?
    private var bytesWritten = 0

    init(directory: URL = RawFixLog.defaultDirectory) {
        self.directory = directory
    }

    func begin(tripId: UUID) {
        prepareDirectory()
        let url = directory.appendingPathComponent("\(tripId.uuidString).csv")
        let head = Self.header + "\n"
        FileManager.default.createFile(atPath: url.path, contents: Data(head.utf8))
        currentURL = url
        bytesWritten = head.utf8.count
    }

    func end() {
        currentURL = nil
    }

    func record(line: String) {
        guard let url = currentURL, bytesWritten < Self.maxBytesPerTrip,
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        let data = Data((line + "\n").utf8)
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        bytesWritten += data.count
    }

    /// Отметка жизни процесса: ушёл в фон, вернулся, запущен заново.
    func mark(_ event: String) {
        record(line: "#\(ISO8601DateFormatter().string(from: Date())) \(event)")
    }

    func purgeOld(now: Date = Date()) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        for url in files {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    /// Файлы, тронутые не раньше `date`, самые свежие первыми.
    func files(modifiedSince date: Date) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .compactMap { url -> (URL, Date)? in
                guard let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate, d >= date else { return nil }
                return (url, d)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Каталог исключён из резервной копии: в нём координаты поездок, как у
    /// снимков в `TripPhotos`.
    private func prepareDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }

    /// Строка журнала. Точка — десятичный разделитель в любой локали.
    nonisolated static func line(for fix: CLLocation, decision: FixGate.Decision) -> String {
        let posix = Locale(identifier: "en_US_POSIX")
        func n(_ v: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", locale: posix, v) }
        let verdict: String
        switch decision {
        case .accept: verdict = "accept"
        case .reject(let reason): verdict = "reject:\(reason.rawValue)"
        }
        return [
            n(fix.timestamp.timeIntervalSince1970, 3),
            n(fix.coordinate.latitude, 7), n(fix.coordinate.longitude, 7),
            n(fix.horizontalAccuracy, 2), n(fix.speed, 2), n(fix.course, 1), n(fix.altitude, 1),
            verdict,
        ].joined(separator: ",")
    }

    nonisolated static func startObservingLifecycle() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            Task { await RawFixLog.shared.mark("background") }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { _ in
            Task { await RawFixLog.shared.mark("foreground") }
        }
        center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            Task { await RawFixLog.shared.mark("terminate") }
        }
        Task {
            await RawFixLog.shared.mark("launch")
            await RawFixLog.shared.purgeOld()
        }
    }
}
