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
        // Value must be the XML-plist form: "YES" stays a String in the
        // argument domain and @AppStorage(Bool)'s `as? Bool` cast fails
        // (fresh installs then land on onboarding); "<true/>" parses to a
        // real Bool.
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>"]
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

    /// Walks into the first own trip's detail poster + the cinema replay and
    /// snaps them (6.1.0 Деталка verification). Locale-tolerant, guarded.
    func test_zz_trip_detail_shots() {
        normalizeToHome()
        // Own trips now live on the Я tab (История section) — the feed's
        // «Мои» segment was retired for «Подписки».
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 5), me.isHittable { me.tap(); sleep(2) }
        let anyCard = app.descendants(matching: .any).matching(identifier: "profile_trip_row").firstMatch
        if !anyCard.waitForExistence(timeout: 3) {
            // История sits below the hero/moments — scroll until a row shows.
            for _ in 0..<4 {
                win.swipeUp(); usleep(600_000)
                if anyCard.exists { break }
            }
        }
        print("DETSHOT rows=\(app.descendants(matching: .any).matching(identifier: "profile_trip_row").count)")
        let mapExpand = app.buttons.matching(identifier: "detail_map_expand").firstMatch
        if anyCard.waitForExistence(timeout: 3) {
            // Tap near the row's top — a partially covered row's geometric
            // center can sit under the tab pill, where tap() silently no-ops.
            anyCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        }
        if !mapExpand.waitForExistence(timeout: 4) {
            print("DETSHOT card tap did not open detail, trying title text")
            let title = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS ',' AND label CONTAINS ':'")
            ).firstMatch
            if title.waitForExistence(timeout: 2) { title.tap() }
            _ = mapExpand.waitForExistence(timeout: 4)
        }
        sleep(2)
        snap("80_detail_top")
        win.swipeUp(); usleep(700_000); snap("81_detail_mid")
        win.swipeUp(); usleep(700_000); snap("82_detail_lower")
        win.swipeUp(); usleep(700_000); snap("83_detail_bottom")
        // Back to top, then into the fullscreen map.
        win.swipeDown(); win.swipeDown(); win.swipeDown(); usleep(700_000)
        if mapExpand.waitForExistence(timeout: 3), mapExpand.isHittable {
            mapExpand.tap()
            sleep(3); snap("84_fullscreen_map")
            pt(0.07, 0.05).tap(); sleep(1) // close circle top-left
        }
        pt(0.07, 0.05).tap(); sleep(1) // detail back circle
    }

    /// Walks the redesigned Garage: list → add form → vehicle detail →
    /// auto-record settings. Locale-tolerant, guarded (6.1.0 Гараж).
    func test_zz_garage_shots() {
        normalizeToHome()
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 3) { me.tap(); sleep(2) }
        // The garage row sits below the profile fold — scroll until visible.
        for _ in 0..<4 {
            if tap("Гараж", timeout: 1) || tap("Garage", timeout: 1) { break }
            win.swipeUp(); usleep(600_000)
        }
        sleep(2); snap("100_garage_list")

        let add = app.buttons.matching(identifier: "garage_add").firstMatch
        if add.waitForExistence(timeout: 2), add.isHittable {
            add.tap(); sleep(2); snap("101_add_form")
            let close = app.buttons.matching(identifier: "vehicle_form_close").firstMatch
            if close.waitForExistence(timeout: 2) { close.tap() } else { win.swipeDown() }
            sleep(1)
        }

        let card = app.buttons.matching(identifier: "garage_card").firstMatch
        if card.waitForExistence(timeout: 2), card.isHittable {
            card.tap(); sleep(2); snap("102_vehicle_detail")
            win.swipeUp(); usleep(700_000); snap("103_detail_lower")
            win.swipeDown(); usleep(700_000)
            let ar = app.buttons.matching(identifier: "vehicle_autorecord_row").firstMatch
            if ar.waitForExistence(timeout: 2) {
                if !ar.isHittable { win.swipeUp(); usleep(700_000) }
                ar.tap(); sleep(2); snap("104_autorecord")
                win.swipeDown(); sleep(1) // close the settings sheet
            }
        }
    }

    /// Walks the redesigned Home feed: both segments, bell (guest prompt),
    /// search → Discover, long-press card (guest → sign-in). 6.1.0 Лента.
    func test_zz_feed_shots() {
        normalizeToHome()
        sleep(3); snap("110_feed_all")
        // Scrolled state — cards must flow UNDER the tab bar pill and reach
        // the physical bottom edge (iOS 26 pager used to clip them at the
        // safe-area line, leaving a dark band below).
        win.swipeUp(); usleep(900_000); snap("110b_feed_all_scrolled")
        win.swipeDown(); usleep(700_000)
        let following = app.buttons.matching(identifier: "feed_segment_following").firstMatch
        if following.waitForExistence(timeout: 2) { following.tap(); sleep(2); snap("111_feed_following") }
        let allSeg = app.buttons.matching(identifier: "feed_segment_all").firstMatch
        if allSeg.waitForExistence(timeout: 2) { allSeg.tap(); sleep(2) }
        let bell = app.buttons.matching(identifier: "feed_bell").firstMatch
        if bell.waitForExistence(timeout: 2) {
            bell.tap(); sleep(2); snap("112_bell_guest")
            win.swipeDown(); sleep(1)
        }
        let search = app.buttons.matching(identifier: "feed_search").firstMatch
        if search.waitForExistence(timeout: 2) {
            search.tap(); sleep(2); snap("113_discover")
            win.swipeDown(); sleep(1)
        }
        let card = app.descendants(matching: .any)
            .matching(identifier: "social_trip_card").firstMatch
        if card.waitForExistence(timeout: 3) {
            card.press(forDuration: 0.8); sleep(1); snap("114_longpress")
            win.swipeDown(); sleep(1)
            pt(0.5, 0.1).tap(); sleep(1)
        }
    }

    /// Walks the guest-reachable Account-page surface: the logs journal
    /// (Frame 3). CloudSync/SyncStatus need sign-in — device-verify TODO.
    func test_zz_logs_shots() {
        normalizeToHome()
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 3) { me.tap(); sleep(2) }
        for _ in 0..<5 {
            if tap("Отправить логи", timeout: 1) || tap("Send debug logs", timeout: 1) { break }
            win.swipeUp(); usleep(600_000)
        }
        sleep(3); snap("120_logs_journal")
        win.swipeUp(); usleep(700_000); snap("121_logs_lower")
    }

    /// Groups teaser (6.1.0 Группы): tab → shot → notify CTA → done-state.
    func test_zz_groups_shots() {
        normalizeToHome()
        let groups = app.buttons.matching(identifier: "tab_groups").firstMatch
        if groups.waitForExistence(timeout: 3) { groups.tap(); sleep(2) }
        snap("130_groups_teaser")
        let cta = app.buttons.matching(identifier: "groups_notify_cta").firstMatch
        if cta.waitForExistence(timeout: 2), cta.isHittable {
            cta.tap(); sleep(1); snap("131_groups_notified")
        }
    }

    /// Walks the redesigned Me tab (6.1.0 Профиль·Я): hero, settings
    /// sheet, stats push, wrapped story. Guest-tolerant, guarded.
    func test_zz_me_shots() {
        normalizeToHome()
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 3) { me.tap(); sleep(2) }
        snap("140_me_top")
        win.swipeUp(); usleep(700_000); snap("141_me_lower")
        win.swipeDown(); usleep(700_000)

        let gear = app.buttons.matching(identifier: "profile_gear").firstMatch
        if gear.waitForExistence(timeout: 2), gear.isHittable {
            gear.tap(); sleep(2); snap("142_settings_sheet")
            win.swipeDown(); sleep(1)
        }

        let strip = app.descendants(matching: .any)
            .matching(identifier: "profile_stats_strip").firstMatch
        if strip.waitForExistence(timeout: 2), strip.isHittable {
            strip.tap(); sleep(2); snap("143_stats_screen")
            win.swipeUp(); usleep(700_000); snap("144_stats_lower")
            let back = app.buttons.matching(identifier: "stats_back").firstMatch
            if back.waitForExistence(timeout: 2) { back.tap() } else { pt(0.07, 0.07).tap() }
            sleep(1)
        }

        let wrapped = app.buttons.matching(identifier: "profile_wrapped_cta").firstMatch
        if wrapped.waitForExistence(timeout: 2), wrapped.isHittable {
            wrapped.tap(); sleep(2); snap("145_wrapped_story")
            let close = app.buttons.matching(identifier: "wrapped_close").firstMatch
            if close.waitForExistence(timeout: 2) { close.tap() } else { pt(0.93, 0.07).tap() }
            sleep(1)
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
