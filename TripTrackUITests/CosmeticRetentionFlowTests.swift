import StoreKitTest
import XCTest

/// Real purchase → expiry → temporary free choice → paid restoration. StoreKit
/// runs from the bundled configuration; use an isolated simulator with
/// API_BASE_URL=http://127.0.0.1:1. No injected entitlement or network account.
@MainActor
final class CosmeticRetentionFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var store: SKTestSession!
    private let yearlyID = "com.onezee.TripTrack.pro.yearly"
    private let monthlyID = "com.onezee.TripTrack.pro.monthly"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let configuration = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "TripTrack", withExtension: "storekit"))
        store = try SKTestSession(contentsOf: configuration)
        store.resetToDefaultState()
        store.clearTransactions()
        store.disableDialogs = true
        store.timeRate = .realTime
        store.storefront = "DEU"
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-debug-pro-store",
            "-appLanguage", "ru", "-AppleLanguages", "(ru)", "-AppleLocale", "de_DE"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        store?.clearTransactions()
        store?.resetToDefaultState()
        app = nil
        store = nil
    }

    func testExpiredProKeepsTemporaryFreeChoiceAndRestoresLavaAfterMonthlyPurchase() throws {
        openProfile()
        let sections = button("profile_sections_toggle")
        if sections.exists { reveal(sections); sections.tap() }
        reveal(button("profile_plus_row"))
        tap("profile_plus_row")
        waitFor(element("pro_plans"))
        tap("pro_plan_\(yearlyID)")
        tap("plus_buy")
        waitFor(button("pro_bought_pick_bg"), timeout: 20)
        XCTAssertTrue(store.allTransactions().contains {
            $0.productIdentifier == yearlyID && $0.state == .purchased
        })
        tap("pro_bought_pick_bg")
        waitFor(element("pro_showcase_photo.artframe"))
        choose("pro_tile_plus_lava")
        XCTAssertTrue(button("pro_tile_plus_lava").isSelected)
        tap("pro_showcase_action")
        assertAbsent(element("pro_showcase_photo.artframe"))

        // The checked SDK declares this throwing Swift name on SKTestSession.h.
        // Expiry does not require waiting out a simulated month or changing the
        // phone's clock. Foregrounding makes the real PlusStore reread rights.
        try store.expireSubscription(productIdentifier: yearlyID)
        XCUIDevice.shared.press(.home)
        app.activate()
        openBackgroundsFromProfile()
        waitFor(element("pro_showcase_expired"), timeout: 20)
        XCTAssertTrue(element("pro_showcase_expired").label.contains("Lava"),
                      "The expiry card must name the actual saved background")
        XCTAssertEqual(button("pro_showcase_action").label, "Готово",
                       "Opening the expired picker is not a paid try-on")
        choose("pro_tile_ocean")
        XCTAssertTrue(button("pro_tile_ocean").isSelected)
        XCTAssertEqual(button("pro_showcase_action").label, "Готово")
        capture("expired-free-ocean-done")
        tap("pro_showcase_action")
        assertAbsent(element("pro_showcase_photo.artframe"))
        assertAbsent(element("plus_paywall"))

        // Persistence is part of the contract: a restart cannot turn temporary
        // Ocean back into Lava before renewal, nor erase the retained choice.
        app.terminate()
        app.launch()
        openBackgroundsFromProfile()
        waitFor(element("pro_showcase_expired"), timeout: 20)
        reveal(button("pro_tile_ocean"))
        XCTAssertTrue(button("pro_tile_ocean").isSelected)
        choose("pro_tile_plus_lava")
        XCTAssertEqual(button("pro_showcase_action").label, "Продлить")
        tap("pro_showcase_action")
        waitFor(element("pro_plans"))
        tap("pro_plan_\(monthlyID)")
        XCTAssertTrue(button("pro_plan_\(monthlyID)").isSelected)
        tap("plus_buy")
        waitFor(button("pro_bought_later"), timeout: 20)
        XCTAssertTrue(store.allTransactions().contains {
            $0.productIdentifier == monthlyID && $0.state == .purchased
        }, "The restoration must follow an actual new monthly transaction")
        // Do not use the success screen's background picker: renewal itself,
        // through PlusStore, must restore the retained choice.
        tap("pro_bought_later")
        assertAbsent(element("plus_paywall"))
        waitFor(element("my_profile_screen"))
        reveal(button("my_profile_row_background"))
        tap("my_profile_row_background")
        waitFor(element("pro_showcase_photo.artframe"))
        reveal(button("pro_tile_plus_lava"))
        XCTAssertTrue(button("pro_tile_plus_lava").isSelected,
                      "Renewal must restore Lava without choosing it again")
        assertAbsent(element("pro_showcase_expired"))
        XCTAssertEqual(button("pro_showcase_action").label, "Готово")
        capture("renewed-lava-restored")
    }

    private func openProfile() {
        tap("tab_profile")
        waitFor(button("profile_avatar"))
    }

    private func openBackgroundsFromProfile() {
        openProfile()
        reveal(button("profile_avatar"), upwards: false)
        tap("profile_avatar")
        waitFor(element("my_profile_screen"))
        reveal(button("my_profile_row_background"))
        tap("my_profile_row_background")
        waitFor(element("pro_showcase_photo.artframe"))
    }

    private func choose(_ id: String) { reveal(button(id)); tap(id) }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func button(_ id: String) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func waitFor(_ target: XCUIElement, timeout: TimeInterval = 15) {
        XCTAssertTrue(target.waitForExistence(timeout: timeout), target.identifier)
    }

    private func tap(_ id: String) {
        let target = button(id)
        waitFor(target)
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true AND enabled == true"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed, id)
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
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, target.identifier)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
