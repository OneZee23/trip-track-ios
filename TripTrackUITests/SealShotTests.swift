import XCTest

/// Кадры печатей на «Атласе» — то, что нельзя проверить юнит-тестом.
///
/// Данные могут быть безупречны, а на экране не окажется ничего: печать это
/// `MKAnnotation` над экранной вуалью, и её видимость решает не наш код, а
/// место вуали в дереве `MKMapView`. Поэтому здесь настоящие тапы и три
/// снимка: масштаб страны, масштаб города и карточка печати.
///
/// Сид `-seed-discoveries` кладёт на демо-поездку «Краснодар → Горячий Ключ»
/// две находки — загадку-мост и веху «первый регион».
final class SealShotTests: XCTestCase {
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

    private var win: XCUIElement { app.windows.firstMatch }

    private var anySeal: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "map_seal").firstMatch
    }

    /// Горсть печатей на мелком масштабе. Тап по ней — единственный
    /// ДЕТЕРМИНИРОВАННЫЙ способ доехать до города: карта сама подгоняет камеру
    /// под всех членов кластера (`zoom(into:)`), а двойные тапы вслепую то
    /// попадали по дороге, то не приближали вовсе.
    private var sealCluster: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "map_seal_cluster").firstMatch
    }

    func test_seals_on_the_atlas() {
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 12))
        usleep(2_500_000)
        snap("w070_w2_seals_country")

        XCTAssertTrue(sealCluster.waitForExistence(timeout: 10),
                      "две печати на мелком масштабе слипаются в горсть")
        sealCluster.tap()
        usleep(2_500_000)
        snap("w070_w2_seals_city")

        let seal = app.descendants(matching: .any).matching(identifier: "map_seal").firstMatch
        XCTAssertTrue(seal.waitForExistence(timeout: 8), "печати разошлись по своим местам")
        seal.tap()
        XCTAssertTrue(app.otherElements["mymap_discovery_card"].waitForExistence(timeout: 5),
                      "тап по печати открывает карточку находки")
        usleep(900_000)
        snap("w070_w2_peek")
    }
}
