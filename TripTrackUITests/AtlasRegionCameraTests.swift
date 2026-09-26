import XCTest

/// Тап по региону обязан ПЕРЕВЕСТИ КАМЕРУ на этот регион.
///
/// Владелец на устройстве 26 сентября: «нажал Адыгея — и меня унесло на карте
/// куда-то вникуда». Причин было две, и обе меряются числом, а не глазом.
///
/// Первая: SwiftUI переставал звать `updateUIViewController` у карты «Атласа»
/// после двух вызовов на старте — при шести прогонах `body`. Команда камеры,
/// слой периода и туман до карты просто не доезжали. Поэтому координатор
/// слушает вью-модель напрямую (`bindViewModel`).
///
/// Вторая: `edgePadding` складывался с безопасной зоной карты, которая уже
/// отдана листу (~290 pt), и по вертикали оставалось МИНУС 68 pt — MapKit
/// отвечает на это кадром во весь мир (замер: кадр в 5.34 раза шире
/// запрошенного). Считает отступы `MapCameraCommand.Padding.insets`, её
/// держит `MapCameraPaddingTests`.
///
/// Здесь — то, что не выражается юнит-тестом: картинка карты ОБЯЗАНА
/// измениться. Подложка Apple в симуляторе не грузится, поэтому меряется
/// полоса самой карты, а не её содержимое.
final class AtlasRegionCameraTests: XCTestCase {
    func testTappingARegionMovesTheMap() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()

        let maps = app.buttons["tab_maps"].firstMatch
        XCTAssertTrue(maps.waitForExistence(timeout: 25), "нет вкладки «Атлас»")
        maps.tap()

        let region = app.buttons["atlas_region_RU-KDA"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 25), "нет карточки края")
        // Карта дорисовывает первый кадр уже после того, как список готов.
        usleep(4_000_000)
        let before = mapGrid()
        attach("atlas_camera_before")

        region.tap()
        // Пружина камеры MapKit плюс кадр тумана.
        usleep(5_000_000)
        let after = mapGrid()
        attach("atlas_camera_after")

        let moved = HeroMapProbe.difference(before, after)
        print("ATLAS_CAMERA_DRIFT \(moved)")
        XCTAssertGreaterThan(moved, 0.01,
                             "камера не поехала: картинка карты та же, расхождение \(moved)")
    }

    /// Полоса, в которой у «Атласа» живёт карта: ниже шапки, выше листа.
    private func mapGrid() -> [Double] {
        HeroMapProbe.grid(of: XCUIScreen.main.screenshot(), from: 0.16, to: 0.34)
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
