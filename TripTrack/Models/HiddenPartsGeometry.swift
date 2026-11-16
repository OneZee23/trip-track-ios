import CoreLocation
import Foundation

struct HiddenPartsGeometry {
    struct ParkedBoundaries: Equatable {
        let departure: Int?
        let arrival: Int?
    }

    struct Boundary: Equatable {
        let index: Int
        let metres: Int
    }

    static let parkedRadiusMetres = 60.0
    static let parkedDuration: TimeInterval = 120
    static let minimumVisibleMetres = 100.0
    static let sectionHalfLengthMetres = 120.0
    static let minimumSectionMetres = 40.0
    static let detents = [200, 500, 1_000, 2_000]
    static let detentToleranceMetres = 35.0
    static let continuityWindow = 45
    static let continuityFallbackPoints = 28.0

    static func prefix(points: [TrackPoint], recordingBreaks: [Date]) -> [Double] {
        var result = Array(repeating: 0.0, count: points.count)
        let breaks = RecordingBreaks.normalized(recordingBreaks)
        guard points.count > 1 else { return result }
        for index in 1..<points.count {
            result[index] = result[index - 1]
            guard !RecordingBreaks.crosses(from: points[index - 1].timestamp,
                                           to: points[index].timestamp,
                                           breaks: breaks) else { continue }
            result[index] += GeometryUtils.haversineDistance(
                points[index - 1].coordinate, points[index].coordinate)
        }
        return result
    }

    static func parkedBoundaries(points: [TrackPoint]) -> ParkedBoundaries {
        guard points.count > 1, let first = points.first, let last = points.last else {
            return ParkedBoundaries(departure: nil, arrival: nil)
        }

        var departure: Int?
        for index in points.indices.dropFirst() {
            guard GeometryUtils.haversineDistance(first.coordinate, points[index].coordinate)
                    <= parkedRadiusMetres else { break }
            if points[index].timestamp.timeIntervalSince(first.timestamp) >= parkedDuration {
                departure = index
            }
        }

        var arrival: Int?
        for index in points.indices.reversed().dropFirst() {
            guard GeometryUtils.haversineDistance(last.coordinate, points[index].coordinate)
                    <= parkedRadiusMetres else { break }
            if last.timestamp.timeIntervalSince(points[index].timestamp) >= parkedDuration {
                arrival = index
            }
        }
        return ParkedBoundaries(departure: departure, arrival: arrival)
    }

    static func displayedStartMetres(at index: Int, prefix: [Double], departure: Int?) -> Double {
        guard let last = prefix.indices.last else { return 0 }
        let origin = departure.map { min(last, max(0, $0)) } ?? 0
        return max(0, prefix[min(last, max(0, index))] - prefix[origin])
    }

    static func displayedEndMetres(at index: Int, prefix: [Double], arrival: Int?) -> Double {
        guard let last = prefix.indices.last else { return 0 }
        let end = arrival.map { min(last, max(0, $0)) } ?? last
        return max(0, prefix[end] - prefix[min(last, max(0, index))])
    }

    static func startIndex(forStoredMetres metres: Int, prefix: [Double]) -> Int {
        guard !prefix.isEmpty, metres > 0 else { return 0 }
        var low = 0
        var high = prefix.count
        while low < high {
            let middle = (low + high) / 2
            if prefix[middle] < Double(metres) { low = middle + 1 } else { high = middle }
        }
        return min(prefix.count - 1, low)
    }

    static func endIndex(forStoredMetres metres: Int, prefix: [Double]) -> Int {
        guard let last = prefix.indices.last else { return 0 }
        guard metres > 0 else { return last }
        let total = prefix[last]
        var low = 0
        var high = prefix.count
        while low < high {
            let middle = (low + high) / 2
            if total - prefix[middle] >= Double(metres) { low = middle + 1 } else { high = middle }
        }
        return max(0, min(last, low - 1))
    }

    static func startBoundary(near index: Int, prefix: [Double]) -> Boundary {
        guard let last = prefix.indices.last, last > 0 else { return Boundary(index: 0, metres: 0) }
        let target = min(last, max(0, index))
        guard target > 0 else { return Boundary(index: 0, metres: 0) }
        let candidates = integerCandidates(around: [prefix[target - 1], prefix[target]])
        return candidates
            .map { Boundary(index: startIndex(forStoredMetres: $0, prefix: prefix), metres: $0) }
            .min { lhs, rhs in
                let leftDelta = abs(lhs.index - target)
                let rightDelta = abs(rhs.index - target)
                return leftDelta == rightDelta ? lhs.metres < rhs.metres : leftDelta < rightDelta
            } ?? Boundary(index: 0, metres: 0)
    }

    static func endBoundary(near index: Int, prefix: [Double]) -> Boundary {
        guard let last = prefix.indices.last, last > 0 else { return Boundary(index: max(0, prefix.count - 1), metres: 0) }
        let target = min(last, max(0, index))
        guard target < last else { return Boundary(index: last, metres: 0) }
        let total = prefix[last]
        let candidates = integerCandidates(around: [total - prefix[target], total - prefix[target + 1]])
        return candidates
            .map { Boundary(index: endIndex(forStoredMetres: $0, prefix: prefix), metres: $0) }
            .min { lhs, rhs in
                let leftDelta = abs(lhs.index - target)
                let rightDelta = abs(rhs.index - target)
                return leftDelta == rightDelta ? lhs.metres < rhs.metres : leftDelta < rightDelta
            } ?? Boundary(index: last, metres: 0)
    }

