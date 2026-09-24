import Foundation
import CoreLocation
import MapKit

/// Геометрия достройки (спека §2.3). Чистые функции: их зовут финиш
/// (прямая), `RoadGapFiller` (дорога) и стенд.
enum GapFill {
    /// Шаг точек достройки, метры.
    static let step: Double = 20
    /// Потолок точек на одну дыру.
    static let maxPoints = 500

    /// Прыжок GPS — не дыра: подразумеваемая скорость выше правдоподобной
    /// не достраивается ничем (Review Focus 1).
    static func isFillable(_ gap: TrackGapFinder.Gap) -> Bool {
        guard gap.seconds > 0 else { return false }
        return gap.straightMetres / gap.seconds <= TripDistanceGate.maxPlausibleSpeed
    }

    /// Точки СТРОГО между краями дыры вдоль пути: время — равномерно по длине,
    /// высота — линейно, скорость и точность −1 (неизвестны), курс — по
    /// направлению отрезка.
    static func resample(_ path: [CLLocationCoordinate2D], from start: Date, to end: Date,
                         altitudeFrom: Double, altitudeTo: Double) -> [TrackPoint] {
        guard path.count > 1 else { return [] }
        var cumulative = [0.0]
        for (a, b) in zip(path, path.dropFirst()) {
            let d = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            cumulative.append(cumulative[cumulative.count - 1] + d)
        }
        let total = cumulative[cumulative.count - 1]
        guard total > 0 else { return [] }
        let count = min(maxPoints, max(0, Int((total / step).rounded(.up)) - 1))
        guard count > 0 else { return [] }

        let duration = end.timeIntervalSince(start)
        var result: [TrackPoint] = []
        result.reserveCapacity(count)
        var segment = 0
        for k in 1...count {
            let d = total * Double(k) / Double(count + 1)
            while segment < path.count - 2, cumulative[segment + 1] < d { segment += 1 }
            let segStart = cumulative[segment]
            let segLength = max(cumulative[segment + 1] - segStart, .ulpOfOne)
            let t = (d - segStart) / segLength
            let a = path[segment], b = path[segment + 1]
            let fraction = d / total
            result.append(TrackPoint(
                latitude: a.latitude + (b.latitude - a.latitude) * t,
                longitude: a.longitude + (b.longitude - a.longitude) * t,
                altitude: altitudeFrom + (altitudeTo - altitudeFrom) * fraction,
                speed: -1,
                course: PlaceMatcher.bearing(from: a, to: b),
                horizontalAccuracy: -1,
                timestamp: start.addingTimeInterval(duration * fraction),
                isInterpolated: true
            ))
        }
        return result
    }

    /// Правдоподобен ли маршрут `MKDirections` для этой дыры.
    static func isPlausible(routeMetres: Double, routeSeconds: TimeInterval,
                            straightMetres: Double, gapSeconds: TimeInterval) -> Bool {
        routeMetres <= 2.5 * straightMetres
            && routeSeconds <= max(3 * gapSeconds, gapSeconds + 300)
    }

    /// Лежит ли достройка на прямой между краями — то есть это ещё прямая, а не
    /// дорога. Пустая достройка тоже «ещё не дорога». По этому признаку
    /// `RoadGapFiller` понимает, о какой дыре спрашивать.
    static func isStraight(_ fill: [CLLocationCoordinate2D], from a: CLLocationCoordinate2D,
                           to b: CLLocationCoordinate2D, tolerance: Double = 3) -> Bool {
        let pa = MKMapPoint(a), pb = MKMapPoint(b)
        let dx = pb.x - pa.x, dy = pb.y - pa.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return true }
        let metresPerMapPoint = MKMetersPerMapPointAtLatitude((a.latitude + b.latitude) / 2)
        return fill.allSatisfy { c in
            let p = MKMapPoint(c)
            let offset = abs((p.x - pa.x) * dy - (p.y - pa.y) * dx) / length
            return offset * metresPerMapPoint <= tolerance
        }
    }
}
