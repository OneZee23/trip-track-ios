import XCTest
import CoreLocation
@testable import TripTrack

/// «Сколько времени и километров до этой точки».
///
/// Вопрос из машины: едешь из Краснодара в Геленджик и хочешь знать не сколько
/// вся дорога, а сколько до моря. Считалка обслуживает три входа — палец по
/// карте, кнопку на ходу и время съёмки фотографии, — и все три обязаны давать
/// цифры, сходящиеся с одометром поездки.
final class TripRouteLocatorTests: XCTestCase {

    private static let metersPerDegree = 111_320.0
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    /// Прямая на север: секунда на точку, десять метров на секунду.
    private func straightTrack(seconds: Int) -> [TrackPoint] {
        (0...seconds).map { t in
            TrackPoint(
                latitude: 45.0 + Double(t) * 10 / Self.metersPerDegree,
                longitude: 38.9,
                speed: 10,
                timestamp: start.addingTimeInterval(Double(t))
            )
        }
    }

    /// Туда и обратно по той же дороге — случай, ради которого считалка
    /// возвращает список, а не один ответ.
    private func outAndBackTrack() -> [TrackPoint] {
        var points: [TrackPoint] = []
        for t in 0...100 {                     // туда
            points.append(TrackPoint(
                latitude: 45.0 + Double(t) * 10 / Self.metersPerDegree,
                longitude: 38.9, speed: 10,
                timestamp: start.addingTimeInterval(Double(t))))
        }
        for t in 0...1200 {                    // стоим двадцать минут
            _ = t
        }
        for t in 0...100 {                     // обратно, спустя двадцать минут
            points.append(TrackPoint(
                latitude: 45.0 + Double(100 - t) * 10 / Self.metersPerDegree,
                longitude: 38.9, speed: 10,
                timestamp: start.addingTimeInterval(1_300 + Double(t))))
        }
        return points
    }

    private func coordinate(metresNorth: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 45.0 + metresNorth / Self.metersPerDegree, longitude: 38.9)
    }

    // MARK: - Цифры сходятся с одометром

    /// Отметка обязана считать километры тем же шагом, что и сама поездка.
    /// Иначе «до моря 143 км» и «всего 210 км» жили бы по разным правилам, и
    /// сумма отрезков не сошлась бы с итогом — а именно за суммой человек и
    /// придёт.
    func testDistanceToAPointAgreesWithTheOdometer() {
        let points = straightTrack(seconds: 300)
        let prefix = TripRouteLocator.distancePrefix(points)

        let odometer = TripDistanceGate.totalDistance(points.map {
            TripDistanceGate.Sample(latitude: $0.latitude, longitude: $0.longitude, timestamp: $0.timestamp)
        })
        XCTAssertEqual(prefix[points.count - 1], odometer, accuracy: 0.01,
                       "путь до последней точки разошёлся с одометром поездки")
    }

    /// Отметка на середине даёт половину пути и половину времени.
    func testAPointInTheMiddleReadsHalfTheTrip() {
        let points = straightTrack(seconds: 300)   // 3000 м, 300 с
        guard let fix = TripRouteLocator.fix(at: start.addingTimeInterval(150), in: points) else {
            return XCTFail("середина поездки не найдена")
        }
        XCTAssertEqual(fix.elapsedFromStart, 150, accuracy: 1)
        XCTAssertEqual(fix.distanceFromStart, 1500, accuracy: 20)
    }

    // MARK: - По времени

    /// Момент вне поездки ответа не имеет: снимок, сделанный назавтра, на
    /// маршрут не встаёт. Соврать координатой здесь хуже, чем промолчать.
    func testAMomentOutsideTheTripHasNoPlace() {
        let points = straightTrack(seconds: 60)
        XCTAssertNil(TripRouteLocator.fix(at: start.addingTimeInterval(-10), in: points))
        XCTAssertNil(TripRouteLocator.fix(at: start.addingTimeInterval(3_600), in: points))
    }

    // MARK: - Туда и обратно

    /// Палец у дороги, по которой проехали дважды, попадает в ОБА проезда.
    /// Геометрия их не различает — различает время, и выбор остаётся за
    /// человеком: 2:14 и 5:30 это разные ответы на его вопрос.
    func testTheSameRoadDrivenTwiceOffersBothPasses() {
        let passes = TripRouteLocator.passes(
            near: coordinate(metresNorth: 500), in: outAndBackTrack())

        XCTAssertEqual(passes.count, 2, "проездов найдено \(passes.count), а дорога пройдена дважды")
        guard passes.count == 2 else { return }
        XCTAssertLessThan(passes[0].elapsedFromStart, passes[1].elapsedFromStart,
                          "проезды выданы не по времени")
        XCTAssertGreaterThan(passes[1].elapsedFromStart - passes[0].elapsedFromStart,
                             TripRouteLocator.distinctPassGap,
                             "два проезда слились в один")
    }

    /// Один проезд — выбирать не из чего, и спрашивать человека не о чем.
    func testASinglePassOffersOneAnswer() {
        let passes = TripRouteLocator.passes(
            near: coordinate(metresNorth: 500), in: straightTrack(seconds: 300))
        XCTAssertEqual(passes.count, 1)
    }

    /// Палец мимо маршрута не создаёт отметок из воздуха.
    func testATapAwayFromTheRouteFindsNothing() {
        let far = CLLocationCoordinate2D(latitude: 45.5, longitude: 39.5)
        XCTAssertTrue(TripRouteLocator.passes(near: far, in: straightTrack(seconds: 300)).isEmpty)
    }
}
