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
            "-debug-plus", "-seed-map-demo", "-seed-manual-trip"
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
}
