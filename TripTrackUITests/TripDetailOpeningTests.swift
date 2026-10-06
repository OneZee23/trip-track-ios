import XCTest

/// Run on a simulator with dark system appearance. The app deliberately
/// chooses light mode, matching the reported dark-skeleton/light-detail
/// flash. XCUI waits for quiescence: these assertions cover the first
/// accessible frame, usability and reopening; the native push itself is
/// measured separately from a simctl recording of this same scenario.
@MainActor
final class TripDetailOpeningTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-hasCompletedOnboarding", "<true/>",
            "-seed-map-demo", "-appLanguage", "ru",
            "-appThemeMode", "light", "-profileHistoryMode", "list"
        ]
        app.launch()
    }

    override func tearDownWithError() throws { app?.terminate() }

    func testOpeningFromHistoryKeepsReadableLightContentAndRouteWhenTilesAreSlow() throws {
        tap("tab_profile", timeout: 20)
        let search = app.textFields["profile_history_search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        revealInHistory(search)
        search.tap()
        search.typeText("На работу\n")

        var firstTitle: String?
        for visit in 1...2 {
            let row = try visibleHistoryTrip()
            snapshot("detail-opening-history-\(visit)")
            row.tap()

            let title = element("detail_title")
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            XCTAssertFalse(title.label.isEmpty)
            if let firstTitle {
                XCTAssertEqual(title.label, firstTitle, "Reopening must show the same selected trip")
            } else {
                firstTitle = title.label
            }
            XCTAssertTrue(element("detail_content").exists)
            XCTAssertTrue(element("detail_stats").exists)
            XCTAssertTrue(app.buttons["detail_back"].firstMatch.isHittable,
                          "The screen must stay escapable while MapKit loads")
            XCTAssertTrue(app.buttons["detail_map_expand"].firstMatch.isHittable,
                          "A slow basemap must not make the saved trip unusable")

            let firstFrame = app.screenshot()
            attach(firstFrame, name: "detail-opening-first-accessible-\(visit)")
            assertLightContent(firstFrame)
            assertVisibleRoute(firstFrame)

            // No wait for Apple's network. Both a route preview and a ready
            // live map must support the existing expansion/return path.
            tap("detail_map_expand")
            tap("fullscreen_map_close")
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            let returnedFrame = app.screenshot()
            attach(returnedFrame, name: "detail-opening-returned-\(visit)")
            assertLightContent(returnedFrame)
            assertVisibleRoute(returnedFrame)

            tap("detail_back")
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            XCTAssertTrue((search.value as? String)?.contains("На работу") == true,
                          "Back must preserve the history filter")
        }
    }

    private func visibleHistoryTrip() throws -> XCUIElement {
        for _ in 0..<10 {
            let tabTop = app.buttons["tab_profile"].firstMatch.frame.minY
            if let trip = app.historyTripCells.allElementsBoundByIndex.first(where: {
                $0.isHittable && $0.frame.minY > 70 && $0.frame.maxY < tabTop
            }) { return trip }
            app.swipeUp(velocity: .slow)
        }
        XCTFail("The filtered seeded trip must be reachable")
        return try XCTUnwrap(app.historyTripCells.allElementsBoundByIndex.first)
    }

    private func revealInHistory(_ target: XCUIElement) {
        for _ in 0..<8 {
            let tabTop = app.buttons["tab_profile"].firstMatch.frame.minY
            if target.exists, target.isHittable,
               target.frame.minY > 70, target.frame.maxY < tabTop { return }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(target.isHittable)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ id: String, timeout: TimeInterval = 10) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), id)
        button.tap()
    }

    private func assertLightContent(_ screenshot: XCUIScreenshot,
                                    file: StaticString = #filePath, line: UInt = #line) {
        // Below the hero, away from the status/navigation bars. A light
        // background with dark text stays well above this threshold; the
        // reported charcoal skeleton is below 0.15.
        let lums = HeroMapProbe.grid(of: screenshot, from: 0.56, to: 0.82)
        XCTAssertFalse(lums.isEmpty, file: file, line: line)
        let average = lums.reduce(0, +) / Double(max(1, lums.count))
        XCTAssertGreaterThan(average, 0.75,
                             "Detail ignored the explicitly chosen light theme", file: file, line: line)
    }

    private func assertVisibleRoute(_ screenshot: XCUIScreenshot,
                                   file: StaticString = #filePath, line: UInt = #line) {
        // A loading spinner or flat placeholder is not a saved route.
        // This works with both the offline route drawing and Apple's map;
        // it deliberately does not require network tiles to arrive.
        // A 4 pt gray dash gets averaged away in the 16×8 grid used to
        // compare whole basemaps. Keep enough resolution to see the route,
        // including a trip whose sparse fixture has been gap-filled.
        let routeGrid = HeroMapProbe.grid(of: screenshot, from: 0.12, to: 0.38,
                                          columns: 128, rows: 64)
        XCTAssertGreaterThan(HeroMapProbe.contrast(routeGrid),
                             HeroMapProbe.flat,
                             "The hero lost the saved route while opening or returning",
                             file: file, line: line)
    }

    private func snapshot(_ name: String) { attach(app.screenshot(), name: name) }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
