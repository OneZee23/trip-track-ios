import SwiftUI

/// Groups-tab teaser (Figma 117:2265 «09 · Группы · Скоро») — the clubs
/// feature is frontend-only for 6.1.0: an IdleRing hero, example club
/// chips and a local-only notify-me CTA. No backend; the waitlist line is
/// static showcase copy from the frame.
struct GroupsComingSoonView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    /// Local-only waitlist intent — flips the CTA to its "done" state.
    @AppStorage("groupsNotifyRequested") private var notifyRequested = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            // Page header (feed-header convention: 28 heavy, tracking −0.56).
            HStack {
                Text(AppStrings.tabGroups(l))
                    .font(.system(size: 28, weight: .heavy))
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
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)

                Text(AppStrings.groupsComingBody(l))
                    .font(.system(size: 14))
                    .lineSpacing(6)
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                chipRows(c: c)
                    .padding(.top, 18)

                notifyButton(c: c, l: l)
                    .padding(.top, 22)

                Text(AppStrings.groupsWaitlistCount(l))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 96)
        .frame(maxWidth: .infinity)
        .background(c.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: notifyRequested)
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(c.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(c.card, in: Capsule())
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    // MARK: - CTA

    private func notifyButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            guard !notifyRequested else { return }
            Haptics.success()
            notifyRequested = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: notifyRequested ? "checkmark" : "bell.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(notifyRequested ? AppStrings.groupsNotifyDone(l) : AppStrings.groupsNotifyMe(l))
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(notifyRequested ? AppTheme.accent : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                notifyRequested ? AnyShapeStyle(AppTheme.accentBg) : AnyShapeStyle(AppTheme.accent),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .shadow(
                color: notifyRequested ? .clear : AppTheme.accent.opacity(0.3),
                radius: 1.5, y: 1
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("groups_notify_cta")
    }
}
