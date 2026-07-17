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
        normalizeToHome()
        let bar = { (id: String) in self.app.buttons.matching(identifier: id).firstMatch }
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

    /// Utility flow (used when seeding data for page verification): if a
    /// recording is active — stop it; otherwise start one via slide-to-start,
    /// let (simulated) GPS accumulate, then stop. Handles the 6.1.0 recovery
    /// prompt if one appears at launch. Locale-independent (ids + coordinates
    /// only); every step guarded so it passes trivially when the record
    /// surface is unavailable.
    func test_zz_toggle_recording() {
        adoptRecoveryIfPrompted()
        let record = app.buttons.matching(identifier: "tab_record").firstMatch
        if record.waitForExistence(timeout: 5), record.isHittable {
            record.tap(); sleep(1)
        }
        let stop = app.buttons.matching(identifier: "tracking_stop").firstMatch
        if stop.waitForExistence(timeout: 3), stop.isHittable {
            stop.tap(); sleep(4); snap("99_after_stop")
            dismissSummaryIfShown()
            return
        }
        // Idle → drag the slide-to-start thumb, record ~45s, then stop.
        pt(0.17, 0.935).press(forDuration: 0.15, thenDragTo: pt(0.90, 0.935))
        sleep(45)
        if stop.waitForExistence(timeout: 5), stop.isHittable {
            stop.tap(); sleep(4); snap("99_after_stop")
            dismissSummaryIfShown()
        }
    }

    /// Starts a recording and leaves it RUNNING (the runner's app-termination
    /// turns it into a force-quit orphan → next launch shows the recovery
    /// prompt). Used to stage Figma 505:119.
    func test_zz_start_recording_only() {
        adoptRecoveryIfPrompted()
        let record = app.buttons.matching(identifier: "tab_record").firstMatch
        if record.waitForExistence(timeout: 5), record.isHittable {
            record.tap(); sleep(1)
        }
        let stop = app.buttons.matching(identifier: "tracking_stop").firstMatch
        guard !(stop.exists && stop.isHittable) else { return } // already recording
        pt(0.17, 0.935).press(forDuration: 0.15, thenDragTo: pt(0.90, 0.935))
        // Long enough that the orphan clears the junk filter (>500m).
        sleep(25)
        snap("90_recording_started")
    }

    /// Walks the recording states for screenshots: recording → (host clears
    /// the location scenario mid-sleep → GPS-lost banner) → pause → resume →
    /// stop → finish sheet.
    func test_zz_recording_states() {
        adoptRecoveryIfPrompted()
        let record = app.buttons.matching(identifier: "tab_record").firstMatch
        if record.waitForExistence(timeout: 5), record.isHittable {
            record.tap(); sleep(1)
        }
        snap("91_idle")
        let stop = app.buttons.matching(identifier: "tracking_stop").firstMatch
        if !(stop.exists && stop.isHittable) {
            pt(0.17, 0.935).press(forDuration: 0.15, thenDragTo: pt(0.90, 0.935))
        }
        sleep(6); snap("92_recording")
        // Host-side `simctl location clear` happens around +8s; by +20s the
        // 10s staleness threshold has fired.
        sleep(16); snap("93_signal_lost")
        let pause = app.buttons.matching(identifier: "tracking_pause").firstMatch
        if pause.exists, pause.isHittable {
            pause.tap(); sleep(2); snap("94_paused")
            pause.tap(); sleep(1)
        }
        if stop.waitForExistence(timeout: 3), stop.isHittable {
            stop.tap(); sleep(4); snap("95_finish_sheet")
            dismissSummaryIfShown()
        }
    }

    /// Brings the app to Home from ANY persisted state: adopts a leftover
    /// recovery prompt, stops an active recording (the chevron is replaced
    /// by the REC pill while recording), walks celebration/summary sheets.
    private func normalizeToHome() {
        adoptRecoveryIfPrompted()
        let home = app.buttons.matching(identifier: "tab_home").firstMatch
        if !home.waitForExistence(timeout: 5) {
            let back = app.buttons.matching(identifier: "tracking_back").firstMatch
            if back.waitForExistence(timeout: 2), back.isHittable {
                back.tap(); sleep(1)
            } else {
                let stop = app.buttons.matching(identifier: "tracking_stop").firstMatch
                if stop.waitForExistence(timeout: 2), stop.isHittable {
                    stop.tap(); sleep(4)
                    dismissSummaryIfShown()
                    let back2 = app.buttons.matching(identifier: "tracking_back").firstMatch
                    if back2.waitForExistence(timeout: 3), back2.isHittable { back2.tap(); sleep(1) }
                }
            }
        }
        if home.waitForExistence(timeout: 3), home.isHittable { home.tap(); sleep(1) }
    }

    private func adoptRecoveryIfPrompted() {
        let cont = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if cont.waitForExistence(timeout: 3), cont.isHittable {
            snap("96_recovery_prompt")
            cont.tap(); sleep(2)
        }
    }

    private func dismissSummaryIfShown() {
        // Badge celebration (fullScreenCover) precedes the summary sheet —
        // step through every earned badge first.
        let celebration = app.buttons.matching(identifier: "celebration_continue").firstMatch
        var hops = 0
        while celebration.waitForExistence(timeout: 2), celebration.isHittable, hops < 6 {
            celebration.tap(); sleep(1); hops += 1
        }
        let done = app.buttons.matching(identifier: "summary_done").firstMatch
        if done.waitForExistence(timeout: 6) {
            snap("95b_finish_summary_top")
            // The finish sheet scrolls; Done can sit below the fold.
            win.swipeUp(); usleep(600_000)
            snap("95c_finish_summary_bottom")
            if done.isHittable { done.tap(); sleep(1) }
        }
    }

    func test_screenshot_tour() {
        normalizeToHome()
        sleep(1); snap("01_feed")

        // Sign-in sheet (6.1.0 Вход) — the guest feed banner opens it.
        let guestBanner = app.buttons.matching(identifier: "guest_signin_banner").firstMatch
        if guestBanner.waitForExistence(timeout: 3), guestBanner.isHittable {
            guestBanner.tap()
            sleep(1); snap("12_signin_sheet")
            win.swipeDown(); sleep(1)
        }

        // Maps tab — 6.1.0 «Моя карта» (ids, locale-independent)
        let mapsTab = app.buttons.matching(identifier: "tab_maps").firstMatch
        if mapsTab.waitForExistence(timeout: 3), mapsTab.isHittable {
            mapsTab.tap(); sleep(3); snap("02_mymap_all")
            let routes = app.buttons.matching(identifier: "map_mode_routes").firstMatch
            if routes.exists { routes.tap(); sleep(1); snap("02_mymap_routes") }
            let territory = app.buttons.matching(identifier: "map_mode_territory").firstMatch
            if territory.exists { territory.tap(); sleep(1); snap("02_mymap_territory") }
            let all = app.buttons.matching(identifier: "map_mode_all").firstMatch
            if all.exists { all.tap(); sleep(1) }
            let expand = app.buttons.matching(identifier: "mymap_expand").firstMatch
            if expand.exists, expand.isHittable {
                expand.tap(); sleep(2); snap("02_mymap_fullscreen")
                let close = app.buttons.matching(identifier: "mymap_fullscreen_close").firstMatch
                if close.waitForExistence(timeout: 3) { close.tap(); sleep(1) }
            }
        }
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
