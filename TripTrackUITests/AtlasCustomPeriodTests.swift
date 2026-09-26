import XCTest

/// «Свой период» на живом экране, с НЕПУСТЫМ результатом.
///
/// `AtlasDesignTests` проверяет пустой край: старт = сегодня, поездок нет,
/// показывается пустое состояние. Это доказывает, что фильтр умеет обнулять,
/// и ничего не говорит про середину — а владелец на устройстве 26 сентября
/// сказал ровно про неё: «свой период не работает от слова совсем, он нифига
/// не фильтрует».
///
/// Сид `-seed-map-demo` кладёт поездки на 1, 2, 5, 6, 9, 12, 14, 21, 30, 33,
/// 54, 72 и 86 дней назад. Окно «с позавчера» обязано оставить Краснодарский
/// край (1 и 2 дня назад) и убрать Ростовскую область (12 и 14) и Аджарию (5).
final class AtlasCustomPeriodTests: XCTestCase {
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

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testCustomRangeKeepsRecentRegionsAndDropsOlderOnes() {
        let maps = app.buttons["tab_maps"].firstMatch
        XCTAssertTrue(maps.waitForExistence(timeout: 20), "нет вкладки «Атлас»")
        maps.tap()

        // Вся история: обе области на месте — точка отсчёта, без которой
        // «после фильтра их нет» ничего не доказывает.
        XCTAssertTrue(app.buttons["atlas_region_RU-KDA"].waitForExistence(timeout: 25),
                      "Краснодарский край не появился за всю историю")
        XCTAssertTrue(regionExists("atlas_region_RU-ROS"),
                      "Ростовская область не появилась за всю историю")

        applyCustomRange(startingDaysAgo: 2)

        // Пилюля периода обязана отметить, что фильтр применён.
        let filtered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.regionExists("atlas_region_RU-ROS") },
            object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 25), .completed,
                       "поездки Ростовской области старше окна, а область осталась в списке")
        XCTAssertFalse(regionExists("atlas_region_GE-AJ"),
                       "Аджария (5 дней назад) тоже вне окна")
        XCTAssertTrue(regionExists("atlas_region_RU-KDA"),
                      "поездки 1 и 2 дней назад внутри окна — край обязан остаться")
        snap("atlas_custom_period_non_empty")
    }

    /// Свой диапазон целиком: открыть лист, перейти в календарь, выбрать день
    /// начала, применить. Конец остаётся сегодняшним — это и есть путь,
    /// которым в него заходит человек.
    private func applyCustomRange(startingDaysAgo days: Int) {
        tap("atlas_period")
        XCTAssertTrue(app.otherElements["atlas_period_sheet"].waitForExistence(timeout: 10))
        if app.buttons["atlas_period_back"].exists { tap("atlas_period_back") }
        tap("atlas_period_custom")

        let calendar = app.datePickers["atlas_period_calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 10), "календарь своего периода")
        if calendar.frame.maxY > app.buttons["atlas_period_apply"].frame.minY {
            app.otherElements["atlas_period_sheet"].scrollViews.firstMatch.swipeUp()
        }

        // САМ дефект: календарь обязан открыться на месяце ВЫБРАННОЙ даты.
        // На `Date.distantPast...` он показывал произвольный месяц (при
        // выбранном 28 августа — июль) и без подсветки; человек жал день в
        // чужом месяце, окно выходило шире библиотеки, и фильтр не отсекал
        // ничего. Листать здесь нельзя — это и проверяется.
        //
        // `isHittable`, а не `exists`: `UICalendarView` держит соседние
        // страницы месяцев в дереве, и по одному существованию кнопки
        // отличить показанный месяц от подготовленного нельзя.
        snap("atlas_custom_period_calendar_opened")
        let opened = dayButton(daysAgo: 29, in: calendar)
        XCTAssertTrue(opened.exists && opened.isHittable,
                      "календарь открылся не на месяце выбранного начала (29 дней назад)")

        // Переключение на «До» обязано перенести календарь к КОНЦУ окна
        // (по умолчанию сегодня). Если он остаётся на месяце начала, человек
        // правит конец вслепую — и «свой период» ведёт себя не так, как он
        // ожидает.
        app.buttons["atlas_period_to"].firstMatch.tap()
        usleep(600_000)
        let today = dayButton(daysAgo: 0, in: calendar)
        snap("atlas_custom_period_editing_end")
        XCTAssertTrue(today.exists && today.isHittable,
                      "после «До» календарь не перешёл к месяцу конца окна")
        app.buttons["atlas_period_from"].firstMatch.tap()
        usleep(600_000)

        selectDay(daysAgo: days, in: calendar)
        tap("atlas_period_apply")
    }

    /// Календарь открывается на месяце ВЫБРАННОЙ даты (по умолчанию — 29
    /// дней назад), поэтому нужный день бывает в следующем месяце. Листаем
    /// вперёд, а не полагаемся на то, что он уже в кадре.
    private func selectDay(daysAgo: Int, in calendar: XCUIElement) {
        let day = dayButton(daysAgo: daysAgo, in: calendar)
        for _ in 0..<14 {
            if day.exists, day.isHittable { break }
            let next = calendar.buttons["DatePicker.NextMonth"]
            guard next.exists, next.isHittable else { break }
            next.tap()
            usleep(300_000)
        }
        XCTAssertTrue(day.exists && day.isHittable, "день начала не нашёлся в календаре")
        XCTAssertLessThan(day.frame.maxY, app.buttons["atlas_period_apply"].frame.minY,
                          "день обязан быть выше липкой кнопки «Показать»")
        day.tap()
    }

    /// Полная дата, а не число: день 25 соседнего месяца иначе выиграет.
    private func dayButton(daysAgo: Int, in calendar: XCUIElement) -> XCUIElement {
        let target = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM"
        return calendar.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@", formatter.string(from: target))).firstMatch
    }

    private func regionExists(_ identifier: String) -> Bool {
        app.buttons[identifier].firstMatch.exists
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 10) {
        let element = app.buttons[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), identifier)
        element.tap()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
