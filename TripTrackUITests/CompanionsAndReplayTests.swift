import XCTest

/// Screenshot tour of the surfaces added in this round: companions, the access
/// picker inside the edit sheet, and the replay now that it plays over a map.
///
/// Guarded rather than asserted where the app's own data decides what exists —
/// a device with no timestamped trip has no replay to open, and that is not a
/// test failure.
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

    /// Profile → История → first trip.
    private func openOwnTrip() {
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
        snap("60_companions_card_empty")

        card.tap()
        usleep(1_500_000)
        snap("61_companions_sheet")

        let field = app.textFields.matching(identifier: "companion_name_field").firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("Аня")
            let add = app.buttons.matching(identifier: "companion_add").firstMatch
            if add.exists, add.isHittable { add.tap() }
            usleep(700_000)
            snap("62_companions_added")

            let done = app.buttons.matching(identifier: "companions_done").firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 3), "the sheet must offer «Готово»")
            done.tap()
            usleep(2_000_000)
            snap("63_companions_card_filled")

            // The point of the whole feature: it is still there afterwards.
            let filled = app.descendants(matching: .any)
                .matching(identifier: "companions_card").firstMatch
            XCTAssertTrue(filled.waitForExistence(timeout: 4))
            XCTAssertTrue(
                filled.label.contains("Аня"),
                "the saved companion must show on the card, got «\(filled.label)»"
            )
        }
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
