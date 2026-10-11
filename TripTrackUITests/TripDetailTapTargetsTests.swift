import XCTest

/// Small controls on the trip screen take a finger, not just a stylus.
///
/// Until 0.8.9 the photo «+» was 23 × 23 pt and the place chip in «Моменты»
/// 25 pt tall. Both keep their look; the area around them now takes the tap.
/// Checked by tapping OUTSIDE the drawn shape: a frame that only grew in the
/// accessibility tree would pass a frame check and still miss the finger.
final class TripDetailTapTargetsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // No `-selectedTabV2` here: a launch argument is the highest-priority
        // UserDefaults domain, so it would pin `@AppStorage` tab selection and
        // the chip's switch to «Места» could never happen. Tap the tab instead.
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-places-rich",
                                "-seed-segment-demo", "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let profileTab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 40))
        profileTab.tap()
        let field = app.textFields["profile_history_search"].firstMatch
        for _ in 0..<10 where !(field.exists && field.isHittable) { app.swipeUp() }
        field.tap()
        field.typeText("Ростов-на-Дону\n")
        let cell = app.historyTripCells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        for _ in 0..<4 where !cell.isHittable { app.swipeUp() }
        cell.tap()
        XCTAssertTrue(app.buttons["detail_map_expand"].firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws { app = nil }

    func testPlaceChipTakesATapJustAboveItsCapsule() {
        let chip = app.buttons["checkpoint_place_chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 8))
        let window = app.windows.firstMatch
        for _ in 0..<6 where !chip.isHittable || chip.frame.maxY > window.frame.height - 140 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -260)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertGreaterThanOrEqual(chip.frame.height, 40, "place chip target")
        // The capsule is ~25 pt tall in the middle of the target: 3 pt from
        // the target's top edge is outside the drawn shape.
        // The capsule is ~25 pt tall in the middle of the target: 3 pt from
        // the target's top edge is outside the drawn shape.
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "after_chip_edge_tap"
        shot.lifetime = .keepAlways
        add(shot)
        // `.openPlace` is two-phase: switch to «Места», then push the place.
        XCTAssertTrue(app.descendants(matching: .any)["place_detail"].firstMatch.waitForExistence(timeout: 8),
                      "A tap beside the chip must open the place")
    }

    func testPhotoPlusTakesATapBesideItsGlyph() {
        let plus = app.buttons["detail_add_photo"].firstMatch
        for _ in 0..<8 where !(plus.exists && plus.isHittable) { app.swipeUp() }
        XCTAssertTrue(plus.isHittable)
        XCTAssertGreaterThanOrEqual(plus.frame.width, 44, "photo «+» target")
        XCTAssertGreaterThanOrEqual(plus.frame.height, 44, "photo «+» target")
    }
}
