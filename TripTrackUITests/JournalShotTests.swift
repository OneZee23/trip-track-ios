import XCTest

/// Кадры «Журнала первооткрывателя» (0.7.0, волна 4): свёрнутый лист и
/// развёрнутый с тремя группами.
///
/// Юнит-тесты держат сборку журнала числами (`JournalBuilderTests`), но не
/// отвечают на вопрос «влезло ли и видно ли»: печати стоят сеткой над
/// непрозрачным туманом, и панель растёт под содержимое. Такое проверяется
/// только снимком.
///
/// `-seed-discoveries` кладёт на демо-поездку две находки — без него сетка
/// печатей была бы пустой строкой.
final class JournalShotTests: XCTestCase {
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

    func test_journal_collapsed_and_expanded() {
        let tab = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 12), "вкладка «Атлас» на месте")
        tab.tap()
        // Туман выгорает 0.7 с, карта успевает встать за пару секунд.
        usleep(3_500_000)

        let summary = app.otherElements["mymap_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "свёрнутый лист поднят")
        snap("w070_w4_journal_collapsed")

        summary.tap()
        usleep(2_000_000)

        let journal = app.otherElements["mymap_region_list"]
        XCTAssertTrue(journal.waitForExistence(timeout: 8), "журнал открылся")
        snap("w070_w4_journal_expanded")
    }
}
