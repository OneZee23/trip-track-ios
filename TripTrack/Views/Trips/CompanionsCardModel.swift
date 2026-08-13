import Foundation

/// What the trip-detail companions card should show, pulled out of the view
/// body as a pure function so the own/stranger, empty/waiting/declined AND
/// loading/error branching is unit-testable without spinning up SwiftUI
/// (`TripTrackTests/CompanionsCardTests.swift`).
///
/// The server already filters what a non-owner's `/companions/list` call
/// returns — pending and declined rows are only ever sent to the trip owner
/// (see `CompanionItem`'s doc comment in `CompanionsDTOs.swift`). `decide`
/// re-applies the same filter defensively on the client: a roster cached
/// from an earlier owner view, or a future relaxation of the server filter,
/// must never leak a pending/declined row onto a read-only card.
enum CompanionsCardModel {
    /// Whether it's worth asking the server about this trip's roster at
    /// all — and when it isn't, which of the two blockers the viewer is
    /// actually facing. Only meaningful on an OWN trip: a non-owner can
    /// only have reached the detail screen for a trip that already exists
    /// server-side, so their path is always `.allowed`.
    enum Gate: Equatable {
        case allowed
        /// No session. Says nothing about the trip — it may well be public
        /// already.
        case signedOut
        /// Signed in, but this trip has never reached the server
        /// (`Trip.isOnServer == false`). Cloud sync starts OFF and trips
        /// are created private, so this is the app's DEFAULT state.
        case notPublished
    }

    /// One row the card draws, plus the one thing that varies per viewer:
    /// whether it carries the "ждёт" / "pending" note.
    struct Row: Identifiable, Equatable {
        let companion: CompanionItem
        var id: UUID { companion.accountId }
        var status: CompanionStatus { companion.status }
        /// The ONLY note a row ever carries — an accepted or declined
        /// companion shows nothing next to their name.
        var isWaiting: Bool { status == .pending }
    }

    /// What, if anything, to say ABOVE/ALONGSIDE the rows about the state of
    /// the request itself — independent of which rows are showing. `.error`
    /// is deliberately reachable with a non-empty `rows`: a failed refresh
    /// must surface, but it must not blank a roster that was already on
    /// screen (see `decide`'s `banner` helper).
    enum Banner: Equatable {
        case none
        case loading
        case error
        /// Task 7, own trip only: today's fetch failed AND nothing was left
        /// in memory, but a PRIOR successful load wrote something into the
        /// on-device cache (`Trip.companions`). The rows in this `Decision`
        /// ARE that cache — shown instead of the plain `.error` state, with
        /// a quiet note that they might not be current rather than a retry
        /// prompt with nothing to show.
        case stale
        /// Own trip, signed out. Split out of `.notPublished` after that
        /// banner was caught telling a signed-out owner of an ALREADY
        /// PUBLIC trip to "publish it first" — true of the session, false
        /// of the trip, and a dead end either way (publishing needs an
        /// account too). This one names the actual blocker and, unlike
        /// `.notPublished`, its row is tappable: it opens the sign-in
        /// sheet. `rows` is always empty alongside it.
        case signedOut
        /// Fix 2, own trip only: this trip cannot possibly have a companion
        /// roster because it has never reached the server (`Trip.isOnServer
        /// == false`) — cloud sync starts OFF
        /// and trips are created private, so this is the app's DEFAULT
        /// state, not an edge case. `decide` never even asks the network
        /// for this case (see `TripCompanionsSection.load`'s `canQuery`
        /// guard) — every `/companions/*` call on a trip with no server row
        /// answers the identical `TRIP_NOT_FOUND` a genuinely missing trip
        /// would, which used to render as a permanent, unfixable `.error`
        /// retry banner. `rows` is always empty alongside this banner.
        case notPublished
    }

    enum Decision: Equatable {
        /// Own trip — ALWAYS drawn. Empty `rows` with `banner == .none` is
        /// the invitation to invite someone; empty with `.loading`/`.error`
        /// means the invitation can't be trusted yet. Carries every status
        /// the server sent (pending/accepted/declined): declined rows are
        /// only ever sent to the owner in the first place, so nothing
        /// further needs filtering here.
        case own(rows: [Row], banner: Banner)
        /// Someone else's trip with at least one row to draw: either a real
        /// accepted companion, or (when `rows` is empty) an `.error` banner
        /// on its own — see `decide`. Whether the viewer is a fellow
        /// companion or a stranger makes no difference to what's drawn:
        /// the roster item for a companion viewer WOULD carry their own
        /// `TokenStore.shared.accountId` (the same id `CompanionsStore
        /// .respond` compares against) among the accepted rows, so the two
        /// cases are technically distinguishable — nothing in the required
        /// behaviour currently depends on making that distinction, so both
        /// render through this one case.
        case readOnly(rows: [Row], banner: Banner)
        /// Someone else's trip with nothing to show AND no reason to
        /// believe there's anything to show yet (never loaded, still
        /// loading, or loaded and genuinely empty). The card (and its
        /// section header) are not drawn at all. A CONFIRMED failure is
        /// never represented here — see `decide`: it always surfaces as
        /// `.readOnly(rows: [], banner: .error)` instead, so a network
        /// blip can never be mistaken for "this trip has no companions".
        case hidden
    }

