import XCTest
@testable import TripTrack

/// Coverage for `CompanionsCardModel.decide` — the pure "what should the
/// trip-detail companions card show" function behind
/// `TripTrack/Views/Trips/TripCompanionsSection.swift`. Each test is built
/// to fail if the rule it names is removed from `decide`, not just to
/// exercise the happy path.
final class CompanionsCardTests: XCTestCase {

    private func item(_ status: CompanionStatus, id: UUID = UUID()) -> CompanionItem {
        CompanionItem(accountId: id, displayName: "Someone", avatarEmoji: "🙂", status: status)
    }

    // MARK: - Empty roster, resolved (loaded) requests

    /// An empty, SUCCESSFULLY LOADED roster on YOUR OWN trip is the inviting
    /// state, not nothing — the card must still render so «Позвать» is
    /// reachable, and no banner should sit in front of that invitation.
    /// Fails if `decide` starts returning `.hidden`, or an empty `.own`
    /// with a non-`.none` banner, for a resolved empty roster.
    func testEmptyRosterOwnTripLoadedIsInvitingState() {
        let decision = CompanionsCardModel.decide(companions: [], isOwn: true, loadState: .loaded)
        guard case .own(let rows, let banner) = decision else {
            return XCTFail("expected .own(rows: [], banner: .none), got \(decision)")
        }
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(banner, .none)
    }

    /// An empty roster on a STRANGER's trip that genuinely loaded empty
    /// draws nothing at all. Fails if `decide` starts returning
    /// `.readOnly(rows: [], ...)` instead of `.hidden` for a resolved,
    /// truly-empty roster (the view would then render an empty card frame).
    func testEmptyRosterStrangerTripLoadedRendersNothing() {
        let decision = CompanionsCardModel.decide(companions: [], isOwn: false, loadState: .loaded)
        XCTAssertEqual(decision, .hidden)
    }

    // MARK: - Mixed statuses, own trip

    /// On your own trip, "ждёт" is exclusive to pending rows — accepted and
    /// declined companions both carry NO waiting note. Fails if the pending
    /// flag leaks onto (or is dropped from) the wrong rows.
    func testMixedStatusesOwnTripShowsWaitingOnlyOnPending() {
        let pending = item(.pending)
        let accepted = item(.accepted)
        let declined = item(.declined)
        let decision = CompanionsCardModel.decide(
            companions: [pending, accepted, declined], isOwn: true, loadState: .loaded)
        guard case .own(let rows, _) = decision else {
            return XCTFail("expected .own for your own trip, got \(decision)")
        }
        // All three are visible to the owner — declined rows are only kept
        // out of OTHER viewers' lists, not the owner's own.
        XCTAssertEqual(Set(rows.map(\.id)), Set([pending.accountId, accepted.accountId, declined.accountId]))
        XCTAssertEqual(rows.filter(\.isWaiting).map(\.id), [pending.accountId])
        for row in rows where row.id != pending.accountId {
            XCTAssertFalse(row.isWaiting, "only the pending row may carry the waiting note")
        }
    }

    // MARK: - Mixed statuses, stranger's trip

    /// On someone else's trip a stranger (or a fellow companion) never sees
    /// pending or declined rows at all — only accepted. Fails if either
    /// status starts leaking into the read-only list.
    func testMixedStatusesStrangerTripHidesPendingAndDeclined() {
        let pending = item(.pending)
        let accepted = item(.accepted)
        let declined = item(.declined)
        let decision = CompanionsCardModel.decide(
            companions: [pending, accepted, declined], isOwn: false, loadState: .loaded)
        guard case .readOnly(let rows, _) = decision else {
            return XCTFail("expected .readOnly, got \(decision)")
        }
        XCTAssertEqual(rows.map(\.id), [accepted.accountId])
        XCTAssertFalse(rows.contains { $0.status != .accepted })
    }

    // MARK: - Finding 1: a failed load must never look like an empty roster

