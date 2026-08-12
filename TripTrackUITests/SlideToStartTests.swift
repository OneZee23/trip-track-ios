import XCTest

/// The reported bug, as tests: with no GPS fix yet («Ищем спутники») a swipe on
/// the start control sent the thumb home and left the screen exactly as it was
/// — no recording HUD, no message, nothing to read.
///
/// A simulator always hands out a location, so `-no-gps-fix` withholds every
/// one and parks the app in that state. The contract under test: the control
/// never moves without saying something. Silence is the bug.
///
/// The names are numbered because XCTest runs them alphabetically and the
/// order matters here: after a couple of launches that ignore every fix, the
/// simulator stops handing them out to this bundle at all, and the one test
/// that NEEDS a fix would then fail for a reason that has nothing to do with
/// the app. It goes first.
final class SlideToStartTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // Everything here is about what the start control does with a GPS
        // signal, which needs permission to have one. Earlier classes in the
        // suite leave that permission denied — these tests then land on the
        // «Нет доступа к геолокации» card, where the same control opens
        // Settings instead, and every assertion is about a screen that is not
        // under test. Reset it so the run starts from the prompt.
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>"]
    }

    /// A trip left running leaks into the next test: the app relaunches into
    /// the recovery sheet, and the GPS session it left behind is not the one a
    /// fresh screen sets up. Every test hands back a stopped app.
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

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The location prompt lives in Springboard, so it is not in `app`.
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

    /// A trip left running by an earlier test greets the next launch with the
    /// recovery sheet, which covers the whole screen.
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

    private func openRecordScreen() {
        clearRecoveryIfPresent()
        // The app reopens on the tab you left it on, and the Record screen
        // hides the tab bar — so it may already be in front of us.
        if slider.waitForExistence(timeout: 4) {
            grantLocationIfAsked()
            usleep(1_500_000)
            return
        }
        let record = app.buttons.matching(identifier: "tab_record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10), "the Record tab must be reachable")
        record.tap()
        usleep(2_000_000)
        grantLocationIfAsked()
        usleep(1_500_000)
    }

    private var slider: XCUIElement {
        app.buttons.matching(identifier: "slide_to_start").firstMatch
    }

    private func dragSliderAcross() {
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)))
        usleep(2_500_000)
    }

    /// The bug itself: touching the control with no fix must produce a reason.
    func test_2_no_fix_touch_states_a_reason() {
        app.launchArguments += ["-no-gps-fix"]
        app.launch()
        openRecordScreen()
        snap("01_idle_no_fix")

        XCTAssertTrue(slider.waitForExistence(timeout: 5), "the start control must be on screen")
        dragSliderAcross()
        snap("02_after_drag_no_fix")

        let refusal = app.descendants(matching: .any)
            .matching(identifier: "start_refused_toast").firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 3),
                      "a touch on the held control must say why it is held")
        XCTAssertFalse(app.buttons.matching(identifier: "tracking_pause").firstMatch.exists,
                       "and it must NOT have quietly started a recording")
    }

    /// The way past the wait, for a car park that never gives a fix.
    func test_3_start_anyway_records() {
        app.launchArguments += ["-no-gps-fix"]
        app.launch()
        openRecordScreen()

        dragSliderAcross()
        let anyway = app.buttons.matching(identifier: "start_anyway").firstMatch
        XCTAssertTrue(anyway.waitForExistence(timeout: 3), "the refusal must offer a way past itself")
        anyway.tap()
        usleep(2_000_000)
        snap("03_started_anyway")

        XCTAssertTrue(app.buttons.matching(identifier: "tracking_pause").firstMatch.waitForExistence(timeout: 5),
                      "«Всё равно начать» must actually start the recording")
    }

    /// With a fix — the simulator's simulated location — the control behaves
    /// exactly as it always did. This is the guard on the wait not leaking
    /// into the normal path.
    func test_1_with_a_fix_a_slide_starts_recording() throws {
        app.launch()
        openRecordScreen()

        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        // A cold receiver takes a moment even in a simulator; the control says
        // when it is ready by dropping the waiting label.
        //
        // A simulator only has a location if one was simulated for it, and the
        // test run does not always leave one in place — that is a fact about
        // the machine, not about the app, so it skips rather than fails. Set
        // one with `xcrun simctl location <udid> set 45.035,38.975` to make
        // this test actually run.
        let ready = NSPredicate(format: "label != 'Waiting for GPS' AND label != 'Ждём сигнал GPS'")
        let becameReady = XCTNSPredicateExpectation(predicate: ready, object: slider)
        try XCTSkipUnless(XCTWaiter().wait(for: [becameReady], timeout: 25) == .completed,
                          "no simulated location on this simulator — nothing to test the normal path with")

        dragSliderAcross()
        snap("04_started_with_fix")

        XCTAssertTrue(app.buttons.matching(identifier: "tracking_pause").firstMatch.waitForExistence(timeout: 5),
                      "a completed slide with a fix starts a recording")
    }
}
