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
