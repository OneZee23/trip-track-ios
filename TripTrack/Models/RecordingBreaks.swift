import Foundation

/// Boundaries made by an explicit pause, not inferred from missing GPS fixes.
/// Keeping them on the trip preserves them through point filtering and sync
/// with older clients that do not know about this optional metadata.
enum RecordingBreaks {
    static func normalized(_ breaks: [Date]) -> [Date] {
        Array(Set(breaks.filter { $0.timeIntervalSinceReferenceDate.isFinite })).sorted()
    }

    static func segmentIndex(at date: Date, breaks: [Date]) -> Int {
        index(at: date, sortedBreaks: normalized(breaks))
    }

    static func annotate(_ points: [TrackPoint], breaks: [Date]) -> [TrackPoint] {
        let sorted = normalized(breaks)
        var annotated = points
        for (offset, point) in points.enumerated() {
            let segment = index(at: point.timestamp, sortedBreaks: sorted)
            if point.recordingSegmentIndex != segment {
                annotated[offset].recordingSegmentIndex = segment
            }
        }
        return annotated
    }

    static func crosses(from: Date, to: Date, breaks: [Date]) -> Bool {
        let sorted = normalized(breaks)
        return index(at: from, sortedBreaks: sorted) != index(at: to, sortedBreaks: sorted)
    }

    private static func index(at date: Date, sortedBreaks: [Date]) -> Int {
        var low = 0
        var high = sortedBreaks.count
        while low < high {
            let middle = low + (high - low) / 2
            if sortedBreaks[middle] <= date { low = middle + 1 }
            else { high = middle }
        }
        return low
    }
}
