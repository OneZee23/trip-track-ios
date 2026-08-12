import XCTest

/// «Редактировать поездку» — the sheet that replaced four scattered inline
/// editors. Two things about it are only visible in a picture: whether the
/// title survives between the two buttons, and whether the sheet stops where
/// its content does.
final class TripEditSheetTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The charts answer a finger: touch anywhere along one and the sample
    /// under it is marked and read out («186 м · 14:05 / 212-й км»).
    func test_chart_scrub() {
        openFirstTrip()

        // Scroll to «Профиль высоты» — it sits below the stat grid.
        for _ in 0..<3 {
            app.swipeUp(velocity: .slow)
            usleep(1_200_000)
        }
        snap("03_charts_before")

        // Aim at the chart itself, not at a screen coordinate that a different
        // scroll position would put somewhere else entirely.
        let chart = app.descendants(matching: .any)
            .matching(identifier: "speed_chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "the speed chart must be on screen")

        // A tap reads out the point under it.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.55)).tap()
        usleep(1_000_000)
        snap("04_chart_scrubbed")

        // And a sideways drag moves the readout along the trip.
        // Hold first — a swipe that merely crosses the chart must scroll the
        // page, so the readout only follows a finger that stayed put.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.55))
            .press(forDuration: 0.6,
                   thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55)))
        usleep(1_000_000)
        snap("05_chart_dragged")
    }

    /// «Выберите фото» — the app's own grid, with the pick order on the badges.
    func test_photo_picker() {
        openFirstTrip()

        for _ in 0..<4 {
            app.swipeUp(velocity: .slow)
            usleep(1_200_000)
        }

        // The «+» on the photos section header.
        let plus = app.buttons.matching(identifier: "detail_add_photo").firstMatch
        guard plus.waitForExistence(timeout: 5) else {
            snap("05_no_photo_button")
            XCTFail("the photos section must offer a way to add one")
            return
        }
        plus.tap()
        usleep(2_000_000)

        // The library prompt belongs to Springboard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow Full Access", "Разрешить доступ ко всем фото", "Allow Access to All Photos"] {
            let button = springboard.buttons[label].firstMatch
            if button.waitForExistence(timeout: 2) { button.tap(); break }
        }
        usleep(2_500_000)
        snap("06_photo_picker")

        // Pick two, in order, and check the badges say so.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35)).tap()
        usleep(600_000)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        usleep(900_000)
        snap("07_photo_picker_selected")

        XCTAssertTrue(
            app.buttons.matching(identifier: "photo_picker_done").firstMatch.exists,
            "the picker must offer «Готово»"
        )
    }

    private func openFirstTrip() {
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

    func test_edit_sheet() {
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

        let actions = app.buttons.matching(identifier: "detail_actions").firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 6), "the «…» menu must be on an own trip")
        actions.tap()
        usleep(1_200_000)
        snap("01_owner_menu")

        // «Редактировать» is the first item in the popover.
        let edit = app.buttons.element(boundBy: 0)
        if edit.exists { edit.tap() }
        usleep(2_000_000)
        snap("02_edit_sheet")

        XCTAssertTrue(
            app.buttons.matching(identifier: "edit_done").firstMatch.waitForExistence(timeout: 5),
            "the edit sheet must be up"
        )
    }
}
