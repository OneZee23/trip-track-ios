import SwiftUI

/// «Настройки» sheet (Figma 154:1365) — the gear behind the Я header.
/// Every row is a feature relocated from the pre-6.1.0 ProfileView body:
/// nothing is deleted, only re-homed. Forks honored: «Уведомления» is a
/// chevron row, not a toggle (FK-7 — no master push-toggle exists);
/// Язык/Тема/Средняя скорость use native confirmation dialogs (FK-8);
/// «Гараж» lives here (FK-9); «Фон профиля» stays reachable (FK-10).
struct ProfileSettingsSheet: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var notificationsInbox = NotificationsInboxStore.shared

    @AppStorage("distanceUnit") private var distanceUnit: String = "km"

    @State private var showNotificationPrefs = false
    @State private var showNotificationsInbox = false
    @State private var showUnits = false
    @State private var showLanguageDialog = false
    @State private var showThemeDialog = false
    @State private var showAvgSpeedDialog = false
    @State private var showGarage = false
    @State private var showCloudSync = false
    @State private var showDebugLogs = false
    @State private var showBackgroundPicker = false
    @State private var showSignOutAlert = false
    @State private var showSignOutPublishedDialog = false
    @State private var publishedAtSignOut = 0

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(l)

            ScrollView {
                VStack(spacing: 10) {
                    if auth.isSignedIn {
                        accountGroup(c, l)
                    }
                    preferencesGroup(c, l)
                    actionsGroup(c, l)
                    aboutGroup(c, l)
                    #if DEBUG
                    devGroup(c, l)
                    #endif
                    footer(c, l)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("settings_sheet")
        .sheet(isPresented: $showNotificationPrefs) {
            NotificationPreferencesView()
                .environmentObject(lang)
                .environmentObject(themeManager)
                // Same single detent as the inbox route — tall enough for
                // the footer note, and it can't re-resolve on re-render.
                .presentationDetents([.fraction(0.88)])
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showNotificationsInbox) {
            NotificationsInboxView()
                .environment(\.navBarInSheet, true)
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showUnits) {
            UnitsSheetWrapper()
                .environmentObject(lang)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showGarage) {
            GarageView()
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showCloudSync) {
            CloudSyncView()
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showDebugLogs) {
            DebugLogsView()
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showBackgroundPicker) {
            ProfileBackgroundPickerSheet()
                .environmentObject(lang)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .confirmationDialog(
            AppStrings.lang(l),
            isPresented: $showLanguageDialog,
            titleVisibility: .visible
        ) {
            Button("Русский") { lang.language = .ru }
            Button("English") { lang.language = .en }
            Button(AppStrings.cancel(l), role: .cancel) {}
        }
        .confirmationDialog(
            AppStrings.theme(l),
            isPresented: $showThemeDialog,
            titleVisibility: .visible
        ) {
            Button(AppStrings.themeSystem(l)) { themeManager.mode = .system }
            Button(AppStrings.dark(l)) { themeManager.mode = .dark }
            Button(AppStrings.light(l)) { themeManager.mode = .light }
            Button(AppStrings.cancel(l), role: .cancel) {}
        }
        .confirmationDialog(
            AppStrings.avgSpeedModeTitle(l),
            isPresented: $showAvgSpeedDialog,
            titleVisibility: .visible
        ) {
            Button(AppStrings.avgSpeedOverall(l)) { settings.avgSpeedMode = .overall }
            Button(AppStrings.avgSpeedMoving(l)) { settings.avgSpeedMode = .moving }
            Button(AppStrings.cancel(l), role: .cancel) {}
        }
        // Sign-out — same two-step semantics as CloudSyncView: with public
        // trips on the server → 3-way hide/keep dialog; without → straight
        // sign-out. Calls AuthService API only.
        .alert(
            AppStrings.signOutConfirmTitle(l),
            isPresented: $showSignOutAlert
        ) {
            Button(AppStrings.cancel(l), role: .cancel) {}
            Button(AppStrings.signOut(l), role: .destructive) {
                let count = auth.publishedTripCount()
                if count > 0 {
                    publishedAtSignOut = count
                    showSignOutPublishedDialog = true
                } else {
                    Task {
                        await auth.signOut()
                        dismiss()
                    }
                }
            }
        } message: {
            Text(AppStrings.signOutConfirmMessage(l))
        }
        .confirmationDialog(
            AppStrings.signOutPublishedTitle(l),
            isPresented: $showSignOutPublishedDialog,
            titleVisibility: .visible
        ) {
            Button(AppStrings.signOutHidePublic(l), role: .destructive) {
                Task {
                    await auth.unpublishAllPublicTrips()
                    await auth.signOut()
                    dismiss()
                }
            }
            Button(AppStrings.signOutKeepPublic(l)) {
                Task {
                    await auth.signOut()
                    dismiss()
                }
            }
            Button(AppStrings.cancel(l), role: .cancel) {}
        } message: {
            Text(AppStrings.publishedTripsSignOutMessage(l, count: publishedAtSignOut))
        }
    }

    // MARK: - Chrome

    /// The shared bar, so this sheet's chrome measures the same as every
    /// other screen's instead of a hand-sized row of its own. A sheet root has
    /// nothing to pop — it closes from the trailing side — so the back chevron
    /// is off and «×» is the one control (same shape as Discover). ProfileView
    /// hands the bar `navBarInSheet`, which is what lifts the row clear of the
    /// grabber UIKit draws over the sheet's top edge.
    private func navRow(_ l: LanguageManager.Language) -> some View {
        CustomNavBar(title: AppStrings.settingsTitle(l), showsBack: false) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.closeSheet(l))
        }
    }

    private func rowDivider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.borderBright)
            .frame(height: 1)
            .padding(.leading, 56) // 14 (px) + 30 (icon) + 12 (gap)
    }

    // MARK: - Group 1 — account (signed-in only)

    private func accountGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            SettingsIconRow(
                icon: "globe",
                title: AppStrings.settingsPublicProfile(l)
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.showOnPublicMap },
                    set: { setShowOnPublicMap($0) }
                ))
                .labelsHidden()
                .tint(AppTheme.accent)
                .scaleEffect(0.9)
            }
            .accessibilityIdentifier("settings_public_profile")

            rowDivider(c)

            // FK-7: chevron row → granular server prefs, NOT a fake master
            // toggle (no client- or server-side master push switch exists).
            SettingsIconRow(
                icon: "bell.fill",
                title: AppStrings.settingsNotifications(l),
                action: { showNotificationPrefs = true }
            ) {
                SettingsRowChevron()
            }
            .accessibilityIdentifier("settings_notifications")

            rowDivider(c)

            SettingsIconRow(
                icon: "tray.fill",
                title: AppStrings.settingsInbox(l),
                action: { showNotificationsInbox = true }
            ) {
                HStack(spacing: 8) {
                    if notificationsInbox.unreadCount > 0 {
                        Text(notificationsInbox.unreadCount > 99 ? "99+" : "\(notificationsInbox.unreadCount)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(AppTheme.accent, in: Capsule())
                            .fixedSize()
                    }
                    SettingsRowChevron()
                }
            }
        }
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Group 2 — preferences

    private func preferencesGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let isRu = l == .ru
        return VStack(spacing: 0) {
            SettingsIconRow(
                icon: "ruler",
                title: AppStrings.settingsUnits(l),
                action: { showUnits = true }
            ) {
                SettingsRowValue(text: GarageFormat.distanceShort(distanceUnit, isRu: isRu))
            }
            .accessibilityIdentifier("settings_units")

            rowDivider(c)

            SettingsIconRow(
                icon: "character.bubble",
                title: AppStrings.lang(l),
                action: { showLanguageDialog = true }
            ) {
                SettingsRowValue(text: isRu ? "Русский" : "English")
            }
            .accessibilityIdentifier("settings_language")

            rowDivider(c)

            SettingsIconRow(
                icon: "sun.max.fill",
                title: AppStrings.theme(l),
                action: { showThemeDialog = true }
            ) {
                SettingsRowValue(text: themeLabel(l))
            }
            .accessibilityIdentifier("settings_theme")

            rowDivider(c)

            SettingsIconRow(
                icon: "speedometer",
                title: AppStrings.settingsAvgSpeed(l),
                action: { showAvgSpeedDialog = true }
            ) {
                SettingsRowValue(text: settings.avgSpeedMode == .overall
                                 ? AppStrings.avgSpeedOverall(l)
                                 : AppStrings.avgSpeedMoving(l))
            }
        }
        .surfaceCard(cornerRadius: 16)
    }

    private func themeLabel(_ l: LanguageManager.Language) -> String {
        switch themeManager.mode {
        case .system: return AppStrings.themeSystem(l)
        case .dark: return AppStrings.dark(l)
        case .light: return AppStrings.light(l)
        }
    }

    // MARK: - Group 3 — actions

    private func actionsGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            SettingsIconRow(
                icon: "car.2.fill",
                title: AppStrings.garage(l),
                action: { showGarage = true }
            ) {
                SettingsRowChevron()
            }
            .accessibilityIdentifier("settings_garage")

            if auth.isSignedIn {
                rowDivider(c)

                SettingsIconRow(
                    icon: settings.cloudSyncEnabled ? "icloud.fill" : "icloud.slash",
                    title: AppStrings.settingsAccountSync(l),
                    action: { showCloudSync = true }
                ) {
                    SettingsRowChevron()
                }
                .accessibilityIdentifier("settings_account_sync")

                rowDivider(c)

                SettingsIconRow(
                    icon: "square.and.arrow.up",
                    title: AppStrings.settingsShareProfile(l),
                    action: { presentShareProfile() }
                ) {
                    SettingsRowChevron()
                }
            }

            rowDivider(c)

            SettingsIconRow(
                icon: "ladybug.fill",
                title: AppStrings.settingsSendLogs(l),
                action: { showDebugLogs = true }
            ) {
                SettingsRowChevron()
            }

            #if DEBUG
            rowDivider(c)

            // Debug builds only. The finish screen is otherwise reachable only
            // by driving far enough for the trip to survive the junk filter,
            // which makes every change to it a trip outside.
            SettingsIconRow(
                icon: "flag.checkered",
                title: l == .ru ? "Экран финиша (отладка)" : "Finish screen (debug)",
                action: {
                    dismiss()
                    // After the sheet is gone: the summary is presented from
                    // the app root and would otherwise queue behind this one.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        mapVM.debugShowLastTripSummary()
                    }
                }
            ) {
                SettingsRowChevron()
            }
            #endif

            if auth.isSignedIn {
                rowDivider(c)

                // Neutral (not red) icon square — per Figma.
                SettingsIconRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    iconColor: c.text,
                    iconBg: c.text.opacity(0.12),
                    title: AppStrings.signOut(l),
                    action: { showSignOutAlert = true }
                ) {
                    EmptyView()
                }
                .accessibilityIdentifier("settings_signout")
            }
        }
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Group 4 — about

    private func aboutGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionLabel(text: AppStrings.about(l))
                .padding(.leading, 2)
                .padding(.top, 6)

            VStack(spacing: 0) {
                SettingsIconRow(
                    icon: "photo.on.rectangle",
                    title: AppStrings.settingsProfileBackground(l),
                    action: { showBackgroundPicker = true }
                ) {
                    SettingsRowChevron()
                }

                rowDivider(c)

                SettingsIconRow(
                    icon: "paperplane.fill",
                    assetIcon: "TelegramIcon",
                    iconColor: Color(red: 0.16, green: 0.57, blue: 0.86),
                    iconBg: Color(red: 0.16, green: 0.57, blue: 0.86).opacity(0.1),
                    title: "Telegram",
                    action: { openURL("https://t.me/onezee_co") }
                ) {
                    SettingsRowChevron()
                }

                rowDivider(c)

                SettingsIconRow(
                    icon: "play.rectangle.fill",
                    assetIcon: "YouTubeIcon",
                    iconColor: Color(red: 1.0, green: 0.0, blue: 0.0),
                    iconBg: Color(red: 1.0, green: 0.0, blue: 0.0).opacity(0.08),
                    title: "YouTube",
                    action: { openURL("https://www.youtube.com/@onezee_dev") }
                ) {
                    SettingsRowChevron()
                }

                rowDivider(c)

                SettingsIconRow(
                    icon: "chevron.left.forwardslash.chevron.right",
                    assetIcon: "GitHubIcon",
                    iconColor: c.text,
                    iconBg: c.text.opacity(0.08),
                    title: "GitHub",
                    action: { openURL("https://github.com/OneZee23/trip-track-ios") }
                ) {
                    SettingsRowChevron()
                }
            }
            .surfaceCard(cornerRadius: 16)
        }
    }

    // MARK: - Footer

    private func footer(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text("TRIP TRACK")
                    .font(.custom("PressStart2P-Regular", size: 8))
                    .foregroundStyle(AppTheme.accent)
                Text("· v\(version) · OneZee")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }

            HStack(spacing: 16) {
                Button {
                    Haptics.tap()
                    UIApplication.shared.open(AppConfig.privacyPolicyURL(l))
                } label: {
                    Text(AppStrings.privacyPolicy(l))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .underline()
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    UIApplication.shared.open(AppConfig.termsURL(l))
                } label: {
                    Text(AppStrings.termsOfService(l))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    #if DEBUG
    // MARK: - Dev (debug builds only)

    /// TEMPORARY. Replays first-run flows without deleting the app: flipping
    /// `hasCompletedOnboarding` is what the app root watches, so the
    /// onboarding takes over immediately.
    ///
    /// Wrapped in `#if DEBUG` so it cannot ship — a release build doesn't
    /// compile this group at all. Delete the whole block when the onboarding
    /// pass is done.
    private func devGroup(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AccountSectionLabel(text: "DEV · только debug-сборка")
                .padding(.leading, 2)
                .padding(.top, 6)

            VStack(spacing: 0) {
                SettingsIconRow(
                    icon: "arrow.counterclockwise",
                    iconColor: AppTheme.accent,
                    iconBg: AppTheme.accentBg,
                    title: "Пройти онбординг заново",
                    action: { restartOnboarding() }
                ) {
                    SettingsRowChevron()
                }
            }
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func restartOnboarding() {
        Haptics.action()
        // Close settings first: the root swaps its whole content for the
        // onboarding, and doing that under a presented sheet leaves the
        // sheet floating over it.
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
    }
    #endif

    // MARK: - Handlers

    /// Copied verbatim from pre-6.1.0 ProfileView: mutate-then-sync with a
    /// guard on unchanged values so redundant server syncs never fire.
    private func setShowOnPublicMap(_ value: Bool) {
        guard settings.showOnPublicMap != value else { return }
        settings.showOnPublicMap = value
        Task { await auth.syncProfileToServer(refreshFeedAfter: false) }
    }

    private func presentShareProfile() {
        guard let accountId = TokenStore.shared.accountId else { return }
        let urlString = "https://trip-track.app/u/\(accountId)"
        guard let url = URL(string: urlString) else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        var vc = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        vc?.present(av, animated: true)
    }

    private func openURL(_ string: String) {
        if let u = URL(string: string) {
            UIApplication.shared.open(u)
        }
    }
}

/// Medium-detent host for the existing `UnitsSettingsCard` (GarageView.swift)
/// — no dedicated Единицы screen is designed, the card already covers
/// distance/volume/currency.
private struct UnitsSheetWrapper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ScrollView {
            UnitsSettingsCard()
                .padding(.horizontal, 14)
                .padding(.top, 22)
                .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
    }
}
