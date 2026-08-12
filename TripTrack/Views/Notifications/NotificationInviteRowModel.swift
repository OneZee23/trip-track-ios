import Foundation

/// What one row in the notifications inbox should draw for the two
/// companion-related kinds (`companion_invite` / `companion_accepted`),
/// pulled out of `NotificationsInboxView` as a pure function — same reason
/// `CompanionsCardModel.decide` exists next to `TripCompanionsSection`: the
/// invite-vs-info branching, and the "never show a trip title on a pending
/// invite" rule, need to be unit-testable without spinning up SwiftUI
/// (`TripTrackTests/NotificationsInviteRowTests.swift`).
enum NotificationInviteRowModel {

    /// This session's optimistic outcome for a pending invite, applied by
    /// `NotificationsInboxView` the instant the invitee taps a button —
    /// BEFORE the server confirms. `nil` means "not yet acted on". A
    /// `companion_invite` notification row is a permanent log entry — its
    /// `kind` never changes server-side once answered — so "already
    /// answered" has to be tracked separately from `NotificationItem` and
    /// threaded in here (the view sources it from
    /// `CompanionsStore.respondedStatus(for:)`, which survives the
    /// notifications sheet being dismissed and reopened within the same
    /// app session).
    enum LocalResponse: Equatable {
        case accepted
        case declined
    }

    /// `CompanionsStore.invitePreview(tripId:)`'s request lifecycle for one
    /// row. Mirrors the loading/loaded/failed shape `CompanionsLoadState`
    /// uses elsewhere in the companions feature (no `idle` case — a
    /// decision row starts fetching the moment it's decided, so there is
    /// no "not asked yet" state a caller ever needs to render).
    enum PreviewState: Equatable {
        case loading
        case loaded(CompanionInvitePreview)
        /// A genuine, retryable failure (network blip, server hiccup) —
        /// the underlying invite is still pending server-side, so
        /// Accept/Decline underneath still work even though the preview
        /// blurb didn't load.
        case failed
        /// Fix 2: the server confirms there is no longer a live PENDING
        /// invite to preview at all (`COMPANION_INVITE_NOT_FOUND` from
        /// `/companions/invite-preview`) — most commonly because the
        /// invitee already answered on ANOTHER device, so THIS device
        /// never recorded a `LocalResponse` and would otherwise still
        /// treat the row as an open decision. Distinguished from the
        /// generic `.failed` above precisely because here the
        /// Accept/Decline buttons themselves cannot succeed either — the
        /// same "no longer pending" row is exactly what
        /// `/companions/respond` checks — so `presentation` routes this
        /// straight to `.info` instead of offering dead controls.
        case unavailable
    }

    /// What the row should draw.
    enum Presentation: Equatable {
        /// Still awaiting the invitee's decision: accept/decline controls,
        /// backed by `preview`. The associated value is built ONLY from
        /// `CompanionInvitePreview` — the server's `/companions/invite-
        /// preview` payload the type wraps has exactly five keys (`driver`,
        /// `startDate`, `distance`, `duration`, `region`) and none of them
        /// is a title, so a decision row is structurally unable to surface
        /// one even if `NotificationItem.tripTitle` carries a value.
        case decision(PreviewState)
        /// Every other case: an ordinary tap-to-open row. Covers
        /// `companion_accepted`, any other known kind, an unknown future
        /// kind (the pre-existing generic fallback this must not break),
        /// AND a `companion_invite` already answered this session.
        case info
    }

    /// Single entry point the view calls per row.
    ///
    /// Fix 2: `preview == .unavailable` routes to `.info` on its own,
    /// independent of `localResponse` — THIS device may never have
    /// recorded an answer (the invite was answered on another device), so
    /// `localResponse == nil` alone can't be trusted to mean "still
    /// actionable" once the server itself confirms there's nothing left to
    /// answer.
    static func presentation(
        for item: NotificationItem, localResponse: LocalResponse?, preview: PreviewState
    ) -> Presentation {
        guard item.kind == NotificationKind.companionInvite.rawValue,
              localResponse == nil,
              preview != .unavailable
        else {
            return .info
        }
        return .decision(preview)
    }

