import Foundation
import CoreLocation

struct HiddenPartsEditorModel: Equatable {
    private(set) var saved: TripHiddenParts
    var draft: TripHiddenParts

    init(parts: TripHiddenParts) {
        saved = parts
        draft = parts
    }

    mutating func setStartPreset(_ metres: Int) { draft.startMetres = max(0, metres) }
    mutating func setEndPreset(_ metres: Int) { draft.endMetres = max(0, metres) }

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
        let sorted = sections.sorted { $0.from < $1.from }
        var result: [HiddenSection] = []
        for section in sorted {
            if let last = result.last, section.from <= last.to {
                result[result.count - 1].to = max(last.to, section.to)
            } else {
                result.append(section)
            }
        }
        return result
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
