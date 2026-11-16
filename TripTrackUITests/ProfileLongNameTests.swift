import XCTest

/// A long name stays on one line and shrinks to fit beside the PRO badge and
/// the follow button (owner, 5 Nov 2026: a surname broke by letter onto a
/// third line). The fixture name is invented.
final class ProfileLongNameTests: XCTestCase {
    func testALongNameShrinksOntoOneLine() throws {
        try check(variant: "longname", words: ["Ярослав", "Подзаборовский"])
    }

    func testAHugeNameStaysWithinTwoSmallLines() throws {
        try check(variant: "hugename", words: ["Константин", "Преображенский"])
    }

    private func check(variant: String, words: [String]) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", variant, "-appLanguage", "ru", "-appThemeMode", "dark"]
        app.launch()

        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()

        let name = app.buttons["profile_copy_name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(words.allSatisfy { name.label.contains($0) }, name.label)
        // One line at full size or up to two short lines: never three, never a lone letter.
        XCTAssertLessThanOrEqual(name.frame.height, 33, "The name took more room than two small lines")
        let follow = app.buttons["profile_follow"].firstMatch
        if follow.exists { XCTAssertLessThanOrEqual(name.frame.maxX, follow.frame.minX + 1) }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "public_profile_\(variant)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