    /// THE bug this whole `loadState` plumbing exists to close: a stranger
    /// (or companion) viewing a trip whose `/companions/list` call FAILED
    /// must see a retryable error, never the same "nothing here" the card
    /// draws for a trip that genuinely has no companions. Fails if `decide`
    /// still returns `.hidden` for a failed, empty non-owner load.
    func testFailedLoadStrangerTripWithNoCompanionsShowsErrorNotHidden() {
        let decision = CompanionsCardModel.decide(companions: [], isOwn: false, loadState: .failed)
        XCTAssertEqual(decision, .readOnly(rows: [], banner: .error))
        XCTAssertNotEqual(decision, .hidden)
    }

    /// The companion piece of the same rule: a STILL-LOADING or NEVER-YET-
    /// REQUESTED non-owner roster must still render nothing (no premature
    /// card, no premature error) — only a CONFIRMED failure earns the error
    /// row. Fails if `decide` starts treating "not answered yet" the same
    /// as "answered with an error".
    func testLoadingOrIdleStrangerTripWithNoCompanionsRendersNothingYet() {
        XCTAssertEqual(
            CompanionsCardModel.decide(companions: [], isOwn: false, loadState: .idle), .hidden)
        XCTAssertEqual(
            CompanionsCardModel.decide(companions: [], isOwn: false, loadState: .loading), .hidden)
    }

    /// Own-trip mirror of the same fix: a failed load with nothing cached
    /// shows the error state, not the "add companions" invitation — inviting
    /// someone onto a roster we couldn't actually confirm is empty would be
    /// misleading in the other direction.
    func testFailedLoadOwnTripWithNoCompanionsShowsErrorNotInvitingState() {
        let decision = CompanionsCardModel.decide(companions: [], isOwn: true, loadState: .failed)
        XCTAssertEqual(decision, .own(rows: [], banner: .error))
    }

    // MARK: - Finding 2: loading/error must not blank an already-cached roster

    /// A background refresh in flight must keep showing whatever roster is
    /// already cached — no spinner replacing real rows. Fails if a cached,
    /// non-empty roster starts showing `.loading` (or drops its rows) while
    /// a request is in flight.
    func testLoadingOwnTripWithCachedRosterKeepsShowingRows() {
        let accepted = item(.accepted)
        let decision = CompanionsCardModel.decide(
            companions: [accepted], isOwn: true, loadState: .loading)
        XCTAssertEqual(decision, .own(rows: [.init(companion: accepted)], banner: .none))
    }

    /// The other half: loading with NOTHING cached yet shows the spinner
    /// state, not the empty-roster invitation (we don't know yet whether
    /// it's empty). Fails if an in-flight, empty-so-far load starts reading
    /// as `.none`/inviting instead of `.loading`.
    func testLoadingOwnTripWithNothingCachedShowsLoadingBanner() {
        let decision = CompanionsCardModel.decide(companions: [], isOwn: true, loadState: .loading)
        XCTAssertEqual(decision, .own(rows: [], banner: .loading))
    }

    /// A failed REFRESH (not the first load) with an already-cached roster
    /// must keep the roster on screen AND surface the failure — neither
    /// silently dropping the error nor evicting good rows to show one.
    /// Fails if the rows disappear on failure, or if the banner stops being
    /// `.error` just because rows are present.
    func testFailedOwnTripWithCachedRosterKeepsRowsAndSurfacesError() {
        let accepted = item(.accepted)
        let decision = CompanionsCardModel.decide(
            companions: [accepted], isOwn: true, loadState: .failed)
        XCTAssertEqual(decision, .own(rows: [.init(companion: accepted)], banner: .error))
    }

    /// Same failed-refresh-keeps-rows rule, non-owner side: a stranger who
    /// already saw an accepted companion must not lose that row just
    /// because a later background refresh failed.
    func testFailedStrangerTripWithCachedRosterKeepsRowsAndSurfacesError() {
        let accepted = item(.accepted)
        let decision = CompanionsCardModel.decide(
            companions: [accepted], isOwn: false, loadState: .failed)
        XCTAssertEqual(decision, .readOnly(rows: [.init(companion: accepted)], banner: .error))
    }
}
