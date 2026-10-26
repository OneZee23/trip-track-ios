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

    private func launchOwn(theme: String = "light", extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += common + ["-appThemeMode", theme, "-seed-map-demo", "-seed-garage-demo", "-seed-garage-reset", "-seed-profile-card"] + extra
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
