import XCTest
@testable import TripTrack

/// Coverage for `TripDetailView.canOfferShare` — Task 5 review finding 1.
/// The poster's Share button used to render unconditionally, regardless of
/// ownership or privacy. `SocialService.share` refuses server-side
/// (`TripNotPublic`) when a non-owner tries to share a private trip — there
/// is no data-exposure hole, but offering a button that can only fail is
/// still a defect the client should not present. A companion viewing a
/// genuinely private «Со мной» trip is exactly this case (the whole point
/// of a companion invite is access to a trip that ISN'T public).
final class TripDetailSharePrivacyTests: XCTestCase {

    /// Baseline: your own trip, public — the common case, still offered.
    func testShareOfferedForOwnPublicTrip() {
        XCTAssertTrue(TripDetailView.canOfferShare(isOwn: true, isPrivate: false))
    }

    /// Sharing your own private trip is a legitimate action (it doubles as
    /// "publish and share in one motion" — see `ownerActions`'s privacy
    /// chip); ownership alone must be enough regardless of the privacy flag.
    func testShareOfferedForOwnPrivateTrip() {
        XCTAssertTrue(TripDetailView.canOfferShare(isOwn: true, isPrivate: true))
    }

    /// A stranger (or companion) viewing a PUBLIC trip can share it — the
    /// server has nothing to refuse there.
    func testShareOfferedForSomeoneElsesPublicTrip() {
        XCTAssertTrue(TripDetailView.canOfferShare(isOwn: false, isPrivate: false))
    }

    /// THE rule this finding exists to fix: a non-owner (a companion, most
    /// concretely) viewing a PRIVATE trip must not be offered a Share button
    /// the server can only refuse.
    func testShareNotOfferedForNonOwnersPrivateTrip() {
        XCTAssertFalse(TripDetailView.canOfferShare(isOwn: false, isPrivate: true))
    }
}
