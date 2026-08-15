import SwiftUI

// MARK: - Достижение (Figma 899:375 / 917:385 / 918:395 / 1689:132)

/// One achievement, full screen: the medallion, what it takes, and — when it is
/// yours — the pin that promotes it to the top of the Я tab.
///
/// Four canon states off two flags. `isUnlocked` splits earned from not; on the
/// locked side `badge.isHidden` splits a rule you can read from one you cannot
/// («? ? ?»). The fourth state is the pin confirmation, which is a dialog over
/// the unlocked one rather than a screen of its own.
///
/// The pin is the only action here and the only thing that writes anything.
/// `SettingsManager.pinnedBadgeId` is the store — the same key
/// `ProfileAchievementsSection` already reads to decide whether its featured row
/// says «Закреплено» or silently falls back to the rarest unlocked badge. A
/// second UserDefaults key here would leave that row reading empty forever.
struct AchievementDetailView: View {
    let badge: Badge
    let isUnlocked: Bool

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    /// Observed, not read once: pinning from the nav bar has to repaint the
    /// pin glyph and the «Закреплено» chip in the same frame.
    @ObservedObject private var settings = SettingsManager.shared
    @State private var confirmingPin = false

    /// Locked AND hidden — the badge whose rule is itself the secret. A hidden
    /// badge that is already earned is just an earned badge.
    private var isSecret: Bool { !isUnlocked && badge.isHidden }

