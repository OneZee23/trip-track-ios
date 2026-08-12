import Foundation

/// What the «Со мной» profile section should show, pulled out of
/// `WithMeSection`'s body as a pure function — same reasoning as
/// `CompanionsCardModel`/`CompanionsPickerModel`: the hidden/loading/
/// loaded-empty/failed branching has to be unit-testable without spinning up
/// SwiftUI (`TripTrackTests/WithMeSectionTests.swift`).
///
/// Reuses `CompanionsLoadState` — the same tri-state `list(tripId:)` and
/// `candidates` already use — via `CompanionsStore.myTripsLoadState`, added
/// alongside this task specifically so a failed `/companions/my-trips` page
/// can be told apart from "genuinely no companion trips" (the same fix
/// Task 2/3's reviews made `list`/`candidates` apply to their own load
/// states; `loadMyTrips` used to swallow its error exactly like they did
/// before those fixes).
enum WithMeSectionModel {
    /// One row: a trip the signed-in user rode as an accepted companion on.
    /// Wraps the raw `SocialFeedTrip` — the view converts it to `Trip` via
    /// `Trip(social:)` only at render/open time, exactly like the feed does.
    struct Row: Identifiable, Equatable {
        let trip: SocialFeedTrip
        var id: UUID { trip.id }
    }

    /// What to say ALONGSIDE whatever rows are already known — never
    /// instead of them once any rows exist (see `decide`).
    enum Banner: Equatable {
        case none
        /// Rows already on screen; the NEXT page is in flight. There is no
        /// bare "first load" banner: with nothing cached yet, a request in
        /// flight (or not yet started) reads as `.hidden`, not a skeleton —
        /// the section's whole contract is "show up only when there's
        /// something to show" (brief), and "loading" alone confirms
        /// nothing either way yet.
        case loadingMore
        /// A confirmed failure — ALWAYS shown, with or without rows. This is
        /// the one exception to "hidden unless there's something to show":
        /// a retryable error is itself something to show, and must never be
        /// silently swallowed into the same blank the section draws for a
        /// genuinely companion-trip-free account.
        case error
    }

    enum Decision: Equatable {
        /// Nothing to draw: never asked yet, still asking with nothing
        /// cached, or asked and genuinely came back empty. The section (and
        /// its header) render nothing at all — a companion-trip-free
        /// account must never show an empty card or a permanent spinner.
        case hidden
        case content(rows: [Row], banner: Banner)
    }

    static func decide(myTrips: [SocialFeedTrip], loadState: CompanionsLoadState) -> Decision {
        let rows = myTrips.map(Row.init)
        switch loadState {
        case .idle, .loading:
            // No rows yet and nothing confirmed either way → stay hidden
            // rather than flash a skeleton on every profile load for the
            // common case (an account with zero companion trips). Rows
            // already cached from an earlier page must never blank while a
            // refresh/next-page request is in flight.
            return rows.isEmpty ? .hidden : .content(rows: rows, banner: .loadingMore)
        case .loaded:
            return rows.isEmpty ? .hidden : .content(rows: rows, banner: .none)
        case .failed:
            // Surfaced with or without rows — see `Banner.error`.
            return .content(rows: rows, banner: .error)
        }
    }
}
