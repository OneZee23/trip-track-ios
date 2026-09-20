import XCTest

/// Снимки «Вписать поездку» (0.8.0).
///
/// Запуск с `-debug-plus`: без него гейт отвечает `.locked`, и «+» открывает
/// пейвол, а не форму (флаг живёт в `PlusAccess` под `#if DEBUG`, как
/// `-debug-admin`).
///
/// Настоящего маршрута на симуляторе не построить: сеть MapKit там мертва —
/// плитки карты не грузятся, `MKLocalSearchCompleter` молчит, `MKDirections`
/// не отвечает. Поэтому поездка приезжает сидом `-seed-manual-trip` (та же
/// сборка, та же запись в базу, подделана только геометрия дороги), а форма
/// снимается пустой — какой её и видит человек, открывший лист.
final class ManualTripShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>",
            "-debug-plus", "-seed-map-demo", "-seed-places-rich", "-seed-manual-trip"
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func normalise() {
        let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if recovery.waitForExistence(timeout: 3), recovery.isHittable {
            recovery.tap(); sleep(2)
        }
    }

    private func openProfile() {
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 20), "нет вкладки «Я»")
        me.tap(); sleep(3)
    }

    /// Форма: точки, дата, длительность, машина, название, «Создать».
    func test_manual_form() {
        normalise()
        openProfile()

        let add = app.buttons.matching(identifier: "profile_history_add").firstMatch
        for _ in 0..<10 where !(add.exists && add.isHittable) {
            app.swipeUp(); sleep(1)
        }
        XCTAssertTrue(add.exists && add.isHittable, "нет «+» в шапке «Истории»")
        add.tap(); sleep(3)

        XCTAssertTrue(
            app.buttons.matching(identifier: "manual_trip_create").firstMatch
                .waitForExistence(timeout: 5),
            "лист «Вписать поездку» не открылся — гейт отдал пейвол?"
        )
        snap("w080_manual_form")
    }

    /// Карточка вписанной поездки в «Мои» — с карандашом у даты.
    func test_manual_card() {
        normalise()
        openProfile()

        let card = app.buttons.matching(identifier: "profile_trip_card").firstMatch
        for _ in 0..<12 where !(card.exists && card.isHittable) {
            app.swipeUp(); sleep(1)
        }
        XCTAssertTrue(card.exists, "в «Мои» нет ни одной карточки поездки")
        snap("w080_manual_card")
    }

    /// Экран вписанной поездки: маршрут, чип «вписана рукой», плитки без
    /// «макс.» и без графика скорости.
    func test_manual_route() {
        normalise()
        openProfile()

        let card = app.buttons.matching(identifier: "profile_trip_card").firstMatch
        for _ in 0..<12 where !(card.exists && card.isHittable) {
            app.swipeUp(); sleep(1)
        }
        XCTAssertTrue(card.exists && card.isHittable, "в «Мои» нет ни одной карточки поездки")
        card.tap(); sleep(5)
        snap("w080_manual_route")
    }

    /// Редизайн 20 сен: чипы («Дом»/частые места/«Точка на карте») заполняют
    /// поле, карта-герой сразу показывает точку.
    func test_manual_chips() {
        normalise()
        openProfile()
        // Чипы частых мест зависят от штатной сверки `PlaceManager.reconcile()`
        // на запуске (комментарий `-seed-places-rich`) — на богатом сиде она
        // не всегда успевает до того, как открылся лист.
        sleep(8)

        let add = app.buttons.matching(identifier: "profile_history_add").firstMatch
        for _ in 0..<10 where !(add.exists && add.isHittable) {
            app.swipeUp(); sleep(1)
        }
        XCTAssertTrue(add.exists && add.isHittable, "нет «+» в шапке «Истории»")
        add.tap(); sleep(3)

        let quickRow = app.scrollViews.matching(identifier: "manual_trip_quick_points").firstMatch
        XCTAssertTrue(quickRow.waitForExistence(timeout: 5), "нет ряда чипов над точками")
        // Первый чип — «Дом», если он известен, иначе первое частое место:
        // оба ведут в первое пустое поле («Откуда»), поэтому просто первый.
        let firstChip = quickRow.buttons.firstMatch
        if firstChip.exists && firstChip.isHittable {
            firstChip.tap(); sleep(2)
        }
        snap("w080_manual_chips")
    }

    /// Вторая стадия того же листа: поиск, а не второй лист поверх первого.
    func test_manual_search_stage() {
        normalise()
        openProfile()

        let add = app.buttons.matching(identifier: "profile_history_add").firstMatch
        for _ in 0..<10 where !(add.exists && add.isHittable) {
            app.swipeUp(); sleep(1)
        }
        XCTAssertTrue(add.exists && add.isHittable, "нет «+» в шапке «Истории»")
        add.tap(); sleep(3)

        let to = app.buttons.matching(identifier: "manual_trip_point_to").firstMatch
        XCTAssertTrue(to.waitForExistence(timeout: 5), "нет поля «Куда»")
        to.tap(); sleep(2)
        XCTAssertTrue(
            app.textFields.matching(identifier: "manual_trip_search").firstMatch
                .waitForExistence(timeout: 5),
            "стадия поиска не открылась"
        )
        snap("w080_manual_search")
    }
}

/// Пустая история (0 поездок) — редизайн 20 сен добавил вторую кнопку рядом
/// с «Записать первую». Отдельный класс: этому снимку нужен телефон БЕЗ
/// единой поездки, а остальные снимки этого файла специально сидят
/// `-seed-manual-trip`.
final class ManualTripEmptyHistoryShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-plus"]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_manual_welcome_two_buttons() {
        let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if recovery.waitForExistence(timeout: 3), recovery.isHittable {
            recovery.tap(); sleep(2)
        }
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 20), "нет вкладки «Я»")
        me.tap(); sleep(3)

        XCTAssertTrue(
            app.buttons.matching(identifier: "profile_welcome_manual_trip").firstMatch
                .waitForExistence(timeout: 10),
            "нет второй кнопки «Вписать поездку» в пустой истории"
        )
        snap("w080_manual_welcome")
    }
}
