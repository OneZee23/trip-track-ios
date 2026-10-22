import XCTest

@MainActor
final class VehicleCatalogPickerShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate(); app = nil }

    func testPickExactPoloAndSaveSpecCapsule() {
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-seed-garage-demo", "-debug-plus",
        ]
        app.launch()
        tap("tab_profile", timeout: 30)
        tap("garage_header_vehicle", timeout: 30)
        tap("garage_vehicle_actions", timeout: 15)
        tap("Редактировать")
        XCTAssertTrue(app.buttons["vehicle_form_close"].firstMatch.waitForExistence(timeout: 5))
        let open = app.buttons["vehicle_catalog_open"].firstMatch
        for _ in 0..<6 {
            if open.isHittable && open.frame.maxY < 650 { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(open.isHittable)
        open.tap()
        let search = app.textFields["catalog_search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        let count = (search.value as? String)?.count ?? 0
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + "polo 2018")
        let model = app.buttons["catalog_model_volkswagen-polo"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "есть 2018"))
            .firstMatch.waitForExistence(timeout: 5))
        capture("picker-1-search")
        model.tap()
        let generation = "catalog_generation_volkswagen-polo-sedan-2015"
        XCTAssertTrue(app.buttons[generation].firstMatch.waitForExistence(timeout: 5))
        capture("picker-2-generation")
        tap(generation)
        let year = app.buttons["catalog_year_2018"].firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        XCTAssertTrue(year.isSelected)
        capture("picker-3-year")
        tap("catalog_year_continue")
        let variant = "catalog_variant_volkswagen-polo-sedan-2015-16-110-at6"
        XCTAssertTrue(app.buttons[variant].firstMatch.waitForExistence(timeout: 5))
        capture("picker-4-variant")
        tap(variant)
        tap("vehicle_form_save")
        let capsule = app.staticTexts["vehicle_catalog_spec"].firstMatch
        XCTAssertTrue(capsule.waitForExistence(timeout: 10))
        XCTAssertTrue(capsule.label.contains("110"), capsule.label)
        capture("picker-5-done")
    }

    private func tap(_ id: String, timeout: TimeInterval = 5) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), id)
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
