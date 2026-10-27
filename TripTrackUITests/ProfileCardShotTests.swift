import XCTest

@MainActor
final class ProfileCardShotTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    private var common: [String] {
        ["-hasCompletedOnboarding", "<true/>", "-appLanguage", "ru",
         "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-profileHistoryMode", "list"]
    }

    func testOwnProfileCard() {
        launchOwn()
        let counter = app.staticTexts["profile_cover_counter"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 30))
        XCTAssertEqual(counter.label, "1 / 4")
        XCTAssertTrue(app.staticTexts["profile_bio"].firstMatch.exists)
        XCTAssertTrue(app.buttons["garage_header_vehicle"].firstMatch.exists)
        XCTAssertTrue(app.buttons["profile_gear"].firstMatch.exists)
        capture("own-first-light")
        app.buttons["profile_photo_0"].firstMatch.swipeLeft()
        XCTAssertTrue(counter.waitForExistence(timeout: 5))
        XCTAssertEqual(counter.label, "2 / 4")
        app.buttons["profile_photo_1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["photo_viewer_main"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["photo_viewer_counter"].firstMatch.label, "2 / 4")
        XCTAssertTrue(app.buttons["photo_viewer_add"].firstMatch.exists)
        XCTAssertTrue(app.buttons["photo_viewer_delete"].firstMatch.exists)
        app.buttons["photo_viewer_main"].firstMatch.tap()
        app.buttons["photo_viewer_close"].firstMatch.tap()
        XCTAssertEqual(counter.label, "1 / 4", "Choosing a cover resets the synced pager order")
        XCTAssertFalse(app.staticTexts["Витрина"].exists)
        app.buttons["profile_photo_0"].firstMatch.tap()
        let add = app.buttons["photo_viewer_add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5), "Add from viewer opens the photo picker after dismissal")
    }

    func testOwnDarkCover() {
        launchOwn(theme: "dark")
        XCTAssertTrue(app.staticTexts["profile_cover_counter"].firstMatch.waitForExistence(timeout: 30))
        capture("own-first-dark")
    }

    func testOwnWithoutPhotos() {
        launchOwn(extra: ["-seed-profile-no-cover"])
        let add = app.buttons["profile_photos_add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["profile_cover_counter"].exists)
        XCTAssertTrue(app.buttons["profile_gear"].firstMatch.exists)
        capture("own-without-photos")
        add.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5), "The native photo picker opens")
    }

    func testRoadDawnLight() { roadFrame(time: "dawn", theme: "light", sky: 0xF3BF9F) }
    func testRoadDayLight() { roadFrame(time: "day", theme: "light", sky: 0x74CAD7) }
    func testRoadSunsetLight() { roadFrame(time: "sunset", theme: "light", sky: 0x5B4373) }
    func testRoadNightLight() { roadFrame(time: "night", theme: "light", sky: 0x243450) }
    func testRoadDawnDark() { roadFrame(time: "dawn", theme: "dark", sky: 0xF3BF9F) }
    func testRoadDayDark() { roadFrame(time: "day", theme: "dark", sky: 0x74CAD7) }
    func testRoadSunsetDark() { roadFrame(time: "sunset", theme: "dark", sky: 0x5B4373) }

    /// Машина с фото: снимок занимает всю полосу, сцены вокруг нет (вариант А
    /// 27 окт 2026). В углу полосы — небо самого снимка, а не ночное.
    func testRoadPhotoFillsTheBand() {
        launchOwn(theme: "dark", extra: ["-seed-profile-no-cover", "-debug-road-time", "night", "-seed-garage-photo"])
        XCTAssertTrue(app.buttons["profile_photos_add"].firstMatch.waitForExistence(timeout: 30))
        assertSky(0x8FB3CF)
        capture("road-photo-night-dark")
    }
    func testRoadNightDark() { roadFrame(time: "night", theme: "dark", sky: 0x243450) }

    func testRoadYieldsToChosenFreeBackground() {
        backgroundFrame(background: "ocean", extra: [], name: "chosen-free-ocean")
    }

    func testRoadYieldsToChosenProBackground() {
        backgroundFrame(background: "plus_nebula", extra: ["-debug-plus"], name: "chosen-pro-nebula")
    }

    func testRoadAtAccessibilitySize() {
        launchOwn(extra: ["-seed-profile-no-cover", "-debug-road-time", "day",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let bio = app.staticTexts["profile_bio"].firstMatch
        XCTAssertTrue(bio.waitForExistence(timeout: 30))
        let vehicle = app.buttons["garage_header_vehicle"].firstMatch
        XCTAssertTrue(vehicle.exists)
        XCTAssertGreaterThanOrEqual(vehicle.frame.minY, bio.frame.maxY)
        reveal(app.buttons["profile_stats_strip"].firstMatch)
        XCTAssertTrue(app.buttons["profile_stats_strip"].firstMatch.isHittable)
        capture("road-accessibility")
        reveal(vehicle)
        vehicle.tap()
        XCTAssertTrue(app.buttons["vehicle_level_row"].firstMatch.waitForExistence(timeout: 15))
    }

    func testForeignDefaultRoad() {
        app = XCUIApplication()
        app.launchArguments += common + ["-appThemeMode", "light", "-debug-foreign-trip",
                                         "-debug-foreign-profile", "free", "-debug-road-time", "day"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        preview.tap()
        let author = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 15))
        author.tap()
        XCTAssertTrue(app.buttons["garage_header_vehicle"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["profile_cover_counter"].exists)
        assertSky(0x74CAD7)
        capture("road-foreign-day")
    }

    private func roadFrame(time: String, theme: String, sky: UInt32) {
        launchOwn(theme: theme, extra: ["-seed-profile-no-cover", "-debug-road-time", time])
        XCTAssertTrue(app.buttons["profile_photos_add"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["profile_cover_counter"].exists)
        XCTAssertTrue(app.staticTexts["profile_bio"].firstMatch.exists)
        assertSky(sky)
        capture("road-\(time)-\(theme)")
    }

    private func backgroundFrame(background: String, extra: [String], name: String) {
        launchOwn(background: background, extra: ["-seed-profile-no-cover", "-debug-road-time", "day"] + extra)
        XCTAssertTrue(app.buttons["profile_photos_add"].firstMatch.waitForExistence(timeout: 30))
        let color = skyPixel()
        XCTAssertLessThan(color.r + color.g + color.b, 1, "Выбранный фон сохраняет прежнее затемнение")
        capture(name)
    }

    private func assertSky(_ hex: UInt32) {
        let color = skyPixel()
        XCTAssertEqual(color.r, Double((hex >> 16) & 255) / 255, accuracy: 0.025)
        XCTAssertEqual(color.g, Double((hex >> 8) & 255) / 255, accuracy: 0.025)
        XCTAssertEqual(color.b, Double(hex & 255) / 255, accuracy: 0.025)
    }

    private func skyPixel() -> (r: Double, g: Double, b: Double) {
        usleep(700_000)
        let header = app.buttons["garage_header_vehicle"].firstMatch
        XCTAssertTrue(header.exists)
        let shot = XCUIScreen.main.screenshot()
        let scale = shot.image.scale
        let point = CGRect(x: (header.frame.minX + 8) * scale, y: (header.frame.minY + 8) * scale,
                           width: 1, height: 1)
        guard let cg = shot.image.cgImage?.cropping(to: point) else {
            XCTFail("Не удалось прочитать сцену"); return (0, 0, 0)
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    /// Приглашение «Добавить обложку» скрывается крестиком, а дверь к обложке
    /// остаётся в «Мой профиль» (TestFlight 0.9.2 (96)).
    func testCoverPromptCanBeHidden() {
        launchOwn(extra: ["-seed-profile-no-cover"])
        let add = app.buttons["profile_photos_add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 30))
        app.buttons["profile_photos_add_hide"].firstMatch.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: add)
        wait(for: [gone], timeout: 5)
        capture("own-cover-prompt-hidden")
    }

    func testPinnedFirstAndRoutineExpansion() {
        launchOwn(extra: ["-seed-profile-journal"])
        XCTAssertTrue(app.staticTexts["profile_cover_counter"].firstMatch.waitForExistence(timeout: 30))
        let scroll = app.scrollViews.firstMatch
        reveal(app.staticTexts["profile_trip_pinned"].firstMatch)
        let firstCard = app.buttons["profile_trip_card"].firstMatch
        XCTAssertTrue(firstCard.exists)
        XCTAssertTrue(firstCard.label.contains("Закреплено"))
        let fold = app.buttons["profile_routine_toggle"].firstMatch
        reveal(fold)
        align(fold, top: 132)
        capture("journal-folded")
        let declaredCount = fold.label.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first ?? 0
        XCTAssertGreaterThan(declaredCount, 7)
        fold.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profile_routine_trip_"))
        XCTAssertEqual(rows.count, 7)
        reveal(fold)
        align(fold, top: 132)
        capture("journal-expanded")
        let more = app.buttons["profile_routine_more"].firstMatch
        reveal(more)
        XCTAssertEqual(more.label, "Ещё \(declaredCount - 7)")
        more.tap()
        XCTAssertEqual(rows.count, declaredCount)
        reveal(rows.firstMatch)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["detail_title"].firstMatch.waitForExistence(timeout: 10))
        _ = scroll
    }

    func testForeignProfileCard() {
        app = XCUIApplication()
        app.launchArguments += common + ["-appThemeMode", "light", "-debug-foreign-trip", "-debug-foreign-profile", "pro"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 30))
        preview.tap()
        let author = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(author.waitForExistence(timeout: 15))
        author.tap()
        let counter = app.staticTexts["profile_cover_counter"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 20))
        XCTAssertEqual(counter.label, "1 / 5")
        XCTAssertTrue(app.buttons["profile_followers"].firstMatch.exists)
        XCTAssertTrue(app.buttons["profile_following"].firstMatch.exists)
        XCTAssertTrue(app.buttons["profile_follow"].firstMatch.exists)
        capture("foreign-first")
        app.buttons["profile_photo_0"].firstMatch.tap()
        let close = app.buttons["photo_viewer_close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["photo_viewer_counter"].firstMatch.label, "1 / 5")
        XCTAssertFalse(app.buttons["photo_viewer_delete"].exists)
        XCTAssertFalse(app.buttons["photo_viewer_main"].exists)
        XCTAssertFalse(app.buttons["photo_viewer_add"].exists)
        close.tap()
        reveal(app.staticTexts["profile_trip_pinned"].firstMatch)
        XCTAssertTrue(app.buttons["profile_trip_card"].firstMatch.label.contains("Закреплено"))
        XCTAssertFalse(app.staticTexts["Витрина"].exists)
        XCTAssertFalse(app.buttons["profile_photos_add"].exists)
        capture("foreign-pinned")
    }

    private func launchOwn(theme: String = "light", background: String = "", extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += common + ["-appThemeMode", theme, "-seed-map-demo", "-seed-garage-demo", "-seed-garage-reset",
                                         "-seed-profile-card", "-com.triptrack.settings.profileBackground", background] + extra
        app.launch()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<18 {
            if target.exists, target.frame.minY > 70, target.frame.maxY < app.frame.height - 115 { return }
            if target.exists && target.frame.minY <= 70 {
                app.scrollViews.firstMatch.swipeDown(velocity: .slow)
            } else {
                app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(target.exists)
        XCTAssertTrue(target.isHittable)
    }

    private func align(_ target: XCUIElement, top: CGFloat) {
        let delta = target.frame.minY - top
        guard abs(delta) > 4 else { return }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.65))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -delta)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func capture(_ name: String) {
        usleep(700_000)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "profile-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
