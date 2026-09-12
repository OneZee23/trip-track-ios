import XCTest
import CoreLocation
@testable import TripTrack

/// Проезд — трек в 100 м от места. Синтетическая прямая на север от
/// (44.30, 38.70): шаг 50 м (0.00045° широты), 10 с; «туда и обратно» — та же
/// прямая назад с курсом 180.
final class PlaceMatcherTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    private let lat0 = 44.30, lon0 = 38.70
    private let stepLat = 0.00045   // ≈ 50 м
    private let tripId = UUID()

    private func point(_ i: Int, lat: Double, lon: Double, course: Double, t: TimeInterval) -> TrackPoint {
        TrackPoint(id: UUID(), latitude: lat, longitude: lon, altitude: 0, speed: 5,
                   course: course, horizontalAccuracy: 5, timestamp: t0.addingTimeInterval(t), isInterpolated: false)
    }

    /// `count` точек на север.
    private func northLine(count: Int, course: Double = 0) -> [TrackPoint] {
        (0..<count).map { point($0, lat: lat0 + Double($0) * stepLat, lon: lon0, course: course, t: Double($0) * 10) }
    }

    /// Туда (0…count-1) и обратно теми же точками, курс 180, время продолжается.
    private func outAndBack(count: Int) -> [TrackPoint] {
        let out = northLine(count: count)
        let back = (0..<count).map { k -> TrackPoint in
            let i = count - 1 - k
            return point(i, lat: lat0 + Double(i) * stepLat, lon: lon0, course: 180, t: Double(count + k) * 10)
        }
        return out + back
    }

    private func place(lat: Double, lon: Double) -> Place {
        let cell = Place.cell(latitude: lat, longitude: lon)
        return Place(id: Place.id(forCell: cell), cell: cell, latitude: lat, longitude: lon, name: nil, createdAt: t0)
    }

    func testOnePassStraightThrough() {
        let points = northLine(count: 60)
        let p = place(lat: lat0 + 30 * stepLat, lon: lon0)
        let passes = PlaceMatcher.passes(through: p, tripId: tripId, points: points, startDate: t0)
        XCTAssertEqual(passes.count, 1)
        XCTAssertEqual(passes[0].elapsedFromStart, 300, accuracy: 0.5)
        XCTAssertEqual(passes[0].distanceFromStart, 1500, accuracy: 75)   // 30 шагов по ~50 м, ±5 %
        XCTAssertEqual(passes[0].course, 0, accuracy: 0.5)
        XCTAssertEqual(passes[0].placeId, p.id)
        XCTAssertEqual(passes[0].tripId, tripId)
    }

    func testOutAndBackGivesTwoPassesWithOppositeCourses() {
        let points = outAndBack(count: 120)           // 6 км: между проездами > 10 мин
        let p = place(lat: lat0 + 30 * stepLat, lon: lon0)
        let passes = PlaceMatcher.passes(through: p, tripId: tripId, points: points, startDate: t0)
            .sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(passes.count, 2)
        XCTAssertEqual(passes[0].course, 0, accuracy: 0.5)
        XCTAssertEqual(passes[1].course, 180, accuracy: 0.5)
        XCTAssertGreaterThan(passes[1].elapsedFromStart, passes[0].elapsedFromStart + 600)
    }

    func testRadiusIsOneHundredMetres() {
        let points = northLine(count: 60)
        // 1° долготы на 44.3° ≈ 79.7 км: 80 м ≈ 0.001°, 150 м ≈ 0.00188°.
        let near = place(lat: lat0 + 30 * stepLat, lon: lon0 + 0.0010)
        let far = place(lat: lat0 + 30 * stepLat, lon: lon0 + 0.00188)
        XCTAssertEqual(PlaceMatcher.passes(through: near, tripId: tripId, points: points, startDate: t0).count, 1)
        XCTAssertEqual(PlaceMatcher.passes(through: far, tripId: tripId, points: points, startDate: t0).count, 0)
    }

    /// GPS не дал курса (−1) — курс берётся из соседних точек: прямая на север
    /// даёт ≈ 0°, а не «неизвестно».
    func testCourseFallsBackToNeighbours() {
        let points = northLine(count: 60, course: -1)
        XCTAssertEqual(PlaceMatcher.course(at: 30, in: points), 0, accuracy: 1)
        XCTAssertEqual(PlaceMatcher.course(at: 0, in: points), 0, accuracy: 1)      // край: вперёд
        XCTAssertEqual(PlaceMatcher.course(at: 59, in: points), 0, accuracy: 1)     // край: назад
        XCTAssertEqual(PlaceMatcher.course(at: 0, in: [points[0]]), PlacePass.unknownCourse)
    }

    /// Предфильтр по geohash-5: поездка по Москве не кандидат для места в
    /// Джубге; сосед ячейки — кандидат; пустое превью — кандидат (исключить
    /// то, чего не видно, нельзя).
    func testPrefilterByGeohash5() {
        let jubga = place(lat: 44.3196, lon: 38.7089)
        let moscow = PlaceMatcher.cells(of: [CLLocationCoordinate2D(latitude: 55.75, longitude: 37.61)])
        XCTAssertFalse(PlaceMatcher.isCandidate(place: jubga, tripCells: moscow))
        // Та же ячейка — координаты самого места.
        let sameCell = PlaceMatcher.cells(of: [jubga.coordinate])
        XCTAssertTrue(PlaceMatcher.isCandidate(place: jubga, tripCells: sameCell))
        // Соседняя ячейка geohash-5 (~2 км восточнее) — тоже кандидат: место у
        // границы ячейки видно из соседней.
        let neighbour = PlaceMatcher.cells(of: [CLLocationCoordinate2D(latitude: 44.3196, longitude: 38.7350)])
        XCTAssertTrue(PlaceMatcher.isCandidate(place: jubga, tripCells: neighbour))
        XCTAssertTrue(PlaceMatcher.isCandidate(place: jubga, tripCells: []))
    }

    func testTooFewPointsGiveNoPasses() {
        let p = place(lat: lat0, lon: lon0)
        XCTAssertEqual(PlaceMatcher.passes(through: p, tripId: tripId, points: [northLine(count: 1)[0]], startDate: t0).count, 0)
    }
}
