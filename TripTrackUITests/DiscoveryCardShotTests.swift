import XCTest

/// Кадры карточки находки (0.7.0, волна 4): загадка и веха.
///
/// Модель карточки держат числами `DiscoveryCardModelTests`, но они не
/// отвечают на вопрос «влезло ли и видно ли»: у загадки под текстом стоит
/// мини-карта со снимком MapKit и кругом поверх него, и нарисован ли круг там,
/// где думает вью, проверяется только снимком.
///
/// Секрета в этих кадрах НЕТ и быть не может: карточка секрета живёт от
/// каталога с сервера (волна 3), а сид кладёт в базу только загадку и веху —
/// секрет без каталога это печать без имени, истории и счётчика.
final class DiscoveryCardShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-discoveries",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Журнал открыт, сетка печатей на экране.
    private func openJournal() {
        let tab = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 12), "вкладка «Атлас» на месте")
        tab.tap()
        // Туман выгорает 0.7 с, карта успевает встать за пару секунд.
        usleep(3_500_000)

        let summary = app.otherElements["mymap_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "свёрнутый лист поднят")
        summary.tap()
        usleep(2_000_000)
        XCTAssertTrue(app.otherElements["mymap_region_list"].waitForExistence(timeout: 8),
                      "журнал открылся")
    }

    /// Печать ищется ПО ПОДПИСИ вида ВНУТРИ ЖУРНАЛА.
    ///
    /// По подписи, а не по месту в сетке: у обеих находок сида одна дата, и
    /// порядок между ними ничем не закреплён. Внутри журнала, а не по всему
    /// экрану: те же печати стоят и на карте под панелью, и первым совпадением
    /// приходила именно карта — тап по ней уходил в «hit point {-1, -1}».
    private func tapSeal(kind: String) {
        let seal = app.otherElements["mymap_region_list"].buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", kind)).firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: 8), "печать «\(kind)» в сетке журнала")
        seal.tap()
        XCTAssertTrue(app.otherElements["mymap_discovery_card"].waitForExistence(timeout: 8),
                      "карточка находки открылась")
    }

    func test_card_riddle() {
        openJournal()
        tapSeal(kind: "riddle")
        // Мини-карта тянет тайлы сетью — без паузы в кадр попадает пустой
        // прямоугольник с одним кругом.
        usleep(9_000_000)
        snap("w070_w4_card_riddle")
    }

    func test_card_milestone() {
        openJournal()
        tapSeal(kind: "milestone")
        usleep(1_500_000)
        snap("w070_w4_card_milestone")
    }
}
