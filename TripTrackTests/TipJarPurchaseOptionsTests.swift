import XCTest
import StoreKit
@testable import TripTrack

/// `appAccountToken` is written into the signed transaction and cannot be added
/// afterwards — a purchase made without it stays anonymous for its whole life.
/// These tests pin the rule for choosing it, which is the part that is easy to
/// get wrong later without noticing.
final class TipJarPurchaseOptionsTests: XCTestCase {
    /// `Product.PurchaseOption` compares by KIND, not by value — two
    /// `.appAccountToken`s holding different UUIDs are `==` to each other,
    /// which is how the Set guarantees only one of each kind. So
    /// `contains(.appAccountToken(anything))` proves only that some token is
    /// present, never which one. The UUID is visible only through the
    /// description, so that is what these tests read.
    private func tokenText(_ options: Set<Product.PurchaseOption>) -> String {
        options.map { String(describing: $0) }.sorted().joined()
    }

    func testSignedInPurchaseCarriesTheAccountToken() {
        let accountId = UUID()
        let options = TipJarService.purchaseOptions(accountId: accountId)

        XCTAssertEqual(options.count, 1)
        XCTAssertTrue(
            tokenText(options).lowercased().contains(accountId.uuidString.lowercased()),
            "the option must carry THIS account's id, not merely some token")
    }

    /// Signing in must not be a precondition for tipping. An anonymous purchase
    /// is the honest outcome, not a reason to block the button.
    func testSignedOutPurchaseCarriesNoToken() {
        XCTAssertTrue(TipJarService.purchaseOptions(accountId: nil).isEmpty)
    }

    /// Guards against someone later "simplifying" this to a constant or to
    /// `SettingsManager.localUserId` — which is a CoreData row id and is minted
    /// afresh every time the store is lost. Two different accounts must never
    /// collapse to the same token.
    func testDifferentAccountsProduceDifferentTokens() {
        let a = TipJarService.purchaseOptions(accountId: UUID())
        let b = TipJarService.purchaseOptions(accountId: UUID())

        // Deliberately NOT XCTAssertNotEqual(a, b): see `tokenText` — those
        // two sets ARE equal by StoreKit's rules while carrying different ids.
        XCTAssertNotEqual(tokenText(a), tokenText(b))
    }
}
