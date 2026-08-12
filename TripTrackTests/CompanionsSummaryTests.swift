import XCTest
@testable import TripTrack

/// Coverage for `CompanionsSummaryModel.summarize` — the pure "what does the
/// trip-detail companions plaque say" function behind
/// `TripTrack/Views/Trips/TripCompanionsSection.swift`.
///
/// The plaque shows a handful of faces and one sentence about them, so every
/// test here is about the sentence being TRUE of the faces next to it: an
/// unanswered invite must never be described as someone who rode along, and
/// people the plaque doesn't have room to name must not vanish silently.
final class CompanionsSummaryTests: XCTestCase {

    private func item(
        _ status: CompanionStatus, _ name: String?, emoji: String? = "🙂"
    ) -> CompanionItem {
        CompanionItem(accountId: UUID(), displayName: name, avatarEmoji: emoji, status: status)
    }

    // MARK: - Who the plaque speaks for

    /// The ordinary case: everyone accepted, so the plaque names them and
    /// says they rode with you. Fails if the subtitle stops distinguishing
    /// the owner's view.
    func testAcceptedOnlyOwnTripNamesThemAndSaysRodeWithYou() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Аня К."), item(.accepted, "Дмитрий П.")],
            isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.names, "Аня К., Дмитрий П.")
        XCTAssertEqual(summary?.subtitle, "Ездили вместе с вами")
        XCTAssertEqual(summary?.avatars.count, 2)
        XCTAssertEqual(summary?.overflow, 0)
    }

    /// The same roster on SOMEONE ELSE's trip can't say "с вами" — the
    /// viewer isn't the driver. Fails if the plaque stops being role-aware.
    func testAcceptedOnlyForeignTripDropsWithYou() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Аня К.")], isOwn: false, lang: .ru)

        XCTAssertEqual(summary?.subtitle, "Ездили вместе")
    }

    /// THE failure this model exists to prevent: a pending invite must never
    /// be presented as someone who came along. With nobody accepted yet, the
    /// plaque names the invitees and says it's waiting on them. Fails if
    /// pending rows get folded into the "rode with you" wording.
    func testPendingOnlySaysWaitingNotRodeAlong() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.pending, "Аня К."), item(.pending, "Дмитрий П.")],
            isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.names, "Аня К., Дмитрий П.")
        XCTAssertEqual(summary?.subtitle, "Ждём ответов")
    }

    /// Singular/plural is a real difference here — one outstanding invite
    /// reads «Ждём ответа». Fails if the count stops reaching the string.
    func testSinglePendingUsesSingularWaiting() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.pending, "Аня К.")], isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.subtitle, "Ждём ответа")
    }

    /// Mixed roster: the plaque names the people who actually rode, and the
    /// ones still deciding move into the subtitle's tail rather than being
    /// dropped — the owner shouldn't have to open the roster to learn an
    /// invite is outstanding. Fails if pending rows are silently discarded
    /// once anyone has accepted.
    func testAcceptedPlusPendingNamesAcceptedAndFlagsTheRest() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Аня К."), item(.pending, "Дмитрий П.")],
            isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.names, "Аня К.")
        XCTAssertEqual(summary?.subtitle, "Ездили вместе с вами · ещё один ждёт")
        XCTAssertEqual(summary?.avatars.count, 1, "the pending face isn't one of the riders")
    }

    /// Two or more outstanding invites pluralize the tail.
    func testAcceptedPlusTwoPendingPluralizesTheTail() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Аня К."), item(.pending, "Дмитрий П."), item(.pending, "Лена")],
            isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.subtitle, "Ездили вместе с вами · ещё 2 ждут")
    }

    /// Everyone said no (owner-only — declined rows never leave the server
    /// for anyone else). The plaque says so rather than implying the trip
    /// had company. Fails if declined rows are treated as riders.
    func testDeclinedOnlySaysDeclined() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.declined, "Аня К."), item(.declined, "Дмитрий П.")],
            isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.names, "Аня К., Дмитрий П.")
        XCTAssertEqual(summary?.subtitle, "Отказались")
    }

    /// A declined row alongside a real rider is not worth a word on the
    /// plaque — it's in the roster. Fails if a refusal starts colouring the
    /// summary of a trip that DID have company.
    func testDeclinedAlongsideAcceptedIsIgnoredBySummary() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Аня К."), item(.declined, "Дмитрий П.")],
            isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.names, "Аня К.")
        XCTAssertEqual(summary?.subtitle, "Ездили вместе с вами")
    }

    // MARK: - Overflow

    /// More riders than the plaque can show: the faces cap at three, the
    /// names at two, and BOTH remainders are accounted for — "+2" on the
    /// cluster, «и ещё 3» after the names. Fails if either cap starts
    /// dropping people without saying so.
    func testOverflowIsReportedByBothClusterAndNames() {
        let summary = CompanionsSummaryModel.summarize(
            rows: (1...5).map { item(.accepted, "Имя \($0)") }, isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.avatars.count, CompanionsSummaryModel.avatarLimit)
        XCTAssertEqual(summary?.overflow, 2)
        XCTAssertEqual(summary?.names, "Имя 1, Имя 2 и ещё 3")
    }

    /// The two caps are independent: three riders all fit the face cluster
    /// (no "+N" chip) while still exceeding the two-name line, so the third
    /// is accounted for there. Fails if one cap starts driving the other.
    func testThreeRidersFitTheClusterButNotTheNamesLine() {
        let summary = CompanionsSummaryModel.summarize(
            rows: (1...3).map { item(.accepted, "Имя \($0)") }, isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.overflow, 0)
        XCTAssertEqual(summary?.names, "Имя 1, Имя 2 и ещё 1")
    }

    // MARK: - Missing data

    /// An account with no display name still gets a readable row instead of
    /// an empty gap in the names line.
    func testMissingDisplayNameFallsBackToPlaceholder() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, nil)], isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.names, "Без имени")
    }

    /// An account with no avatar emoji still contributes a face to the
    /// cluster — a missing emoji must not shrink the group.
    func testMissingEmojiStillOccupiesTheCluster() {
        let summary = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Аня К.", emoji: nil), item(.accepted, "Дмитрий П.")],
            isOwn: true, lang: .ru)

        XCTAssertEqual(summary?.avatars.count, 2)
        XCTAssertEqual(summary?.avatars.first, "🙂")
    }

    /// Nothing to show is `nil`, not an empty plaque — the caller has its
    /// own empty/invite/loading/error states and must be allowed to use
    /// them. Fails if `summarize` starts returning a blank `Summary`.
    func testEmptyRosterHasNoPlaque() {
        XCTAssertNil(CompanionsSummaryModel.summarize(rows: [], isOwn: true, lang: .ru))
    }

    // MARK: - English

    /// The plaque is fully localized — every branch, not just the common
    /// one. Fails if a new string lands Russian-only.
    func testEnglishSubtitlesCoverEveryBranch() {
        let rode = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Ann")], isOwn: true, lang: .en)
        let waiting = CompanionsSummaryModel.summarize(
            rows: [item(.pending, "Ann"), item(.pending, "Dan")], isOwn: true, lang: .en)
        let mixed = CompanionsSummaryModel.summarize(
            rows: [item(.accepted, "Ann"), item(.pending, "Dan")], isOwn: true, lang: .en)
        let declined = CompanionsSummaryModel.summarize(
            rows: [item(.declined, "Ann")], isOwn: true, lang: .en)
        let overflow = CompanionsSummaryModel.summarize(
            rows: (1...4).map { item(.accepted, "P\($0)") }, isOwn: true, lang: .en)

        XCTAssertEqual(rode?.subtitle, "Rode along with you")
        XCTAssertEqual(waiting?.subtitle, "Waiting for replies")
        XCTAssertEqual(mixed?.subtitle, "Rode along with you · 1 more pending")
        XCTAssertEqual(declined?.subtitle, "Declined the invite")
        XCTAssertEqual(overflow?.names, "P1, P2 and 2 more")
    }
}
