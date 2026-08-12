import XCTest

/// Screenshot tour of the surfaces added in this round: companions, the access
/// picker inside the edit sheet, and the replay now that it plays over a map.
///
/// Guarded rather than asserted where the app's own data decides what exists —
/// a device with no timestamped trip has no replay to open, and that is not a
/// test failure.
///
/// `test_companions` cannot drive the real invite flow: companions are real
/// accounts now (no more typed name + emoji), and inviting one needs both a
/// signed-in session and a trip that exists on the server — Sign in with
/// Apple can't be scripted, so neither is reachable here. What it asserts
/// instead is the one thing a signed-out simulator with a device-only trip
/// genuinely guarantees: the companions card renders its "not published"
/// invite-with-hint state, never the red load-failed row. That is exactly
/// the regression `fix: companion photos and card` (faaa8ac) closed.
final class CompanionsAndReplayTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ui-testing"]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Puts the app on a known screen before a test starts.
    ///
    /// The app does not always launch on the tab bar: an interrupted
    /// recording left behind by an earlier test is restored on the next
    /// launch, so the app can come up on the tracking screen or behind the
    /// "continue this recording?" prompt, and no tab is reachable from
    /// either. `TripTrackUITests` has always done this; this suite did not,
    /// which is why all three of its tests failed with "no way into Я" the
    /// moment the simulator happened to carry an orphaned recording — a
    /// harness gap, not a product defect.
    private func normalizeToHome() {
        let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if recovery.waitForExistence(timeout: 3), recovery.isHittable {
            recovery.tap(); sleep(2)
        }
        let home = app.buttons.matching(identifier: "tab_home").firstMatch
        if !home.waitForExistence(timeout: 5) {
            let back = app.buttons.matching(identifier: "tracking_back").firstMatch
            if back.waitForExistence(timeout: 2), back.isHittable {
                back.tap(); sleep(1)
            }
        }
        if home.waitForExistence(timeout: 3), home.isHittable { home.tap(); sleep(1) }
    }

    /// Profile → История → first trip.
    private func openOwnTrip() {
        normalizeToHome()
        let profile = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "no way into Я")
        profile.tap()
        usleep(3_000_000)

        let row = app.buttons.matching(identifier: "profile_trip_row").firstMatch
        var attempts = 0
        while !row.exists && attempts < 6 {
            app.swipeUp(velocity: .slow)
            usleep(900_000)
            attempts += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "История must list a trip")
        row.tap()
        usleep(4_000_000)
    }

    func test_companions() {
        openOwnTrip()

        let card = app.descendants(matching: .any)
            .matching(identifier: "companions_card").firstMatch
        var attempts = 0
        while !card.exists && attempts < 8 {
            app.swipeUp(velocity: .slow)
            usleep(700_000)
            attempts += 1
        }
        XCTAssertTrue(card.waitForExistence(timeout: 4), "own trip must offer companions")
        snap("60_companions_card")

        // Signed out (no Sign in with Apple in a UI test) + a device-only
        // trip (never uploaded on this simulator) is exactly `canQuery ==
        // false` in `TripDetailView.canQueryCompanions` — the card must
        // show the disabled "publish first" invite, never ask the network
        // a question it can only answer TRIP_NOT_FOUND to.
        let publishHint = app.descendants(matching: .any)
            .matching(identifier: "companions_publish_first").firstMatch
        XCTAssertTrue(
            publishHint.waitForExistence(timeout: 3),
            "a signed-out, unpublished own trip must show the publish-first hint"
        )

        // The defect this test exists to catch: that same trip must never
        // show the red load-failed row instead of (or alongside) the hint.
        let errorRow = app.descendants(matching: .any)
            .matching(identifier: "companions_retry").firstMatch
        XCTAssertFalse(
            errorRow.exists,
            "an unpublished trip's companions card must not show the load-failed row"
        )

        // NOT covered here: the own-trip-with-rows, read-only, stale-cache
        // and genuine-network-error banners, and the invite flow itself —
        // all need either a signed-in account or a trip already on the
        // server, neither of which a UI test can produce.
    }

    func test_access_picker_keeps_edits() {
        openOwnTrip()

        let actions = app.buttons.matching(identifier: "detail_actions").firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 6), "«…» must be on an own trip")
        actions.tap()
        usleep(1_200_000)
        app.buttons.element(boundBy: 0).tap()
        usleep(2_000_000)

        let title = app.textFields.matching(identifier: "edit_title_field").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the edit sheet must be up")
        title.tap()
        title.typeText(" ТЕСТ")
        snap("70_edit_typed")

        // The whole point: opening access must not take the sheet away.
        let access = app.buttons.matching(identifier: "edit_access_row").firstMatch
        XCTAssertTrue(access.waitForExistence(timeout: 3))
        access.tap()
        usleep(1_500_000)
        snap("71_access_picker")

        let priv = app.buttons.matching(identifier: "access_option_private").firstMatch
        XCTAssertTrue(priv.waitForExistence(timeout: 3), "the picker must offer both accesses")
        priv.tap()
        usleep(1_200_000)

        XCTAssertTrue(
            app.buttons.matching(identifier: "edit_done").firstMatch.exists,
            "the edit sheet must still be open, with what was typed still in it"
        )
        snap("72_edit_after_access")
    }

    func test_replay_shows_map() {
        openOwnTrip()

        let replay = app.buttons.matching(identifier: "detail_replay").firstMatch
        guard replay.waitForExistence(timeout: 5) else {
            // No timestamped track on this device — nothing to relive.
            return
        }
        replay.tap()
        usleep(4_000_000)
        snap("90_replay_follow")

        let toggle = app.buttons.matching(identifier: "replay_camera_toggle").firstMatch
        if toggle.waitForExistence(timeout: 3), toggle.isHittable {
            toggle.tap()
            usleep(2_500_000)
            snap("91_replay_overview")
        }
    }
}
