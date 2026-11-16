import Foundation
import CoreLocation

struct HiddenPartsEditorModel: Equatable {
    private(set) var saved: TripHiddenParts
    var draft: TripHiddenParts

    init(parts: TripHiddenParts) {
        saved = parts
        draft = parts
    }

    mutating func setStartMetres(_ metres: Int) { draft.startMetres = max(0, metres) }
    mutating func setEndMetres(_ metres: Int) { draft.endMetres = max(0, metres) }

    mutating func addSection(from: Date, to: Date) {
        guard from != to else { return }
        draft.sections = Self.merged(draft.sections + [HiddenSection(id: UUID(), from: min(from, to), to: max(from, to))])
    }

    mutating func removeSection(_ id: UUID) { draft.sections.removeAll { $0.id == id } }

    mutating func moveBoundary(_ id: UUID, to date: Date, movingStart: Bool) {
        guard let index = draft.sections.firstIndex(where: { $0.id == id }) else { return }
        if movingStart { draft.sections[index].from = min(date, draft.sections[index].to) }
        else { draft.sections[index].to = max(date, draft.sections[index].from) }
        draft.sections = Self.merged(draft.sections)
    }

    func apply() -> TripHiddenParts { draft }

    mutating func cancel() { draft = saved }

    mutating func commit() {
        saved = draft
    }

    static func merged(_ sections: [HiddenSection]) -> [HiddenSection] {
        HiddenPartsGeometry.mergedSections(sections)
    }

    static func preview(points: [TrackPoint], recordingBreaks: [Date], parts: TripHiddenParts,
                        defaultEdgeMetres: Int?, zone: Zone?) -> (distanceMetres: Double, duration: TimeInterval) {
        let result = HiddenPartsResolver.resolve(
            points: points, recordingBreaks: recordingBreaks,
            startMetres: parts.startMetres ?? defaultEdgeMetres ?? 0,
            endMetres: parts.endMetres ?? defaultEdgeMetres ?? 0,
            sections: parts.sections, zone: zone)
        let distance = result.visibleRuns.reduce(0.0) { total, run in
            total + zip(run, run.dropFirst()).reduce(0.0) {
                $0 + GeometryUtils.haversineDistance($1.0.coordinate, $1.1.coordinate)
            }
        }
        let duration = result.visibleRuns.reduce(0.0) { total, run in
            guard let first = run.first, let last = run.last else { return total }
            return total + last.timestamp.timeIntervalSince(first.timestamp)
        }
        return (distance, duration)
    }
}

enum HiddenEdgesQuestionPolicy {
    static func shouldAskOnOpen(answered: Bool, recording: Bool, anotherSheetOpen: Bool) -> Bool {
        !answered && !recording && !anotherSheetOpen
    }

    static func shouldAskBeforePublish(pending: Bool, answered: Bool) -> Bool {
        pending && !answered
    }
}

/// One time axis for the editor's trip bar: speed colours, hidden hatch and
/// section handles all sit on it, from the first to the last recorded point.
/// TestFlight 101 placed the colours by point number and the hatch by time,
/// and on a trip whose points are uneven in time the hidden start showed up
/// a quarter of the way along the bar (owner, 5 Nov 2026).
struct HiddenTimelineAxis: Equatable {
    let start: Date
    let end: Date

    init(points: [TrackPoint], tripStart: Date, tripEnd: Date?) {
        start = points.first?.timestamp ?? tripStart
        end = points.last?.timestamp ?? tripEnd ?? start
    }

    func fraction(of date: Date) -> CGFloat {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return CGFloat(min(1, max(0, date.timeIntervalSince(start) / length)))
    }

    func date(atFraction fraction: CGFloat) -> Date {
        start.addingTimeInterval(Double(min(1, max(0, fraction))) * end.timeIntervalSince(start))
    }

    /// A handle snaps to the recorded point nearest in time: a boundary
    /// between two points would hide half a segment. Points are in time order.
    static func nearestTimestamp(to date: Date, in points: [TrackPoint]) -> Date? {
        guard !points.isEmpty else { return nil }
        var low = 0, high = points.count - 1
        while low < high {
            let middle = (low + high) / 2
            if points[middle].timestamp < date { low = middle + 1 } else { high = middle }
        }
        if low > 0, date.timeIntervalSince(points[low - 1].timestamp) < points[low].timestamp.timeIntervalSince(date) {
            return points[low - 1].timestamp
        }
        return points[low].timestamp
    }
}

extension HiddenPartsEditorModel {
    /// What other people will see under the current choice: the numbers that
    /// upload (`TripSyncPayload`). TestFlight 101 always printed the visible
    /// numbers, so «Вся поездка» promised 1.6 km for a 2.6 km trip.
    static func numbersForOthers(trip: Trip, visibleRuns: [[TrackPoint]],
                                 visibleOnly: Bool) -> (metres: Double, seconds: TimeInterval) {
        guard visibleOnly else { return (trip.distance, trip.duration) }
        let visible = TripSyncPayload.visibleMetrics(visibleRuns)
        guard let start = visible.startDate, let end = visible.endDate else { return (0, 0) }
        return (visible.distance, end.timeIntervalSince(start))
    }
}
