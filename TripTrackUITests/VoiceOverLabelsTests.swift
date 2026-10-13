import XCTest

/// VoiceOver reads words, not file names (0.8.9).
///
/// An `Image(systemName:)` with no label is announced by its symbol name
/// («person.badge.plus», «flag.checkered»), and an asset image by its path
/// («Badges/early_tester»). Both were spoken on the trip screen, the public
/// profile and «Я». A decorative glyph next to its own text is hidden; a
/// meaningful one gets words. This walks those screens and fails on any label
/// shaped like a symbol or asset name.
final class VoiceOverLabelsTests: XCTestCase {
    private static let symbolName = try! NSRegularExpression(pattern: "^[a-z0-9]+(\\.[a-z0-9]+)+$")

    private func isName(_ label: String) -> Bool {
        let range = NSRange(label.startIndex..., in: label)
        return label.hasPrefix("Badges/") || Self.symbolName.firstMatch(in: label, range: range) != nil
    }

    /// Labels VoiceOver actually speaks. A button reads its own label, not the
    /// glyph inside it, so an image within a button that already has words is
    /// skipped — XCUITest still lists that image under its symbol name.
    private func leaks(in app: XCUIApplication) -> [String] {
        let buttons = app.buttons.allElementsBoundByIndex.prefix(400)
            .map { ($0.label, $0.frame) }
        var found = Set<String>()
        for (label, _) in buttons where isName(label) { found.insert(label) }
        for image in app.images.allElementsBoundByIndex.prefix(400) {
            let label = image.label
            guard !label.isEmpty, isName(label) else { continue }
            let frame = image.frame
            let wrapped = buttons.contains { !$0.0.isEmpty && !isName($0.0) && $0.1.contains(frame) }
            if !wrapped { found.insert(label) }
        }
        return found.sorted()
    }

    func testTripScreenSpeaksWords() {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-segment-demo",
                                "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()
        let field = app.textFields["profile_history_search"].firstMatch
        for _ in 0..<10 where !(field.exists && field.isHittable) { app.swipeUp() }
        field.tap()
        field.typeText("Ростов-на-Дону\n")
        let cell = app.historyTripCells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        for _ in 0..<4 where !cell.isHittable { app.swipeUp() }
        cell.tap()
        XCTAssertTrue(app.buttons["detail_map_expand"].firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        app.swipeUp(); app.swipeUp()
        XCTAssertEqual(leaks(in: app), [], "VoiceOver would read these names on the trip screen")
    }

    func testPublicProfileSpeaksWords() {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        XCTAssertTrue(app.staticTexts["profile_display_name"].firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        app.swipeUp()
        XCTAssertEqual(leaks(in: app), [], "VoiceOver would read these names on the public profile")
    }
}
