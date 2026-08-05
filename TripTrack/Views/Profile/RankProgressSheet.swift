import SwiftUI

/// Driver-level surface behind the header LVL pill (fork FK-2). Read-only
/// view over `settings.profileXP/profileLevel` + `LevelSystem`/`DriverRank`;
/// also the new home for «Награды» since the canon Я dropped the badges tile.
/// Built NEW on purpose — `DriverLevelView` belongs to the user's uncommitted
/// batch and must not be edited.
struct RankProgressSheet: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    /// Needed locally: nested sheets are NEW presentations — the
    /// `.preferredColorScheme` ProfileView applies to THIS sheet does not
    /// reach them (see ProfileView's sheet comments), so we re-apply it.
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @State private var showBadges = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let level = settings.profileLevel
        let xp = settings.profileXP
        let rank = DriverRank.from(level: level)
        let progress = LevelSystem.progressToNextLevel(xp: xp, level: level)
        let xpCurrent = xp - LevelSystem.xpForLevel(level)
        let xpNeeded = LevelSystem.xpForNextLevel(level) - LevelSystem.xpForLevel(level)
        let isMaxLevel = level >= LevelSystem.maxLevel

        VStack(spacing: 0) {
            // Title row — same chrome as the settings sheet.
            HStack {
                Text(AppStrings.rankProgressTitle(lang.language))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(c.text)
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    ZStack {
                        Circle().fill(c.cardAlt)
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 10) {
                    // Rank card
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(rank.color.opacity(0.15))
                                .frame(width: 64, height: 64)
                            Image(systemName: rank.icon)
                                .font(.system(size: 28))
                                .foregroundStyle(rank.color)
                        }

                        LvlPill(level: level, rankTitle: rank.title(lang.language))

                        VStack(spacing: 6) {
                            VehicleXPBar(progress: isMaxLevel ? 1 : progress, tint: rank.color)
                            Text(isMaxLevel
                                 ? "\(xp) XP"
                                 : "\(xpCurrent) / \(xpNeeded) XP")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(c.textSecondary)
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 14)
                    .surfaceCard(cornerRadius: 16)

                    // Awards → existing BadgesView
                    VStack(spacing: 0) {
                        SettingsIconRow(
                            icon: "trophy.fill",
                            iconColor: AppTheme.yellow,
                            iconBg: AppTheme.yellow.opacity(0.12),
                            title: AppStrings.awards(lang.language),
                            action: { showBadges = true }
                        ) {
                            SettingsRowChevron()
                        }
                        .accessibilityIdentifier("rank_awards_row")
                    }
                    .surfaceCard(cornerRadius: 16)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("rank_sheet")
        .sheet(isPresented: $showBadges) {
            BadgesView(trips: mapVM.tripManager.fetchTrips())
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                // Without this, app-theme dark + system light opened a
                // LIGHT badges list over the dark rank sheet.
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
    }
}
