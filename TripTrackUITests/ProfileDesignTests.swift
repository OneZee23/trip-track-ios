import StoreKitTest
import XCTest

/// Visual and interaction coverage for the 0.8.8 Me/profile/PRO refresh.
/// The StoreKit catalog is local; these tests never purchase a live product.
@MainActor
final class ProfileDesignTests: XCTestCase {
    private var app: XCUIApplication!
    private var store: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let catalog = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TripTrack", withExtension: "storekit"))
        store = try SKTestSession(contentsOf: catalog)
        store.resetToDefaultState()
        store.clearTransactions()
        store.disableDialogs = true
        store.storefront = "USA"
    }

    override func tearDownWithError() throws {
        app?.terminate()
        store?.clearTransactions()
        store?.resetToDefaultState()
    }

    func testLightProfileAndPlanSelection() {
        launch(theme: "light", language: "ru")
        capture("088-me-light-ru")
        tap("profile_avatar")
        XCTAssertTrue(element("my_profile_screen").waitForExistence(timeout: 10))
        capture("088-profile-light-ru")
        tap("my_profile_hero_avatar")
        XCTAssertTrue(app.buttons["🙂"].waitForExistence(timeout: 5))
        capture("088-avatar-choices-light-ru")
        // Collapse without changing the person's avatar.
        tap("my_profile_hero_avatar")
        reveal("my_profile_row_background")
        tap("my_profile_row_background")
        XCTAssertTrue(element("pro_showcase_photo.artframe").waitForExistence(timeout: 10))
        app.terminate()
        launch(theme: "light", language: "ru")
        openPaywall()
        capture("088-pro-light-ru")
        let monthly = button("pro_plan_com.onezee.TripTrack.pro.monthly")
        let yearly = button("pro_plan_com.onezee.TripTrack.pro.yearly")
        XCTAssertTrue(yearly.isSelected)
        monthly.tap()
        XCTAssertTrue(monthly.isSelected)
        XCTAssertFalse(yearly.isSelected)
        yearly.tap()
        XCTAssertTrue(yearly.isSelected)
        assertOfferOnScreen()
        tap("plus_close")
        XCTAssertTrue(button("tab_profile").isHittable)
    }

    func testDarkProfileAndFeaturePreview() {
        launch(theme: "dark", language: "en")
        capture("088-me-dark-en")
        tap("profile_avatar")
        capture("088-profile-dark-en")
        app.terminate()
        launch(theme: "dark", language: "en")
        openPaywall()
        capture("088-pro-dark-en")
        tap("pro_hero")
        // Closing a feature preview returns to the offer, not to Me.
        tap("plus_close")
        XCTAssertTrue(button("pro_hero").waitForExistence(timeout: 10))
        assertOfferOnScreen()
    }

    func testLargeTextKeepsFeaturesAndOfferReachable() {
        launch(theme: "light", language: "de", largeText: true)
        capture("088-me-large-de")
        tap("profile_avatar")
        capture("088-profile-large-de")
        reveal("my_profile_row_stats")
        XCTAssertTrue(button("my_profile_row_stats").isHittable)
        capture("088-profile-fields-large-de")
        app.terminate()
        launch(theme: "light", language: "de", largeText: true)
        openPaywall()
        assertOfferOnScreen()
        let scroll = app.scrollViews["pro_features_scroll"].firstMatch
        XCTAssertTrue(scroll.exists)
        let lastFeature = button("pro_feature_pencil.line")
        for _ in 0..<14 {
            if lastFeature.isHittable && lastFeature.frame.maxY < button("plus_buy").frame.minY - 90 { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(lastFeature.isHittable)
        assertOfferOnScreen()
        capture("088-pro-large-de")
    }

    private func launch(theme: String, language: String, largeText: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "<true/>", "-debug-pro-store",
            "-selectedTabV2", "profile", "-seed-map-demo", "-appLanguage", language, "-appThemeMode", theme]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", largeText
            ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        tap("tab_profile")
        XCTAssertTrue(button("profile_avatar").waitForExistence(timeout: 10))
    }

    private func openPaywall() {
        reveal("profile_sections_toggle")
        tap("profile_sections_toggle")
        reveal("profile_plus_row")
        tap("profile_plus_row")
        XCTAssertTrue(element("pro_plans").waitForExistence(timeout: 20))
        assertOfferOnScreen()
    }

    private func assertOfferOnScreen() {
        let buy = button("plus_buy")
        XCTAssertTrue(buy.isHittable)
        XCTAssertLessThan(buy.frame.maxY, app.frame.maxY)
        let yearly = button("pro_plan_com.onezee.TripTrack.pro.yearly")
        XCTAssertTrue(yearly.isHittable)
        XCTAssertLessThan(yearly.frame.maxY, buy.frame.minY)
        XCTAssertTrue(button("plus_close").isHittable)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func button(_ id: String) -> XCUIElement { app.buttons[id].firstMatch }
    private func tap(_ id: String) {
        let target = button(id)
        XCTAssertTrue(target.waitForExistence(timeout: 15), id)
        XCTAssertTrue(target.isHittable, id)
        target.tap()
    }
    private func reveal(_ id: String) {
        let target = button(id)
        for _ in 0..<16 {
            if target.exists && target.isHittable && target.frame.maxY < app.frame.maxY - 110 { return }
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable, id)
    }
    private func capture(_ name: String) {
        // Navigation is interactive before its transition finishes.
        usleep(650_000)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
