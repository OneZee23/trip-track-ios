import SwiftUI

/// One club's page (Figma 1934:160) — a preview, and honest about it: the
/// «СКОРО» pill in the bar, «Что будет в клубе» as a list of promises, and a
/// footnote that names when this arrives.
///
/// The only live thing on the page is the button: it puts you on this club's
/// waitlist and the count above it is the real number of people who did the
/// same.
struct ClubDetailView: View {
    let club: Club

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var waitlist = GroupsWaitlistStore.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            CustomNavBar(title: club.name(l)) {
                SoonBadge()
            }

            ScrollView {
                VStack(spacing: 0) {
                    ClubAvatar(club: club, size: 84, emojiSize: 40)
                        .padding(.top, 8)

                    Text(club.name(l))
                        .font(.inter(21, weight: .heavy))
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)

                    Text(waitlist.waiting(forClub: club.id).map {
                        AppStrings.clubWaitingCount(l, count: $0)
                    } ?? AppStrings.clubBeFirst(l))
                        .font(.inter(13))
                        .foregroundStyle(c.textTertiary)
                        .padding(.top, 4)

                    Text(club.blurb(l))
                        .font(.inter(14))
                        .lineSpacing(5)
                        .foregroundStyle(c.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.horizontal, 8)

                    perksCard(c: c, l: l)
                        .padding(.top, 22)

                    ClubJoinButton(club: club)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)

                    Text(AppStrings.clubComingFootnote(l))
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("club_detail")
        .task { await waitlist.refresh() }
    }

    private func perksCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.clubPerksTitle(l).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.44)
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(Club.perks(l).enumerated()), id: \.element.id) { index, perk in
                    HStack(spacing: 12) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(c.text)
                            .frame(width: 26)

                        Text(perk.text)
                            .font(.inter(14, weight: .semibold))
                            .foregroundStyle(c.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)

                    if index < Club.perks(l).count - 1 {
                        Rectangle()
                            .fill(c.border)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: 16)
        }
    }
}
