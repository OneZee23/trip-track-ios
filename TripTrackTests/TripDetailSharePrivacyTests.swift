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

    // MARK: - `TripDetailView.companionCanLeave` — Fix 3 (companions review, second wave)

    /// THE case the whole affordance exists for: an accepted companion on
    /// someone else's trip earns the «…» → «Покинуть поездку» option.
    func testLeaveOfferedForAcceptedCompanionOnForeignTrip() {
        let myId = UUID()
        let companions = [CompanionItem(accountId: myId, displayName: nil, avatarEmoji: nil, status: .accepted)]
        XCTAssertTrue(TripDetailView.companionCanLeave(isOwn: false, myAccountId: myId, companions: companions))
    }

    /// The owner of the trip is never offered "leave" — they aren't a
    /// companion of their own trip regardless of what the roster contains.
    func testLeaveNotOfferedForOwnTrip() {
        let myId = UUID()
        let companions = [CompanionItem(accountId: myId, displayName: nil, avatarEmoji: nil, status: .accepted)]
        XCTAssertFalse(TripDetailView.companionCanLeave(isOwn: true, myAccountId: myId, companions: companions))
    }

    /// A signed-out viewer (no account id to match against the roster)
    /// must never be offered the affordance.
    func testLeaveNotOfferedWhenSignedOut() {
        let companions = [CompanionItem(accountId: UUID(), displayName: nil, avatarEmoji: nil, status: .accepted)]
        XCTAssertFalse(TripDetailView.companionCanLeave(isOwn: false, myAccountId: nil, companions: companions))
    }

    /// A still-PENDING invite (not yet accepted) must not offer "leave" —
    /// there is nothing to leave yet, and the server's own `/companions/
    /// remove` self-branch is for an existing companion relationship.
    func testLeaveNotOfferedForPendingInvite() {
        let myId = UUID()
        let companions = [CompanionItem(accountId: myId, displayName: nil, avatarEmoji: nil, status: .pending)]
        XCTAssertFalse(TripDetailView.companionCanLeave(isOwn: false, myAccountId: myId, companions: companions))
    }

    /// A stranger viewing a foreign trip (their id isn't in the roster at
    /// all) must not be offered "leave".
    func testLeaveNotOfferedForStranger() {
        let myId = UUID()
        let companions = [CompanionItem(accountId: UUID(), displayName: nil, avatarEmoji: nil, status: .accepted)]
        XCTAssertFalse(TripDetailView.companionCanLeave(isOwn: false, myAccountId: myId, companions: companions))
    }
}

/// The reaction row's ordering.
///
/// It only became worth pinning when the detail screen learned to re-read the
/// trip it is showing: the row is rebuilt from that re-read, so an ordering
/// that is not total lets equally popular reactions swap places on a pull to
/// refresh — the tally appearing to change when nothing has.
final class ReactionTalliesOrderTests: XCTestCase {
    func test_most_reacted_first() {
        XCTAssertEqual(
            TripDetailView.tallies(["👍": 1, "❤️": 9, "🤯": 4]).map(\.emoji),
            ["❤️", "🤯", "👍"]
        )
    }

    func test_level_reactions_get_a_total_order() {
        // Same tallies, and the only thing that differs between the two calls
        // is the order the dictionary was written in — which is exactly what a
        // re-read varies and what must not reach the screen.
        XCTAssertEqual(
            TripDetailView.tallies(["👍": 1, "❤️": 1, "🤯": 1]).map(\.emoji),
            TripDetailView.tallies(["🤯": 1, "👍": 1, "❤️": 1]).map(\.emoji)
        )
    }

    func test_the_count_still_outranks_the_emoji() {
        // '❤️' sorts ahead of '👍' by code point, so the tiebreak must not be
        // allowed to overturn a genuine lead.
        XCTAssertEqual(
            TripDetailView.tallies(["❤️": 1, "👍": 9]).map(\.emoji),
            ["👍", "❤️"]
        )
    }

    func test_counts_survive_the_sort() {
        XCTAssertEqual(
            TripDetailView.tallies(["👍": 2, "❤️": 5]).map(\.count),
            [5, 2]
        )
    }
}

/// The feed's local-privacy filter, at the level that actually broke: the
/// predicate itself.
///
/// It named `isDeleted`, which `TripEntity` does not have — and CoreData does
/// not answer an unknown key with an empty result, it throws. Every launch
/// that reached the feed took the app down with it. A compiled predicate is
/// only checked against the model at fetch time, so nothing before this test
/// could have caught it.
final class LocallyPrivateTripsFetchTests: XCTestCase {
    func test_predicate_only_names_keys_the_entity_has() throws {
        let model = PersistenceController.shared.container.managedObjectModel
        let entity = try XCTUnwrap(
            model.entitiesByName["TripEntity"], "the model must still have TripEntity"
        )
        let attributes = Set(entity.attributesByName.keys)

        for key in ["id", "isPrivate", "syncStatus"] {
            XCTAssertTrue(
                attributes.contains(key),
                "`locallyPrivateTripIds` filters on `\(key)`, which TripEntity no longer has"
            )
        }
        XCTAssertFalse(
            attributes.contains("isDeleted"),
            "if this ever exists, revisit the filter — soft delete lives in syncStatus"
        )
    }

    func test_fetch_runs_against_the_real_store() {
        // The assertion is that this does not throw: an unsatisfiable id list
        // still compiles and executes the same predicate the feed uses.
        let ids = [UUID(), UUID()]
        XCTAssertTrue(TripManager.locallyPrivateTripIds(among: ids).isEmpty)
    }

    func test_empty_input_short_circuits() {
        XCTAssertTrue(TripManager.locallyPrivateTripIds(among: []).isEmpty)
    }
}

/// The gate that decides whether a photo delete is allowed to leave the
/// device with Cloud Sync OFF.
///
/// It used to answer by looking the photo up in CoreData — from inside a call
/// that runs AFTER the row has been deleted. The lookup could only ever fail,
/// the gate fails closed, and so a deleted photo was never deleted on the
/// server: it stayed public, and every screen that reads the server's roster
/// put it back on the trip. These pin the answer to what the caller read off
/// the row while it still existed.
final class PhotoDeleteEnqueueGateTests: XCTestCase {
    private func gate(_ hasServerCopy: Bool?) -> Bool {
        SyncEnqueuer.allowsPhotoDelete(
            hasServerCopy: hasServerCopy,
            cloudSyncEnabled: false,
            lookup: { nil as Bool? }  // the row is gone — exactly the real situation
        )
    }

    func test_photo_that_was_on_the_server_is_deleted_there_too() {
        XCTAssertTrue(gate(true))
    }

    func test_photo_that_never_reached_the_server_stays_local() {
        XCTAssertFalse(gate(false))
    }

    func test_without_an_answer_it_still_fails_closed() {
        // No caller-supplied answer and no row to read: deny, as before.
        XCTAssertFalse(gate(nil))
    }

    func test_cloud_sync_on_needs_no_gate_at_all() {
        XCTAssertTrue(
            SyncEnqueuer.allowsPhotoDelete(
                hasServerCopy: nil, cloudSyncEnabled: true, lookup: { nil as Bool? }
            )
        )
    }
}