    static func nearestIndex(
        to finger: CGPoint,
        currentIndex: Int,
        allowed: ClosedRange<Int>,
        pointAtIndex: (Int) -> CGPoint
    ) -> Int {
        guard !allowed.isEmpty else { return allowed.lowerBound }
        let current = min(allowed.upperBound, max(allowed.lowerBound, currentIndex))
        let local = max(allowed.lowerBound, current - continuityWindow)...min(allowed.upperBound, current + continuityWindow)
        let localBest = nearestIndex(to: finger, in: local, pointAtIndex: pointAtIndex)
        let deltaX = pointAtIndex(localBest).x - finger.x
        let deltaY = pointAtIndex(localBest).y - finger.y
        if hypot(deltaX, deltaY) <= continuityFallbackPoints { return localBest }
        return nearestIndex(to: finger, in: allowed, pointAtIndex: pointAtIndex)
    }

    static func detent(near distance: Double, tolerance: Double = detentToleranceMetres) -> Int? {
        detents.first { abs(distance - Double($0)) <= tolerance }
    }

    static func maximumStartIndex(endingAt endIndex: Int, prefix: [Double]) -> Int {
        guard !prefix.isEmpty else { return 0 }
        let end = min(prefix.count - 1, max(0, endIndex))
        let target = prefix[end] - minimumVisibleMetres
        var low = 0
        var high = end + 1
        while low < high {
            let middle = (low + high) / 2
            if prefix[middle] <= target { low = middle + 1 } else { high = middle }
        }
        return max(0, min(end, low - 1))
    }

    static func minimumEndIndex(startingAt startIndex: Int, prefix: [Double]) -> Int {
        guard !prefix.isEmpty else { return 0 }
        let start = min(prefix.count - 1, max(0, startIndex))
        let target = prefix[start] + minimumVisibleMetres
        var low = start
        var high = prefix.count
        while low < high {
            let middle = (low + high) / 2
            if prefix[middle] < target { low = middle + 1 } else { high = middle }
        }
        return min(prefix.count - 1, low)
    }

    static func sectionRange(
        around index: Int,
        visibleStart: Int,
        visibleEnd: Int,
        prefix: [Double],
        occupied: [ClosedRange<Int>]
    ) -> ClosedRange<Int>? {
        guard prefix.count > 1 else { return nil }
        let firstVisible = min(prefix.count - 1, max(0, visibleStart))
        let lastVisible = min(prefix.count - 1, max(firstVisible, visibleEnd))
        let centreIndex = min(lastVisible, max(firstVisible, index))
        let lowerDistance = max(prefix[firstVisible + (firstVisible < lastVisible ? 1 : 0)],
                                prefix[centreIndex] - sectionHalfLengthMetres)
        let upperDistance = min(prefix[lastVisible], prefix[centreIndex] + sectionHalfLengthMetres)
        let first = lowerBound(lowerDistance, in: prefix, range: (firstVisible + 1)..<(lastVisible + 1))
        let afterLast = upperBound(upperDistance, in: prefix, range: firstVisible..<lastVisible)
        let last = min(lastVisible - 1, afterLast - 1)
        guard first <= last, first >= firstVisible + 1, last < lastVisible,
              prefix[last] - prefix[first] >= minimumSectionMetres else { return nil }
        let range = first...last
        guard !occupied.contains(where: { range.overlaps($0) }) else { return nil }
        return range
    }

    static func mergedSections(_ sections: [HiddenSection]) -> [HiddenSection] {
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

    static func sectionNeedsRemoval(from firstIndex: Int, to lastIndex: Int, prefix: [Double]) -> Bool {
        guard prefix.indices.contains(firstIndex), prefix.indices.contains(lastIndex),
              firstIndex <= lastIndex else { return false }
        return prefix[lastIndex] - prefix[firstIndex] < minimumSectionMetres
    }

    private static func nearestIndex(to finger: CGPoint, in range: ClosedRange<Int>, pointAtIndex: (Int) -> CGPoint) -> Int {
        var best = range.lowerBound
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in range {
            let point = pointAtIndex(index)
            let dx = point.x - finger.x
            let dy = point.y - finger.y
            let distance = dx * dx + dy * dy
            if distance < bestDistance { best = index; bestDistance = distance }
        }
        return best
    }

    private static func integerCandidates(around values: [Double]) -> [Int] {
        let candidates = values.flatMap { value -> [Int] in
            guard value.isFinite, value >= 0, value < Double(Int.max - 2) else { return [] }
            let floorValue = Int(floor(value))
            let ceilValue = Int(ceil(value))
            return [floorValue - 1, floorValue, floorValue + 1, ceilValue, ceilValue + 1]
        }.filter { $0 > 0 }
        return Array(Set(candidates)).sorted()
    }

    private static func lowerBound(_ value: Double, in values: [Double], range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        var low = range.lowerBound
        var high = range.upperBound
        while low < high {
            let middle = (low + high) / 2
            if values[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private static func upperBound(_ value: Double, in values: [Double], range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        var low = range.lowerBound
        var high = range.upperBound
        while low < high {
            let middle = (low + high) / 2
            if values[middle] <= value { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
