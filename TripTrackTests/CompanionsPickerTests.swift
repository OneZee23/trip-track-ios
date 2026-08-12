import XCTest
@testable import TripTrack

/// Coverage for `CompanionsPickerModel.decide` — the pure "what should the
/// invite picker show" function behind
/// `TripTrack/Views/Trips/CompanionsPickerSheet.swift`. Each test is built
/// to fail if the rule it names is removed from `decide`, not just to
/// exercise the happy path.
final class CompanionsPickerTests: XCTestCase {

    private func candidate(_ id: UUID = UUID()) -> CompanionCandidate {
        CompanionCandidate(accountId: id, displayName: "Someone", avatarEmoji: "🙂", profileLevel: 3)
    }

    // MARK: - Nothing loaded yet / still loading, no rows

    /// The picker just opened and the first request hasn't even started —
    /// must show the loading skeleton, never the "only people you follow"
    /// empty message (that message is a claim about a LOADED result). Fails
    /// if `decide` starts treating `.idle` differently from `.loading` for
    /// an empty candidate list.
    func testNothingLoadedYetShowsLoadingBanner() {
        let decision = CompanionsPickerModel.decide(candidates: [], invitedIds: [], loadState: .idle)
        XCTAssertEqual(decision, .empty(.loading))
    }

    /// The first page is in flight. Same loading skeleton as `.idle`. Fails
    /// if `decide` stops mapping `.loading` + no rows to `.loading`.
    func testLoadingWithNoRowsShowsLoadingBanner() {
        let decision = CompanionsPickerModel.decide(candidates: [], invitedIds: [], loadState: .loading)
        XCTAssertEqual(decision, .empty(.loading))
    }

    // MARK: - Loading with rows already shown (pagination)

    /// A next page is loading while the first page's rows are already on
    /// screen — the rows must NOT blank. Fails if `decide` starts returning
    /// `.empty` (or drops the rows) while `loadState == .loading` with a
    /// non-empty candidate list.
    func testLoadingWithRowsAlreadyShownKeepsRows() {
        let c = candidate()
        let decision = CompanionsPickerModel.decide(candidates: [c], invitedIds: [], loadState: .loading)
        XCTAssertEqual(decision, .rows([.init(candidate: c, isInvited: false)], banner: .loadingMore))
    }

    // MARK: - Loaded and empty — the "only people you follow" state

    /// A genuinely empty, LOADED result — the state that must say "you can
    /// only invite people you follow" rather than look like a network blip.
    /// Fails if `decide` starts reporting `.loading` or `.error` for a
    /// resolved empty page.
    func testLoadedAndEmptyIsOnlyFollowState() {
        let decision = CompanionsPickerModel.decide(candidates: [], invitedIds: [], loadState: .loaded)
        XCTAssertEqual(decision, .empty(.none))
    }

    // MARK: - Failed, no rows

    /// The first page failed outright — error + retry, never an endless
    /// skeleton. Fails if `decide` keeps reporting `.loading` (or `.none`)
    /// for a failed, empty candidate list.
    func testFailedWithNoRowsShowsError() {
        let decision = CompanionsPickerModel.decide(candidates: [], invitedIds: [], loadState: .failed)
        XCTAssertEqual(decision, .empty(.error))
    }

    // MARK: - Failed, rows already shown

    /// A later page failed but the first page's rows are already good — the
    /// error must surface WITHOUT evicting those rows. Fails if the rows
    /// disappear on failure, or if the banner stops being `.error` just
    /// because rows are present.
    func testFailedWithRowsKeepsRowsAndSurfacesError() {
        let c = candidate()
        let decision = CompanionsPickerModel.decide(candidates: [c], invitedIds: [], loadState: .failed)
        XCTAssertEqual(decision, .rows([.init(candidate: c, isInvited: false)], banner: .error))
    }

    // MARK: - Already invited this session

    /// A candidate this sheet session already invited renders as invited —
    /// independent of the request's own loading/error state. Fails if
    /// `invitedIds` membership stops being reflected in `Row.isInvited`.
    func testAlreadyInvitedCandidateRendersAsInvited() {
        let c = candidate()
        let decision = CompanionsPickerModel.decide(
            candidates: [c], invitedIds: [c.accountId], loadState: .loaded)
        guard case .rows(let rows, _) = decision else {
            return XCTFail("expected .rows, got \(decision)")
        }
        XCTAssertEqual(rows, [.init(candidate: c, isInvited: true)])
        XCTAssertTrue(rows[0].isInvited)
    }

    // MARK: - `isCurrent` — the race guard behind `CompanionsPickerSheet.load(reset:)`

    /// Review Finding 1: a slow, since-superseded search must not publish
    /// its result. `token` is the generation captured BEFORE the request;
    /// `latest` is what the view's generation counter has moved on to by
    /// the time the request resolves. Fails if `isCurrent` stops rejecting
    /// a stale token (e.g. is loosened to `token <= latest`, which a
    /// smaller, older token would still pass).
    func testStaleLoadTokenIsNotCurrent() {
        XCTAssertFalse(CompanionsPickerModel.isCurrent(token: 1, latest: 2))
    }

    /// The other half: the call that actually IS the most recent one must
    /// still be allowed to publish. Fails if `isCurrent` is broken in the
    /// other direction (e.g. hard-coded to `false`, or comparing the wrong
    /// values), which would make the picker never show a result at all.
    func testCurrentLoadTokenIsCurrent() {
        XCTAssertTrue(CompanionsPickerModel.isCurrent(token: 2, latest: 2))
    }
}
