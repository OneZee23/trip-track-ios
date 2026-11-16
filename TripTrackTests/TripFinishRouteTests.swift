import XCTest
@testable import TripTrack

/// Куда идёт только что законченная поездка. Мусор побеждает черновик
/// (Review Focus 2): поездку по парковке не спрашивают «Твоя?».
final class TripFinishRouteTests: XCTestCase {
    private func trip(metres: Double, seconds: TimeInterval, draft: Bool, points: Int = 2) -> Trip {
        let start = TrackTestKit.epoch
        let track = (0..<points).map { i in
            TrackPoint(latitude: 45 + Double(i) * 0.001, longitude: 38,
                       timestamp: start.addingTimeInterval(seconds * Double(i) / Double(max(points - 1, 1))))
        }
        return Trip(startDate: start, endDate: start.addingTimeInterval(seconds),
                    distance: metres, maxSpeed: 12, trackPoints: track,
                    confirmation: draft ? .draft : .confirmed)
    }

    func testJunkWinsOverDraft() {
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 300, seconds: 60, draft: true)), .discardJunk)
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 300, seconds: 60, draft: false)), .discardJunk)
    }

    func testDraftWaitsAndConfirmedEntersTheWorld() {
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 5000, seconds: 900, draft: true)), .awaitConfirmation)
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 5000, seconds: 900, draft: false)), .enterWorld)
    }

    /// Запись без единой точки GPS уходит при ЛЮБОЙ длительности. Между 120 и
    /// 180 секундами её не ловило ни одно правило по числам, и пустая
    /// «поездка» на 2:30 оставалась в истории.
    func testRecordingWithoutPointsIsDiscardedAtAnyLength() {
        for seconds in [5.0, 121, 150, 179, 900] {
            for draft in [false, true] {
                let empty = trip(metres: 0, seconds: seconds, draft: draft, points: 0)
                XCTAssertEqual(TripWorldEntry.route(for: empty), .discardJunk, "\(seconds) s, draft \(draft)")
                XCTAssertEqual(empty.finishDiscardReason, .noTrackPoints)
            }
        }
    }

    /// Правило про точки — только у финиша. `isJunk` зовут и у лёгких поездок
    /// из списка, у которых точек нет ни у одной, и там оно обязано молчать.
    func testListTripsWithoutLoadedPointsAreNotJunk() {
        let listed = trip(metres: 5000, seconds: 900, draft: false, points: 0)
        XCTAssertFalse(listed.isJunk)
    }

    func testOnePointKeepsTheOldRules() {
        XCTAssertNil(trip(metres: 0, seconds: 150, draft: false, points: 1).finishDiscardReason)
        XCTAssertEqual(trip(metres: 0, seconds: 60, draft: false, points: 1).finishDiscardReason, .tooShort)
    }
}
