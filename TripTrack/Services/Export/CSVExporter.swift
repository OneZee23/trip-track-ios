import Foundation

/// CSV for a single trip — a pure function, no I/O and no main actor. Same
/// shape as `GPXExporter`: callers write the returned string to disk
/// themselves, off the main thread (`Task.detached`, per CLAUDE.md while the
/// project is on Swift 5.9).
///
/// The header names carry the unit (`altitude_m`, `speed_mps`, …) because
/// this is a file format, not a place `Measure` shows a number to a person —
/// CSV readers on the other end (a spreadsheet, another app) need the unit in
/// the column, not a locale-aware string.
enum CSVExporter {

    /// Numbers always print with a DOT, regardless of the phone's locale —
    /// same reasoning as `GPXExporter.numberLocale`: a comma here would break
    /// every spreadsheet importer that expects one column per value.
    private static let numberLocale = Locale(identifier: "en_US_POSIX")

    private static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static let header = "timestamp,latitude,longitude,altitude_m,speed_mps,course_deg,horizontal_accuracy_m"

    /// Builds a CSV document for `trip`. Points are sorted by time here —
    /// callers don't need to guarantee order themselves. `trip` itself isn't
    /// read: unlike GPX there is no per-file name element, and no
    /// meta-row about the trip is wanted (row count == point count + header).
    ///
    /// An empty track yields the header line alone — a legitimate, openable
    /// (if uninteresting) CSV, not an error.
    static func csv(for trip: Trip, points: [TrackPoint]) -> String {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        var lines = [header]
        lines.reserveCapacity(sorted.count + 1)
        for point in sorted {
            lines.append(row(for: point))
        }
        return lines.joined(separator: "\n")
    }

    private static func row(for point: TrackPoint) -> String {
        let time = timeFormatter.string(from: point.timestamp)
        let latitude = number(point.latitude)
        let longitude = number(point.longitude)
        // 0 is what an unmeasured point carries (same convention GPXExporter
        // uses for `<ele>`) — real altitude readings essentially never land
        // on exactly zero metres.
        let altitude = point.altitude != 0 ? number(point.altitude) : ""
        // Negative marks "unknown" the same way GPXExporter treats speed —
        // writing it would claim a reading the sensor never reported.
        let speed = point.speed >= 0 ? number(point.speed) : ""
        let course = point.course >= 0 ? number(point.course) : ""
        let accuracy = number(point.horizontalAccuracy)
        return [time, latitude, longitude, altitude, speed, course, accuracy].joined(separator: ",")
    }

    /// Six decimal places, dot separator always — the same precision
    /// `GPXExporter.coord` uses for coordinates, applied uniformly here so
    /// every numeric column in the file is formatted one way.
    private static func number(_ value: Double) -> String {
        String(format: "%.6f", locale: numberLocale, value)
    }
}
