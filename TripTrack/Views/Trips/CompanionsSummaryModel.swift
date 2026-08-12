import Foundation

/// What the condensed «Попутчики» plaque on the trip detail says: a small
/// cluster of avatars, the names under them, and one line explaining what
/// those names mean.
///
/// Pulled out of the view as a pure function for the same reason
/// `CompanionsCardModel` is (`TripTrackTests/CompanionsSummaryTests.swift`) —
/// the interesting part isn't the layout, it's WHICH people a mixed roster
/// puts forward and what it claims about them. A plaque that says «Ездили
/// вместе с вами» over the name of someone who hasn't answered the invite
/// yet is a lie the layout can't catch.
///
/// The rule: the plaque speaks for the people it actually shows. Accepted
/// companions come first and the line reads "rode with you"; if nobody has
/// accepted, it shows the people who were invited and says it's waiting on
/// them; if every invite was declined, it says that instead of pretending
/// the trip had company. Pending invites that coexist with accepted ones
/// are never dropped silently — they move into the second line's tail
/// (`companionsPendingSuffix`), because the whole point of the plaque is
/// that the owner shouldn't have to open the roster to know where things
/// stand.
enum CompanionsSummaryModel {
    /// Beyond three, overlapping circles stop reading as faces and start
    /// reading as a texture — the rest become a "+N" chip.
    static let avatarLimit = 3
    /// Two names is what fits on one line at the plaque's font size for
    /// realistic Russian display names («Аня К., Дмитрий П.»).
    static let nameLimit = 2

    struct Summary: Equatable {
        /// Emoji avatars for the featured people, in the same order as the
        /// names line, capped at `avatarLimit`.
        let avatars: [String]
        /// How many featured people the avatar cluster couldn't fit — 0
        /// when they all did. Rendered as a "+N" circle.
        let overflow: Int
        /// «Аня К., Дмитрий П. и ещё 2»
        let names: String
        /// «Ездили вместе с вами · ещё один ждёт»
        let subtitle: String
    }

    /// `nil` means there is nothing to put on a plaque — an empty roster, or
    /// one that holds nothing but rows this viewer shouldn't be told about.
    /// The caller keeps its own empty/invite/loading/error states
    /// (`CompanionsCardModel.decide`); this only describes a roster that
    /// HAS people in it.
    static func summarize(
        rows: [CompanionItem],
        isOwn: Bool,
        lang: LanguageManager.Language
    ) -> Summary? {
        let accepted = rows.filter { $0.status == .accepted }
        let pending = rows.filter { $0.status == .pending }
        let declined = rows.filter { $0.status == .declined }

        let featured: [CompanionItem]
        let subtitle: String

        if !accepted.isEmpty {
            featured = accepted
            let base = isOwn
                ? AppStrings.companionsRodeWithYou(lang)
                : AppStrings.companionsRodeTogether(lang)
            subtitle = pending.isEmpty
                ? base
                : base + " · " + AppStrings.companionsPendingSuffix(pending.count, lang)
        } else if !pending.isEmpty {
            featured = pending
            subtitle = AppStrings.companionsAwaitingReply(pending.count, lang)
        } else if !declined.isEmpty {
            featured = declined
            subtitle = AppStrings.companionsAllDeclined(declined.count, lang)
        } else {
            return nil
        }

        return Summary(
            avatars: featured.prefix(avatarLimit).map { $0.avatarEmoji ?? "🙂" },
            overflow: max(0, featured.count - avatarLimit),
            names: namesLine(featured, lang: lang),
            subtitle: subtitle
        )
    }

    private static func namesLine(
        _ people: [CompanionItem], lang: LanguageManager.Language
    ) -> String {
        let shown = people.prefix(nameLimit)
            .map { $0.displayName ?? AppStrings.companionsNoName(lang) }
            .joined(separator: ", ")
        let rest = people.count - min(people.count, nameLimit)
        guard rest > 0 else { return shown }
        return shown + " " + AppStrings.companionsAndMore(rest, lang)
    }
}
