import Foundation
import CoreLocation

/// Prepared once for a route snapshot, never while expanding or animating
/// its map. All three replay arrays use the same shape-preserving indices.
struct TripReplayInput {
    let coords: [CLLocationCoordinate2D]
    let speeds: [Double]
    let timestamps: [Date]

    static let empty = TripReplayInput(coords: [], speeds: [], timestamps: [])

    init(points: [TrackPoint]) {
        self.init(coords: points.map(\.coordinate), speeds: points.map(\.speed),
                  timestamps: points.map(\.timestamp))
    }

    init(coords: [CLLocationCoordinate2D], speeds: [Double], timestamps: [Date]) {
        guard coords.count > 300 else {
            self.coords = coords
            self.speeds = speeds
            self.timestamps = timestamps
            return
        }
        let indices = GeometryUtils.significantIndices(coords, budget: 300)
        self.coords = indices.map { coords[$0] }
        self.speeds = speeds.count == coords.count ? indices.map { speeds[$0] } : []
        self.timestamps = timestamps.count == coords.count ? indices.map { timestamps[$0] } : []
    }

    static func prepare(points: [TrackPoint]) async throws -> TripReplayInput {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = TripReplayInput(points: points)
            try Task.checkCancellation()
            return result
        }
        let result = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return result
    }
}
