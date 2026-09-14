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

    /// Asserting smoke test for the 0.6.0 five-tab navigation: every tab is
    /// reachable by tapping its (language-independent) accessibility id, the
    /// bar hides on the Record tab, and the back chevron restores it.
    func test_tab_navigation_smoke() {
        normalizeToHome()
        let bar = { (id: String) in self.app.buttons.matching(identifier: id).firstMatch }
        XCTAssertTrue(bar("tab_maps").waitForExistence(timeout: 4), "tab bar should be visible after normalization")

        for id in ["tab_maps", "tab_places", "tab_profile", "tab_home"] {
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
    /// let (simulated) GPS accumulate, then stop. Handles the 0.6.0 recovery
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
    /// snaps them (0.6.0 Деталка verification). Locale-tolerant, guarded.
    func test_zz_trip_detail_shots() {
        normalizeToHome()
        // Own trips now live on the Я tab (История section) — the feed's
        // «Мои» segment was retired for «Подписки».
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 5), me.isHittable { me.tap(); sleep(2) }
        let anyCard = app.anyHistoryTripCells.firstMatch
        if !anyCard.waitForExistence(timeout: 3) {
            // История sits below the hero/moments — scroll until a row shows.
            for _ in 0..<4 {
                win.swipeUp(); usleep(600_000)
                if anyCard.exists { break }
            }
        }
        print("DETSHOT rows=\(app.anyHistoryTripCells.count)")
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
    /// auto-record settings. Locale-tolerant, guarded (0.6.0 Гараж).
    func test_zz_garage_shots() {
        normalizeToHome()
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 3) { me.tap(); sleep(2) }
        // The Гараж section sits below the profile fold — scroll until its
        // «Весь транспорт ›» header control is reachable. Matched by identifier,
        // not by label: «Гараж» is now a section TITLE on this page (a static
        // text), and the label match used to walk straight past it and shoot
        // the profile instead of the garage.
        let garage = app.buttons.matching(identifier: "settings_garage").firstMatch
        for _ in 0..<5 {
            if garage.exists, garage.isHittable { garage.tap(); break }
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
    /// search → Discover, long-press card (guest → sign-in). 0.6.0 Лента.
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
        // Behind the gear, not on the Я page: the journal is a row of the
        // «Поддержка» card inside the settings sheet.
        let gear = app.buttons.matching(identifier: "profile_gear").firstMatch
        if gear.waitForExistence(timeout: 4), gear.isHittable { gear.tap(); sleep(1) }
        let logs = app.buttons.matching(identifier: "settings_send_logs").firstMatch
        for _ in 0..<5 {
            if logs.exists, logs.isHittable { logs.tap(); break }
            win.swipeUp(); usleep(600_000)
        }
        sleep(3); snap("120_logs_journal")
        win.swipeUp(); usleep(700_000); snap("121_logs_lower")
    }

    /// Places tab shots — list with a demo place, its detail screen, the
    /// «…» menu — then the clubs teaser reached via profile (0.6.8). The
    /// demo place only appears after `DebugMapSeed` runs, and that only
    /// happens at process launch, so the app is relaunched here instead of
    /// reused from `setUpWithError` — same trick as
    /// `MyMapTourTests.mapLuminanceAtStreetZoom`.
    func test_zz_places_shots() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-places-demo"]
        app.launch()
        normalizeToHome()

        let places = app.buttons.matching(identifier: "tab_places").firstMatch
        if places.waitForExistence(timeout: 3) { places.tap(); sleep(2) }
        // `places_map` sits on the bare `MKMapView` inside `PlacesMapView` (a
        // `UIViewRepresentable`) — XCUITest can report that as
        // `XCUIElementTypeMap` rather than `.other`, or hoist the identifier
        // onto a SwiftUI wrapper. `.any` finds it either way — same fallback
        // already used below for `social_trip_card`/`profile_stats_strip`.
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "places_map").firstMatch.waitForExistence(timeout: 5),
            "places_map не найдена — демо-место не отрисовалось"
        )
        snap("130_places_list")

        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place_card_'")).firstMatch
        if card.waitForExistence(timeout: 3), card.isHittable {
            card.tap(); sleep(2); snap("131_place_detail")
            let menu = app.buttons.matching(identifier: "place_menu").firstMatch
            if menu.waitForExistence(timeout: 2), menu.isHittable {
                menu.tap(); sleep(1); snap("132_place_menu")
                pt(0.5, 0.85).tap(); sleep(1) // закрыть поповер тапом мимо
            }
            // Экран места прячет таб-бар (`hideAppTabBar`) — назад раньше,
            // чем идти в профиль за клубами. `NavBackButton` несёт только
            // `accessibilityLabel` (локализован под язык устройства — на
            // BA1BECF1 это оказался pt-BR, «Voltar»), но без явного
            // `accessibilityIdentifier` XCUITest сам подставляет в него имя
            // SF Symbol — «chevron.backward», не зависящее от языка.
            // Координата верхнего левого угла тут не подошла: `CustomNavBar`
            // кладёт кружок в {{20, 69}, {40, 40}}, а не в те ~5% высоты, что
            // работают у `TripDetailView`.
            let back = app.buttons.matching(identifier: "chevron.backward").firstMatch
            if back.waitForExistence(timeout: 2), back.isHittable { back.tap() }
            sleep(1)
        }

        // Клубы переехали из вкладки в профиль (0.6.8): строка под гаражом.
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 3) { me.tap(); sleep(2) }
        let row = app.buttons.matching(identifier: "profile_clubs_row").firstMatch
        // `.exists`, and even `.isHittable`, are not enough: with the demo
        // seed (46 trips — a fixed height for «Достижения»/«Гараж» above
        // «Клубы») the row's accessibility frame lands almost entirely
        // BEHIND the floating tab bar right after the tab switch. It still
        // reports `exists`/`isHittable == true` (SwiftUI's accessibility
        // tree doesn't model the overlay's occlusion), but the synthesized
        // tap at its centre lands on the tab bar instead of the row —
        // measured: row centre (196, 794) sits inside the pill's own y-range
        // (767–815). Scroll until the row's frame genuinely clears the tab
        // bar's top edge before trusting either flag.
        let tabBarTop = app.buttons.matching(identifier: "tab_profile").firstMatch.frame.minY
        for _ in 0..<5 {
            if row.exists, row.frame.maxY < tabBarTop, row.isHittable { break }
            win.swipeUp(); usleep(700_000)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 2), "profile_clubs_row не найдена — потерян вход в клубы из профиля")
        if row.waitForExistence(timeout: 2), row.isHittable {
            row.tap(); sleep(2); snap("133_clubs_teaser")
            let cta = app.buttons.matching(identifier: "groups_notify_cta").firstMatch
            if cta.waitForExistence(timeout: 2), cta.isHittable {
                cta.tap(); sleep(1); snap("134_clubs_notified")
            }
        }
    }

    /// Публичное путешествие (0.6.8), гостем: своя карточка в «Мои», экран
    /// путешествия, поповер «…», лист публикации/вход. Ничего не публикует —
    /// гость на «Опубликовать путешествие» получает `SignInPromptSheet`, а не
    /// сеть (`JourneyDetailView.requestPublish`), и тест закрывает его без
    /// входа.
    func test_zz_journey_shots() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-journey-demo"]
        app.launch()
        normalizeToHome()

        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 3) { me.tap(); sleep(2) }

        // Демо-путешествие сеется из НАЗВАННЫХ поездок («Краснодар →
        // Ростов-на-Дону» + «По Ростову», `DebugMapSeed.seedJourneyDemo») —
        // его дата в «Истории» это дата самого свежего плеча («По Ростову»,
        // ~12 дней назад), а не «только что», так что карточка стоит позади
        // примерно десятка более новых городских поездок. Бюджет свайпов —
        // с запасом под это расстояние по прокрутке.
        let card = app.buttons.matching(identifier: "profile_journey_card").firstMatch
        var found = false
        for _ in 0..<30 {
            if card.exists, card.isHittable { found = true; break }
            win.swipeUp(); usleep(400_000)
        }
        XCTAssertTrue(found, "profile_journey_card не найдена — демо-путешествие не отрисовалось в «Мои»")
        guard found else { return }

        card.tap(); sleep(2); snap("140_journey_own")

        let actions = app.buttons.matching(identifier: "detail_actions").firstMatch
        guard actions.waitForExistence(timeout: 4), actions.isHittable else { return }
        actions.tap(); sleep(1); snap("141_journey_actions")

        // Жёсткая проверка ДО тапа: пункт публикации обязан стоять в
        // поповере, иначе следующий тап промахивается мимо уже закрытого
        // экрана и тест молча снимает не тот кадр.
        XCTAssertTrue(app.buttons["journey_action_publish"].waitForExistence(timeout: 5),
                      "journey_action_publish не найдена в поповере «…»")
        app.buttons["journey_action_publish"].tap()

        // Поповер гасит себя первым и только спустя ~260мс зовёт действие
        // (см. `present(_:)` в `JourneyDetailView.actions`) — ждём с запасом,
        // прежде чем снимать лист входа.
        sleep(1)
        snap("142_journey_sign_in")
        win.swipeDown(); sleep(1)
    }

    /// Отрезок между отметками (0.6.8): скобка в «Моментах» и лист правки.
    ///
    /// Сеется отдельным аргументом — отрезок иначе пришлось бы заводить
    /// руками через два листа, и первый же кадр зависел бы от четырёх тапов.
    func test_zz_segment_shots() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-segment-demo", "-seed-places-rich"]
        app.launch()
        normalizeToHome()

        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        if me.waitForExistence(timeout: 3) { me.tap(); sleep(2) }

        // Если демо-путешествие уже есть (`test_zz_journey_shots` отработал
        // раньше по алфавиту), «Краснодар → Ростов-на-Дону» — уже его плечо,
        // своей карточки у оригинала в «Мои» больше нет (`HistoryFolding`).
        // Клоны `-seed-places-rich` при этом остаются ОБЫЧНЫМИ карточками с
        // тем же названием, но БЕЗ единой отметки — поиск ниже по названию
        // открыл бы клон вместо оригинала. Проверяем плечо сначала и
        // однозначно, по `journey_leg_row`, а не вслепую по заголовку.
        var opened = openRostovLegThroughJourney(searchingUp: true)
        if !opened {
            // Демо-путешествия нет (одиночный прогон этого теста) — «Мои»
            // ещё стоит на самом верху, ищем «Краснодар → Ростов-на-Дону» по
            // названию; среди клонов первым становится хитовым ОРИГИНАЛ —
            // он ближе к сегодня и оттого выше в списке.
            let card = app.buttons.matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "profile_trip_card", "Ростов-на-Дону")).firstMatch
            for _ in 0..<30 {
                // Тап по карточке, до которой список ещё доезжает, уходит в
                // пустоту: свайп даёт инерцию, `isHittable` становится
                // истинным раньше, чем строка встаёт на место. Поэтому пауза
                // перед тапом и проверка, что экран поездки правда открылся,
                // — иначе тест молча продолжает свайпать ленту «Мои» и
                // падает на «Моментах».
                if card.exists, card.isHittable {
                    usleep(600_000)
                    card.tap()
                    if app.buttons["detail_map_expand"].waitForExistence(timeout: 8) {
                        opened = true; break
                    }
                }
                win.swipeUp(); usleep(400_000)
            }
            if !opened { opened = openRostovLegThroughJourney() }
        }
        XCTAssertTrue(opened, "поездка «Краснодар → Ростов-на-Дону» не открылась из «Мои»")
        guard opened else { return }
        sleep(2)

        // Лента «Моменты» — в самом низу экрана поездки.
        let block = app.buttons.matching(identifier: "moment_segment").firstMatch
        var reached = false
        for _ in 0..<20 {
            if block.exists, block.isHittable { reached = true; break }
            win.swipeUp(); usleep(500_000)
        }
        XCTAssertTrue(reached, "скобка отрезка не найдена в «Моментах»")
        guard reached else { return }
        snap("150_segment_row")

        // Строка истории появляется только когда сверка на запуске
        // (`PlaceManager.reconcile()`) успела посчитать три проезда у обоих
        // мест демо-отрезка (`-seed-places-rich`) — она асинхронна, и до
        // 8 секунд ожидания это нормально. Если экран уже отрисован без
        // строки (сверка ещё не закончилась к первому рендеру «Моментов»),
        // свайп вниз-вверх форсирует перерисовку под уже готовые данные.
        let history = app.staticTexts["moment_segment_history"]
        if !history.waitForExistence(timeout: 8) {
            win.swipeDown(); usleep(300_000)
            win.swipeUp(); usleep(300_000)
            _ = history.waitForExistence(timeout: 8)
        }
        XCTAssertTrue(history.exists, "история отрезка не появилась — сверка мест не досчиталась")
        snap("152_segment_history")

        block.tap()
        XCTAssertTrue(app.otherElements["segment_editor"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["segment_editor"].waitForExistence(timeout: 1),
                      "лист отрезка не открылся")
        sleep(1); snap("151_segment_editor")
        win.swipeDown(); sleep(1)
    }

    /// Путь к плечу через карточку демо-путешествия — единственный
    /// однозначный, когда путешествие существует: «Краснодар →
    /// Ростов-на-Дону» после `test_zz_journey_shots` (он идёт раньше по
    /// алфавиту) — уже плечо, своей карточки в «Мои» у него нет
    /// (`HistoryFolding`), а клоны `-seed-places-rich` с тем же названием
    /// остаются обычными карточками БЕЗ единой отметки. Стор между тестами
    /// один, и перезапуск с аргументами его не чистит.
    ///
    /// - Parameter searchingUp: `true` — список ещё у самого верха (первая
    ///   попытка, до слепого поиска по названию), свайпаем ВНИЗ по контенту
    ///   (`swipeUp`); `false` (по умолчанию) — список уже уведён в самый низ
    ///   прошлым циклом, возвращаемся `swipeDown`, чтобы не свайпать вниз
    ///   ещё раз с нуля.
    private func openRostovLegThroughJourney(searchingUp: Bool = false) -> Bool {
        let journey = app.buttons.matching(identifier: "profile_journey_card").firstMatch
        var reached = false
        for _ in 0..<30 {
            if journey.exists, journey.isHittable { reached = true; break }
            if searchingUp { win.swipeUp() } else { win.swipeDown() }
            usleep(400_000)
        }
        guard reached else { return false }
        journey.tap(); sleep(2)

        let leg = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "journey_leg_row", "Ростов-на-Дону")).firstMatch
        for _ in 0..<15 {
            if leg.exists, leg.isHittable {
                usleep(600_000)
                leg.tap()
                if app.buttons["detail_map_expand"].waitForExistence(timeout: 6) { return true }
            }
            win.swipeUp(); usleep(400_000)
        }
        return false
    }

    /// Walks the redesigned Me tab (0.6.0 Профиль·Я): hero, settings
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

        // 0.6.0 replaced the Wrapped hero with «Достижения» — shoot that instead.
        let achievements = app.buttons.matching(identifier: "profile_achievements_all").firstMatch
        if achievements.waitForExistence(timeout: 2), achievements.isHittable {
            achievements.tap(); sleep(2); snap("145_achievements")
            // Pushed screen with a LEADING back circle — the trailing corner
            // this used to tap is empty, so the tour stayed on Достижения and
            // shot the rest of the run from the wrong screen.
            let back = app.buttons.matching(identifier: "achievements_back").firstMatch
            if back.waitForExistence(timeout: 2) { back.tap() } else { pt(0.07, 0.07).tap() }
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

        // Sign-in sheet (0.6.0 Вход) — the guest feed banner opens it.
        let guestBanner = app.buttons.matching(identifier: "guest_signin_banner").firstMatch
        if guestBanner.waitForExistence(timeout: 3), guestBanner.isHittable {
            guestBanner.tap()
            sleep(1); snap("12_signin_sheet")
            win.swipeDown(); sleep(1)
        }

        // Maps tab — 0.6.0 «Моя карта» (ids, locale-independent)
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
