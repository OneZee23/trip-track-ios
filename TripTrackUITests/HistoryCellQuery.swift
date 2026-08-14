import XCTest

/// Finding a trip in История, whichever way the user last left it displayed.
///
/// Since 0.6.0 the section renders `profile_trip_card` in list mode and
/// `profile_trip_tile` in grid mode, and the choice persists in
/// `@AppStorage("profileHistoryMode")` — so it survives an app reinstall's
/// UserDefaults on the same simulator and a suite that hardcoded either id
/// would pass or fail depending on how someone last used the app by hand.
/// Matching both keeps the tests about the trip, not about the layout.
extension XCUIApplication {
    var historyTripCells: XCUIElementQuery {
        buttons.matching(
            NSPredicate(format: "identifier IN %@", ["profile_trip_card", "profile_trip_tile"])
        )
    }

    /// Same query without the `.button` narrowing — for the snapshot tour,
    /// which counts elements rather than tapping them.
    var anyHistoryTripCells: XCUIElementQuery {
        descendants(matching: .any).matching(
            NSPredicate(format: "identifier IN %@", ["profile_trip_card", "profile_trip_tile"])
        )
    }
}
