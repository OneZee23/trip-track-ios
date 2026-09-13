import XCTest
@testable import TripTrack

final class PlaceChipTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    func testChipCarriesCountAndUsual() {
        let id = UUID()
        let passes = [PlacePass(placeId: id, tripId: UUID(), timestamp: now, elapsedFromStart: 8040, distanceFromStart: 1, course: 0),
                      PlacePass(placeId: id, tripId: UUID(), timestamp: now.addingTimeInterval(-86_400), elapsedFromStart: 7680, distanceFromStart: 1, course: 4)]
        let chip = PlaceChip.build(placeId: id, stats: PlaceStats.build(from: passes, now: now))
        XCTAssertEqual(chip.count, 2)
        XCTAssertEqual(chip.usual, 7860)
    }
    func testSinglePassHasNoUsual() {
        let id = UUID()
        let stats = PlaceStats.build(from: [PlacePass(placeId: id, tripId: UUID(), timestamp: now, elapsedFromStart: 8040, distanceFromStart: 1, course: 0)], now: now)
        let chip = PlaceChip.build(placeId: id, stats: stats)
        XCTAssertEqual(chip.count, 1)
        XCTAssertNil(chip.usual, "один проезд — не «обычно», а «первый раз здесь»")
    }

    func testTextForFirstVisit() {
        let chip = PlaceChip(placeId: UUID(), count: 1, usual: nil)
        XCTAssertEqual(chip.text(.ru), AppStrings.placeChipFirst(.ru))
    }

    func testTextWithoutUsual() {
        let chip = PlaceChip(placeId: UUID(), count: 5, usual: nil)
        let text = chip.text(.ru)
        XCTAssertEqual(text, AppStrings.placeHereTimes(.ru, count: 5))
        XCTAssertFalse(text.contains("·"))
    }

    func testTextWithUsual() {
        let chip = PlaceChip(placeId: UUID(), count: 5, usual: 8040)
        let text = chip.text(.ru)
        XCTAssertTrue(text.contains("·"))
        XCTAssertTrue(text.contains(CheckpointReading.clock(8040, lang: .ru)))
    }
}
