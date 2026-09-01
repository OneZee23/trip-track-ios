import XCTest
@testable import TripTrack

/// The profile push is the ONLY writer of the server's `display_name`, and it
/// used to be fired exactly once, fire-and-forget. When the server rejected it
/// — eight prod accounts hit `VALIDATION_FAILED` on an unlisted `language` in
/// August 2026 — the name never landed, and nothing ever tried again: the
/// launch-time retry asked "do I have a name in the Keychain?", which is a
/// question about THIS phone, not about the server. The name was right there,
/// so the retry stayed silent and the user rendered as «Пользователь» to
/// everyone but themselves.
///
/// Same family as `BackfillLatchTests`: a latch that reads a local accident as
/// a finished decision. The latch has to record what the SERVER confirmed.
final class ProfileSyncLatchTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "profile-sync-\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    // MARK: - The regression

    /// The bug, in one assertion. A name on the phone says nothing about
    /// whether the server ever accepted it.
    func testPushesWhenTheNameIsLocalButTheServerNeverConfirmedIt() {
        ProfileSyncLatch.markUnconfirmed(defaults)

        XCTAssertTrue(
            ProfileSyncLatch.needsPush(isSignedIn: true, localName: "Дерзкий Гонщик 472", defaults: defaults),
            "a rejected push must be retried even though the Keychain has a name"
        )
    }

    /// The upgrade path for accounts already broken in prod: they predate the
    /// latch entirely, so «no record» must mean «not confirmed», never «done».
    func testTreatsAnAbsentRecordAsUnconfirmed() {
        XCTAssertTrue(
            ProfileSyncLatch.needsPush(isSignedIn: true, localName: "Клаус", defaults: defaults),
            "never-recorded must not be mistaken for confirmed, or already-broken accounts stay broken"
        )
    }

    // MARK: - Staying quiet when there is nothing to do

    func testDoesNotPushOnceTheServerConfirmed() {
        ProfileSyncLatch.markConfirmed(defaults)

        XCTAssertFalse(
            ProfileSyncLatch.needsPush(isSignedIn: true, localName: "Клаус", defaults: defaults),
            "a confirmed profile must not re-push on every launch"
        )
    }

    func testDoesNotPushWhenSignedOut() {
        XCTAssertFalse(
            ProfileSyncLatch.needsPush(isSignedIn: false, localName: nil, defaults: defaults),
            "a guest has no account to push to"
        )
    }

    // MARK: - The pre-existing behaviour this must not lose

    func testPushesWhenThereIsNoNameAtAll() {
        ProfileSyncLatch.markConfirmed(defaults)

        XCTAssertTrue(
            ProfileSyncLatch.needsPush(isSignedIn: true, localName: nil, defaults: defaults),
            "a missing name still needs generating and pushing, confirmed or not"
        )
    }

    func testTreatsAWhitespaceOnlyNameAsMissing() {
        ProfileSyncLatch.markConfirmed(defaults)

        XCTAssertTrue(
            ProfileSyncLatch.needsPush(isSignedIn: true, localName: "   ", defaults: defaults),
            "whitespace is not a name"
        )
    }

    // MARK: - The latch flips both ways

    func testAFailedPushAfterAGoodOneReopensTheLatch() {
        ProfileSyncLatch.markConfirmed(defaults)
        ProfileSyncLatch.markUnconfirmed(defaults)

        XCTAssertTrue(
            ProfileSyncLatch.needsPush(isSignedIn: true, localName: "Клаус", defaults: defaults),
            "a later rejection must reopen the latch, not be shadowed by an old success"
        )
    }

    /// Sign-out hands the phone to whoever signs in next; a stale «confirmed»
    /// would suppress the new account's very first push.
    func testResetClearsTheRecord() {
        ProfileSyncLatch.markConfirmed(defaults)
        ProfileSyncLatch.reset(defaults)

        XCTAssertTrue(
            ProfileSyncLatch.needsPush(isSignedIn: true, localName: "Клаус", defaults: defaults),
            "a new identity inherits nothing from the previous one"
        )
    }
}
