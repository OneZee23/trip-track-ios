import XCTest

@MainActor
final class HistoryManualFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-rich", "-debug-plus", "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        tap("tab_profile")
        XCTAssertTrue(app.textFields["profile_history_search"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws { app?.terminate() }

    func testSearchCanRecoverFromEmptyResultAndFindTripWithoutOpeningOtherFlows() throws {
        snapshot("history-first-screen")
        let search = app.textFields["profile_history_search"]
        reveal(search)
        search.tap()
        search.typeText("zz-no-trip-with-this-name\n")
        let empty = app.descendants(matching: .any)["profile_history_empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["manual_trip_create"].exists)
        reveal(app.buttons["profile_history_clear_filters"])
        snapshot("history-empty-search")
        tap("profile_history_clear_filters")
        XCTAssertEqual(search.value as? String, search.placeholderValue)
        reveal(search, upwards: false)
        search.tap()
        search.typeText("На работу\n")
        let card = app.historyTripCells.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        var visible: XCUIElement?
        for _ in 0..<8 {
            let tabTop = app.buttons["tab_profile"].firstMatch.frame.minY
            visible = app.historyTripCells.allElementsBoundByIndex.first {
                $0.isHittable && $0.frame.minY > 70 && $0.frame.maxY < tabTop
            }
            if visible != nil { break }
            app.swipeUp(velocity: .slow)
        }
        let result = try XCTUnwrap(visible, "A matching trip must be reachable in the list")
        XCTAssertTrue(result.label.localizedCaseInsensitiveContains("работу"))
        snapshot("history-found-trip")
    }

    func testCalendarFiltersBeforeOfferingManualAddAndSaveActionIsExplicit() {
        let cal = Calendar.current
        let today = Date()
        let dayID = "profile_calendar_day_\(cal.component(.year, from: today))-\(cal.component(.month, from: today))-\(cal.component(.day, from: today))"
        let day = app.buttons[dayID].firstMatch
        reveal(day)
        day.tap()
        XCTAssertTrue(app.buttons["profile_calendar_clear"].waitForExistence(timeout: 5),
                      "A day tap must select a filter, regardless of its kilometre total")
        XCTAssertFalse(app.buttons["manual_trip_create"].exists,
                       "Filtering a day must not silently open another flow")
        let emptyAdd = app.buttons["profile_history_empty_add"].firstMatch
        if emptyAdd.exists {
            reveal(emptyAdd)
            snapshot("history-empty-day")
            emptyAdd.tap()
        } else {
            // Existing simulator data can contain today's routes. The same
            // explicit entry remains available above the calendar in that case.
            let add = app.buttons["profile_history_add"].firstMatch
            reveal(add, upwards: false)
            add.tap()
        }
        let save = app.buttons["manual_trip_create"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertEqual(save.label, "Сохранить поездку")
        XCTAssertFalse(save.isEnabled)
        snapshot("manual-explicit-save")
        tap("manual_trip_cancel")
        XCTAssertTrue(day.exists, "Closing manual entry returns to the selected history day")
    }

    private func tap(_ id: String) {
        let e = app.buttons[id].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 20), id)
        e.tap()
    }
    private func reveal(_ e: XCUIElement, upwards: Bool = true) {
        for _ in 0..<9 {
            let tabTop = app.buttons["tab_profile"].firstMatch.frame.minY
            if e.exists && e.isHittable && e.frame.maxY < tabTop && e.frame.minY > 70 { return }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(e.exists && e.isHittable, e.identifier)
    }
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
