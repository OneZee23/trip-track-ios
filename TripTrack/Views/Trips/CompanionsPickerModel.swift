import Foundation

/// What `CompanionsPickerSheet` should show, pulled out of the view body as
/// a pure function — same reasoning as `CompanionsCardModel` for the roster
/// card (`TripTrack/Views/Trips/CompanionsCardModel.swift`): the loading /
/// loaded-empty / failed branching (plus, here, "already invited this
/// session") has to be unit-testable without spinning up SwiftUI
/// (`TripTrackTests/CompanionsPickerTests.swift`).
///
/// `CompanionsStore.candidates(tripId:query:reset:)` used to swallow its own
/// errors (it followed `NotificationsInboxStore`'s convention: log and leave
/// stale state in place), so unlike `list(tripId:)` there was no `loadState`
/// to consume for candidates specifically. `CompanionsStore` gained a
/// sibling `candidatesLoadState: CompanionsLoadState` (same enum `list`
/// already used for the roster) so a failed candidates page can be told
/// apart from "no results" here — the same fix Task 2's review made `list`
/// apply to the roster card.
enum CompanionsPickerModel {
    /// One row: a candidate plus whether THIS SHEET SESSION already invited
    /// them. `CompanionsStore.invite` optimistically drops an invited
    /// account out of `store.candidates` (it's no longer a valid future
    /// candidate — see that method's doc comment) — `CompanionsPickerSheet`
    /// keeps its own copy that only ever grows or gets replaced wholesale on
    /// a fresh search, so an already-rendered row can keep showing this flag
    /// instead of vanishing the instant it's tapped.
    struct Row: Identifiable, Equatable {
        let candidate: CompanionCandidate
        let isInvited: Bool
        var id: UUID { candidate.accountId }
    }

    /// What to say about the request itself, layered ALONGSIDE (never
    /// instead of) whatever rows are already known.
    enum Banner: Equatable {
        case none
        /// No rows yet and none confirmed absent either — first load or a
        /// fresh search, still in flight (or not yet started).
        case loading
        /// Rows already on screen; the NEXT page is in flight. Deliberately
        /// distinct from `.loading` so pagination never blanks what's
        /// already showing.
        case loadingMore
        /// A confirmed failure — always shown, with or without rows.
        case error
    }

    enum Decision: Equatable {
        /// Nothing to draw as a row. `banner` says why: `.loading` (first
        /// load in flight / not started yet), `.none` (genuinely loaded
        /// empty — "you can only invite people you follow"), or `.error`
        /// (the first page failed outright).
        case empty(Banner)
        case rows([Row], banner: Banner)
    }

    static func decide(
        candidates: [CompanionCandidate],
        invitedIds: Set<UUID>,
        loadState: CompanionsLoadState
    ) -> Decision {
        let rows = candidates.map { Row(candidate: $0, isInvited: invitedIds.contains($0.accountId)) }
        let resolvedBanner = banner(for: loadState, hasRows: !rows.isEmpty)
        return rows.isEmpty ? .empty(resolvedBanner) : .rows(rows, banner: resolvedBanner)
    }

    /// - `.idle`/`.loading` + no rows → `.loading` (skeleton; nothing
    ///   confirmed either way — covers both "never asked yet" and "first
    ///   page in flight" identically, same reasoning as
    ///   `CompanionsCardModel.banner`).
    /// - `.idle`/`.loading` + rows already on screen → `.loadingMore`
    ///   (paging forward; the existing rows must not blank).
    /// - `.loaded` → `.none` always — the rows (or lack of them) already
    ///   speak for themselves.
    /// - `.failed` → `.error` always, WITH or WITHOUT rows.
    private static func banner(for loadState: CompanionsLoadState, hasRows: Bool) -> Banner {
        switch loadState {
        case .idle, .loading:
            return hasRows ? .loadingMore : .loading
        case .loaded:
            return .none
        case .failed:
            return .error
        }
    }

    /// Whether a `CompanionsPickerSheet.load(reset:)` call that captured
    /// `token` (a snapshot of the view's own generation counter, taken
    /// BEFORE its `await store.candidates(...)`) is still the most recent
    /// one and may publish its result into `displayedCandidates`.
    ///
    /// `CompanionsStore.candidates` already drops a stale response with its
    /// OWN `candidatesGeneration` guard before writing `store.candidates` —
    /// but that guard only protects the store. It does nothing for the
    /// VIEW's local mirror: a slow, since-superseded call still resumes
    /// past its `await`, and an unconditional `displayedCandidates =
    /// store.candidates` there would publish whatever `store.candidates`
    /// happens to hold at that instant — data belonging to neither the old
    /// search nor the new one. Extracted as a pure function (rather than
    /// left as inline `Task`/`await` code) specifically so this guard is
    /// unit-testable: `TripTrackTests/CompanionsPickerTests` cannot spin up
    /// real concurrent network races, but it CAN assert the guard itself
    /// rejects a stale token and accepts a current one.
    static func isCurrent(token: Int, latest: Int) -> Bool {
        token == latest
    }
}
