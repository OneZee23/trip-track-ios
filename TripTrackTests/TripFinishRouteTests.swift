import XCTest
@testable import TripTrack

/// Куда идёт только что законченная поездка. Мусор побеждает черновик
/// (Review Focus 2): поездку по парковке не спрашивают «Твоя?».
final class TripFinishRouteTests: XCTestCase {
    private func trip(metres: Double, seconds: TimeInterval, draft: Bool) -> Trip {
        Trip(startDate: TrackTestKit.epoch, endDate: TrackTestKit.epoch.addingTimeInterval(seconds),
             distance: metres, maxSpeed: 12, confirmation: draft ? .draft : .confirmed)
    }

    func testJunkWinsOverDraft() {
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 300, seconds: 60, draft: true)), .discardJunk)
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 300, seconds: 60, draft: false)), .discardJunk)
    }

    func testDraftWaitsAndConfirmedEntersTheWorld() {
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 5000, seconds: 900, draft: true)), .awaitConfirmation)
        XCTAssertEqual(TripWorldEntry.route(for: trip(metres: 5000, seconds: 900, draft: false)), .enterWorld)
    }
}
