import XCTest
@testable import TripTrack

/// Coverage for `CompanionsStore`'s persistence of `respondedTripIds` — the
/// fix for "an answered invitation comes back to life after a relaunch":
/// a `companion_invite` a user already accepted/declined must stay
/// answered across an app relaunch (iOS evicts backgrounded apps
/// routinely), not just for the lifetime of one `CompanionsStore` instance.
/// `CompanionsStore.init` is no longer `private` specifically so this suite
/// can construct a SECOND instance independent of `.shared` and prove
/// restoration happens in `init` itself, not merely "the same object
/// remembers what it was told" (a bug confined to `init` couldn't be
/// exposed by testing `.shared` alone, since `.shared` is constructed
/// exactly once per test run).
@MainActor
final class CompanionsStorePersistenceTests: XCTestCase {

    private let defaultsKey = "com.triptrack.companions.respondedTripIds"
    /// Fix 1's companion key — see `CompanionsStore.respondedInvitationIds`.
    private let invitationDefaultsKey = "com.triptrack.companions.respondedInvitationIds"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: invitationDefaultsKey)
        super.tearDown()
    }

    /// The actual regression: write the same wire shape `respond` persists
    /// (`[tripId.uuidString: CompanionStatus.rawValue]`) directly to
    /// `UserDefaults`, THEN construct a fresh store and confirm it comes up
    /// already knowing the answer instead of blank. Fails if `init` stops
    /// calling `loadRespondedTripIds`, or that function stops reading the
    /// same key/shape `persistRespondedTripIds` writes.
    func testPersistedResponseSurvivesFreshStoreInstance() {
        let tripId = UUID()
        UserDefaults.standard.set(
            [tripId.uuidString: CompanionStatus.accepted.rawValue], forKey: defaultsKey)

        let freshStore = CompanionsStore()

        XCTAssertEqual(freshStore.respondedStatus(for: tripId), .accepted)
    }

    /// Baseline the test above contrasts against: with nothing persisted,
    /// a fresh store reads nil (not, say, `.pending` or a crash) for an
    /// arbitrary trip id — proves the restore path doesn't manufacture
    /// answers out of thin air.
    func testUnansweredTripReadsNilAfterFreshStoreInstance() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        let freshStore = CompanionsStore()
        XCTAssertNil(freshStore.respondedStatus(for: UUID()))
    }

    /// A corrupt or unrecognized persisted entry (not a valid UUID string,
    /// or a status int a future app version added that this build doesn't
    /// know about) must be dropped rather than crashing construction or
    /// poisoning the rest of the restore. Fails if `loadRespondedTripIds`
    /// starts force-unwrapping instead of using `UUID(uuidString:)` /
    /// `CompanionStatus(rawValue:)`'s failable initializers.
    func testCorruptEntryIsDroppedNotCrashing() {
        UserDefaults.standard.set(["not-a-uuid": 1, UUID().uuidString: 99], forKey: defaultsKey)
        let freshStore = CompanionsStore()
        XCTAssertTrue(freshStore.respondedTripIds.isEmpty)
    }

    // MARK: - Fix 1: a re-invitation for the same trip is answerable

    /// THE regression Fix 1 closes: `respondedTripIds` alone is keyed by
    /// TRIP, so once an invite is declined, the owner deletes the row and
    /// invites the same person again — a genuinely NEW `trip_companion`
    /// row, surfaced as a NEW notification with a NEW id — the OLD verdict
    /// used to leak onto the new invitation forever (same trip id, so the
    /// same dictionary entry), making its decision card permanently
    /// "already answered" with dead buttons. Seeds BOTH persisted keys
    /// directly (mirroring `testPersistedResponseSurvivesFreshStoreInstance`'s
    /// technique) so this is a restore-time proof, not merely "the same
    /// object remembers what it was told this session". Fails if
    /// `respondedStatus(for:notificationId:)` stops comparing
    /// `notificationId` against `respondedInvitationIds[tripId]` (e.g. if
    /// it's simplified back down to the trip-only lookup).
    func testFreshInvitationAfterDeclineIsAnswerable() {
        let tripId = UUID()
        let declinedNotificationId = UUID()
        let freshNotificationId = UUID()
        UserDefaults.standard.set(
            [tripId.uuidString: CompanionStatus.declined.rawValue], forKey: defaultsKey)
        UserDefaults.standard.set(
            [tripId.uuidString: declinedNotificationId.uuidString], forKey: invitationDefaultsKey)

        let freshStore = CompanionsStore()

        // A fresh invitation (a DIFFERENT notification id) for the same
        // trip must read as unanswered — answerable again.
        XCTAssertNil(freshStore.respondedStatus(for: tripId, notificationId: freshNotificationId))
    }

    /// Baseline contrast: the SAME notification id that was actually
    /// answered must still read back its recorded verdict — proves the
    /// test above isn't passing because `respondedStatus(for:
    /// notificationId:)` always returns `nil`.
    func testSameInvitationRespondedStatusPersists() {
        let tripId = UUID()
        let notificationId = UUID()
        UserDefaults.standard.set(
            [tripId.uuidString: CompanionStatus.declined.rawValue], forKey: defaultsKey)
        UserDefaults.standard.set(
            [tripId.uuidString: notificationId.uuidString], forKey: invitationDefaultsKey)

        let freshStore = CompanionsStore()

        XCTAssertEqual(freshStore.respondedStatus(for: tripId, notificationId: notificationId), .declined)
    }
}
