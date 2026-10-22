import XCTest

@MainActor
final class ProfileCardShotTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    private var common: [String] {
        ["-hasCompletedOnboarding", "<true/>", "-appLanguage", "ru", "-appThemeMode", "light",
         "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
    }

    func testOwnProfileCard() {
        app = XCUIApplication()
        app.launchArguments += common + ["-seed-map-demo", "-seed-profile-card"]
        app.launch()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        // The grid is lazy: the second row is built only once it scrolls in,
        // so the first photo proves the seed and the fourth is asked below.
        XCTAssertTrue(app.buttons["profile_photo_0"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["profile_bio"].firstMatch.exists)
        capture("own-top")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        XCTAssertTrue(app.buttons["profile_photo_3"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Витрина"].firstMatch.waitForExistence(timeout: 10))
        capture("own-showcase")
    }

    func testForeignProfileCard() {
        app = XCUIApplication()
        app.launchArguments += common + ["-debug-foreign-trip", "-debug-foreign-profile", "pro"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        preview.tap()
        let author = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 15))
        author.tap()
        XCTAssertTrue(app.buttons["profile_photo_4"].firstMatch.waitForExistence(timeout: 20))
        capture("foreign-top")
        app.buttons["profile_photo_0"].firstMatch.tap()
        let close = app.buttons["photo_viewer_close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["photo_viewer_delete"].exists)
        XCTAssertFalse(app.buttons["photo_viewer_main"].exists)
        close.tap()
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        XCTAssertTrue(app.staticTexts["Витрина"].firstMatch.waitForExistence(timeout: 10))
        capture("foreign-showcase")
        XCTAssertFalse(app.buttons["profile_photos_add"].exists)
    }

    private func capture(_ name: String) {
        usleep(700_000)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "profile-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
