import XCTest

/// Поведение экрана статистики после варианта B (0.9.1): столбик полосы
/// выбирает месяц, «Год» и «Всё время» — кнопки под полосой, повторное
/// нажатие на выбранную возвращает к месяцу. Проверяется ЧИСЛОМ — подписью
/// периода над итогом, а не цветом столбика.
final class StatsScreenFlowTests: XCTestCase {

    private func snap(_ name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name; att.lifetime = .keepAlways; add(att)
    }

    func testBarPicksMonthAndChipsSwitchRange() {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
                                "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        defer { app.terminate() }

        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()
        let strip = app.buttons["profile_stats_strip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
        strip.tap()

        let summary = app.descendants(matching: .any)["stats_summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        let opened = summary.label

        // Сентябрь демо-сида — самый длинный месяц; столбик выбирает его.
        let september = app.buttons["stats_month_8"].firstMatch
        XCTAssertTrue(september.waitForExistence(timeout: 5))
        september.tap()
        let picked = NSPredicate(format: "label CONTAINS[c] %@", "Сентябрь")
        expectation(for: picked, evaluatedWith: summary)
        waitForExpectations(timeout: 3)
        XCTAssertNotEqual(summary.label, opened)
        XCTAssertTrue(september.isSelected, "выбранный столбик не помечен для VoiceOver")
        snap("flow_september")

        // Будущий месяц не выбирается — нажатие ничего не меняет.
        let december = app.buttons["stats_month_11"].firstMatch
        XCTAssertFalse(december.isEnabled, "месяц, которого ещё не было, нажимается")

        let year = app.buttons["stats_range_year"].firstMatch
        year.tap()
        let yearOnly = NSPredicate(format: "NOT (label CONTAINS[c] %@)", "Сентябрь")
        expectation(for: yearOnly, evaluatedWith: summary)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(year.isSelected)
        snap("flow_year")

        // Повторное нажатие на выбранную кнопку возвращает к месяцу.
        year.tap()
        expectation(for: picked, evaluatedWith: summary)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(year.isSelected)

        let all = app.buttons["stats_range_all"].firstMatch
        all.tap()
        expectation(for: NSPredicate(format: "label CONTAINS[c] %@", "Всё время"),
                    evaluatedWith: summary)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(app.buttons["stats_month_8"].firstMatch.isEnabled,
                       "на «Всё время» столбик — сумма всех лет, выбирать в нём нечего")
        XCTAssertFalse(app.buttons["stats_year_back"].firstMatch.exists,
                       "на «Всё время» листать годы нечем и незачем")
        snap("flow_all")

        // Имя экрана больше не перекрывает кнопку «Назад».
        let back = app.buttons["stats_back"].firstMatch
        XCTAssertTrue(back.exists, "«Назад» снова без своего имени")
        back.tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
    }
}
