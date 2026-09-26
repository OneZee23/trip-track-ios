import XCTest

/// Кадры экрана места (0.7.0, фикс-волна вёрстки): две плашки — «Обычно
/// занимает» и «Проезды» — обязаны стоять одной колонкой текста.
///
/// Юнит-тест держит слова строки (`PlaceUsuallyLineTests`), но не отвечает на
/// вопрос «сходятся ли отступы двух карточек глазами»: это видно только
/// снимком.
///
/// Места заводят отметки (`-seed-places-demo`, `-seed-segment-demo`), а три
/// проезда у них — клоны дороги из `-seed-places-rich`: без них в карточке
/// «обычно» стояла бы одна строка счёта, и разброс «от … до …» не показался
/// бы никогда.
final class PlaceDetailShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich", "-seed-segment-demo",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_place_detail_layout() {
        let tab = app.buttons.matching(identifier: "tab_places").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "вкладка «Места» на месте")
        tab.tap()

        // Места заводит сверка на запуске (`PlaceManager.reconcile`), и список
        // приходит уведомлением — карточки появляются позже самой вкладки.
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place_card_'")).firstMatch
        if !card.waitForExistence(timeout: 60) {
            XCTFail("карточка места не появилась\n\(app.debugDescription)")
            return
        }
        card.tap()

        let screen = app.otherElements["place_detail"]
        XCTAssertTrue(screen.waitForExistence(timeout: 20), "экран места открылся")
        usleep(3_000_000)
        snap("w070_place")

        // Лист уехал вверх — обязана проявиться шапка с именем и «Назад».
        // Она НЕ видна в покое (карта — фон экрана) и НЕ нажимается, пока
        // прозрачна: иначе её кнопка перехватывала бы тапы по карте.
        screen.swipeUp()
        screen.swipeUp()
        usleep(1_500_000)
        snap("w081_place_scrolled")

        // Второе место — другой счёт проездов: одна строка счёта против
        // разброса. Обе формы карточки «обычно» должны попасть в кадр.
        app.buttons["Back"].firstMatch.tap()
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place_card_'"))
        if cards.count > 1 {
            cards.element(boundBy: 1).tap()
            XCTAssertTrue(screen.waitForExistence(timeout: 20), "второй экран места открылся")
            usleep(3_000_000)
            snap("w070_place_second")
        }
    }
}
