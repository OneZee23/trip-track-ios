import Foundation
import CoreLocation

/// Ячейки, которых коснулся записанный трек.
///
/// Две точности, и они отвечают на разные вопросы. Geohash-7 (~150 м) — это
/// сама единица секрета: по ней считается хеш, и другой точности у бандла
/// быть не может, иначе хеши разъедутся. Geohash-5 (~5 км) — предфильтр
/// загадок, тот же приём, что у `PlaceMatcher.prefilterPrecision`: у
/// большинства поездок кандидатов ноль, и дорогая геометрия не зовётся вовсе.
///
/// Считается по ЗАПИСАННОМУ треку после финиша, а не по превью: превью
/// упрощено под рисование, и срезанный им угол — это пропущенная ячейка.
enum TrackCells {

    /// Точность секрета. Менять нельзя никогда: хеши в бандле посчитаны по
    /// строке именно такой длины.
    static let secretPrecision = 7

    /// Точность предфильтра загадок.
    static let prefilterPrecision = 5

    static func geohash7(_ points: [TrackPoint]) -> Set<String> {
        cells(points, precision: secretPrecision)
    }

    static func geohash5(_ points: [TrackPoint]) -> Set<String> {
        cells(points, precision: prefilterPrecision)
    }

    private static func cells(_ points: [TrackPoint], precision: Int) -> Set<String> {
        var result = Set<String>()
        result.reserveCapacity(min(points.count, 4096))
        for point in points {
            result.insert(GeohashEncoder.encode(
                latitude: point.latitude, longitude: point.longitude, precision: precision))
        }
        return result
    }
}
