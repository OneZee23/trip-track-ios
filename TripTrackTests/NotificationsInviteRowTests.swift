import XCTest
@testable import TripTrack

/// Coverage for `NotificationInviteRowModel` — the pure "what should this
/// notifications-inbox row show" logic behind the `companion_invite` /
/// `companion_accepted` rows in `NotificationsInboxView`. Each test is
/// built to fail if the rule it names is removed, not just to exercise the
/// happy path (see each test's doc comment for the exact mutation that
/// would break it).
final class NotificationsInviteRowTests: XCTestCase {

    // MARK: - Fixtures

    private func makeItem(
        kind: String, tripId: UUID = UUID(), tripTitle: String? = nil
    ) -> NotificationItem {
        NotificationItem(
            id: UUID(), kind: kind, tripId: tripId, tripTitle: tripTitle, emoji: nil,
            commentId: nil, commentText: nil, isFollowing: nil, isRead: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), actor: nil)
    }

    private func makePreview(
        distance: Double = 42_000, duration: Double? = 3_600, region: String? = "Тверская область"
    ) -> CompanionInvitePreview {
        CompanionInvitePreview(
            driver: CompanionDriverPreview(accountId: UUID(), displayName: "Аня", avatarEmoji: "🚗"),
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            distance: distance, duration: duration, region: region)
    }

    // MARK: - A pending invite is a decision row

    /// Baseline the other tests contrast against: a `companion_invite`
    /// with nothing answered yet IS the decision row (accept/decline
    /// controls). Fails if `presentation` stops routing a genuinely
    /// pending invite to `.decision`.
    func testPendingInviteWithNoLocalResponseYieldsDecisionRow() {
        let item = makeItem(kind: NotificationKind.companionInvite.rawValue)
        let result = NotificationInviteRowModel.presentation(
            for: item, localResponse: nil, preview: .loading)
        XCTAssertEqual(result, .decision(.loading))
    }

    // MARK: - Rule 1: a decision row never exposes a trip title

    /// The server withholds the trip title from `/companions/invite-
    /// preview` until the invite is accepted (`CompanionInvitePreview` has
    /// no title field at all). This proves the CLIENT honors that even if
    /// `NotificationItem.tripTitle` somehow carries a value — a future
    /// server change, or a bug — by giving it a distinctive marker and
    /// checking the marker never surfaces in the rendered decision line.
    /// Fails if `decisionLine` (or a future edit to it) starts reading
    /// `item.tripTitle` into any of its output fields.
    func testDecisionRowNeverExposesTripTitleEvenWhenPayloadCarriesOne() {
        let marker = "LEAKED-TITLE-\(UUID().uuidString.prefix(8))"
        let item = makeItem(kind: NotificationKind.companionInvite.rawValue, tripTitle: marker)
        let preview = makePreview()

        // The routing itself must still be a decision — a leaked title
        // must not somehow suppress the row.
        let presentation = NotificationInviteRowModel.presentation(
            for: item, localResponse: nil, preview: .loaded(preview))
        XCTAssertEqual(presentation, .decision(.loaded(preview)))

        let line = NotificationInviteRowModel.decisionLine(item: item, preview: preview, lang: .ru)
        XCTAssertFalse(line.dateText.contains(marker))
        XCTAssertFalse((line.regionText ?? "").contains(marker))
        XCTAssertFalse(line.distanceText.contains(marker))
        XCTAssertFalse((line.durationText ?? "").contains(marker))
    }

    // MARK: - Rule 2: an accepted invitation is a navigating row, not buttons

    /// Once the invitee has answered THIS SESSION (`localResponse` is
    /// non-nil), the row must stop being a decision — it becomes an
    /// ordinary `.info` row, whatever `preview` currently holds. Fails if
    /// `presentation` still returns `.decision` after a local response is
    /// recorded (e.g. if the guard only checked `.declined` and forgot
    /// `.accepted`, or dropped the `localResponse` check entirely).
    func testAcceptedInvitationRendersAsNavigatingRowNotButtons() {
        let item = makeItem(kind: NotificationKind.companionInvite.rawValue)
        let result = NotificationInviteRowModel.presentation(
            for: item, localResponse: .accepted, preview: .loaded(makePreview()))
        XCTAssertEqual(result, .info)
    }

    /// The companion half of the same rule: declining also exits the
    /// decision state, not just accepting.
    func testDeclinedInvitationAlsoRendersAsInfoRow() {
        let item = makeItem(kind: NotificationKind.companionInvite.rawValue)
        let result = NotificationInviteRowModel.presentation(
            for: item, localResponse: .declined, preview: .loading)
        XCTAssertEqual(result, .info)
    }

    // MARK: - Rule 3: an unknown kind still yields a generic (non-crashing) row

    /// A future server kind the client doesn't know about yet must not be
    /// mistaken for a decision row (which would render accept/decline
    /// controls with no way to ever load a preview for them) — it has to
    /// fall through to the plain informational row, exactly like
    /// `NotificationItem.typedKind` already falls through to `nil` for it
    /// elsewhere in the inbox. Fails if `presentation` starts matching on
    /// something looser than the exact `companion_invite` raw string (e.g.
    /// a `hasPrefix("companion")` check) and swallows an unrelated future
    /// kind into the decision branch.
    func testUnknownKindYieldsGenericRow() {
        let item = makeItem(kind: "some_future_kind_v7")
        let result = NotificationInviteRowModel.presentation(
            for: item, localResponse: nil, preview: .loading)
        XCTAssertEqual(result, .info)
    }

    /// `companion_accepted` is always informational — never a decision —
    /// regardless of local response state, since it's the OWNER'S kind
    /// (someone else answered, not this recipient).
    func testCompanionAcceptedAlwaysYieldsInfoRow() {
        let item = makeItem(kind: NotificationKind.companionAccepted.rawValue)
        XCTAssertEqual(
            NotificationInviteRowModel.presentation(for: item, localResponse: nil, preview: .loading),
            .info)
    }

    // MARK: - Rule 5 (Fix 2): a preview confirming the invite is gone yields an info row

    /// THE bug this fix closes: an invite answered on ANOTHER device has no
    /// local `LocalResponse` recorded on THIS device, so before this rule
    /// `presentation` kept routing it to `.decision` — rendering dead
    /// Accept/Decline buttons the server can only refuse
    /// (`COMPANION_INVITE_NOT_FOUND`). `preview == .unavailable` alone
    /// (even with `localResponse == nil`) must be enough to fall back to
    /// `.info`. Fails if `presentation` stops checking `preview` and only
    /// gates on `localResponse`.
    func testUnavailablePreviewYieldsInfoRowEvenWithoutLocalResponse() {
        let item = makeItem(kind: NotificationKind.companionInvite.rawValue)
        let result = NotificationInviteRowModel.presentation(
            for: item, localResponse: nil, preview: .unavailable)
        XCTAssertEqual(result, .info)
    }

    // MARK: - `previewStateAfterFailure` (Fix 8 + Fix 2)

    /// Fix 8: a CANCELLED fetch (the row scrolled off screen mid-request)
    /// must not be cached as `.failed` — it resets to "never fetched"
    /// (`nil`) so the next time the row appears it retries automatically
    /// instead of showing a permanent, spurious failure. Fails if
    /// cancellation stops taking priority (e.g. the function starts
    /// returning `.failed` regardless of `wasCancelled`).
    func testPreviewStateAfterFailure_CancelledIsNilNotFailed() {
        XCTAssertNil(NotificationInviteRowModel.previewStateAfterFailure(wasCancelled: true, isInviteGone: false))
    }

    /// Cancellation wins even if the SAME failure would otherwise have
    /// looked like "the invite is gone" — a cancelled request never
    /// actually got a trustworthy server answer either way.
    func testPreviewStateAfterFailure_CancelledWinsOverInviteGone() {
        XCTAssertNil(NotificationInviteRowModel.previewStateAfterFailure(wasCancelled: true, isInviteGone: true))
    }

    /// Fix 2: a genuine, non-cancelled "invite is gone" signal maps to
    /// `.unavailable`, not the generic retryable `.failed`. Fails if the
    /// function stops distinguishing the two and collapses everything
    /// non-cancelled to `.failed`.
    func testPreviewStateAfterFailure_InviteGoneIsUnavailable() {
        XCTAssertEqual(
            NotificationInviteRowModel.previewStateAfterFailure(wasCancelled: false, isInviteGone: true),
            .unavailable)
    }

    /// Baseline: an ordinary, non-cancelled, non-"invite gone" failure
    /// (a network blip) still maps to the retryable `.failed` — proves the
    /// two special cases above didn't swallow the plain failure path.
    func testPreviewStateAfterFailure_OrdinaryFailureIsFailed() {
        XCTAssertEqual(
            NotificationInviteRowModel.previewStateAfterFailure(wasCancelled: false, isInviteGone: false),
            .failed)
    }

    // MARK: - `shouldContinuePagingForTrip` (Fix 11)

    /// THE bug this fix closes: `performLoadMyTrips` leaves `hasMoreMyTrips`
    /// and its cursor UNTOUCHED when a page fails — so without this guard,
    /// `openAcceptedInviteTrip`'s paging loop would call `loadMyTrips(reset:
    /// false)` again with the EXACT SAME cursor, silently re-requesting the
    /// page that just failed. Fails if the function stops checking
    /// `loadState != .failed` (e.g. loosened to ignore load state entirely).
    func testShouldContinuePagingForTrip_StopsOnFailedPage() {
        XCTAssertFalse(NotificationInviteRowModel.shouldContinuePagingForTrip(
            found: false, loadState: .failed, hasMore: true, pagesLoaded: 1, maxPages: 5))
    }

    /// The trip was found — must stop regardless of everything else (no
    /// reason to keep paging once the target is in hand).
    func testShouldContinuePagingForTrip_StopsWhenFound() {
        XCTAssertFalse(NotificationInviteRowModel.shouldContinuePagingForTrip(
            found: true, loadState: .loaded, hasMore: true, pagesLoaded: 1, maxPages: 5))
    }

    /// The server says there's no next page — must stop even though
    /// nothing failed and the page cap hasn't been hit.
    func testShouldContinuePagingForTrip_StopsWhenNoMorePages() {
        XCTAssertFalse(NotificationInviteRowModel.shouldContinuePagingForTrip(
            found: false, loadState: .loaded, hasMore: false, pagesLoaded: 1, maxPages: 5))
    }

    /// The page cap has been reached — must stop even with more pages
    /// genuinely available server-side (bounds the request count on a
    /// single tap).
    func testShouldContinuePagingForTrip_StopsAtPageCap() {
        XCTAssertFalse(NotificationInviteRowModel.shouldContinuePagingForTrip(
            found: false, loadState: .loaded, hasMore: true, pagesLoaded: 5, maxPages: 5))
    }

    /// The happy path: not found yet, the last page succeeded, more pages
    /// are available, and the cap hasn't been hit — must continue.
    func testShouldContinuePagingForTrip_ContinuesWhenEligible() {
        XCTAssertTrue(NotificationInviteRowModel.shouldContinuePagingForTrip(
            found: false, loadState: .loaded, hasMore: true, pagesLoaded: 1, maxPages: 5))
    }

    // MARK: - Rule 4: a nil duration omits the duration line, not a zero

    /// `CompanionInvitePreview.duration` is nil when the server never
    /// computed a driving time. The decision line must OMIT that segment
    /// entirely, not render "0 мин"/"0 min" (which would read as "this
    /// trip took no time at all" rather than "unknown"). Fails if
    /// `decisionLine` starts coalescing a nil duration to a formatted zero
    /// instead of passing through `preview.formattedDurationHuman`'s nil.
    func testPreviewWithNilDurationOmitsDurationLine() {
        let item = makeItem(kind: NotificationKind.companionInvite.rawValue)
        let preview = makePreview(duration: nil)
        let line = NotificationInviteRowModel.decisionLine(item: item, preview: preview, lang: .ru)
        XCTAssertNil(line.durationText)

        // English side too — the omission isn't locale-specific.
        let lineEn = NotificationInviteRowModel.decisionLine(item: item, preview: preview, lang: .en)
        XCTAssertNil(lineEn.durationText)
    }

    /// Contrast case: a REAL duration renders, so the omission above is
    /// proven to be conditional on nil, not a permanently-dead code path.
    func testPreviewWithRealDurationRendersIt() {
        let item = makeItem(kind: NotificationKind.companionInvite.rawValue)
        let preview = makePreview(duration: 3_600)
        let line = NotificationInviteRowModel.decisionLine(item: item, preview: preview, lang: .ru)
        XCTAssertNotNil(line.durationText)
    }
}
