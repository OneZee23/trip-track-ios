import CoreLocation
import Foundation

struct HiddenSection: Codable, Identifiable, Equatable {
    var id: UUID
    var from: Date
    var to: Date
}

struct TripHiddenParts: Codable, Equatable {
    var startMetres: Int?
    var endMetres: Int?
    var sections: [HiddenSection]
    var numbersVisibleOnly: Bool

    init(startMetres: Int? = nil, endMetres: Int? = nil,
         sections: [HiddenSection] = [], numbersVisibleOnly: Bool = false) {
        self.startMetres = startMetres
        self.endMetres = endMetres
        self.sections = sections
        self.numbersVisibleOnly = numbersVisibleOnly
    }
}

struct HiddenTimeRange: Codable, Equatable {
    let from: Date
    let to: Date
}

struct HiddenPartsResolution {
    let visibleRuns: [[TrackPoint]]
    let hiddenRuns: [[TrackPoint]]
    let lockPoints: [CLLocationCoordinate2D]
    let hiddenRanges: [HiddenTimeRange]
    let previewBreaks: [Int]

    var visiblePoints: [TrackPoint] { visibleRuns.flatMap { $0 } }
    var previewPoints: [CLLocationCoordinate2D] { visibleRuns.flatMap { $0.map(\.coordinate) } }
}

enum HiddenPartsResolver {
    static func resolve(points: [TrackPoint], recordingBreaks: [Date],
                        startMetres: Int, endMetres: Int,
                        sections: [HiddenSection], zone: Zone? = nil) -> HiddenPartsResolution {
        guard !points.isEmpty else {
            return HiddenPartsResolution(visibleRuns: [], hiddenRuns: [], lockPoints: [], hiddenRanges: [], previewBreaks: [])
        }
        let breaks = RecordingBreaks.normalized(recordingBreaks)
        let odometer = HiddenPartsGeometry.prefix(points: points, recordingBreaks: recordingBreaks)
        let total = odometer.last ?? 0
        var hidden = points.indices.map { i in
            odometer[i] < Double(max(0, startMetres)) || total - odometer[i] < Double(max(0, endMetres)) ||
            sections.contains { $0.from <= points[i].timestamp && points[i].timestamp <= $0.to } ||
            (zone.map { PrivacyZone.hides(points[i].coordinate, centre: $0.centre, radius: $0.radius) } ?? false)
        }
        while true {
            let runs = makeRuns(hidden: hidden, points: points, breaks: breaks)
            // A lone point is a sliver only NEXT TO a hidden piece: a pause can leave one point between
            // two recording breaks, and with nothing hidden the trip must leave the phone unchanged.
            let slivers = runs.filter {
                ($0.count < 2 && touchesHidden($0, hidden: hidden)) ||
                    (isBetweenHiddenRuns($0, runs: runs, hidden: hidden) && runDistance($0, points: points) < 100)
            }
            if slivers.isEmpty { break }
            for run in slivers { for index in run { hidden[index] = true } }
        }
        let visible = makeRuns(hidden: hidden, points: points, breaks: breaks)
        let hiddenRunIndices = makeContiguousRuns(hidden)
        var ranges: [HiddenTimeRange] = []
        for run in hiddenRunIndices where !run.isEmpty { ranges.append(HiddenTimeRange(from: points[run[0]].timestamp, to: points[run.last!].timestamp)) }
        var previewBreaks: [Int] = []
        var previewCount = 0
        for (index, run) in visible.enumerated() {
            if index > 0 { previewBreaks.append(previewCount) }
            previewCount += run.count
        }
        let lockPoints = makeContiguousRuns(hidden).flatMap { run -> [CLLocationCoordinate2D] in
            guard let first = run.first, let last = run.last else { return [] }
            return [first > 0 ? points[first - 1].coordinate : nil,
                    last + 1 < points.count ? points[last + 1].coordinate : nil].compactMap { $0 }
        }
        var segments = Array(repeating: 0, count: points.count)
        for i in 1..<points.count {
            segments[i] = segments[i - 1] +
                (RecordingBreaks.crosses(from: points[i - 1].timestamp, to: points[i].timestamp, breaks: breaks) ? 1 : 0)
        }
        let hiddenRuns = drawnHiddenRuns(hidden: hidden, segments: segments).map { $0.map { points[$0] } }
        return HiddenPartsResolution(
            visibleRuns: visible.map { $0.map { points[$0] } },
            hiddenRuns: hiddenRuns, lockPoints: lockPoints,
            hiddenRanges: ranges, previewBreaks: previewBreaks)
    }