    /// - Parameter cached: Task 7's offline cache for OWN trips
    ///   (`Trip.companions`, converted to `CompanionItem`) — consulted ONLY
    ///   when `companions` (the in-memory roster) is empty AND `loadState
    ///   == .failed`, i.e. exactly the state that used to render as the
    ///   bare `.own(rows: [], banner: .error)`. A non-owner never has one
    ///   (a foreign trip has no local cache to read — see `TripCompanion`'s
    ///   doc comment), so this parameter is unused on that path.
    /// - Parameter gate: Fix 2 — whether this trip could possibly have a
    ///   roster at all, and if not, WHY. Defaults `.allowed` so every
    ///   pre-existing call site (and the loadState-driven branches below) is
    ///   unaffected; a blocked own trip takes the matching banner branch,
    ///   ignoring `loadState` and `cached` entirely — a trip nobody can ask
    ///   the server about has nothing genuine to fall back to.
    ///
    ///   The two blocked reasons are kept apart deliberately: they used to
    ///   share `.notPublished`, which meant a signed-out owner of a PUBLIC
    ///   trip was told to publish it. Only the viewer can be asked to fix
    ///   the blocker, so the card has to name the right one.
    static func decide(
        companions: [CompanionItem], isOwn: Bool, loadState: CompanionsLoadState,
        cached: [CompanionItem] = [], gate: Gate = .allowed
    ) -> Decision {
        if isOwn {
            switch gate {
            case .signedOut: return .own(rows: [], banner: .signedOut)
            case .notPublished: return .own(rows: [], banner: .notPublished)
            case .allowed: break
            }
            // Nothing in memory this session (never asked yet, or asked and
            // got back nothing) AND today's request outright failed: if an
            // EARLIER successful load left something in the on-device
            // cache, show it — flagged as possibly stale — instead of the
            // plain retry prompt. `loadState == .failed` (not `.loading`)
            // deliberately excludes still-in-flight/never-asked states:
            // the fallback only kicks in once the network has genuinely
            // been tried and lost.
            // Not just on `.failed` any more. A trip that has been taken off
            // the server resolves as a perfectly successful EMPTY roster — the
            // server has no such trip to have companions on — and requiring a
            // failure here meant that exact case, the one where the cache is
            // the only record left, was the one where the cache was ignored.
            //
            // Safe against a genuine removal: a successful list overwrites the
            // on-device cache with whatever came back, so a roster the owner
            // really emptied leaves `cached` empty too and there is nothing
            // here to resurrect. `.loading` still shows nothing, so the rows
            // don't flash in before the first answer.
            if companions.isEmpty, !cached.isEmpty, loadState != .loading {
                return .own(rows: cached.map(Row.init), banner: .stale)
            }
            let rows = companions.map(Row.init)
            return .own(rows: rows, banner: banner(for: loadState, hasRows: !rows.isEmpty))
        }
        // Defense in depth, not trust: only ever show accepted companions
        // to a non-owner, even if a pending/declined row somehow made it
        // into the cache.
        let rows = companions.filter { $0.status == .accepted }.map(Row.init)
        guard rows.isEmpty else {
            return .readOnly(rows: rows, banner: banner(for: loadState, hasRows: true))
        }
        // Nothing to show — but "nothing YET" (never asked / still asking /
        // loaded and truly empty) must render as `.hidden`, exactly like
        // before, while a CONFIRMED failure must not: that's the bug this
        // whole `loadState` threading exists to close. A trip that really
        // does have companions must never look permanently empty just
        // because one request blipped.
        return loadState == .failed ? .readOnly(rows: [], banner: .error) : .hidden
    }

    /// Shared by both `own` and `readOnly`: what to show about the request
    /// itself, given whether there are already rows on screen to protect.
    ///  - `.idle`/`.loading` + no rows yet → `.loading` (spinner; nothing
    ///    confirmed either way).
    ///  - `.idle`/`.loading` + rows already cached → `.none`. A background
    ///    refresh must not blank, or even visibly flag, a roster that's
    ///    already showing — "loading with a cached roster keeps showing the
    ///    roster" means exactly that, not "roster plus a spinner".
    ///  - `.loaded` → `.none` always; the rows (or lack of them) already
    ///    speak for themselves.
    ///  - `.failed` → `.error` always, WITH or WITHOUT rows — a failure is
    ///    always worth saying, it just must not evict rows that are still
    ///    good.
    private static func banner(for loadState: CompanionsLoadState, hasRows: Bool) -> Banner {
        switch loadState {
        case .idle, .loading:
            return hasRows ? .none : .loading
        case .loaded:
            return .none
        case .failed:
            return .error
        }
    }
}
