import XCTest

@MainActor
final class HiddenPartsEditorShotTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    func testEditorLightShowsStagesSectionsAndNumbers() {
        launch(theme: "light", flags: ["-seed-hidden-parts", "-open-hidden-editor"])
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "hidden_parts_editor").firstMatch.waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["hidden_section_title"].waitForExistence(timeout: 10))
        capture("hidden-editor-light-top")
        let add = app.buttons["hidden_add_section"].firstMatch
        XCTAssertTrue(add.exists)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "hidden_numbers_choice").firstMatch.waitForExistence(timeout: 5))
        capture("hidden-editor-light-numbers")
    }

    func testEditorDarkFreshState() {
        launch(theme: "dark", flags: ["-seed-hidden-parts-fresh", "-open-hidden-editor"])
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "hidden_parts_editor").firstMatch.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["hidden_section_title"].exists)
        capture("hidden-editor-dark")
    }

    private func launch(theme: String, flags: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "<true/>", "-ui-testing",
                              "-appLanguage", "ru", "-AppleLanguages", "(ru)",
                              "-appThemeMode", theme] + flags
        app.launch()
    }

    private func capture(_ name: String) {
        usleep(700_000)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