    static func photoIsHidden(capturedAt: Date?, coordinate: CLLocationCoordinate2D?,
                              resolution: HiddenPartsResolution, points: [TrackPoint], zone: Zone?) -> Bool {
        if let capturedAt { return resolution.hiddenRanges.contains { $0.from <= capturedAt && capturedAt <= $0.to } }
        if let coordinate, let zone, PrivacyZone.hides(coordinate, centre: zone.centre, radius: zone.radius) { return true }
        guard let coordinate else { return false }
        // A set, not `contains(where:)` per point: that was points × visible points per photo, minutes
        // on a long trip, and it runs on every upload of a trip with photos.
        let visibleIds = Set(resolution.visiblePoints.map(\.id))
        return points.contains { !visibleIds.contains($0.id) && GeometryUtils.haversineDistance(coordinate, $0.coordinate) <= 150 }
    }

    private static func makeRuns(hidden: [Bool], points: [TrackPoint], breaks: [Date]) -> [[Int]] {
        var result: [[Int]] = []; var current: [Int] = []
        for i in points.indices {
            let separated = i > 0 && RecordingBreaks.crosses(from: points[i - 1].timestamp, to: points[i].timestamp, breaks: breaks)
            if hidden[i] || separated { if !current.isEmpty { result.append(current); current = [] } }
            if !hidden[i] { current.append(i) }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// The hidden runs to DRAW (Style A). Each reaches to its visible neighbour on either side within
    /// the same recording segment, so the dots meet the visible line at the lock instead of stopping a
    /// sampling step short, and a hidden run of one point still draws: on a sparse track the hidden start
    /// was one point and the map showed a lock with no hidden line at all (found on Android, 5 Nov). A
    /// pause is never crossed. Drawing only: what is hidden is decided above. Android has the same
    /// function (`TripHiddenPartsResolver.drawnHiddenRuns`).
    static func drawnHiddenRuns(hidden: [Bool], segments: [Int]) -> [[Int]] {
        var runs: [[Int]] = []
        var index = 0
        while index < hidden.count {
            guard hidden[index] else { index += 1; continue }
            let start = index
            while index + 1 < hidden.count, hidden[index + 1], segments[index + 1] == segments[start] { index += 1 }
            let from = start > 0 && segments[start - 1] == segments[start] ? start - 1 : start
            let to = index + 1 < hidden.count && segments[index + 1] == segments[index] ? index + 1 : index
            if to > from { runs.append(Array(from...to)) }
            index += 1
        }
        return runs
    }

    private static func touchesHidden(_ run: [Int], hidden: [Bool]) -> Bool {
        guard let first = run.first, let last = run.last else { return false }
        return (first > 0 && hidden[first - 1]) || (last + 1 < hidden.count && hidden[last + 1])
    }

    private static func makeContiguousRuns(_ values: [Bool]) -> [[Int]] {
        var result: [[Int]] = []; var current: [Int] = []
        for i in values.indices { if values[i] { current.append(i) } else if !current.isEmpty { result.append(current); current = [] } }
        if !current.isEmpty { result.append(current) }; return result
    }

    private static func runDistance(_ run: [Int], points: [TrackPoint]) -> Double {
        zip(run, run.dropFirst()).reduce(0) { $0 + GeometryUtils.haversineDistance(points[$1.0].coordinate, points[$1.1].coordinate) }
    }

    private static func isBetweenHiddenRuns(_ run: [Int], runs: [[Int]], hidden: [Bool]) -> Bool {
        guard let first = run.first, let last = run.last else { return false }
        return first > 0 && last + 1 < hidden.count && hidden[first - 1] && hidden[last + 1]
    }
}

typealias Zone = (centre: CLLocationCoordinate2D, radius: Double)
