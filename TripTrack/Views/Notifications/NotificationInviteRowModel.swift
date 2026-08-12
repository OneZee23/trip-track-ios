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
        case failed
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
    static func presentation(
        for item: NotificationItem, localResponse: LocalResponse?, preview: PreviewState
    ) -> Presentation {
        guard item.kind == NotificationKind.companionInvite.rawValue, localResponse == nil else {
            return .info
        }
        return .decision(preview)
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