    private var isPinned: Bool { settings.pinnedBadgeId == badge.id }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ScrollView {
            VStack(spacing: 14) {
                medallion(c)
                titleText(c, l)
                classChip(c, l)

                // The rule. A secret badge has none to print — telling you what
                // to do is exactly what it withholds.
                if !isSecret {
                    Text(badge.description(l))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                        .multilineTextAlignment(.center)
                        // Canon's 280pt is a 360pt artboard measuring itself;
                        // capping the measure keeps the line length readable on
                        // a 440pt phone instead of stretching it edge to edge.
                        .frame(maxWidth: 320)
                }

                storyCard(c, l)
                statusRow(c, l)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hideAppTabBar()
        .safeAreaInset(edge: .top, spacing: 0) {
            navRow(l)
        }
        // Confirm, then write — through the house component, not a copy of it.
        // See CLAUDE.md «Dialogs».
        .appConfirm(
            isPresented: $confirmingPin,
            title: AppStrings.achievementPinConfirmTitle(l),
            message: AppStrings.achievementPinConfirmBody(l),
            actions: [
                AppDialogAction(AppStrings.achievementPin(l),
                                identifier: "achievement_pin_confirm") { pin() }
            ]
        )
        .accessibilityIdentifier("achievement_detail")
    }

    // MARK: - Nav

    /// Canon hangs the pin off the trailing side of the bar (899:378 vs the
    /// empty 917:392) — a locked badge gets no affordance at all, because there
    /// is nothing to promote.
    private func navRow(_ l: LanguageManager.Language) -> some View {
        CustomNavBar(title: AppStrings.achievementDetailTitle(l)) {
            if isUnlocked {
                Button {
                    togglePin()
                } label: {
                    NavCircleIcon(systemImage: isPinned ? "pin.slash.fill" : "pin.fill")
                }
                .buttonStyle(.plain)
                // Icon-only control: the verb lives in the label, and it names
                // what the tap DOES, not what the badge currently is.
                .accessibilityLabel(isPinned
                    ? AppStrings.achievementUnpin(l)
                    : AppStrings.achievementPin(l))
                .accessibilityIdentifier("achievement_pin")
            }
        }
    }

    // MARK: - Medallion

    /// 112pt disc. The rarity owns its colours (`BadgeRarityStyle`) — the ring
    /// and the glow are the same hue at two alphas, which is what makes a
    /// legendary read as gold from across the room.
    private func medallion(_ c: AppTheme.Colors) -> some View {
        let rarity = badge.displayRarity
        return ZStack {
            Circle()
                .fill(isUnlocked ? rarity.chipTint : c.cardAlt)
                // Canon's 22pt blur is a CSS radius; SwiftUI's is half of it.
                .shadow(color: isUnlocked ? rarity.chipRing.opacity(0.45) : .clear, radius: 11)

            if isUnlocked {
                Circle().strokeBorder(rarity.chipRing, lineWidth: 4)
            } else if isSecret {
                // Dashed, not solid: the outline of something not yet filled in.
                Circle().strokeBorder(
                    c.textTertiary,
                    style: StrokeStyle(lineWidth: 2.5, dash: [7, 5])
                )
            } else {
                Circle().strokeBorder(c.textTertiary, lineWidth: 3)
            }

            // Canon draws emoji; the app has an SF Symbol per badge and keeps
            // it, so the grid and this screen show the same mark.
            Image(systemName: isSecret ? "questionmark" : badge.icon)
                .font(.system(size: isSecret ? 46 : 44, weight: isSecret ? .heavy : .regular))
                .foregroundStyle(isUnlocked ? rarity.chipText : c.textTertiary)
        }
        .frame(width: 112, height: 112)
    }

    // MARK: - Title & class

    private func titleText(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        // Two lines and a floor on the scale — «Воскресный водитель» at 24pt
        // heavy already runs the full 360pt width.
        Text(isSecret ? AppStrings.achievementsSecretTitle(l) : badge.title(l))
            .font(.system(size: 24, weight: .heavy))
            .foregroundStyle(isSecret ? c.textSecondary : c.text)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    /// «★ ЛЕГЕНДАРНОЕ» — or «🔒 СЕКРЕТНОЕ», which is the one badge class that
    /// isn't a rarity: an unreadable rule can't be ranked by how many people
    /// have it.
    @ViewBuilder
    private func classChip(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        if isSecret {
            chip(
                icon: "lock.fill",
                text: AppStrings.achievementsSecretCaption(l).uppercased(l),
                ink: c.textSecondary,
                background: c.cardAlt,
                kerning: 0.48
            )
        } else {
            let rarity = badge.displayRarity
            chip(
                icon: "star.fill",
                text: rarity.title(l).uppercased(l),
                ink: rarity.chipText,
                background: rarity.rowTint,
                kerning: 0.48
            )
        }
    }

    // MARK: - Story card

    /// The one card on the screen, and it says something different in each
    /// state: how rare this is when we know, and «keep driving» when the badge
    /// is a surprise. A locked badge with no global figure gets no card at all
    /// — canon fills that slot with «2 430 / 50 000 км», and no badge in the
    /// catalogue carries a target to count toward: `checkUnlocked` is an opaque
    /// predicate over `BadgeStats`, not a threshold this screen can read. An
    /// invented bar would be a made-up number under a real one.
    @ViewBuilder
    private func storyCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        if isSecret {
            card {
                Text(AppStrings.achievementsEmptyHint(l))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
            }
        } else if let percent = badge.globalUnlockPercent {
            card {
                Text(AppStrings.achievementsEarnedBy(l, percent: Badge.unlockShareText(percent, l)))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(badge.displayRarity.chipText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .surfaceCard(cornerRadius: 20)
    }

    // MARK: - Status

    /// Earned or not, plus the pin state when it is on. Two capsules rather
    /// than one line, so «Закреплено» can appear and disappear without the
    /// earned state moving.
    private func statusRow(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            if isUnlocked {
                chip(
                    icon: "checkmark",
                    text: AppStrings.unlocked(l).capitalized,
                    ink: c.text,
                    iconInk: AppTheme.green,
                    background: AppTheme.green.opacity(0.12)
                )

                if isPinned {
                    chip(
                        icon: "pin.fill",
                        text: AppStrings.achievementPinned(l),
                        ink: AppTheme.accent,
                        background: AppTheme.accentDim
                    )
                    .transition(.opacity)
                }
            } else {
                chip(
                    icon: "lock.fill",
                    text: AppStrings.locked(l),
                    ink: c.textSecondary,
                    background: c.cardAlt
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPinned)
    }

    // MARK: - Chip

    private func chip(
        icon: String,
        text: String,
        ink: Color,
        iconInk: Color? = nil,
        background: Color,
        kerning: CGFloat = 0
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(iconInk ?? ink)

            Text(text)
                .font(.system(size: 12.5, weight: .bold))
                .kerning(kerning)
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(background, in: Capsule())
    }

    // MARK: - Pin

    private func togglePin() {
        if isPinned {
            // Undo needs no confirmation — nothing is lost, and the profile
            // simply falls back to the rarest unlocked badge.
            Haptics.tap()
            settings.pinnedBadgeId = ""
        } else {
            Haptics.tap()
            confirmingPin = true
        }
    }

    /// The whole point of this screen: the single source of truth the Я tab
    /// reads. `SettingsManager` persists it in its own `didSet`.
    private func pin() {
        Haptics.success()
        settings.pinnedBadgeId = badge.id
    }

    // MARK: - Copy

}
