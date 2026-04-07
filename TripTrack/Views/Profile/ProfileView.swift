import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var settings = SettingsManager.shared

    // Profile avatar
    @State private var selectedAvatar: String = "😎"
    @State private var isEditingAvatar = false
    @State private var avatarBounce = false

    @State private var showStats = false
    @State private var showBadges = false
    @State private var showGarage = false

    private let profileAvatars = ["😎", "🧑‍💻", "👨‍🚀", "🧔", "🤠", "🥷", "🏂", "🎸"]

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        ScrollView {
            VStack(spacing: 16) {
                avatarCard(c)

                // Driver Level Card
                DriverLevelView(
                    xp: settings.profileXP,
                    level: settings.profileLevel
                )

                // Quick stats row
                quickStatsRow(c, isRu: isRu)

                // Vehicle Card
                if let vehicle = selectedVehicle {
                    VehicleCardView(vehicle: vehicle)
                }

                // Garage button
                Button { showGarage = true } label: {
                    profileNavButton(
                        icon: "car.2.fill",
                        iconColor: AppTheme.blue,
                        label: isRu ? "Гараж" : "Garage",
                        c: c
                    )
                }
                .buttonStyle(.plain)

                // Badges & Stats side by side
                HStack(spacing: 12) {
                    Button { showBadges = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(AppTheme.yellow)
                            Text(AppStrings.badges(lang.language))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(c.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .surfaceCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)

                    Button { showStats = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(AppTheme.accent)
                            Text(AppStrings.stats(lang.language))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(c.text)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .surfaceCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }

                themeCard(c, isRu: isRu)
                languageCard(c, isRu: isRu)

                aboutCard(c, isRu: isRu)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .onAppear {
            selectedAvatar = settings.avatarEmoji
            settings.reloadGamificationState()
        }
        .sheet(isPresented: $showStats) {
            StatsView(tripManager: mapVM.tripManager)
        }
        .sheet(isPresented: $showBadges) {
            BadgesView(trips: mapVM.tripManager.fetchTrips())
        }
        .sheet(isPresented: $showGarage) {
            GarageView()
        }
    }

    private var selectedVehicle: Vehicle? {
        if let id = settings.selectedVehicleId {
            return settings.vehicles.first { $0.id == id }
        }
        return settings.vehicles.first
    }

    private func quickStatsRow(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                showStats = true
            } label: {
                quickStatPill(
                    icon: "flame.fill",
                    value: "\(settings.currentStreak)",
                    label: isRu ? "серия" : "streak",
                    color: AppTheme.accent, c: c
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                showStats = true
            } label: {
                quickStatPill(
                    icon: "car.fill",
                    value: String(format: "%.0f", mapVM.cachedTotalKm),
                    label: isRu ? "км" : "km",
                    color: AppTheme.green, c: c
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                showStats = true
            } label: {
                quickStatPill(
                    icon: "flag.fill",
                    value: "\(mapVM.cachedTripCount)",
                    label: isRu ? "поездок" : "trips",
                    color: AppTheme.blue, c: c
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func quickStatPill(icon: String, value: String, label: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 12)
    }

    private func profileNavButton(icon: String, iconColor: Color, label: String, c: AppTheme.Colors) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Avatar Card (Profile)

    private func avatarCard(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 12) {
            HStack {
                Label {
                    Text(lang.language == .ru ? "Аватар" : "Avatar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                } icon: {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditingAvatar.toggle()
                    }
                } label: {
                    Image(systemName: isEditingAvatar ? "checkmark" : "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isEditingAvatar ? AppTheme.accent : c.textTertiary)
                        .frame(width: 28, height: 28)
                }
            }

            Text(selectedAvatar)
                .font(.system(size: 48))
                .frame(width: 72, height: 72)
                .background(Circle().fill(c.cardAlt))
                .scaleEffect(avatarBounce ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: avatarBounce)

            if isEditingAvatar {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(profileAvatars, id: \.self) { emoji in
                        Button {
                            Haptics.tap()
                            selectedAvatar = emoji
                            settings.avatarEmoji = emoji
                            settings.saveSettings()
                            // Bounce the main avatar
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                avatarBounce = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                avatarBounce = false
                            }
                        } label: {
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(width: 48, height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedAvatar == emoji ? AppTheme.accentBg : c.cardAlt)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedAvatar == emoji ? AppTheme.accent : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Theme Card

    private func themeCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(AppStrings.theme(lang.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            } icon: {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.yellow)
            }

            HStack(spacing: 8) {
                themeChip(
                    label: AppStrings.dark(lang.language),
                    icon: "moon.fill",
                    isActive: themeManager.mode == .dark || (themeManager.mode == .system && scheme == .dark),
                    c: c
                ) { themeManager.mode = .dark }

                themeChip(
                    label: AppStrings.light(lang.language),
                    icon: "sun.max.fill",
                    isActive: themeManager.mode == .light || (themeManager.mode == .system && scheme == .light),
                    c: c
                ) { themeManager.mode = .light }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Language Card

    private func languageCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(AppStrings.lang(lang.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            } icon: {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.blue)
            }

            HStack(spacing: 8) {
                themeChip(label: "English", icon: nil, isActive: lang.language == .en, c: c) {
                    lang.language = .en
                }
                themeChip(label: "Русский", icon: nil, isActive: lang.language == .ru, c: c) {
                    lang.language = .ru
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - About Card

    private func aboutCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 12) {
            // Branding
            VStack(spacing: 4) {
                Text("TRIP TRACK")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(AppTheme.accent)
                    .tracking(3)

                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.1")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)

                Text("\(AppStrings.developer(lang.language)): OneZee")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }

            // Social links — compact grid
            HStack(spacing: 10) {
                socialTile(
                    assetIcon: "TelegramIcon",
                    iconColor: Color(red: 0.16, green: 0.57, blue: 0.86),
                    label: "Telegram",
                    url: "https://t.me/onezee_co",
                    c: c
                )
                socialTile(
                    assetIcon: "YouTubeIcon",
                    iconColor: Color(red: 1.0, green: 0.0, blue: 0.0),
                    label: "YouTube",
                    url: "https://www.youtube.com/@onezee_dev",
                    c: c
                )
                socialTile(
                    assetIcon: "GitHubIcon",
                    iconColor: c.text,
                    label: "GitHub",
                    url: "https://github.com/OneZee23/trip-track-ios",
                    c: c
                )
            }
        }
    }

    private func socialTile(assetIcon: String, iconColor: Color, label: String, url: String, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            if let u = URL(string: url) {
                UIApplication.shared.open(u)
            }
        } label: {
            VStack(spacing: 6) {
                Image(assetIcon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22, alignment: .center)
                    .foregroundStyle(iconColor)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .surfaceCard(cornerRadius: 12)
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Helpers

    private func themeChip(label: String, icon: String?, isActive: Bool, c: AppTheme.Colors, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isActive ? .white : c.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? AppTheme.accent : c.cardAlt)
            )
        }
        .buttonStyle(.plain)
    }
}
