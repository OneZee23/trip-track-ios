import XCTest

/// Кадры каждого шага «Атласа»: сводка → список → регион → назад.
///
/// Кадром, потому что «удобно» и «плавно» не выражаются ни значением, ни
/// состоянием: сторож рядом (`AtlasChromeGeometryTests`) меряет, что ничего
/// не уехало, а этот показывает, что получилось.
final class AtlasFlowShotTests: XCTestCase {
    func testAtlasFlow() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich",
            "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        app.buttons["tab_maps"].firstMatch.tap()
        XCTAssertTrue(app.buttons["atlas_explored_title"].firstMatch.waitForExistence(timeout: 30))
        usleep(2_000_000)
        snap("a1_summary")

        let w = app.windows.firstMatch
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            .press(forDuration: 0.05,
                   thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        usleep(2_000_000)
        snap("a2_list")

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'atlas_region_'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        usleep(3_000_000)
        snap("a3_region")

        // Потянуть регион вверх: там его поездки.
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
            .press(forDuration: 0.05,
                   thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)))
        usleep(2_000_000)
        snap("a4_region_trips")

        app.buttons["atlas_substate_back"].firstMatch.tap()
        usleep(2_500_000)
        snap("a5_back_to_list")

        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        usleep(2_000_000)
        snap("a6_collapsed_by_strip")
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
