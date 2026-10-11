import SwiftUI

/// A person's avatar as every list of people draws it: the emoji in a disc,
/// with their PRO frame when the server says they wear one (0.8.9).
///
/// The feed and comments drew the frame; «Найти людей», followers, reactions
/// and the suggestions carousel did not, though the server sends `avatarFrame`
/// on all of them — someone paying for PRO looked free in half the places
/// their name appears. One view, so the next list cannot forget it.
struct PersonAvatar: View {
    let author: SocialAuthor
    var size: CGFloat = 36
    var fill: Color? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Circle()
            .fill(fill ?? c.cardAlt)
            .frame(width: size, height: size)
            .overlay { Text(author.avatarEmoji ?? "🚗").font(.inter(size * 0.53)) }
            // `from` reads an unknown or absent frame as none, and the server
            // sends a frame only for a live subscription — nothing to recheck.
            .avatarFrame(AvatarFrame.from(author.avatarFrame), lineWidth: size >= 56 ? 3 : 2)
            // The name beside it says who this is.
            .accessibilityHidden(true)
    }
}

/// The name with the PRO badge after it, by the one rule the feed uses
/// (`PlusBadgeVisibility`): someone else's badge always shows, your own obeys
/// the privacy switch.
struct PersonName: View {
    let author: SocialAuthor
    let font: Font
    var badgeHeight: CGFloat = 15
    /// Whose row this is, decided ONCE by the list (`PersonName.ownId()`):
    /// the account id lives in the Keychain, and a read per row per redraw is
    /// the cost the feed avoids by passing `isOwn` in.
    var ownId: UUID? = nil

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(Self.name(author, lang.language))
                .font(font)
                .foregroundStyle(c.text)
                .lineLimit(1)
                .truncationMode(.tail)
            if showsBadge {
                ProBadge(height: badgeHeight)
            }
        }
    }

    private var showsBadge: Bool {
        PlusBadgeVisibility.shows(isPlus: author.isPlus,
                                  isOwn: ownId != nil && author.id == ownId,
                                  showsOwnBadge: SettingsManager.shared.showPlusBadge)
    }

    /// The signed-in account, read once per list.
    static func ownId() -> UUID? { TokenStore.shared.accountId }

    static func name(_ author: SocialAuthor, _ lang: LanguageManager.Language) -> String {
        author.displayName ?? AppStrings.blockedListUser(lang)
    }
}
