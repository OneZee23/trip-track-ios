import StoreKitTest
import XCTest

/// Uses the actual StoreKit purchase callback and the shipped product catalog.
/// Run on an isolated simulator with API_BASE_URL=http://127.0.0.1:1 at build
/// time: this flow needs neither an Apple account nor a backend login.
@MainActor
final class ProPurchaseNavigationTests: XCTestCase {
    private var app: XCUIApplication!
    private var store: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let configuration = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "TripTrack", withExtension: "storekit"),
            "The UI test bundle must include Config/TripTrack.storekit")
        store = try SKTestSession(contentsOf: configuration)
        store.resetToDefaultState()
        store.clearTransactions()
        store.disableDialogs = true
        store.timeRate = .realTime
        store.storefront = "DEU"

        app = XCUIApplication()
        // This flag exposes the storefront but does NOT grant an entitlement.
        // Buying and unlocking premium tiles must go through real StoreKit.
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-selectedTabV2", "profile", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL", "-debug-pro-store"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        store?.clearTransactions()
        store?.resetToDefaultState()
        app = nil
        store = nil
    }

    func testBuyingProOpensBackgroundPickerAndPersistsPremiumSelection() {
        buyYearlyFromProfile()
        tap("pro_bought_pick_bg")

        let showcase = element("pro_showcase_photo.artframe")
        XCTAssertTrue(showcase.waitForExistence(timeout: 10),
                      "Choose profile background must open the picker, not dismiss the paywall")
        assertAbsent(button("pro_bought_pick_bg"))

        // Choose a different background if this simulator already saved Nebula.
        // Reopening the picker then distinguishes a saved change from its local
        // try-on state; relaunching also verifies UserDefaults persistence.
        let nebula = button("pro_tile_plus_nebula")
        reveal(nebula)
        let chosenID = nebula.isSelected ? "pro_tile_plus_lava" : "pro_tile_plus_nebula"
        let chosen = button(chosenID)
        reveal(chosen)
        chosen.tap()
        XCTAssertTrue(chosen.isSelected)
        tap("pro_showcase_action")
        assertAbsent(showcase)

        app.terminate()
        app.launch()
        openProfile()
        let avatar = button("profile_avatar")
        reveal(avatar, upwards: false)
        avatar.tap()
        XCTAssertTrue(element("my_profile_screen").waitForExistence(timeout: 10))
        let backgroundRow = button("my_profile_row_background")
        reveal(backgroundRow)
        backgroundRow.tap()
        XCTAssertTrue(showcase.waitForExistence(timeout: 10))
        let saved = button(chosenID)
        reveal(saved)
        // Persistence and entitlement loading are separate: the saved ID is
        // read synchronously, but StoreKit may still be resolving rights after
        // a cold launch. Wait for the real selected tile, without injecting PRO.
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: saved)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 30), .completed,
                       "Premium background chosen after purchase must survive relaunch\n\(app.debugDescription)")
        assertAbsent(element("plus_paywall"))
    }

    func testLaterClosesPurchaseSuccessWithoutOpeningBackgroundPicker() {
        buyYearlyFromProfile()
        tap("pro_bought_later")
        assertAbsent(button("pro_bought_pick_bg"))
        assertAbsent(element("plus_paywall"))
        assertAbsent(element("pro_showcase_photo.artframe"))
        XCTAssertTrue(button("tab_profile").isHittable,
                      "Later should return to the profile with working navigation")
    }

    private func buyYearlyFromProfile() {
        openProfile()
        let sections = button("profile_sections_toggle")
        if sections.exists { reveal(sections); sections.tap() }
        let pro = button("profile_plus_row")
        reveal(pro)
        pro.tap()
        XCTAssertTrue(element("plus_paywall").waitForExistence(timeout: 10))
        XCTAssertTrue(element("pro_plans").waitForExistence(timeout: 15),
                      "The local StoreKit session must supply subscription products")
        tap("plus_buy")
        // SwiftUI exposes this screen under the enclosing plus_paywall
        // identifier. Its actionable success button is a stable UI boundary.
        XCTAssertTrue(button("pro_bought_pick_bg").waitForExistence(timeout: 20),
                      "A completed StoreKit purchase must offer profile customization\n\(app.debugDescription)")
        XCTAssertTrue(store.allTransactions().contains {
            $0.productIdentifier == "com.onezee.TripTrack.pro.yearly" && $0.state == .purchased
        }, "The test must buy the yearly product, not inject a fake PRO state")
    }

    private func openProfile() {
        tap("tab_profile")
        XCTAssertTrue(button("profile_avatar").waitForExistence(timeout: 10))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func button(_ identifier: String) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    private func tap(_ identifier: String) {
        let target = button(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), identifier)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"),
            object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, identifier)
        target.tap()
    }

    private func reveal(_ target: XCUIElement, upwards: Bool = true) {
        for _ in 0..<10 {
            if target.exists && target.isHittable { return }
            if upwards { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(target.exists && target.isHittable, target.identifier)
    }

    private func assertAbsent(_ target: XCUIElement) {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, target.identifier)
    }
}
