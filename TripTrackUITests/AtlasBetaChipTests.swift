import XCTest

/// Значок «Бета» у заголовка «Атласа» обязан НАЖИМАТЬСЯ.
///
/// Он не нажимался с самого появления (19 сен 2026): `.allowsHitTesting(false)`
/// стоял на всей колонке заголовка, чтобы надписи не крали жесты карты, а
/// значок «переопределял» запрет себе — переопределить его нельзя, SwiftUI
/// спрашивает разрешение сверху вниз. Нашёл это владелец на устройстве 22
/// сентября, а не сборка и не тест: у кнопки, которая не отвечает, нет ни
/// возвращаемого значения, ни состояния — есть только палец.
///
/// Поэтому проверка живёт в UI-таргете и делает ровно то, что делал он:
/// открыть «Атлас», нажать значок, дождаться карточки. Юнит-тестом это не
/// выражается вовсе — хит-тест SwiftUI виден только настоящему касанию.
///
/// Гонять ТОЛЬКО этот класс (`-only-testing:TripTrackUITests/AtlasBetaChipTests`):
/// полный UI-таргет виснет, см. CLAUDE.md.
final class AtlasBetaChipTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTheBetaChipOpensItsCard() {
        let tab = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "вкладка «Атлас» на месте")
        tab.tap()

        let chip = app.buttons["atlas_beta_chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "значок «Бета» на экране")
        XCTAssertTrue(chip.isHittable, "значок «Бета» доступен пальцу, а не закрыт заголовком")
        chip.tap()

        let sheet = app.otherElements["atlas_beta_sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "карточка «Атлас в бете» открылась")
    }
}
