import XCTest
@testable import TripTrack

final class LastSyncedAtStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let account = UUID()

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "lsa-\(UUID().uuidString)")
    }

    private var rawDateKey: String { "com.triptrack.sync.lastSyncedAt.\(account)" }
    private var rawStampKey: String { "com.triptrack.sync.lastSyncedAt.\(account).store" }

    func testCursorSurvivesWhenTheStoreIsTheSameOne() {
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        LastSyncedAtStore.set(d, for: account, storeIdentity: "A", defaults: defaults)

        XCTAssertEqual(
            LastSyncedAtStore.get(accountId: account, storeIdentity: "A", defaults: defaults), d)
    }

    /// The bug that emptied a real user's library. The cursor described a
    /// database that no longer existed, so the delta pull asked for changes
    /// since a timestamp the new empty store had never reached, and the server
    /// truthfully returned nothing — forever.
    func testCursorIsDroppedWhenTheStoreIdentityChanges() {
        LastSyncedAtStore.set(Date(), for: account, storeIdentity: "A", defaults: defaults)

        XCTAssertNil(
            LastSyncedAtStore.get(accountId: account, storeIdentity: "B", defaults: defaults))
    }

    /// A phone upgrading from 0.6.0 has a cursor and no stamp. It pays one full
    /// pull — which is also what heals it if it was already in the broken state.
    func testACursorWrittenBeforeStampingIsTreatedAsStale() {
        defaults.set(Date(), forKey: rawDateKey)

        XCTAssertNil(
            LastSyncedAtStore.get(accountId: account, storeIdentity: "A", defaults: defaults))
    }

    func testNoStoreOpenWritesNothing() {
        LastSyncedAtStore.set(Date(), for: account, storeIdentity: nil, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: rawDateKey))
        XCTAssertNil(defaults.string(forKey: rawStampKey))
    }

    func testNoStoreOpenReadsNothing() {
        LastSyncedAtStore.set(Date(), for: account, storeIdentity: "A", defaults: defaults)

        XCTAssertNil(
            LastSyncedAtStore.get(accountId: account, storeIdentity: nil, defaults: defaults))
    }

    func testResetClearsBothKeys() {
        LastSyncedAtStore.set(Date(), for: account, storeIdentity: "A", defaults: defaults)
        LastSyncedAtStore.reset(for: account, defaults: defaults)

        XCTAssertNil(
            LastSyncedAtStore.get(accountId: account, storeIdentity: "A", defaults: defaults))
        XCTAssertNil(defaults.string(forKey: rawStampKey))
        XCTAssertNil(defaults.object(forKey: rawDateKey))
    }

    /// Reading must never adopt the current identity — that would make the
    /// guard pass on the very next call and disarm it silently.
    func testReadingDoesNotAdoptTheCurrentIdentity() {
        LastSyncedAtStore.set(Date(), for: account, storeIdentity: "A", defaults: defaults)

        _ = LastSyncedAtStore.get(accountId: account, storeIdentity: "B", defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: rawStampKey), "A")
        XCTAssertNil(
            LastSyncedAtStore.get(accountId: account, storeIdentity: "B", defaults: defaults))
    }

    /// Two accounts on one device keep separate cursors and separate stamps.
    func testAccountsDoNotShareACursor() {
        let other = UUID()
        let d = Date(timeIntervalSince1970: 1_700_000_000)
        LastSyncedAtStore.set(d, for: account, storeIdentity: "A", defaults: defaults)

        XCTAssertNil(
            LastSyncedAtStore.get(accountId: other, storeIdentity: "A", defaults: defaults))
        XCTAssertEqual(
            LastSyncedAtStore.get(accountId: account, storeIdentity: "A", defaults: defaults), d)
    }
}
