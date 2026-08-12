import XCTest

/// Every state the recording screen can be in, as pictures.
///
/// The static reviews cover what the code says; this covers what the screen
/// does — a control hidden behind another view, a panel that grew past the
/// bottom edge, a paused state that looks identical to a running one. Those
/// are invisible in a diff and obvious in a screenshot.
final class RecordingStatesTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    override func tearDownWithError() throws {
        let stop = app.buttons.matching(identifier: "tracking_stop").firstMatch
        guard stop.exists else { return }
        stop.tap()
        usleep(700_000)
        let finish = app.buttons.matching(identifier: "stop_confirm_finish").firstMatch
        if finish.waitForExistence(timeout: 3) { finish.tap(); usleep(1_500_000) }
        let done = app.buttons.matching(identifier: "summary_done").firstMatch
        if done.waitForExistence(timeout: 6) { done.tap(); usleep(1_000_000) }
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private var pause: XCUIElement { app.buttons.matching(identifier: "tracking_pause").firstMatch }

    private func grantLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "При использовании"] {
            let button = springboard.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) { button.tap(); usleep(800_000); return }
        }
    }

    private func clearRecoveryIfPresent() {
        let finish = app.buttons.matching(identifier: "recovery_finish").firstMatch
        if finish.waitForExistence(timeout: 2) {
            finish.tap()
            usleep(1_500_000)
            let done = app.buttons.matching(identifier: "summary_done").firstMatch
            if done.waitForExistence(timeout: 4) { done.tap(); usleep(1_000_000) }
        }
    }

    private func openRecord() {
        clearRecoveryIfPresent()
        let slider = app.buttons.matching(identifier: "slide_to_start").firstMatch
        if !slider.waitForExistence(timeout: 4) {
            let record = app.buttons.matching(identifier: "tab_record").firstMatch
            XCTAssertTrue(record.waitForExistence(timeout: 10), "the Record tab must be reachable")
            record.tap()
            usleep(2_000_000)
        }
        grantLocationIfAsked()
        usleep(2_000_000)
    }

    private func startRecording() {
        let slider = app.buttons.matching(identifier: "slide_to_start").firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 6), "the start control must be on screen")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)))
        usleep(2_000_000)
        // See PauseGuardTests: without a fix the start is refused, and the
        // refusal toast that offers the way past it clears after 8s.
        if !pause.exists {
            let anyway = app.buttons.matching(identifier: "start_anyway").firstMatch
            if anyway.waitForExistence(timeout: 3) {
                anyway.tap()
                usleep(2_500_000)
            }
        }
    }

    /// The same screen over a daylight map. Every panel here is dark glass, and
    /// dark glass is where light-map contrast goes wrong.
    func test_recording_over_a_light_map() {
        app.terminate()
        app.launchArguments += ["-force-light-map"]
        app.launch()

        openRecord()
        snap("07_idle_light")

        startRecording()
        XCTAssertTrue(pause.waitForExistence(timeout: 8), "recording must have started")
        usleep(2_000_000)
        snap("08_recording_light")
    }

    func test_recording_states_tour() {
        openRecord()
        snap("01_idle")

        startRecording()
        XCTAssertTrue(pause.waitForExistence(timeout: 8), "recording must have started")
        usleep(2_000_000)
        snap("02_recording")

        pause.tap()
        usleep(1_500_000)
        snap("03_paused")

        pause.tap()
        usleep(1_200_000)
        snap("04_resumed")

        app.buttons.matching(identifier: "tracking_stop").firstMatch.tap()
        usleep(1_200_000)
        snap("05_stop_confirm")

        app.buttons.matching(identifier: "stop_confirm_cancel").firstMatch.tap()
        usleep(1_000_000)
        snap("06_back_to_recording")
    }
}
