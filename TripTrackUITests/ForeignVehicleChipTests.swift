import XCTest

/// Чужая машина на экране чужой поездки открывает свою страницу (0.9.0).
///
/// Владелец 12 окт 2026: «в деталке чужой поездки нажимать на чужую машину и
/// переходить к ней в детализацию, смотреть, что это за машина». Своя машина
/// так открывалась с 0.6.4; чужая была голой подписью. Сервер с 0.9.0 кладёт
/// в карточку ленты id машины — там же, где имя, только у открытой другим.
///
/// Офлайн: `-debug-foreign-trip` — чужая поездка в ленте, её машина
/// «Jolion» с id, и страница этой машины.
final class ForeignVehicleChipTests: XCTestCase {
    func testForeignCarChipOpensTheCarPage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()

        let chip = app.buttons["detail_foreign_vehicle"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "the foreign car is not a button")
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "foreign_trip_vehicle_chip"
        before.lifetime = .keepAlways
        add(before)
        chip.tap()

        // The car page: its name, and the year and model only it shows.
        XCTAssertTrue(app.staticTexts["Jolion"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["detail_foreign_vehicle"].firstMatch.isHittable,
                       "still on the trip screen")
        sleep(1)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "foreign_vehicle_page"
        after.lifetime = .keepAlways
        add(after)
    }
}