    /// Fix 8 + Fix 2: what a decision row's cached preview state should
    /// become after `CompanionsStore.invitePreview` throws.
    ///  - `wasCancelled` (Fix 8): the row scrolled off screen mid-fetch —
    ///    SwiftUI cancelled the backing `.task`, which is NOT "the network
    ///    broke". Returns `nil` (not `.failed`) so the guard in
    ///    `NotificationsInboxView.ensurePreviewIfNeeded` treats this
    ///    exactly like "never fetched" and retries automatically the next
    ///    time the row reappears, instead of getting stuck showing (or
    ///    permanently requiring a manual retry from) a failure that never
    ///    actually happened.
    ///  - `isInviteGone` (Fix 2): the server's specific "no longer a live
    ///    pending invite" signal (`COMPANION_INVITE_NOT_FOUND`) — maps to
    ///    `.unavailable`, which `presentation` above routes to the plain
    ///    info row instead of dead Accept/Decline buttons.
    ///  - Neither → an ordinary retryable `.failed`.
    /// `wasCancelled` wins over `isInviteGone` if somehow both were true:
    /// a cancelled request never got a real server answer to trust either
    /// way.
    static func previewStateAfterFailure(wasCancelled: Bool, isInviteGone: Bool) -> PreviewState? {
        if wasCancelled { return nil }
        return isInviteGone ? .unavailable : .failed
    }

    /// Fix 11: whether `NotificationsInboxView.openAcceptedInviteTrip`'s
    /// paging sweep through `/companions/my-trips` should attempt ANOTHER
    /// `loadMyTrips(reset: false)` call. Extracted as a pure function so
    /// "don't re-run a page that just failed" is provable without a real
    /// network race: `performLoadMyTrips` leaves `hasMoreMyTrips`/its
    /// cursor UNTOUCHED on failure (see its doc comment), so without this
    /// check the sweep's `while` loop would call `loadMyTrips(reset:
    /// false)` again with the EXACT SAME cursor — silently re-requesting
    /// the page that just failed, up to `maxPages` times, instead of
    /// stopping the sweep the moment a page genuinely fails.
    static func shouldContinuePagingForTrip(
        found: Bool, loadState: CompanionsLoadState, hasMore: Bool, pagesLoaded: Int, maxPages: Int
    ) -> Bool {
        !found && loadState != .failed && hasMore && pagesLoaded < maxPages
    }

    /// The decision row's trip-shape line: date · region · distance
    /// (· duration when present) — exactly what a pending invitee is
    /// allowed to know before accepting.
    struct DecisionLine: Equatable {
        let dateText: String
        let regionText: String?
        let distanceText: String
        /// nil when the server never computed a driving time. Callers must
        /// omit this line entirely rather than render "0 мин"/"0 min" —
        /// see `CompanionInvitePreview.formattedDurationHuman`, which this
        /// is built from.
        let durationText: String?
    }

    /// Builds the decision line from `preview` alone. `item` is accepted as
    /// a parameter (rather than dropped from the signature) so the caller
    /// passes the row's actual notification straight through and a future
    /// edit can't quietly start reading `item.tripTitle` here without a
    /// reviewer noticing an unused parameter turn into a used one —
    /// `NotificationsInviteRowTests` proves the omission holds by giving
    /// `item.tripTitle` a value and checking it never reaches the output.
    static func decisionLine(
        item: NotificationItem, preview: CompanionInvitePreview, lang: LanguageManager.Language
    ) -> DecisionLine {
        let region = RegionDisplay.localized(preview.region, language: lang)
        return DecisionLine(
            dateText: RelativeTripDate.string(from: preview.startDate, language: lang),
            regionText: (region?.isEmpty == false) ? region : nil,
            distanceText: "\(oneDecimal(preview.distance / 1000)) \(AppStrings.km(lang))",
            durationText: preview.formattedDurationHuman(lang)
        )
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
