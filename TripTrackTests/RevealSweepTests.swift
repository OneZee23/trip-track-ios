import XCTest
import CoreLocation
import SwiftUI
@testable import TripTrack

/// Выгорание тумана на мини-карте блока «Открыто» (0.7.0).
///
/// `CADisplayLink` в юнит-тесте не тикает, поэтому анимация проверяется своим
/// временем через `advance(to:)` — ради этого метод и выделен из шага.
@MainActor
final class RevealSweepTests: XCTestCase {

    // MARK: Прогресс

    func testProgressIsClampedToTheUnitInterval() {
        XCTAssertEqual(RevealSweep.value(elapsed: -1), 0)
        XCTAssertEqual(RevealSweep.value(elapsed: 0), 0)
        XCTAssertEqual(RevealSweep.value(elapsed: RevealSweep.duration / 2), 0.5, accuracy: 0.001)
        XCTAssertEqual(RevealSweep.value(elapsed: RevealSweep.duration), 1)
        XCTAssertEqual(RevealSweep.value(elapsed: 10), 1)
    }

    func testProgressOnlyEverGrows() {
        let sweep = RevealSweep()
        sweep.begin(reduceMotion: false, now: 100)
        sweep.advance(to: 100 + RevealSweep.duration / 2)
        let half = sweep.progress
        XCTAssertGreaterThan(half, 0)
        // Часы прыгнули назад (возврат из фона) — туман не имеет права поехать
        // обратно.
        sweep.advance(to: 100.01)
        XCTAssertEqual(sweep.progress, half)
    }

    func testSweepReachesOneAndStopsItself() {
        let sweep = RevealSweep()
        sweep.begin(reduceMotion: false, now: 0)
        sweep.advance(to: RevealSweep.duration + 0.1)
        XCTAssertEqual(sweep.progress, 1)
        // Доиграв, он снимает свой `CADisplayLink`: дальше время не идёт.
        sweep.advance(to: RevealSweep.duration + 5)
        XCTAssertEqual(sweep.progress, 1)
    }

    // MARK: Доступность

    func testReduceMotionJumpsStraightToOne() {
        let sweep = RevealSweep()
        sweep.begin(reduceMotion: true, now: 0)
        XCTAssertEqual(sweep.progress, 1, "при уменьшенном движении выгорания нет — сразу кроссфейд")
        // И время его больше не двигает: анимации нет вовсе.
        sweep.advance(to: 10)
        XCTAssertEqual(sweep.progress, 1)
    }

    // MARK: Отмена

    func testCancelStopsTheSweepWhereItStood() {
        let sweep = RevealSweep()
        sweep.begin(reduceMotion: false, now: 0)
        sweep.advance(to: RevealSweep.duration / 4)
        let stopped = sweep.progress
        sweep.cancel()
        sweep.advance(to: RevealSweep.duration)
        XCTAssertEqual(sweep.progress, stopped, "после отмены прогресс двигаться не должен")
    }

    /// Блок, к которому вернулись, не играет анимацию во второй раз.
    func testSecondStartDoesNotRewindAFinishedSweep() {
        let sweep = RevealSweep()
        sweep.begin(reduceMotion: true, now: 0)
        sweep.begin(reduceMotion: false, now: 100)
        XCTAssertEqual(sweep.progress, 1)
    }

    // MARK: Направление

    func testSweepRunsAlongTheRoad() {
        let east = RevealSweep.axis(from: [
            CLLocationCoordinate2D(latitude: 45, longitude: 38),
            CLLocationCoordinate2D(latitude: 45, longitude: 39)
        ])
        XCTAssertEqual(east.start.x, 0, accuracy: 0.001)
        XCTAssertEqual(east.end.x, 1, accuracy: 0.001)
        XCTAssertEqual(east.start.y, 0.5, accuracy: 0.001)

        // На север — снизу вверх: экран растёт вниз, широта вверх.
        let north = RevealSweep.axis(from: [
            CLLocationCoordinate2D(latitude: 45, longitude: 38),
            CLLocationCoordinate2D(latitude: 46, longitude: 38)
        ])
        XCTAssertEqual(north.start.y, 1, accuracy: 0.001)
        XCTAssertEqual(north.end.y, 0, accuracy: 0.001)
    }

    func testStandingStillAndEmptyTrackFallBackToASideWipe() {
        let still = CLLocationCoordinate2D(latitude: 45, longitude: 38)
        for coordinates in [[], [still], [still, still]] {
            let axis = RevealSweep.axis(from: coordinates)
            XCTAssertEqual(axis.start, .leading)
            XCTAssertEqual(axis.end, .trailing)
        }
    }

    // MARK: Кромка

    func testVeilCoversEverythingAtZeroAndNothingAtOne() {
        let atZero = RevealSweep.stops(veil: .black, progress: 0)
        XCTAssertEqual(atZero.first?.location, 0)
        // Второй стоп на нуле — значит прозрачного на карте нет ни полоски.
        XCTAssertEqual(atZero[1].location, 0, accuracy: 0.001)

        let atOne = RevealSweep.stops(veil: .black, progress: 1)
        XCTAssertEqual(atOne[1].location, 1, accuracy: 0.001,
                       "на последнем кадре тумана не остаётся даже в дальнем углу")
    }

    /// Кромка только едет вперёд и не переворачивается: стоп тумана никогда не
    /// оказывается раньше стопа открытого.
    func testEdgeNeverInverts() {
        for step in 0...20 {
            let stops = RevealSweep.stops(veil: .black, progress: Double(step) / 20)
            XCTAssertLessThanOrEqual(stops[1].location, stops[2].location, "шаг \(step)")
            XCTAssertLessThanOrEqual(stops[2].location, stops[3].location, "шаг \(step)")
        }
    }
}
