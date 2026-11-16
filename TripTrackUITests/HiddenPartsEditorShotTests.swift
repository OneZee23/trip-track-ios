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

    /// «Готово» must redraw the trip map at once. TestFlight 101 showed the
    /// new locks only after the trip was opened again (owner, 5 Nov 2026).
    func testDoneShowsTheNewLocksWithoutReopening() {
        launch(theme: "dark", flags: ["-seed-hidden-parts", "-open-hidden-editor"])
        let editor = app.descendants(matching: .any).matching(identifier: "hidden_parts_editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        let start = app.descendants(matching: .any).matching(identifier: "edge:start").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.3)
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 46, dy: -28)))
        app.buttons["hidden_editor_done"].firstMatch.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        let lock = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", "Граница скрытого участка", "Hidden route boundary")).firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 10), "The trip map kept the old route after «Готово»")
        capture("hidden-editor-done-map")
    }

    func testDraggingEndHandleChangesSummary() {
        launch(theme: "dark", flags: ["-seed-hidden-parts", "-open-hidden-editor"])
        let editor = app.descendants(matching: .any).matching(identifier: "hidden_parts_editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        let handle = app.descendants(matching: .any).matching(identifier: "edge:end").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.3)
        let summary = app.staticTexts["hidden_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let previous = summary.label
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -95, dy: 50)))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", previous), object: summary)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    func testLongPressOnVisibleRouteCreatesMiddleSection() {
        launch(theme: "light", flags: ["-seed-hidden-parts-fresh", "-open-hidden-editor"])
        let editor = app.descendants(matching: .any).matching(identifier: "hidden_parts_editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["hidden_section_title"].exists)
        // Nothing is hidden in the fresh seed, so both edges are ghost handles on the ends of
        // the (straight) route: the point between them lies on the line.
        let start = app.descendants(matching: .any).matching(identifier: "edge:start").firstMatch
        let end = app.descendants(matching: .any).matching(identifier: "edge:end").firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.3)
        let middle = CGVector(dx: (start.frame.midX + end.frame.midX) / 2, dy: (start.frame.midY + end.frame.midY) / 2)
        app.coordinate(withNormalizedOffset: .zero).withOffset(middle).press(forDuration: 0.6)
        XCTAssertTrue(app.staticTexts["hidden_section_title"].waitForExistence(timeout: 8))
    }

    /// A lock on the trip page is never dragged there: tapping it opens the editor with that
    /// lock focused (it pulses and shows its value), and nothing changes before «Готово».
    func testTappingATripLockOpensTheEditorOnIt() {
        launch(theme: "light", flags: ["-seed-hidden-parts", "-open-trip-map"])
        XCTAssertTrue(app.buttons["detail_map_expand"].waitForExistence(timeout: 45))
        // The hero map takes no touches on purpose (pull to refresh starts there); the lock is
        // pressed on the full-screen map.
        app.buttons["detail_map_expand"].tap()
        XCTAssertTrue(app.buttons["fullscreen_map_close"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        let lock = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", "Граница скрытого участка", "Hidden route boundary")).firstMatch
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        lock.tap()
        let editor = app.descendants(matching: .any).matching(identifier: "hidden_parts_editor").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "A tap on a trip lock must open the editor")
        for step in 0..<4 {
            usleep(350_000)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "hidden-editor-focused-\(step)"
            shot.lifetime = .keepAlways
            add(shot)
        }
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
