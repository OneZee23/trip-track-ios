import SwiftUI
import AuthenticationServices
import OSLog

private let signInLog = Logger(subsystem: "com.triptrack", category: "signin")
private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

struct ProfileView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var syncQueue = SyncQueue.shared

    // Profile avatar
    @State private var selectedAvatar: String = "😎"
    @State private var isEditingAvatar = false
    @State private var avatarBounce = false

    @State private var showStats = false
    @State private var showBadges = false
    @State private var showGarage = false
    @State private var showVehicleDetail = false
    @State private var showCloudSync = false
    @State private var showDebugLogs = false
    @State private var socialProfile: SocialProfile?
    @State private var followListMode: FollowListMode?
    @State private var showBackgroundPicker = false
    @State private var previewingOwnProfile = false
    /// Nav path for the preview-sheet NavigationStack. Kept alongside the
    /// sheet's `isPresented` so every deep navigation inside the sheet
    /// (profile ↔ followers) shares one path and the `cappedAppend` helper
    /// can enforce a max depth of 3 — preventing the SwiftUI NavigationStack
    /// bug that surfaces a default "← Back" flash at depth 4+.
    @State private var previewPath: [ProfilePreviewDest] = []
    /// Same idea as `previewPath` but for the follow-list sheet. A separate
    /// path lets us reset depth to 0 when the sheet closes without touching
    /// the preview flow's path.
    @State private var followListPath: [ProfilePreviewDest] = []

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

                // Social followers/following (signed in only)
                if auth.isSignedIn {
                    socialCountersRow(c, isRu: isRu)
                    previewProfileButton(c, isRu: isRu)
                    shareProfileButton(c, isRu: isRu)
                }

                // Vehicle Card
                if let vehicle = selectedVehicle {
                    Button { showVehicleDetail = true } label: {
                        VehicleCardView(vehicle: vehicle)
                    }
                    .buttonStyle(.plain)
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

                // Cloud sync settings (only when signed in)
                if auth.isSignedIn {
                    Button { showCloudSync = true } label: {
                        profileNavButton(
                            icon: settings.cloudSyncEnabled ? "icloud.fill" : "icloud.slash",
                            iconColor: settings.cloudSyncEnabled ? AppTheme.blue : c.textTertiary,
                            label: isRu ? "Синхронизация в облаке" : "Cloud sync",
                            c: c
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Debug logs (always available — useful even for guest mode bug reports)
                Button { showDebugLogs = true } label: {
                    profileNavButton(
                        icon: "ladybug.fill",
                        iconColor: .gray,
                        label: isRu ? "Отправить логи" : "Send debug logs",
                        c: c
                    )
                }
                .buttonStyle(.plain)

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
        .task {
            await loadOwnSocialProfile()
        }
        // Pure-SwiftUI navigator rooted at the follow list — replaces the
        // previous sheet-hosted `NavigationStack { FollowListView }` that
        // exhibited the depth-4+ flash when users chained profile↔follower
        // pushes inside it. Same navigator the preview flow uses.
        .fullScreenCover(isPresented: Binding(
            get: { followListMode != nil },
            set: { if !$0 { followListMode = nil } }
        ), onDismiss: {
            navLog.debug("follow list dismissed — clearing path (had depth=\(followListPath.count))")
            followListPath = []
        }) {
            if let mode = followListMode,
               let accountId = TokenStore.shared.accountId {
                PreviewNavigator(
                    rootDest: .followList(accountId, mode),
                    path: $followListPath,
                    onCloseSheet: { followListMode = nil }
                )
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
            }
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
        .sheet(isPresented: $showCloudSync) {
            CloudSyncView()
                .environmentObject(lang)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showBackgroundPicker) {
            ProfileBackgroundPickerSheet()
                .environmentObject(lang)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        // Was `.sheet`, switched to `.fullScreenCover` to sidestep a
        // SwiftUI bug where the system nav bar flashes during pushes inside
        // a sheet-hosted NavigationStack. Research ref: sheet's animating
        // container re-lays-out the UIHostingController, which lets UIKit's
        // `_pushViewController` run a CAAnimation on the bar's presentation
        // layer that KVO / lifecycle hooks cannot intercept. fullScreenCover
        // doesn't trigger the same relayout. UX trade-off: no grabber, no
        // swipe-to-dismiss — users close via the X button wired into
        // `CustomNavBar` (`onClose` already passed below).
        .fullScreenCover(isPresented: $previewingOwnProfile, onDismiss: {
            navLog.debug("preview dismissed — clearing path (had depth=\(previewPath.count))")
            previewPath = []
        }) {
            if let accountId = TokenStore.shared.accountId {
                // Custom ZStack-based navigator — no `NavigationStack`, no
                // underlying `UINavigationController`, no nav-bar flash.
                // `PreviewNavigator` slides destinations in/out and bridges
                // `NavBackButton` via `\.previewPop` environment.
                PreviewNavigator(
                    rootDest: .profile(accountId, nil),
                    path: $previewPath,
                    onCloseSheet: { previewingOwnProfile = false }
                )
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showDebugLogs) {
            DebugLogsView()
                .environmentObject(lang)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showVehicleDetail) {
            if let vehicle = selectedVehicle {
                VehicleDetailView(vehicleId: vehicle.id)
            }
        }
        .alert("Sign in failed",
               isPresented: Binding(
                 get: { auth.lastAuthError != nil },
                 set: { if !$0 { auth.lastAuthError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(String(describing: auth.lastAuthError ?? .transport("unknown")))
        }
    }

    private var selectedVehicle: Vehicle? {
        if let id = settings.selectedVehicleId {
            return settings.vehicles.first { $0.id == id }
        }
        return settings.vehicles.first
    }

    // MARK: - Social Counters Row (followers / following)

    private func socialCountersRow(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                followListMode = .followers
            } label: {
                VStack(spacing: 3) {
                    Text("\(socialProfile?.followerCount ?? 0)")
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(c.text)
                    Text(isRu ? "подписчиков" : "followers")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(c.border).frame(width: 0.5, height: 32)

            Button {
                Haptics.tap()
                followListMode = .following
            } label: {
                VStack(spacing: 3) {
                    Text("\(socialProfile?.followingCount ?? 0)")
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(c.text)
                    Text(isRu ? "подписок" : "following")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 14)
    }

    private func previewProfileButton(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            previewingOwnProfile = true
        } label: {
            HStack {
                Image(systemName: "eye")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.blue)
                Text(isRu ? "Посмотреть глазами других" : "Preview as others see you")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private func shareProfileButton(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            presentShareProfile()
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.accent)
                Text(isRu ? "Поделиться профилем" : "Share profile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
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

    private func loadOwnSocialProfile() async {
        guard auth.isSignedIn, let accountId = TokenStore.shared.accountId else { return }
        do {
            let p: SocialProfile = try await APIClient.shared.get(
                APIEndpoint.userProfile(accountId.uuidString))
            socialProfile = p
        } catch {
            // Silent — social counters just won't populate
        }
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
                    label: isRu ? "дней подряд" : "day streak",
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

    // MARK: - Avatar Card (hero with banner, avatar overlaps seam)

    private static let heroAvatarSize: CGFloat = 108
    private static let heroBannerHeight: CGFloat = 150

    private func avatarCard(_ c: AppTheme.Colors) -> some View {
        let bg = ProfileBackground.from(settings.profileBackground)
        let avatarSize = Self.heroAvatarSize
        let bannerHeight = Self.heroBannerHeight
        // Avatar sits so its center aligns with the banner/content seam.
        let avatarOverlap = avatarSize / 2

        return VStack(spacing: 0) {
            // Banner
            ZStack(alignment: .topTrailing) {
                if bg == .none {
                    c.cardAlt
                } else {
                    bg.view()
                }

                // Banner action row: edit avatar + choose background
                HStack(spacing: 8) {
                    bannerIconButton(system: "pencil") {
                        withAnimation(.easeInOut(duration: 0.2)) { isEditingAvatar.toggle() }
                    }
                    bannerIconButton(system: "photo.on.rectangle") {
                        showBackgroundPicker = true
                    }
                }
                .padding(12)
            }
            .frame(height: bannerHeight)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 18
            ))

            // Content below banner. Top padding = half the avatar so content starts
            // below the avatar's bottom edge; avatar itself is an overlay.
            VStack(spacing: 10) {
                if auth.isSignedIn {
                    signedInHeader(c)
                } else {
                    guestHeader(c)
                }

                if isEditingAvatar {
                    avatarGrid(c)
                        .padding(.top, 4)
                }
            }
            .padding(.top, avatarOverlap + 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(c.border, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .overlay(alignment: .top) {
            // Floating avatar — its vertical center sits on the banner/content seam.
            ZStack(alignment: .bottomTrailing) {
                Text(selectedAvatar)
                    .font(.system(size: avatarSize * 0.58))
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Circle().fill(c.card))
                    .overlay(
                        Circle().stroke(c.card, lineWidth: 5)
                    )
                    .scaleEffect(avatarBounce ? 1.12 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: avatarBounce)

                levelPill
                    .offset(x: 2, y: 2)
            }
            .padding(.top, bannerHeight - avatarOverlap)
        }
    }

    private func bannerIconButton(system: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var levelPill: some View {
        Text("LVL \(settings.profileLevel)")
            .font(.custom("PressStart2P-Regular", size: 9))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(AppTheme.accent)
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 4, y: 2)
            )
    }

    // MARK: - Guest Header

    @ViewBuilder
    private func guestHeader(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 6) {
            Text(AppStrings.guest(lang.language))
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(c.text)
            Text(AppStrings.signInToSync(lang.language))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
        }

        ZStack {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
                signInLog.debug("→ request scopes, bundle=\(Bundle.main.bundleIdentifier ?? "?")")
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    signInLog.debug("✅ got credential")
                    Task { await auth.handleAuthorization(authorization) }
                case .failure(let error):
                    let ns = error as NSError
                    signInLog.debug("❌ domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")
                    signInLog.debug("  userInfo=\(ns.userInfo)")
                    auth.lastAuthError = .transport("Apple: \(ns.code) \(ns.localizedDescription)")
                }
            }
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 44)
            .cornerRadius(10)
            .opacity(auth.isAuthenticating ? 0.5 : 1.0)
            .disabled(auth.isAuthenticating)

            if auth.isAuthenticating {
                ProgressView()
            }
        }
    }

    // MARK: - Signed In Header

    @ViewBuilder
    private func signedInHeader(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 6) {
            Text(auth.userName ?? AppStrings.signedIn(lang.language))
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
            if let email = auth.userEmail {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }
            syncStatusIndicator(c)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func syncStatusIndicator(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        let pending = syncQueue.pendingCount
        let syncing = syncQueue.isSyncing

        HStack(spacing: 6) {
            if !settings.cloudSyncEnabled {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(c.textTertiary)
                Text(isRu ? "Синхронизация выключена" : "Sync disabled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            } else if syncing {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
                let total = syncQueue.batchTotal
                let done = syncQueue.batchProcessed
                Text(total > 0
                     ? (isRu ? "Синхронизация… \(done)/\(total)" : "Syncing… \(done)/\(total)")
                     : (isRu ? "Синхронизация…" : "Syncing…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .monospacedDigit()
            } else if pending > 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text(isRu ? "В очереди: \(pending)" : "Pending: \(pending)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.green)
                Text(isRu ? "Синхронизировано" : "Synced")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: syncing)
        .animation(.easeInOut(duration: 0.2), value: pending)
    }

    // MARK: - Edit Avatar Button

    private func editAvatarButton(_ c: AppTheme.Colors) -> some View {
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

    // MARK: - Avatar Grid

    private func avatarGrid(_ c: AppTheme.Colors) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(profileAvatars, id: \.self) { emoji in
                Button {
                    Haptics.tap()
                    selectedAvatar = emoji
                    settings.avatarEmoji = emoji
                    settings.saveSettings()
                    Task { await auth.syncProfileToServer() }
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

            // Legal links
            HStack(spacing: 16) {
                Button {
                    Haptics.tap()
                    UIApplication.shared.open(AppConfig.privacyPolicyURL(lang.language))
                } label: {
                    Text(AppStrings.privacyPolicy(lang.language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .underline()
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    UIApplication.shared.open(AppConfig.termsURL(lang.language))
                } label: {
                    Text(AppStrings.termsOfService(lang.language))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .underline()
                }
                .buttonStyle(.plain)
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
