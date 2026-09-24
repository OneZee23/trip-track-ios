import XCTest
import CoreLocation
@testable import TripTrack

/// Стиль линии выводится из знания скорости: неизвестная — только у
/// достройки, и она рисуется серым пунктиром (спека §2.6).
final class RouteUnknownSpeedTests: XCTestCase {
    private func c(_ n: Double) -> CLLocationCoordinate2D { TrackTestKit.coordinate(east: 0, north: n) }

    /// Пунктир идёт от края дыры до края: граничные точки общие, линия не
    /// рвётся, а у прогона пунктира все скорости неизвестны.
    func testSplitRunsFromGapEdgeToGapEdge() {
        let coords = (0..<6).map { c(Double($0) * 10) }
        let runs = RouteMapView.splitByKnownSpeed(coords, speeds: [10, 10, -1, -1, 12, 12])
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(runs[0].1, [10, 10])
        XCTAssertEqual(runs[1].0.first?.latitude, coords[1].latitude)
        XCTAssertEqual(runs[1].0.last?.latitude, coords[4].latitude)
        XCTAssertTrue(runs[1].1.allSatisfy { $0 < 0 })
        XCTAssertEqual(runs[2].1, [12, 12])
    }

    func testAllKnownIsOneRun() {
        let coords = (0..<4).map { c(Double($0) * 10) }
        XCTAssertEqual(RouteMapView.splitByKnownSpeed(coords, speeds: [5, 6, 7, 8]).count, 1)
    }

    /// Сам по себе этот тест проходит и на СТАРОМ коде: -1 попадает в самую
    /// медленную цветную зону через `max(0, speedMS)` в `SpeedColorScale`, и
    /// одна лишь сплошь неизвестная поездка ничего не пришпиливает. Пришпиливает
    /// смешанный случай ниже — без отдельной зоны для неизвестной скорости обе
    /// половины легли бы в зону 0 и слились в одну группу.
    func testUnknownSpeedGetsItsOwnGroup() {
        let groups = RouteMapView.groupBySpeedZone(.init(coords: [c(0), c(10), c(20)], speeds: [-1, -1, -1]))
        XCTAssertEqual(groups.count, 1)
        XCTAssertLessThan(groups[0].speed, 0)

        let mixed = RouteMapView.groupBySpeedZone(
            .init(coords: [c(0), c(10), c(20), c(30)], speeds: [0.5, 0.5, -1, -1])
        )
        XCTAssertEqual(mixed.count, 2)
        XCTAssertGreaterThanOrEqual(mixed[0].speed, 0)
        XCTAssertLessThan(mixed[1].speed, 0)
    }
}
