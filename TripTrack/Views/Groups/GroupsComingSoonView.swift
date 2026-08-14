import SwiftUI

/// Groups-tab teaser (Figma 117:2265 «09 · Группы · Скоро»): an IdleRing hero,
/// example club chips, «Уведомить меня» and «Посмотреть что будет».
///
/// Two things here used to be theatre and are not any more:
///  • «Уведомить меня» set a local `@AppStorage` bool. Nothing on the server
///    knew anyone wanted this, so nobody could ever have been notified — the
///    button promised a message that had no way of being sent. It now joins a
///    real waitlist AND asks for notification permission, which is the other
///    half of being able to keep that promise.
///  • «Уже ждут 1 240 человек» was a string in the layout. It is the count of
///    that waitlist now, and it does not appear at all until somebody is on it.
struct GroupsComingSoonView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var waitlist = GroupsWaitlistStore.shared
    @ObservedObject private var auth = AuthService.shared

    /// Type-erased because the stack carries two kinds of destination: the
    /// catalogue (one of a kind) and a club (many).
    @State private var path = NavigationPath()

    /// The non-club destinations of this tab.
    private enum GroupsRoute: Hashable { case catalog }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        NavigationStack(path: $path) {
            content(c: c, l: l)
                .navigationDestination(for: GroupsRoute.self) { _ in
                    ClubsCatalogView()
                }
                .navigationDestination(for: Club.self) { club in
                    // A pushed screen with its own bar; the tab bar stays,
                    // exactly as canon draws it.
                    ClubDetailView(club: club)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .task { await waitlist.refresh() }
    }

    @ViewBuilder
    private func content(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            // Page header (feed-header convention: 28 heavy, tracking −0.56).
            HStack {
                Text(AppStrings.tabGroups(l))
                    .font(.inter(28, weight: .heavy))
                    .tracking(-0.56)
                    .foregroundStyle(c.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 10)

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                // Shared Figma 114:151 hero (accent-tinted outer ring + peach
                // accentBg disc) — same component instance the frame places
                // here (117:2280).
                IdleRing()

                Text(AppStrings.groupsComingTitle(l))
                    .font(.inter(21, weight: .heavy))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)

                Text(AppStrings.groupsComingBody(l))
                    .font(.inter(14))
                    .lineSpacing(6)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                chipRows(c: c)
                    .padding(.top, 18)

                notifyButton(c: c, l: l)
                    .padding(.top, 22)

                previewButton(c: c, l: l)
                    .padding(.top, 10)

                waitlistLine(c: c, l: l)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 96)
        .frame(maxWidth: .infinity)
        .background(c.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: waitlist.state.joined)
    }

    // MARK: - Chips

    /// Example clubs (Figma order). Two fixed rows so the wrap matches the
    /// frame on every device width. Miata/VAG names stay untranslated.
    private func chipRows(c: AppTheme.Colors) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                chip("🏎 Miata Club", c: c)
                chip("⚙️ VAG", c: c)
            }
            HStack(spacing: 7) {
                chip(AppStrings.groupsChipTrucking(lang.language), c: c)
                chip(AppStrings.groupsChipOffroad(lang.language), c: c)
            }
        }
    }

    private func chip(_ text: String, c: AppTheme.Colors) -> some View {
        Text(text)
            .font(.inter(13, weight: .semibold))
            .foregroundStyle(c.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(c.card, in: Capsule())
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    // MARK: - CTAs

    private func notifyButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let joined = waitlist.state.joined
        return Button {
            Haptics.success()
            Task { await waitlist.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: joined ? "checkmark" : "bell.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(joined ? AppStrings.groupsNotifyDone(l) : AppStrings.groupsNotifyMe(l))
                    .font(.inter(14, weight: .bold))
            }
            .foregroundStyle(joined ? AppTheme.accent : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                joined ? AnyShapeStyle(AppTheme.accentBg) : AnyShapeStyle(AppTheme.accent),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .shadow(
                color: joined ? .clear : AppTheme.accent.opacity(0.3),
                radius: 1.5, y: 1
            )
        }
        .buttonStyle(.plain)
        .disabled(waitlist.isBusy)
        .accessibilityIdentifier("groups_notify_cta")
    }

    /// «Посмотреть что будет» (canon 117:2265) — the second CTA, and the one
    /// that was drawn in Figma but never built: the tab had no way into the
    /// catalogue at all.
    private func previewButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        NavigationLink(value: GroupsRoute.catalog) {
            Text(AppStrings.groupsPreviewCTA(l))
                .font(.inter(14, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(AppTheme.accent, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        .accessibilityIdentifier("groups_preview_cta")
    }

    /// The real number, and only when there IS one. «Уже ждут 0 человек» is
    /// worse than silence; an invitation is better than either.
    @ViewBuilder
    private func waitlistLine(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 4) {
            Text(waitlist.state.total > 0
                 ? AppStrings.groupsWaitlistCount(l, count: waitlist.state.total)
                 : AppStrings.groupsWaitlistFirst(l))
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .accessibilityIdentifier("groups_waitlist_count")

            // A guest's place in the queue is recorded, but a push needs an
            // account to land on — say so instead of quietly not sending one.
            if waitlist.state.joined && !auth.isSignedIn {
                Text(AppStrings.groupsNotifySignInHint(l))
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
