import XCTest

/// The stop confirmation must describe what will happen before a destructive
/// tap. Run on an isolated simulator, built with API_BASE_URL=http://127.0.0.1:1.
/// Demo history and withheld GPS fixes keep this independent of Apple login,
/// a backend account, real movement and simulated-location settings.
@MainActor
final class RecordingFinishFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments = [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-no-gps-fix",
            "-appLanguage", "ru", "-appThemeMode", "dark",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        // A failed assertion must not leave a recording for the next test.
        if app?.state == .runningForeground {
            finishExistingRecordingIfPresent()
            app.terminate()
        }
        app = nil
    }

    func testShortRecordingWarnsBeforeDiscardAndReturningPreservesPause() {
        openRecordScreen()
        startWithoutGPS()
        // There are no fixes, so the distance is exactly zero. Stay well below
        // the two-minute threshold while testing the actual recording flow.
        Thread.sleep(forTimeInterval: 2)

        tap("tracking_stop")
        assertDiscardWarning()
        snapshot("recording_short_discard_warning")

        tap("stop_confirm_cancel")
        assertAbsent(button("stop_confirm_finish"))
        assertLabelContains(button("tracking_pause"), "Пауза")
        XCTAssertTrue(button("tracking_stop").exists, "Returning must keep the recording alive")

        tap("tracking_pause")
        assertLabelContains(button("tracking_pause"), "Продолжить")
        tap("tracking_stop")
        assertDiscardWarning()
        XCTAssertFalse(button("stop_confirm_pause").exists,
                       "An already paused recording must not offer Pause again")
        snapshot("recording_paused_discard_warning")

        tap("stop_confirm_cancel")
        assertAbsent(button("stop_confirm_finish"))
        assertLabelContains(button("tracking_pause"), "Продолжить")
        XCTAssertTrue(button("tracking_stop").exists,
                      "Returning from the question must preserve the paused recording")

        tap("tracking_stop")
        assertDiscardWarning()
        tap("stop_confirm_finish")
        XCTAssertTrue(button("slide_to_start").waitForExistence(timeout: 5),
                      "Finishing without saving must return to the idle recording screen")
        assertAbsent(button("tracking_stop"))
        XCTAssertFalse(button("summary_done").exists,
                       "A discarded recording must not show a saved-trip summary")
        snapshot("recording_discarded_idle")
    }

    private func assertDiscardWarning(file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts["stop_confirm_title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(title.label, "Завершить без сохранения?", file: file, line: line)
        XCTAssertEqual(app.staticTexts["stop_confirm_explanation"].firstMatch.label,
                       "Поездка слишком короткая и не попадёт в историю.", file: file, line: line)
        assertLabelContains(button("stop_confirm_finish"), "Завершить без сохранения", file: file, line: line)
        assertLabelContains(button("stop_confirm_cancel"), "Вернуться к записи", file: file, line: line)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Завершить и сохранить")).firstMatch.exists,
                       "The discarded trip must never be presented as a Save action", file: file, line: line)
    }

    private func openRecordScreen() {
        let recovery = button("recovery_finish")
        if recovery.waitForExistence(timeout: 2) {
            recovery.tap()
            let done = button("summary_done")
            if done.waitForExistence(timeout: 4) { done.tap() }
        }
        if !button("slide_to_start").exists && !button("tracking_stop").exists {
            tap("tab_record", timeout: 20)
        }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "При использовании"] {
            let allow = springboard.buttons[label].firstMatch
            if allow.waitForExistence(timeout: 2) { allow.tap(); break }
        }
        // Recovery may silently adopt an unfinished recording from an earlier
        // interrupted suite. Close it before starting the one under test.
        finishExistingRecordingIfPresent()
        XCTAssertTrue(button("slide_to_start").waitForExistence(timeout: 5))
    }

    private func startWithoutGPS() {
        let slider = button("slide_to_start")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)))
        // The refusal lasts eight seconds: address it before waiting for a HUD
        // that cannot appear until the user chooses Start anyway.
        tap("start_anyway", timeout: 4)
        XCTAssertTrue(button("tracking_pause").waitForExistence(timeout: 5))
        assertLabelContains(button("tracking_pause"), "Пауза")
    }

    private func finishExistingRecordingIfPresent() {
        guard button("tracking_stop").exists else { return }
        if !button("stop_confirm_finish").exists { button("tracking_stop").tap() }
        let finish = button("stop_confirm_finish")
        if finish.waitForExistence(timeout: 2) {
            finish.tap()
            // A newly crossed threshold refreshes the question instead of
            // accepting the stale outcome. Cleanup can accept that new one.
            if finish.waitForExistence(timeout: 1), finish.isHittable { finish.tap() }
        }
        let done = button("summary_done")
        if done.exists { done.tap() }
    }

    private func button(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, timeout: TimeInterval = 5) {
        let target = button(id)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), id)
        target.tap()
    }

    private func assertLabelContains(_ element: XCUIElement, _ text: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func assertAbsent(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
