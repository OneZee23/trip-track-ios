import XCTest

/// The HTML atlas flow, exercised through real controls and seeded trips.
/// Run this class alone; it does not rely on live Apple map tile delivery.
final class AtlasDesignTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ id: String, timeout: TimeInterval = 10) {
        let button = app.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), id)
        XCTAssertTrue(button.isHittable, "\(id) must be reachable")
        button.tap()
    }

    private func openAtlas() {
        tap("tab_maps", timeout: 25)
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["atlas_region_RU-KDA"].waitForExistence(timeout: 20))
    }

    private func openSearch() {
        tap("mymap_grabber")
        XCTAssertTrue(app.otherElements["mymap_region_list"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["atlas_search"].exists, "first stop is the half sheet")
        shot("atlas_02_half")
        tap("mymap_grabber")
        XCTAssertTrue(app.textFields["atlas_search"].waitForExistence(timeout: 10))
    }

    private func applyPeriod(_ id: String) {
        tap("atlas_period")
        XCTAssertTrue(app.otherElements["atlas_period_sheet"].waitForExistence(timeout: 10))
        if app.buttons["atlas_period_back"].exists { tap("atlas_period_back") }
        tap("atlas_period_\(id)")
        tap("atlas_period_apply")
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 15))
    }

    func testAtlasOverviewSearchPeriodAndNightStyle() {
        openAtlas()
        // The preference persists between launches; establish the starting
        // appearance through its real UI without clearing the trip store.
        tap("atlas_appearance")
        tap("atlas_style_fog")
        tap("atlas_controls_close")
        shot("atlas_01_summary_light")

        openSearch()
        let search = app.textFields["atlas_search"]
        search.tap()
        search.typeText("кРаСнОдАр")
        let region = app.buttons["atlas_region_RU-KDA"]
        XCTAssertTrue(region.waitForExistence(timeout: 10), "search ignores letter case")
        shot("atlas_03_search_opened")
        region.tap()
        XCTAssertTrue(app.otherElements["mymap_region_card"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab_maps"].isHittable, "selected cards leave navigation reachable")
        shot("atlas_04_region")
        tap("mymap_close")
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 10))

        openSearch()
        search.tap()
        search.typeText("новоси")
        let unopened = app.buttons["atlas_region_RU-NVS"]
        XCTAssertTrue(unopened.waitForExistence(timeout: 10), "search includes the bundled unopened region")
        XCTAssertTrue(unopened.label.contains("Ещё не открыто"))
        shot("atlas_05_search_unopened")
        unopened.tap()
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["mymap_region_card"].exists,
                       "an unopened region frames the map without inventing visited statistics")

        applyPeriod("last_30_days")
        let periodUpdated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "30"), object: app.buttons["atlas_period"])
        XCTAssertEqual(XCTWaiter.wait(for: [periodUpdated], timeout: 15), .completed)
        XCTAssertTrue(app.buttons["atlas_region_RU-KDA"].waitForExistence(timeout: 15))
        shot("atlas_06_last_30_days")

        tap("atlas_period")
        tap("atlas_period_custom")
        let calendar = app.datePickers["atlas_period_calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        // Keep the day grid above the sticky Apply footer on small screens;
        // UIKit can report a clipped graphical picker as hittable.
        if calendar.frame.maxY > app.buttons["atlas_period_apply"].frame.minY {
            let scroller = app.otherElements["atlas_period_sheet"].scrollViews.firstMatch
            XCTAssertTrue(scroller.exists)
            scroller.swipeUp()
        }
        selectTodayAsStart(in: calendar)
        shot("atlas_07_custom_calendar")
        tap("atlas_period_apply")
        XCTAssertTrue(app.staticTexts["В этом периоде поездок нет"].waitForExistence(timeout: 20),
                       "today has no trips in DebugMapSeed; the map must show the filtered empty state")
        shot("atlas_07_custom_empty")

        applyPeriod("all_time")
        XCTAssertTrue(app.buttons["atlas_region_RU-KDA"].waitForExistence(timeout: 15),
                       "all time restores the cached complete atlas")
        tap("atlas_appearance")
        tap("atlas_style_night")
        XCTAssertTrue(app.buttons["atlas_style_night"].isSelected)
        tap("atlas_controls_close")
        shot("atlas_08_night")

        app.terminate()
        app.launch()
        openAtlas()
        tap("atlas_appearance")
        XCTAssertTrue(app.buttons["atlas_style_night"].isSelected,
                       "the map appearance survives rebuilding the atlas screen")
    }

    private func selectTodayAsStart(in calendar: XCUIElement) {
        let today = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        let fullDate = formatter.string(from: today)
        let todayButton = calendar.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", fullDate)).firstMatch
        // UIDatePicker's displayed month is an implementation detail. Match
        // the full date first, so day 25 in the previous month cannot win.
        if !todayButton.exists {
            let next = calendar.buttons["DatePicker.NextMonth"]
            XCTAssertTrue(next.waitForExistence(timeout: 5), "calendar next-month control")
            XCTAssertTrue(next.isHittable)
            XCTAssertLessThan(next.frame.maxY, app.buttons["atlas_period_apply"].frame.minY,
                              "the month control must be above the sticky Apply button")
            next.tap()
        }
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5), "today in the custom calendar")
        XCTAssertTrue(todayButton.isHittable)
        XCTAssertLessThan(todayButton.frame.maxY, app.buttons["atlas_period_apply"].frame.minY)
        todayButton.tap()
    }
}
