import XCTest
import CoreLocation
import MapKit
@testable import TripTrack

/// Прогресс воспроизведения меряется ДОЛЕЙ пути, а не номером точки.
///
/// Точки на треке лежат неравномерно: в городе густо, на трассе редко. «Сотая
/// из двухсот» может означать пятую часть пути, и подсветка, считающая точки,
/// убегала бы вперёд на городском куске и отставала на трассе.
final class PlaybackProgressTests: XCTestCase {

    /// Прямая линия по экватору: там градус долготы даёт ровные метры, и
    /// ожидания можно писать числом, а не «примерно».
    private func line(_ n: Int) -> [CLLocationCoordinate2D] {
        (0..<n).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.001) }
    }

    private func cum(_ coords: [CLLocationCoordinate2D]) -> [Double] {
        var out: [Double] = [0]
        var total: Double = 0
        for i in 1..<coords.count {
            total += GeometryUtils.haversineDistance(coords[i - 1], coords[i])
            out.append(total)
        }
        return out
    }

    func testStartIsZeroAndFinishIsOne() {
        let c = line(11)
        XCTAssertEqual(RouteMapView.Coordinator.fraction(cum: cum(c), coords: c, car: c[0], trailIndex: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(RouteMapView.Coordinator.fraction(cum: cum(c), coords: c, car: c[10], trailIndex: 10), 1, accuracy: 1e-9)
    }

    func testMiddleIsHalf() {
        let c = line(11)
        XCTAssertEqual(RouteMapView.Coordinator.fraction(cum: cum(c), coords: c, car: c[5], trailIndex: 5), 0.5, accuracy: 1e-6)
    }

    /// Машина стоит МЕЖДУ точками — доля обязана это учитывать, иначе
    /// подсветка ползёт ступеньками по точке за раз.
    func testCarBetweenPointsCountsThePartialLeg() {
        let c = line(11)
        let mid = CLLocationCoordinate2D(latitude: 0, longitude: 0.0045)
        let f = RouteMapView.Coordinator.fraction(cum: cum(c), coords: c, car: mid, trailIndex: 4)
        XCTAssertEqual(f, 0.45, accuracy: 1e-6)
    }

    /// Неравномерный трек: половина ТОЧЕК — это не половина ПУТИ.
    func testUnevenSpacingIsMeasuredInMetresNotPoints() {
        var c = (0..<5).map { CLLocationCoordinate2D(latitude: 0, longitude: Double($0) * 0.0001) }
        c += (1...5).map { CLLocationCoordinate2D(latitude: 0, longitude: 0.0004 + Double($0) * 0.01) }
        let f = RouteMapView.Coordinator.fraction(cum: cum(c), coords: c, car: c[4], trailIndex: 4)
        XCTAssertLessThan(f, 0.02, "четыре точки из девяти прошли, а пути — меньше двух процентов")
    }

    func testOutOfRangeIndexDoesNotEscapeTheRange() {
        let c = line(11)
        let below = RouteMapView.Coordinator.fraction(cum: cum(c), coords: c, car: c[0], trailIndex: -5)
        let above = RouteMapView.Coordinator.fraction(cum: cum(c), coords: c, car: c[10], trailIndex: 99)
        XCTAssertEqual(below, 0, accuracy: 1e-9)
        XCTAssertEqual(above, 1, accuracy: 1e-9)
    }

    func testDegenerateInputsAreZeroNotCrash() {
        let one = [CLLocationCoordinate2D(latitude: 0, longitude: 0)]
        XCTAssertEqual(RouteMapView.Coordinator.fraction(cum: [0], coords: one, car: one[0], trailIndex: 0), 0)
        XCTAssertEqual(RouteMapView.Coordinator.fraction(cum: [], coords: [], car: one[0], trailIndex: 0), 0)
    }

    func testLengthOfAPolylineIsTheSumOfItsLegs() {
        let c = line(6)
        let legs = (1..<6).map { GeometryUtils.haversineDistance(c[$0 - 1], c[$0]) }.reduce(0, +)
        XCTAssertEqual(GeometryUtils.polylineLength(c), legs, accuracy: 1e-6)
        XCTAssertEqual(GeometryUtils.polylineLength([c[0]]), 0)
        XCTAssertEqual(GeometryUtils.polylineLength([]), 0)
    }
}
