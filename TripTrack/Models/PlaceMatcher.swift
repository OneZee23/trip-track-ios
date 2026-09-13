import Foundation
import CoreLocation

/// Где поездка прошла мимо места — чистая функция над точками трека.
///
/// Считает `TripRouteLocator.passes(near:)`: он уже умеет «туда и обратно»
/// (два проезда, если между попаданиями больше десяти минут) и набирает
/// километры тем же шагом, что одометр. Здесь только радиус, курс и
/// предфильтр, чтобы не поднимать точки поездок, которые заведомо далеко.
enum PlaceMatcher {

    /// 100 м, а не 120 (радиус тапа): тап — это палец, проезд — это машина.
    static let passRadius: Double = 100

    /// Два попадания ближе десяти минут — ОДИН проезд. Заезд в магазин по
    /// тупиковой дороге и обратно за шесть минут «туда и обратно» не делает;
    /// двумя проездами это становится только при разрыве больше порога. Сам
    /// порог унаследован от тапа по карте (0.6.5) и живёт в
    /// `TripRouteLocator`: параметром `passes(near:)` его не принимает, а
    /// названо это здесь затем, чтобы решение было видно там, где считают
    /// проезды места.
    static let passGap = TripRouteLocator.distinctPassGap

    /// Предфильтр по ячейкам geohash-5 (~4.9 км): у большинства поездок ноль
    /// кандидатов, и `passes(near:)` вообще не зовётся.
    static let prefilterPrecision = 5

    /// Ячейки geohash-5 по координатам превью-полилинии.
    static func cells(of coordinates: [CLLocationCoordinate2D]) -> Set<String> {
        Set(coordinates.map {
            GeohashEncoder.encode(latitude: $0.latitude, longitude: $0.longitude, precision: prefilterPrecision)
        })
    }

    /// Может ли поездка с такими ячейками пройти мимо места.
    ///
    /// Ячейка места и её восемь соседей: место у границы ячейки видно из
    /// соседней. Пустой набор — кандидат: исключить то, чего не видно, нельзя
    /// (у поездки без превью точки поднимутся и всё решат сами).
    static func isCandidate(place: Place, tripCells: Set<String>) -> Bool {
        guard !tripCells.isEmpty else { return true }
        let cell5 = String(place.cell.prefix(prefilterPrecision))
        if tripCells.contains(cell5) { return true }
        return GeohashEncoder.neighbors(of: cell5).contains { tripCells.contains($0) }
    }

    /// Все проезды поездки мимо места.
    static func passes(through place: Place, tripId: UUID, points: [TrackPoint], startDate: Date) -> [PlacePass] {
        TripRouteLocator
            .passes(near: place.coordinate, in: points, radius: passRadius, startDate: startDate)
            .map { fix in
                PlacePass(placeId: place.id, tripId: tripId, timestamp: fix.timestamp,
                          elapsedFromStart: fix.elapsedFromStart,
                          distanceFromStart: fix.distanceFromStart,
                          course: course(at: fix.index, in: points))
            }
    }

    /// Курс в точке: свой, если GPS его дал; иначе — по соседям (от
    /// предыдущей точки к следующей, на краях — по единственной паре).
    /// Стоящая машина курса не имеет, и `-1` у точки — обычное дело.
    static func course(at index: Int, in points: [TrackPoint]) -> Double {
        guard points.indices.contains(index) else { return PlacePass.unknownCourse }
        let own = points[index].course
        if own >= 0 { return own }
        let from = points[max(0, index - 1)]
        let to = points[min(points.count - 1, index + 1)]
        guard from.latitude != to.latitude || from.longitude != to.longitude else {
            return PlacePass.unknownCourse
        }
        return bearing(from: from.coordinate, to: to.coordinate)
    }

    /// Начальный азимут по большому кругу, градусы 0…360.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}
