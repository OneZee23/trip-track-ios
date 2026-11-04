import XCTest
@testable import TripTrack

final class HiddenPartsCopyTests: XCTestCase {
    func testSummaryOnlyListsHiddenPartsAndPublishRowHandlesEmptyState() {
        XCTAssertEqual(AppStrings.hiddenSummary(.ru, start: "500 м", end: "", sections: 0),
                       "Начало 500 м")
        XCTAssertEqual(AppStrings.hiddenSummary(.ru, start: "", end: "1 000 м", sections: 0),
                       "Конец 1 000 м")
        XCTAssertEqual(AppStrings.hiddenSummary(.ru, start: "", end: "", sections: 1),
                       "1 участок в середине")
        XCTAssertEqual(AppStrings.hiddenSummary(.ru, start: "", end: "", sections: 0),
                       "Ничего не скрыто")
        XCTAssertEqual(AppStrings.hiddenPublishRow(.ru, summary: "Ничего не скрыто"),
                       "Скрыть от других")
        XCTAssertEqual(AppStrings.hiddenPublishRow(.ru, summary: "Начало 500 м"),
                       "Скрыто: Начало 500 м")
    }

    func testLocalOnlyCardUsesSectionAndPhotoCounts() {
        XCTAssertEqual(AppStrings.hiddenLocalCardBody(.ru, pieces: 3, photos: 3),
                       "3 скрытых куска и 3 фото с них не попадут ни в ленту, ни в облачную копию.")
        XCTAssertEqual(AppStrings.hiddenLocalCardBody(.ru, pieces: 1, photos: 0),
                       "1 скрытый кусок не попадёт ни в ленту, ни в облачную копию.")
    }
}
