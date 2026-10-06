import Foundation
import CoreLocation

/// Matches saved recordings, including trips restored with only a preview.
/// This is a history count, not the device-local RoadEntity reward counter.
enum SimilarRecordedTrips {
    static func count(for trip: Trip, in history: [Trip]) -> Int {
        guard isEligible(trip), let reference = Fingerprint(coordinates: coordinates(of: trip)) else {
            return 0
        }
        // The just-finished recording may already be in the fetch, or may not
        // have reached it yet. Public/private representations retain this UUID.
        var matches: Set<UUID> = [trip.id]
        for candidate in history where !matches.contains(candidate.id) && isEligible(candidate) {
            // A materially longer/shorter recording is a different trip shape,
            // even if a coarse cell happens to contain both its endpoints.
            let longestDistance = max(trip.distance, candidate.distance)
            guard abs(trip.distance - candidate.distance) <= longestDistance * 0.3 else { continue }
            let coordinates = coordinates(of: candidate)
            guard reference.hasMatchingEndpoints(coordinates),
                  let fingerprint = Fingerprint(coordinates: coordinates),
                  reference.isSimilar(to: fingerprint) else { continue }
            matches.insert(candidate.id)
        }
        return matches.count
    }

    private static func isEligible(_ trip: Trip) -> Bool {
        trip.endDate != nil && !trip.isDraft && !trip.isJunk && trip.source == .recorded
            && trip.distance.isFinite && trip.distance > 0 && trip.recordingBreaks.isEmpty
    }

    private static func coordinates(of trip: Trip) -> [CLLocationCoordinate2D] {
        // A preview cannot say which part of a known recording gap was driven.
        // Omit uncertain matches rather than joining those gaps for a counter.
        if trip.trackPoints.contains(where: \.isInterpolated) { return [] }
        for (a, b) in zip(trip.trackPoints, trip.trackPoints.dropFirst()) {
            if a.recordingSegmentIndex != b.recordingSegmentIndex
                || b.timestamp.timeIntervalSince(a.timestamp) > 60 { return [] }
        }
        if let preview = trip.previewPolyline {
            let coordinates = Trip.decodePolyline(preview)
            if coordinates.count >= 2 && coordinates.allSatisfy(CLLocationCoordinate2DIsValid) {
                return coordinates
            }
        }
        return trip.trackPoints.map(\.coordinate)
    }

    /// Geohash-5 cells, as in the existing road collection. Integer grid cells
    /// avoid encoding thousands of strings while examining a long history.
    /// Walking the segments keeps a two-vertex preview comparable to a dense
    /// recording of the same line. Sampling just the vertices misses its cells.
    private struct Fingerprint {
        private static let cellDegrees = 360.0 / 8192
        let start: Cell
        let end: Cell
        let cells: Set<Cell>

        init?(coordinates: [CLLocationCoordinate2D]) {
            guard coordinates.count >= 2,
                  coordinates.allSatisfy(CLLocationCoordinate2DIsValid),
                  let first = coordinates.first, let last = coordinates.last else { return nil }
            start = Cell(coordinate: first)
            end = Cell(coordinate: last)
            var visited: Set<Cell> = [start]
            for (a, b) in zip(coordinates, coordinates.dropFirst()) {
                var longitudeDelta = b.longitude - a.longitude
                if longitudeDelta > 180 { longitudeDelta -= 360 }
                if longitudeDelta < -180 { longitudeDelta += 360 }
                let latitudeDelta = b.latitude - a.latitude
                // Four samples per crossed cell; at most 16,384 for any
                // valid pair of coordinates. Dense adjacent points stay O(1).
                let steps = max(1, Int(ceil(max(abs(longitudeDelta), abs(latitudeDelta))
                                           / Self.cellDegrees * 4)))
                for step in 1...steps {
                    let fraction = Double(step) / Double(steps)
                    visited.insert(Cell(coordinate: CLLocationCoordinate2D(
                        latitude: a.latitude + latitudeDelta * fraction,
                        longitude: a.longitude + longitudeDelta * fraction)))
                }
            }
            guard visited.count >= 2 else { return nil }
            cells = visited
        }

        func hasMatchingEndpoints(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
            guard let first = coordinates.first, let last = coordinates.last,
                  CLLocationCoordinate2DIsValid(first), CLLocationCoordinate2DIsValid(last) else { return false }
            let otherStart = Cell(coordinate: first), otherEnd = Cell(coordinate: last)
            return (start.isNear(otherStart) && end.isNear(otherEnd))
                || (start.isNear(otherEnd) && end.isNear(otherStart))
        }

        func isSimilar(to other: Fingerprint) -> Bool {
            let intersection = cells.intersection(other.cells).count
            let union = cells.count + other.cells.count - intersection
            return Double(intersection) / Double(union) >= 0.7
        }

        struct Cell: Hashable {
            let x: Int
            let y: Int

            init(coordinate: CLLocationCoordinate2D) {
                let rawX = Int(floor((coordinate.longitude + 180) / Fingerprint.cellDegrees))
                x = (rawX % 8192 + 8192) % 8192
                y = min(4095, max(0, Int(floor((coordinate.latitude + 90) / Fingerprint.cellDegrees))))
            }

            func isNear(_ other: Cell) -> Bool {
                let dx = abs(x - other.x)
                return min(dx, 8192 - dx) <= 1 && abs(y - other.y) <= 1
            }
        }
    }
}
