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
        var odometer = Array(repeating: 0.0, count: points.count)
        let breaks = RecordingBreaks.normalized(recordingBreaks)
        for i in 1..<points.count {
            odometer[i] = odometer[i - 1]
            if !RecordingBreaks.crosses(from: points[i - 1].timestamp, to: points[i].timestamp, breaks: breaks) {
                odometer[i] += GeometryUtils.haversineDistance(points[i - 1].coordinate, points[i].coordinate)
            }
        }
        let total = odometer.last ?? 0
        var hidden = points.indices.map { i in
            odometer[i] < Double(max(0, startMetres)) || total - odometer[i] < Double(max(0, endMetres)) ||
            sections.contains { $0.from <= points[i].timestamp && points[i].timestamp <= $0.to } ||
            (zone.map { PrivacyZone.hides(points[i].coordinate, centre: $0.centre, radius: $0.radius) } ?? false)
        }
        while true {
            let runs = makeRuns(hidden: hidden, points: points, breaks: breaks)
            let slivers = runs.filter { $0.count < 2 || (isBetweenHiddenRuns($0, runs: runs, hidden: hidden) && runDistance($0, points: points) < 100) }
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
        let hiddenRuns = makeContiguousRuns(hidden).map { $0.map { points[$0] } }
        let lockPoints = hiddenRuns.flatMap { run -> [CLLocationCoordinate2D] in
            guard let first = run.first, let last = run.last,
                  let firstIndex = points.firstIndex(where: { $0.id == first.id }),
                  let lastIndex = points.firstIndex(where: { $0.id == last.id }) else { return [] }
            return [firstIndex > 0 ? points[firstIndex - 1].coordinate : nil,
                    lastIndex + 1 < points.count ? points[lastIndex + 1].coordinate : nil].compactMap { $0 }
        }
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
        let hiddenIndices = makeContiguousRuns(points.map { point in
            !resolution.visiblePoints.contains(where: { $0.id == point.id })
        }).flatMap { $0 }
        return hiddenIndices.contains { GeometryUtils.haversineDistance(coordinate, points[$0].coordinate) <= 150 }
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
