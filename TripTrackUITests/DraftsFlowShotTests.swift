import XCTest

/// Кадры черновиков: карточка на «Я», список, режим выбора, свайпы, диалог,
/// экран поездки, пустой список и «Я» без раздела.
///
/// Снимается на засеянных черновиках (`-seed-drafts`): завести их настоящим
/// путём нельзя — черновик рождается только из старта автотрекинга по
/// магнитоле, а её в симуляторе нет.
final class DraftsFlowShotTests: XCTestCase {

    func testDraftsFlow() {
        let app = launch(theme: "dark")

        openMe(app)
        XCTAssertTrue(app.otherElements["profile_drafts_row"].firstMatch
            .waitForExistence(timeout: 20)
            || app.buttons["profile_drafts_row"].firstMatch.exists,
                      "раздел «Черновики» не появился на «Я»")
        snap(app, "d1_me_card")

        openDrafts(app)
        snap(app, "d3_list")

        // Состояние 7: режим выбора.
        app.buttons["drafts_select"].firstMatch.tap()
        usleep(600_000)
        snap(app, "d7_select_empty")
        app.buttons["draft_row"].firstMatch.tap()
        usleep(600_000)
        snap(app, "d7_select_one")
        app.buttons["drafts_done"].firstMatch.tap()
        usleep(600_000)

        // Состояние 5: свайп вправо — «Моя», без диалога.
        let first = app.buttons["draft_row"].firstMatch
        first.swipeRight()
        usleep(700_000)
        snap(app, "d5_swipe_mine")
        let mineAction = app.buttons.matching(NSPredicate(format: "label == 'Моя'")).firstMatch
        if mineAction.waitForExistence(timeout: 5) {
            let before = app.buttons.matching(identifier: "draft_row").count
            mineAction.tap()
            usleep(1_200_000)
            XCTAssertEqual(app.buttons.matching(identifier: "draft_row").count, before - 1,
                           "строка не ушла после свайпа «Моя»")
        }

        // Состояние 6 + 9: свайп влево и диалог удаления.
        let row = app.buttons["draft_row"].firstMatch
        row.swipeLeft()
        usleep(700_000)
        snap(app, "d6_swipe_delete")
        let delete = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'далит'"))
            .firstMatch
        if delete.waitForExistence(timeout: 5) {
            delete.tap()
            usleep(800_000)
            snap(app, "d9_delete_dialog")
            let cancel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'тмен'"))
                .firstMatch
            if cancel.waitForExistence(timeout: 5) { cancel.tap() }
            usleep(600_000)
        }

        // Состояние 8: экран поездки, открытый из списка. Кнопка «Моя» на нём
        // обязана вернуть в список, а не в «Я».
        app.buttons["draft_row"].firstMatch.tap()
        usleep(2_500_000)
        snap(app, "d8_trip")

        let mine = app.buttons.matching(NSPredicate(format: "label == 'Моя'")).firstMatch
        if mine.waitForExistence(timeout: 10) {
            mine.tap()
            usleep(1_500_000)
            XCTAssertTrue(app.buttons["drafts_back"].firstMatch.waitForExistence(timeout: 10),
                          "«Моя» на экране поездки не вернула в список черновиков")
            snap(app, "d3_after_mine")
        }

        // Чек-лист §10 пункт 6: «Удалить» с экрана поездки тоже возвращает в
        // список — через тот же домашний диалог.
        app.buttons["draft_row"].firstMatch.tap()
        usleep(2_500_000)
        let discard = app.buttons["draft_discard"].firstMatch
        if discard.waitForExistence(timeout: 10) {
            discard.tap()
            usleep(800_000)
            let confirmDelete = app.buttons
                .matching(NSPredicate(format: "label CONTAINS[c] 'далит'")).firstMatch
            XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5),
                          "«Удалить» на экране поездки не спросило подтверждения")
            confirmDelete.tap()
            usleep(1_500_000)
            XCTAssertTrue(app.buttons["drafts_back"].firstMatch.waitForExistence(timeout: 10),
                          "«Удалить» на экране поездки не вернуло в список черновиков")
        }

        // Состояние 4: черновик остался один — кнопка внизу говорит «Моя», а
        // не «Все мои · 1»: числа у единственной строки быть не должно.
        usleep(800_000)
        if app.buttons.matching(identifier: "draft_row").count == 1 {
            let button = app.buttons["drafts_all_mine"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            XCTAssertEqual(button.label, "Моя", "у одного черновика кнопка обязана быть «Моя»")
            snap(app, "d4_single")
        }
    }

    /// Состояния 10 и 2: последний черновик ушёл.
    func testDraftsEmptyAfterConfirmingAll() {
        let app = launch(theme: "dark")
        openMe(app)
        openDrafts(app)

        app.buttons["drafts_all_mine"].firstMatch.tap()
        usleep(1_500_000)
        snap(app, "d10_empty")

        app.buttons["drafts_back"].firstMatch.tap()
        usleep(1_200_000)
        XCTAssertFalse(app.staticTexts["profile_drafts_header"].exists,
                       "раздел «Черновики» остался после того, как черновики кончились")
        snap(app, "d2_me_without_section")
    }

    /// Светлая тема — чек-лист §10 пункт 9.
    func testDraftsLight() {
        let app = launch(theme: "light")
        openMe(app)
        snap(app, "l1_me_card")
        openDrafts(app)
        snap(app, "l3_list")
        app.buttons["drafts_select"].firstMatch.tap()
        usleep(600_000)
        app.buttons["draft_row"].firstMatch.tap()
        usleep(600_000)
        snap(app, "l7_select")
        app.buttons["drafts_done"].firstMatch.tap()
        usleep(500_000)

        // Светлые 8 и 10 — те же состояния, что сняты тёмными.
        app.buttons["draft_row"].firstMatch.tap()
        usleep(2_500_000)
        snap(app, "l8_trip")
        app.buttons["detail_back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["drafts_back"].firstMatch.waitForExistence(timeout: 10))
        usleep(1_000_000)
        app.buttons["drafts_all_mine"].firstMatch.tap()
        usleep(1_500_000)
        snap(app, "l10_empty")
    }

    // MARK: -

    private func launch(theme: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>",
            "-seed-map-demo", "-seed-drafts",
            "-appLanguage", "ru", "-appThemeMode", theme,
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        return app
    }

    private func openMe(_ app: XCUIApplication) {
        let me = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 30))
        me.tap()
        usleep(2_500_000)
    }

    private func openDrafts(_ app: XCUIApplication) {
        let card = app.buttons["profile_drafts_row"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "карточки «Черновики» нет")
        card.tap()
        XCTAssertTrue(app.buttons["drafts_back"].firstMatch.waitForExistence(timeout: 20),
                      "список черновиков не открылся")
        usleep(1_500_000)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
