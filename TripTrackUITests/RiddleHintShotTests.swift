import XCTest

/// Кадр КРУГА ПОДСКАЗКИ на «Атласе» — того единственного, чего не показал ни
/// один снимок волны.
///
/// Снимать его до слияния бандла было нечем: каталог загадок стоял пустой, и
/// `riddleHints` никогда не набирался. Настоящий бандл (`Riddles.json`, 1 028
/// точек) даёт под Краснодаром безымянный `border` в 4.6 км от центра, и с
/// демо-поездками вокруг он попадает в тройку ближайших к открытому.
///
/// До городского масштаба доезжаем ТАПОМ ПО ГОРСТИ поездок (`map_cluster`):
/// карта сама подгоняет камеру под её членов — тот же приём, которым
/// `SealShotTests` доезжает до печатей, и по той же причине (двойные тапы
/// вслепую то попадают по дороге, то не приближают вовсе).
final class RiddleHintShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-places-rich",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_riddle_hint_circle() {
        XCTAssertTrue(app.buttons["atlas_explored_title"].waitForExistence(timeout: 12))
        usleep(2_500_000)

        // Приближаем ДВОЙНЫМИ ТАПАМИ ПО САМОЙ ПОДСКАЗКЕ: карта зумит к точке
        // касания, поэтому круг остаётся в кадре и растёт вдвое за тап. Щипок
        // здесь не годится — он считает центром середину экрана и на третьем
        // приближении уводит камеру за сотню километров от круга, а тап по
        // горсти поездок попадает в регион под ней и открывает карточку края.
        //
        // Подсказку находим по её же подписи для VoiceOver — сам круг не
        // нажимается (`isEnabled = false`), но координаты у него есть, а
        // больше от него ничего и не нужно.
        for _ in 0..<4 {
            let hint = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "border post"))
                .firstMatch
            guard hint.waitForExistence(timeout: 6) else { break }
            hint.doubleTap()
            usleep(1_500_000)
        }
        // Двойной тап по карте попадает и в дорогу под кругом — снизу
        // поднимается карточка «16 поездок на этой дороге». Закрываем: кадр
        // про круг, а не про неё.
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        if close.exists { close.tap() }
        usleep(2_500_000)
        snap("w070_w2_hint")
    }
}
