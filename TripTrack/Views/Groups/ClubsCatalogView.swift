import SwiftUI

/// «Клубы» — the preview behind «Посмотреть что будет» (Figma «09 · Группы ·
/// Каталог (превью)»).
///
/// A catalogue of things that do not exist yet, and it says so twice: the
/// «СКОРО» pill beside the title and, on every row, a count of people WAITING
/// rather than of members. The counts come from the waitlist, so the page is a
/// preview whose numbers are nonetheless true.
struct ClubsCatalogView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var waitlist = GroupsWaitlistStore.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            // Our own bar — a pushed screen would otherwise get UIKit's blue
            // «‹ Back», which is exactly the borrowed chrome this app never
            // ships (CLAUDE.md «Dialogs»). Title lives in the big header
            // below, as canon draws it, so the bar carries the control only.
            CustomNavBar(title: "") { EmptyView() }

            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AppStrings.clubsTitle(l))
                        .font(.inter(28, weight: .heavy))
                        .tracking(-0.56)
                        .foregroundStyle(c.text)
                    Spacer(minLength: 0)
                    SoonBadge()
                }

                Text(AppStrings.clubsSubtitle(l))
                    .font(.inter(13))
                    .foregroundStyle(c.textSecondary)

                LazyVStack(spacing: 10) {
                    ForEach(Club.all) { club in
                        NavigationLink(value: club) {
                            row(club, c: c, l: l)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("clubs_catalog")
        .task { await waitlist.refresh() }
    }

    // MARK: - Row

    private func row(_ club: Club, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 12) {
            ClubAvatar(club: club, size: 44, emojiSize: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(club.name(l))
                    .font(.inter(15, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)

                // «N ждут», never «N участников»: nobody is a member of a club
                // that hasn't opened, and a made-up membership number is the
                // exact thing this screen was rebuilt to stop printing.
                Text(waitlist.waiting(forClub: club.id).map {
                    AppStrings.clubWaitingCount(l, count: $0)
                } ?? AppStrings.clubBeFirst(l))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ClubJoinButton(club: club, compact: true)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 16)
        .contentShape(Rectangle())
    }
}

// MARK: - Shared bits

/// «СКОРО» pill. One component, so the catalogue and the club page can never
/// disagree about how loudly the app admits this isn't built yet.
struct SoonBadge: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Text(AppStrings.clubsSoonBadge(lang.language))
            .font(.inter(10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(c.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(c.cardAlt, in: Capsule())
            .accessibilityIdentifier("clubs_soon_badge")
    }
}

struct ClubAvatar: View {
    let club: Club
    var size: CGFloat = 44
    var emojiSize: CGFloat = 22

    var body: some View {
        Circle()
            .fill(club.tint)
            .frame(width: size, height: size)
            .overlay { Text(club.emoji).font(.system(size: emojiSize)) }
    }
}

/// «Вступить» → «Ждёте». The button cannot join anything yet, so what it
/// actually does is put you on that club's waitlist — and it says «Ждёте»
/// afterwards rather than pretending you are a member.
struct ClubJoinButton: View {
    let club: Club
    var compact = false

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var waitlist = GroupsWaitlistStore.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let waiting = waitlist.isWaiting(forClub: club.id)

        Button {
            Haptics.selection()
            Task { await waitlist.toggle(clubKey: club.id) }
        } label: {
            HStack(spacing: 5) {
                if waiting {
                    Image(systemName: "checkmark")
                        .font(.system(size: compact ? 10 : 13, weight: .bold))
                }
                Text(waiting ? AppStrings.clubJoinWaiting(l) : AppStrings.clubJoin(l))
                    .font(.inter(compact ? 12 : 14, weight: .bold))
            }
            .foregroundStyle(waiting ? AppTheme.accent : c.text)
            .padding(.horizontal, compact ? 12 : 20)
            .padding(.vertical, compact ? 7 : 13)
            .background(
                waiting ? AnyShapeStyle(AppTheme.accentBg) : AnyShapeStyle(c.cardAlt),
                in: RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: waiting)
        .accessibilityIdentifier("club_join_\(club.id)")
    }
}
