import XCTest

@MainActor
final class GarageProfileShotTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    func testOwnGarageScreensAndModPersistence() {
        launchOwn()
        let header = app.buttons["garage_header_vehicle"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 30))
        capture("01-own-header")
        header.tap()
        XCTAssertTrue(app.buttons["vehicle_level_row"].firstMatch.waitForExistence(timeout: 15))
        capture("03-car-top")
        reveal("garage_mileage", top: 138)
        capture("04-mileage-regions-photos")
        reveal("garage_trip_photos")
        app.buttons["garage_trip_photos"].firstMatch.tap()
        let photo = app.buttons["garage_photo_0"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        // Seeded photos are 4:3; a fill image framed only by height spilled
        // into the next cell (owner on device, 23 Oct 2026).
        let next = app.buttons["garage_photo_1"].firstMatch
        if next.exists {
            XCTAssertLessThanOrEqual(photo.frame.maxX, next.frame.minX + 0.5)
            XCTAssertEqual(photo.frame.width, next.frame.width, accuracy: 0.5)
        }
        capture("04b-trip-photos-grid")
        photo.tap()
        let closePhoto = app.buttons["photo_viewer_close"].firstMatch
        XCTAssertTrue(closePhoto.waitForExistence(timeout: 5))
        closePhoto.tap()
        app.buttons["Назад"].firstMatch.tap()
        reveal("garage_mods")
        capture("05-mods")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Шумоизоляция дверей")).firstMatch.tap()
        XCTAssertTrue(app.textFields["garage_mod_title"].firstMatch.waitForExistence(timeout: 5))
        capture("07-mod-editor")
        app.buttons["garage_mod_save"].firstMatch.tap()
        app.buttons["garage_add_mod"].firstMatch.tap()
        let title = app.textFields["garage_mod_title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Garage regression\n")
        app.buttons["garage_mod_save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Garage regression"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        launchOwn(reset: false)
        app.buttons["garage_header_vehicle"].firstMatch.tap()
        reveal("garage_mods")
        XCTAssertTrue(app.staticTexts["Garage regression"].firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Garage regression")).firstMatch.tap()
        app.buttons["garage_mod_delete"].firstMatch.tap()
        let confirm = app.buttons["garage_mod_delete_confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["app_dialog"].firstMatch.exists,
            "Deletion uses AppConfirmDialog")
        confirm.tap()
        XCTAssertTrue(app.buttons["garage_add_mod"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Garage regression"].firstMatch.exists)
    }

    func testDrive2SheetValidationAndLocalDisclosure() {
        launchOwn()
        let header = app.buttons["garage_header_vehicle"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 30))
        header.tap()
        XCTAssertTrue(app.buttons["vehicle_level_row"].firstMatch.waitForExistence(timeout: 15))
        let more = app.buttons["garage_vehicle_actions"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Бортжурнал на DRIVE2")).firstMatch.tap()
        let field = app.textViews["garage_drive2_field"].firstMatch
        let textField = app.textFields["garage_drive2_field"].firstMatch
        XCTAssertTrue(app.buttons["garage_drive2_save"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Ссылка останется на этом телефоне"))
                .firstMatch.exists)
        XCTAssertTrue(app.buttons["garage_drive2_save"].firstMatch.isEnabled)
        capture("06-drive2-sheet")
        // Clearing is reversible and does not invoke any system confirmation.
        app.buttons["Отвязать"].firstMatch.tap()
        XCTAssertTrue(app.buttons["garage_drive2_row"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["garage_drive2_row"].firstMatch.tap()
        XCTAssertFalse(app.buttons["garage_drive2_save"].firstMatch.isEnabled)
        let input = textField.exists ? textField : field
        input.tap()
        input.typeText("https://www.drive2.ru/r/volkswagen/polo/123456789/")
        XCTAssertTrue(app.buttons["garage_drive2_save"].firstMatch.isEnabled)
        app.buttons["garage_drive2_save"].firstMatch.tap()
        XCTAssertTrue(app.buttons["garage_drive2_row"].firstMatch.waitForExistence(timeout: 5))
    }

    func testForeignHeaderAndReadOnlyCar() {
        app = XCUIApplication()
        app.launchArguments += common + ["-debug-foreign-trip", "-debug-foreign-profile", "pro"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        preview.tap()
        let author = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 15))
        author.tap()
        let header = app.buttons["garage_header_vehicle"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["profile_follow"].firstMatch.exists)
        capture("02-foreign-header")
        header.tap()
        XCTAssertTrue(
            app.staticTexts["Haval Jolion"].firstMatch.waitForExistence(timeout: 10)
                || app.staticTexts["Haval Jolion кроссовер · 2022"].firstMatch.waitForExistence(timeout: 10))
        capture("08-foreign-car")
        reveal("garage_mods")
        XCTAssertFalse(app.buttons["garage_add_mod"].exists)
        capture("09-foreign-mods")
    }

    func testVehicleCustomizationSavesFinishTagsAndPlatform() {
        launchOwn()
        let header = app.buttons["garage_header_vehicle"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 30))
        header.tap()
        let more = app.buttons["garage_vehicle_actions"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap()
        app.buttons["Редактировать"].firstMatch.tap()
        XCTAssertTrue(app.buttons["vehicle_form_close"].firstMatch.waitForExistence(timeout: 5))
        let finish = app.buttons["garage_finish_row"].firstMatch
        for _ in 0..<8 {
            if finish.isHittable && finish.frame.minY > 130 && finish.frame.maxY < 650 { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(finish.isHittable)
        app.buttons["garage_finish_row"].firstMatch.tap()
        let matte = app.buttons["garage_finish_row_1"].firstMatch
        XCTAssertTrue(matte.waitForExistence(timeout: 5))
        capture("10-finish-picker")
        matte.tap()
        let tag = app.textFields["garage_tag_0"].firstMatch
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.tap()
        let count = (tag.value as? String)?.count ?? 0
        tag.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + "GarageTag\n")
        reveal("vehicle_card_style_row", top: 200)
        app.buttons["vehicle_card_style_row"].firstMatch.tap()
        let gold = app.buttons["pro_tile_card_gold"].firstMatch
        XCTAssertTrue(gold.waitForExistence(timeout: 5))
        gold.tap()
        XCTAssertTrue(gold.isSelected)
        capture("11-platform-showcase")
        app.buttons["pro_showcase_action"].firstMatch.tap()
        app.buttons["vehicle_form_save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["GarageTag"].firstMatch.waitForExistence(timeout: 5))
        capture("12-customized-car")
        app.terminate()
        launchOwn(reset: false)
        app.buttons["garage_header_vehicle"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["GarageTag"].firstMatch.waitForExistence(timeout: 10))
    }

    private var common: [String] {
        [
            "-hasCompletedOnboarding", "<true/>", "-appLanguage", "ru", "-appThemeMode", "light", "-AppleLanguages",
            "(ru)", "-AppleLocale", "ru_RU",
        ]
    }
    private func launchOwn(reset: Bool = true) {
        app = XCUIApplication()
        app.launchArguments += common + ["-seed-garage-demo", "-debug-plus"]
            + (reset ? ["-seed-garage-reset"] : [])
        app.launch()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
    }
    private func reveal(_ id: String, top: CGFloat = 175) {
        let target = app.descendants(matching: .any)[id].firstMatch
        let window = app.windows.firstMatch
        var previousY: CGFloat?
        for _ in 0..<12 {
            let y = target.exists ? target.frame.minY : .infinity
            if target.exists && target.isHittable {
                if abs(y - top) < 25 { return }
                if let previousY, abs(y - previousY) < 1, y > 110, y < 600 { return }
            }
            previousY = y
            let offset = target.exists ? max(-240, min(240, top - y)) : -240
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.55))
            start.press(
                forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(target.exists && target.isHittable, id)
    }
    private func capture(_ name: String) {
        usleep(700_000)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "garage-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
