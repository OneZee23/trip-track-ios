import XCTest

/// «Все | Подписки» take a tap across their whole half (0.8.9).
///
/// The segment pill had no content shape: the active one caught taps through
/// its white fill, the inactive one only on the letters of its word. «Подписки»
/// was a 66 × 16 pt target inside a 178 × 32 pt half — a thumb on the empty
/// part of the half, or just above the word, did nothing. Checked by tapping
/// the inactive half away from its word: at the side and near the top edge.
final class FeedSegmentTapTargetTests: XCTestCase {
    func testInactiveSegmentTakesATapAcrossItsHalf() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-feedSegmentFollowingV2", "<false/>",
                                "-appLanguage", "ru", "-AppleLanguages", "(ru)", "-appThemeMode", "light"]
        app.launch()
        let tab = app.buttons["tab_home"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()

        let all = app.buttons["feed_segment_all"].firstMatch
        let following = app.buttons["feed_segment_following"].firstMatch
        XCTAssertTrue(following.waitForExistence(timeout: 10))
        XCTAssertTrue(all.isSelected, "starts on «Все»")
        // The inactive half reports the same size as the active one: the
        // whole half is the control, not the word inside it.
        XCTAssertEqual(following.frame.width, all.frame.width, accuracy: 1, "\(following.frame) vs \(all.frame)")
        XCTAssertGreaterThanOrEqual(following.frame.height, 30, "\(following.frame)")

        // Near the right end of the half and 4 pt below its top: off the word.
        let window = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let f = following.frame
        window.withOffset(CGVector(dx: f.maxX - 12, dy: f.minY + 4)).tap()
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: following)
        waitForExpectations(timeout: 3)
    }
}
