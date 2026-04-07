import CoreLocation

/// Shared geometry utilities for route simplification.
enum GeometryUtils {

    // MARK: - Ramer-Douglas-Peucker

    /// Simplify a polyline using the Ramer-Douglas-Peucker algorithm.
    /// Epsilon is in degrees (~0.00003 ≈ 3m at mid-latitudes).
    static func simplifyRDP(
        _ coords: [CLLocationCoordinate2D],
        epsilon: Double
    ) -> [CLLocationCoordinate2D] {
        guard coords.count > 2,
              let first = coords.first,
              let last = coords.last else { return coords }

        var maxDist = 0.0
        var maxIndex = 0

        for i in 1..<(coords.count - 1) {
            let d = perpendicularDistance(point: coords[i], lineStart: first, lineEnd: last)
            if d > maxDist {
                maxDist = d
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            let left = simplifyRDP(Array(coords[...maxIndex]), epsilon: epsilon)
            let right = simplifyRDP(Array(coords[maxIndex...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [first, last]
        }
    }

    /// Simplify coordinates and return the kept indices (useful when parallel arrays like speeds must stay aligned).
    static func simplifyIndices(
        _ coords: [CLLocationCoordinate2D],
        startIndex: Int,
        endIndex: Int,
        epsilon: Double
    ) -> Set<Int> {
        guard endIndex - startIndex > 1 else {
            return [startIndex, endIndex]
        }

        var maxDist = 0.0
        var maxIndex = startIndex

        for i in (startIndex + 1)..<endIndex {
            let d = perpendicularDistance(point: coords[i], lineStart: coords[startIndex], lineEnd: coords[endIndex])
            if d > maxDist {
                maxDist = d
                maxIndex = i
            }
        }

        if maxDist > epsilon {
            let left = simplifyIndices(coords, startIndex: startIndex, endIndex: maxIndex, epsilon: epsilon)
            let right = simplifyIndices(coords, startIndex: maxIndex, endIndex: endIndex, epsilon: epsilon)
            return left.union(right)
        } else {
            return [startIndex, endIndex]
        }
    }

    /// Default gap threshold in meters for splitting routes into segments.
    static let defaultGapThreshold: Double = 1_000

    // MARK: - Gap Splitting

    /// Split a coordinate array into continuous segments, breaking at gaps > threshold meters.
    /// Uses Haversine formula to avoid CLLocation allocations.
    static func splitByGaps(
        _ coords: [CLLocationCoordinate2D],
        threshold: Double
    ) -> [[CLLocationCoordinate2D]] {
        guard coords.count >= 2 else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = [coords[0]]
        for i in 1..<coords.count {
            if haversineDistance(coords[i - 1], coords[i]) > threshold {
                if current.count >= 2 { segments.append(current) }
                current = [coords[i]]
            } else {
                current.append(coords[i])
            }
        }
        if current.count >= 2 { segments.append(current) }
        return segments
    }

    /// Haversine distance in meters between two coordinates.
    static func haversineDistance(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let R = 6_371_000.0 // Earth radius in meters
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    // MARK: - Perpendicular Distance

    /// Distance from a point to a line segment defined by two endpoints, in coordinate degrees.
    static func perpendicularDistance(
        point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        let lenSq = dx * dx + dy * dy

        guard lenSq > 0 else {
            let px = point.longitude - lineStart.longitude
            let py = point.latitude - lineStart.latitude
            return sqrt(px * px + py * py)
        }

        let t = max(0, min(1, (
            (point.longitude - lineStart.longitude) * dx +
            (point.latitude - lineStart.latitude) * dy
        ) / lenSq))

        let px = point.longitude - (lineStart.longitude + t * dx)
        let py = point.latitude - (lineStart.latitude + t * dy)
        return sqrt(px * px + py * py)
    }
}
