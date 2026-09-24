import Foundation

/// GPX 1.1 for a single trip — a pure function, no I/O and no main actor.
///
/// Callers write the returned string to disk themselves, off the main thread
/// (`Task.detached`, per CLAUDE.md while the project is on Swift 5.9): a long
/// trip is tens of thousands of points, and building the XML on the actor
/// that also draws the popover would stall the dismiss animation.
enum GPXExporter {

    /// Coordinates and speed always print with a DOT, regardless of the
    /// phone's locale. GPX is a machine format read by other apps and
    /// devices, not a place `Measure` shows up — a comma here would make the
    /// file unreadable on a ru_RU phone, not merely mis-styled.
    private static let numberLocale = Locale(identifier: "en_US_POSIX")

    private static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Builds a GPX 1.1 document for `trip`. Points are sorted by time here —
    /// callers don't need to guarantee order themselves.
    ///
    /// An empty track yields metadata only, with no `<trk>` element: an empty
    /// `<trkseg>` is not a track any GPX reader can do anything with, and a
    /// missing element is a cleaner signal than one with nothing inside it.
    static func gpx(for trip: Trip, points: [TrackPoint]) -> String {
        let name = escape(displayName(for: trip))
        // Экспорт — записанный трек: достроенных точек в нём нет (спека §2.4).
        let sorted = points.filter { !$0.isInterpolated }.sorted { $0.timestamp < $1.timestamp }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"TripTrack\" "
        xml += "xmlns=\"http://www.topografix.com/GPX/1/1\" "
        xml += "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "
        xml += "xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 "
        xml += "http://www.topografix.com/GPX/1/1/gpx.xsd\">\n"
        xml += "  <metadata>\n"
        xml += "    <name>\(name)</name>\n"
        xml += "    <time>\(timeFormatter.string(from: trip.startDate))</time>\n"
        xml += "  </metadata>\n"

        if !sorted.isEmpty {
            xml += "  <trk>\n"
            xml += "    <name>\(name)</name>\n"
            xml += "    <trkseg>\n"
            for point in sorted {
                xml += trkpt(for: point)
            }
            xml += "    </trkseg>\n"
            xml += "  </trk>\n"
        }
        xml += "</gpx>\n"
        return xml
    }

    /// The trip's own title, or its start date when it never got one — same
    /// choice the share-poster and the file name at the call site make.
    static func displayName(for trip: Trip) -> String {
        if let title = trip.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let df = DateFormatter()
        df.locale = numberLocale
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "d MMM yyyy"
        return df.string(from: trip.startDate)
    }

    private static func trkpt(for point: TrackPoint) -> String {
        var out = "      <trkpt lat=\"\(coord(point.latitude))\" lon=\"\(coord(point.longitude))\">\n"
        // 0 is what an unmeasured point carries (`ManualTripBuilder` writes it
        // explicitly for a point drawn from a map, not sensed by GPS) — real
        // altitude readings essentially never land on exactly zero metres.
        if point.altitude != 0 {
            out += "        <ele>\(coord(point.altitude))</ele>\n"
        }
        out += "        <time>\(timeFormatter.string(from: point.timestamp))</time>\n"
        // Negative marks "unknown" the same way `TrackPoint.course` uses -1 —
        // writing it would claim a speed the sensor never reported.
        if point.speed >= 0 {
            out += "        <extensions>\n"
            out += "          <speed>\(coord(point.speed))</speed>\n"
            out += "        </extensions>\n"
        }
        out += "      </trkpt>\n"
        return out
    }

    /// Six decimal places (~11cm at the equator), dot separator always.
    private static func coord(_ value: Double) -> String {
        String(format: "%.6f", locale: numberLocale, value)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
