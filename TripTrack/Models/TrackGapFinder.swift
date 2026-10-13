import Foundation
import CoreLocation

/// Где в треке дыра (спека §2.3). Числа — те же, что в замере 24 сентября:
/// цифра приёмки и цифра кода обязаны быть одной.
enum TrackGapFinder {
    static let minDuration: TimeInterval = 10
    static let minDistance: Double = 150

    struct Point: Equatable {
        let latitude: Double
        let longitude: Double
        let timestamp: Date
        let isInterpolated: Bool
        let recordingSegmentIndex: Int

        init(latitude: Double, longitude: Double, timestamp: Date, isInterpolated: Bool,
             recordingSegmentIndex: Int = 0) {
            self.latitude = latitude
            self.longitude = longitude
            self.timestamp = timestamp
            self.isInterpolated = isInterpolated
            self.recordingSegmentIndex = recordingSegmentIndex
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    struct Gap: Equatable {
        let from: Point
        let to: Point

        var seconds: TimeInterval { to.timestamp.timeIntervalSince(from.timestamp) }
        var straightMetres: Double {
            CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        }
    }

    /// Дыры между соседними НЕдостроенными точками. `includeFilled` — вместе
    /// с уже закрытыми достройкой: их зовёт `RoadGapFiller`, чтобы заменить
    /// прямую дорогой.
    static func gaps(in points: [Point], includeFilled: Bool) -> [Gap] {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let fills = sorted.filter(\.isInterpolated).map(\.timestamp)
        let real = sorted.filter { !$0.isInterpolated }
        guard real.count > 1 else { return [] }

        var result: [Gap] = []
        var fillIndex = 0
        for (a, b) in zip(real, real.dropFirst()) {
            guard a.recordingSegmentIndex == b.recordingSegmentIndex else { continue }
            let gap = Gap(from: a, to: b)
            guard gap.seconds >= minDuration, gap.straightMetres >= minDistance else { continue }
            while fillIndex < fills.count, fills[fillIndex] <= a.timestamp { fillIndex += 1 }
            let isFilled = fillIndex < fills.count && fills[fillIndex] < b.timestamp
            if includeFilled || !isFilled { result.append(gap) }
        }
        return result
    }

    /// Дыры, которые ещё ничем не закрыты.
    static func openGaps(in points: [Point]) -> [Gap] {
        gaps(in: points, includeFilled: false)
    }
}
