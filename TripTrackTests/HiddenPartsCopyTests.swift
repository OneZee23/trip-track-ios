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
        let russian: [(Int, String)] = [
            (1, "1 скрытый кусок не попадёт ни в ленту, ни в облачную копию."),
            (2, "2 скрытых куска не попадут ни в ленту, ни в облачную копию."),
            (5, "5 скрытых кусков не попадут ни в ленту, ни в облачную копию."),
            (11, "11 скрытых кусков не попадут ни в ленту, ни в облачную копию."),
            (21, "21 скрытый кусок не попадёт ни в ленту, ни в облачную копию.")
        ]
        for (count, expected) in russian {
            XCTAssertEqual(AppStrings.hiddenLocalCardBody(.ru, pieces: count, photos: 0), expected)
            XCTAssertEqual(AppStrings.hiddenLocalCardBody(.ru, pieces: count, photos: 3),
                           "\(count) \(count == 1 || count == 21 ? "скрытый кусок" : (2...4).contains(count % 10) && !(12...14).contains(count % 100) ? "скрытых куска" : "скрытых кусков") и 3 фото оттуда не попадут ни в ленту, ни в облачную копию.")
        }
        XCTAssertEqual(AppStrings.hiddenLocalCardBody(.ru, pieces: 0, photos: 0),
                       "0 скрытых кусков не попадут ни в ленту, ни в облачную копию.")
        XCTAssertEqual(AppStrings.hiddenLocalCardBody(.ru, pieces: 0, photos: 3),
                       "0 скрытых кусков и 3 фото оттуда не попадут ни в ленту, ни в облачную копию.")
        XCTAssertEqual(AppStrings.hiddenNothing(.ru), "Ничего не скрыто")

        for language: LanguageManager.Language in [.uk, .pl, .en] {
            for count in [1, 2, 5, 11, 21, 0] {
                XCTAssertFalse(AppStrings.hiddenLocalCardBody(language, pieces: count, photos: 0).isEmpty)
                XCTAssertFalse(AppStrings.hiddenLocalCardBody(language, pieces: count, photos: 3).isEmpty)
            }
        }
    }
}
