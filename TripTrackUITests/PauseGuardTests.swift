import XCTest

/// «Свернул приложение — запись оказалась на паузе».
///
/// Two things have to be true for that to be impossible, and both are measured
/// here rather than eyeballed:
///
/// 1. The pause control must sit clear of the home-indicator strip. A control
///    that overlaps it competes with the system gesture: sometimes iOS wins and
///    the app goes to the background, sometimes the app wins and the button
///    fires — which is exactly the reported «то свернулось, то встало на паузу».
/// 2. Pause must answer to a tap and to nothing else. A press that travels —
///    the start of a swipe — is not a tap, and must leave the recording alone.
final class PauseGuardTests: XCTestCase {
    private var app: XCUIApplication!

    /// Bottom safe-area inset on every phone this app supports (iPhone 11 and
    /// up, including the 16 family). The strip iOS reserves for the home
    /// indicator is the bottom ~21pt of it.
    private let homeIndicatorStrip: CGFloat = 21

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>"]
        app.launch()
    }

    override func tearDownWithError() throws {
        let stop = app.buttons.matching(identifier: "tracking_stop").firstMatch
        guard stop.exists else { return }
        stop.tap()
        usleep(700_000)
        let finish = app.buttons.matching(identifier: "stop_confirm_finish").firstMatch
        if finish.waitForExistence(timeout: 3) {
            finish.tap()
            usleep(1_500_000)
        }
        let done = app.buttons.matching(identifier: "summary_done").firstMatch
        if done.waitForExistence(timeout: 6) {
            done.tap()
            usleep(1_000_000)
        }
    }

    // MARK: - Helpers

    private var pause: XCUIElement { app.buttons.matching(identifier: "tracking_pause").firstMatch }

    private func grantLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "При использовании"] {
            let button = springboard.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
                usleep(800_000)
                return
            }
        }
    }

    private func clearRecoveryIfPresent() {
        let finish = app.buttons.matching(identifier: "recovery_finish").firstMatch
        if finish.waitForExistence(timeout: 2) {
            finish.tap()
            usleep(1_500_000)
            let done = app.buttons.matching(identifier: "summary_done").firstMatch
            if done.waitForExistence(timeout: 4) {
                done.tap()
                usleep(1_000_000)
            }
        }
    }

    private func startRecording() {
        clearRecoveryIfPresent()
        let slider = app.buttons.matching(identifier: "slide_to_start").firstMatch
        if !slider.waitForExistence(timeout: 4) {
            let record = app.buttons.matching(identifier: "tab_record").firstMatch
            XCTAssertTrue(record.waitForExistence(timeout: 10), "the Record tab must be reachable")
            record.tap()
            usleep(2_000_000)
        }
        grantLocationIfAsked()
        usleep(1_500_000)
        XCTAssertTrue(slider.waitForExistence(timeout: 6), "the start control must be on screen")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)))
        usleep(2_500_000)
        // Check the refusal FIRST. The «Ждём сигнал GPS» toast that carries
        // «Всё равно начать» clears itself after 8s, so waiting six of them on
        // `tracking_pause` before looking for it meant looking at an empty
        // screen. The simulator stops handing fixes to this bundle once the
        // -no-gps-fix suites have run, so in a full-suite order this is the
        // normal path, not the rare one.
        if !pause.exists {
            let anyway = app.buttons.matching(identifier: "start_anyway").firstMatch
            if anyway.waitForExistence(timeout: 3) {
                anyway.tap()
                usleep(2_500_000)
            }
        }
        if !pause.waitForExistence(timeout: 6) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "start_failed"
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("recording must have started")
        }
    }

    /// True while the trip is running: the control offers «Пауза», not «Продолжить».
    private var isRunning: Bool {
        let label = pause.label
        return !(label.contains("Продолж") || label.contains("Resume"))
    }

    // MARK: - Tests

    /// The other half of the contract: a tap still pauses, and taps again to
    /// resume. A guard that also blocks the real gesture is not a guard.
    func test_0_tap_pauses_and_resumes() {
        startRecording()
        XCTAssertTrue(isRunning, "precondition: the trip is running")

        pause.tap()
        usleep(1_200_000)
        XCTAssertFalse(isRunning, "a tap must pause the recording")

        pause.tap()
        usleep(1_200_000)
        XCTAssertTrue(isRunning, "a second tap must resume it")
    }

    /// Where the control actually is, in points from the bottom of the screen.
    func test_1_pause_button_clears_the_home_indicator() {
        startRecording()

        let screen = app.windows.firstMatch.frame
        let button = pause.frame
        let gap = screen.maxY - button.maxY

        print("""
            GEOMETRY screen=\(screen.height) \
            button=\(button.minY)…\(button.maxY) h=\(button.height) \
            gapBelow=\(gap)pt strip=\(homeIndicatorStrip)pt
            """)

        XCTAssertGreaterThanOrEqual(
            gap, homeIndicatorStrip,
            "the pause control ends \(gap)pt above the screen bottom — it reaches into the "
            + "home-indicator strip, where a swipe-to-home starts on top of it"
        )
    }

    /// A press that travels is a swipe, not a tap.
    func test_2_swipe_from_the_button_does_not_pause() {
        startRecording()
        XCTAssertTrue(isRunning, "precondition: the trip is running")

        let start = pause.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -260)))
        usleep(1_200_000)

        XCTAssertTrue(isRunning, "a swipe that began on the pause control paused the recording")
    }

    /// The one that actually catches people: a swipe that begins on the control
    /// and never leaves it. 18pt is a flick of the thumb, well inside a 52pt
    /// button — SwiftUI считает это тапом, потому что палец не вышел за края.
    func test_2b_short_drag_on_the_button_does_not_pause() {
        startRecording()
        XCTAssertTrue(isRunning, "precondition: the trip is running")

        let start = pause.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -18)))
        usleep(1_200_000)

        XCTAssertTrue(isRunning, "an 18pt drag on the pause control paused the recording")
    }

    /// The same swipe as the one that sends the app home: from the very bottom
    /// edge, straight up through the controls.
    func test_3_swipe_from_the_bottom_edge_does_not_pause() {
        startRecording()
        XCTAssertTrue(isRunning, "precondition: the trip is running")

        let window = app.windows.firstMatch
        let bottom = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.999))
        bottom.press(forDuration: 0.05, thenDragTo: bottom.withOffset(CGVector(dx: 0, dy: -320)))
        usleep(1_200_000)

        XCTAssertTrue(isRunning, "a swipe up from the bottom edge paused the recording")
    }
}
