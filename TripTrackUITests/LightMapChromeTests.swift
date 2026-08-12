import XCTest

/// The recording HUD floats directly on the map, so every one of its greys is
/// a bet on how bright the map is — and the map goes light at sunrise whatever
/// the app's theme is set to. Bets that were lost so far: the pause disc
/// (white at 15%), the car chip (white at 12% with white text), the «КМ/Ч»
/// caption. All three were invisible in daylight and all three were reported
/// from the road, because nobody looks at this screen at noon in a simulator.
///
/// `-force-light-map` pins the daylight map so a screenshot can.
final class LightMapChromeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // See SlideToStartTests: the suite leaves location denied, and the
        // geo-denied card is a different screen with a different control.
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-force-light-map", "-no-gps-fix"]
        app.launch()
    }

    override func tearDownWithError() throws {
        // The test leaves the vehicle sheet open, and a sheet swallows the
        // taps below it — the recording would survive into the next launch and
        // greet it with the recovery prompt instead of the Record screen.
        if app.buttons.matching(identifier: "vehicle_chip").firstMatch.exists {
            app.swipeDown()
            usleep(1_000_000)
        }
        let stop = app.buttons.matching(identifier: "tracking_stop").firstMatch
        guard stop.waitForExistence(timeout: 3) else { return }
        stop.tap()
        usleep(700_000)
        let finish = app.buttons.matching(identifier: "stop_confirm_finish").firstMatch
        if finish.waitForExistence(timeout: 3) { finish.tap(); usleep(1_500_000) }
        let done = app.buttons.matching(identifier: "summary_done").firstMatch
        if done.waitForExistence(timeout: 6) { done.tap(); usleep(1_000_000) }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The prompt only appears once the Record screen asks for it, and it can
    /// take a few seconds — asking before navigating just times out and leaves
    /// the alert sitting over everything the test then tries to touch.
    private func grantLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<8 {
            for label in ["Allow While Using App", "При использовании"] {
                let button = springboard.buttons[label].firstMatch
                if button.exists {
                    button.tap()
                    usleep(800_000)
                    return
                }
            }
            usleep(700_000)
        }
    }

    func test_recording_chrome_reads_on_a_light_map() {
        // A trip left running by an interrupted run opens on the recovery
        // sheet, which covers everything this test wants to touch.
        let recoveryFinish = app.buttons.matching(identifier: "recovery_finish").firstMatch
        if recoveryFinish.waitForExistence(timeout: 3) {
            recoveryFinish.tap()
            usleep(1_500_000)
            let done = app.buttons.matching(identifier: "summary_done").firstMatch
            if done.waitForExistence(timeout: 5) { done.tap(); usleep(1_000_000) }
        }

        let slider = app.buttons.matching(identifier: "slide_to_start").firstMatch
        if !slider.waitForExistence(timeout: 4) {
            let record = app.buttons.matching(identifier: "tab_record").firstMatch
            XCTAssertTrue(record.waitForExistence(timeout: 10))
            record.tap()
            usleep(1_500_000)
        }
        grantLocation()
        usleep(1_500_000)
        snap("01_idle_light_map")

        // No fix in this run, so the deliberate way in is «Всё равно начать».
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)))
        usleep(2_000_000)
        let anyway = app.buttons.matching(identifier: "start_anyway").firstMatch
        XCTAssertTrue(anyway.waitForExistence(timeout: 4))
        anyway.tap()
        usleep(2_500_000)

        snap("02_recording_light_map")
        XCTAssertTrue(app.buttons.matching(identifier: "tracking_pause").firstMatch.exists)

        app.buttons.matching(identifier: "tracking_pause").firstMatch.tap()
        usleep(1_500_000)
        snap("03_paused_light_map")

        // The vehicle picker is a white sheet over the map, and its bottom
        // edge was reported as looking cut off on a phone. A picture is the
        // only way to see how the sheet actually sits.
        app.buttons.matching(identifier: "vehicle_chip").firstMatch.tap()
        usleep(1_500_000)
        snap("04_vehicle_picker_sheet")
    }
}
