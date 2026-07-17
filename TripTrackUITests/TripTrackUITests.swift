import XCTest

/// Autonomous screenshot tour of the v0.5.7 surfaces. Value = the captured
/// screenshots (extracted from the .xcresult), eyeballed afterward. All steps
/// guarded; the tour never asserts so it can't hard-fail. ORDER: tab-bar screens
/// + Record (full-screen, hides tab bar) first, sheet-based Profile/Stats last.
final class TripTrackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // NSArgumentDomain override — read-only flag, safe to pin. Do NOT pin
        // selectedTabV2 the same way: the argument domain shadows reads, so
        // @AppStorage writes from tab taps would be invisible and the app
        // would appear frozen on the pinned tab.
        app.launchArguments += ["-hasCompletedOnboarding", "YES"]
        app.launch()
    }

    private func snap(_ name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name; att.lifetime = .keepAlways; add(att)
    }
    private var win: XCUIElement { app.windows.firstMatch }
    private func pt(_ dx: Double, _ dy: Double) -> XCUICoordinate {
        win.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
    }
    @discardableResult
    private func tap(_ label: String, timeout: TimeInterval = 4) -> Bool {
        let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if b.waitForExistence(timeout: timeout), b.isHittable { b.tap(); usleep(900_000); return true }
        return false
    }

    /// Asserting smoke test for the 6.1.0 five-tab navigation: every tab is
    /// reachable by tapping its (language-independent) accessibility id, the
    /// bar hides on the Record tab, and the back chevron restores it.
    func test_tab_navigation_smoke() {
        let bar = { (id: String) in self.app.buttons.matching(identifier: id).firstMatch }
        // Normalize: the app restores the last persisted tab. If that was
        // Record (bar hidden), leave it via the tracking back chevron.
        if !bar("tab_maps").waitForExistence(timeout: 8) {
            bar("tracking_back").tap()
        }
        XCTAssertTrue(bar("tab_maps").waitForExistence(timeout: 4), "tab bar should be visible after normalization")

        for id in ["tab_maps", "tab_groups", "tab_profile", "tab_home"] {
            bar(id).tap()
            usleep(600_000)
            XCTAssertTrue(bar("tab_record").exists, "tab bar should stay visible after switching to \(id)")
        }

        // Record is full-screen: the bar must disappear…
        bar("tab_record").tap()
        sleep(1)
        XCTAssertFalse(bar("tab_home").exists, "tab bar should hide on the Record tab")
        // …and the back chevron returns to Home with the bar restored.
        XCTAssertTrue(bar("tracking_back").waitForExistence(timeout: 4), "tracking back chevron should exist")
        bar("tracking_back").tap()
        XCTAssertTrue(bar("tab_home").waitForExistence(timeout: 4), "tab bar should be restored after leaving Record")
    }

    func test_screenshot_tour() {
        sleep(2); snap("01_feed")

        // Sign-in sheet (6.1.0 Вход) — the guest feed banner opens it.
        let guestBanner = app.buttons.matching(identifier: "guest_signin_banner").firstMatch
        if guestBanner.waitForExistence(timeout: 3), guestBanner.isHittable {
            guestBanner.tap()
            sleep(1); snap("12_signin_sheet")
            win.swipeDown(); sleep(1)
        }

        // Maps tab (6.1.0: Места → Карта)
        if tap("Карта") { sleep(1); snap("02_places") }
        // Back to feed, Поездки segment (#7 Мои→Поездки)
        if tap("Лента") { sleep(1) }
        if tap("Поездки") { sleep(1); snap("03_feed_trips") }

        // Record tab (full-screen). Slide-to-start fix + recording overlay/vehicle pill.
        if tap("Запись") {
            sleep(1); snap("04_record_idle_slidefix")
            // Drag the slide-to-start thumb L→R along the slider row (very bottom).
            pt(0.17, 0.935).press(forDuration: 0.15, thenDragTo: pt(0.90, 0.935))
            sleep(3); snap("05_recording_overlay")     // expect overlay + vehicle pill
            sleep(4); snap("06_recording_later")
            // Exit Record via the top-left back chevron.
            pt(0.07, 0.09).tap(); sleep(1); snap("07_after_exit_record")
        }

        // Profile sheet (top-left avatar on feed) → settings + Stats.
        pt(0.07, 0.09).tap(); sleep(1); snap("08_profile")
        win.swipeUp(); usleep(500_000); snap("09_profile_settings")   // avg-speed card (#C)
        win.swipeUp(); usleep(500_000); snap("10_profile_more")
        if tap("Статистика") { sleep(1); win.swipeUp(); usleep(500_000); snap("11_stats_calendar") } // (#F)
    }
}
