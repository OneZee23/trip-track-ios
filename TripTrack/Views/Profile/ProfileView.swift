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
    @State private var showSyncStatus = false
    @State private var showDebugLogs = false
    @State private var showNotificationsInbox = false
    @ObservedObject private var notificationsInbox = NotificationsInboxStore.shared
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
    @State private var signInPrompt: SignInPromptSheet.Action?
    @State private var showNameEditor = false
    @State private var editedName: String = ""

    private let profileAvatars = ["😎", "🧑‍💻", "👨‍🚀", "🧔", "🤠", "🥷", "🏂", "🎸"]

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        ScrollView {
            VStack(spacing: 16) {
                avatarCard(c)

                if !auth.isSignedIn {
                    guestSignInCard(c, isRu: isRu)
                }

                // First-launch welcome — when the user has yet to record any
                // trip, the stats row and driver-level card show zeros which
                // reads as broken/sparse. Replace the stats stack below with
                // a single inviting CTA that takes them to Tracking. Once
                // they have ≥1 trip everything reverts to the normal layout.
                if mapVM.cachedTripCount == 0 {
                    firstTripWelcomeCard(c, isRu: isRu)
                }

                // Driver Level + Quick stats hidden until the user has at
                // least one trip — empty zeros read as broken on a fresh
                // install. The welcome card above takes their place.
                if mapVM.cachedTripCount > 0 {
                    DriverLevelView(
                        xp: settings.profileXP,
                        level: settings.profileLevel
                    )

                    quickStatsRow(c, isRu: isRu)
                }

                // Social followers/following (signed in only). The hero card
                // above is itself tappable for "Preview as others see you" —
                // see `avatarCard` for the gesture wiring.
                if auth.isSignedIn {
                    socialCountersRow(c, isRu: isRu)
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

                    // Notifications inbox — visible only when signed in,
                    // since the inbox is per-account. Red dot inside the
                    // row when there's anything unread; matches the
                    // pattern Instagram / Strava use.
                    Button { showNotificationsInbox = true } label: {
                        profileNavButton(
                            icon: "bell.fill",
                            iconColor: AppTheme.accent,
                            label: isRu ? "Уведомления" : "Notifications",
                            badge: notificationsInbox.unreadCount,
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
        .sheet(isPresented: $showSyncStatus) {
            SyncStatusSheetView()
                .environmentObject(lang)
                .environmentObject(themeManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showNotificationsInbox) {
            NotificationsInboxView()
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
        .sheet(item: $signInPrompt) { action in
            SignInPromptSheet(action: action)
                .environmentObject(lang)
                .environmentObject(auth)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showNameEditor) {
            NameEditorSheet(
                initialName: auth.userName ?? "",
                isPlaceholder: RandomDisplayName.isPlaceholder(auth.userName),
                onSave: { newName in
                    Task { await auth.updateUserName(newName) }
                }
            )
            .environmentObject(lang)
            .preferredColorScheme(themeManager.preferredColorScheme)
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

    private func shareProfileButton(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            presentShareProfile()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 22, alignment: .center)
                Text(isRu ? "Поделиться профилем" : "Share profile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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

    private func profileNavButton(
        icon: String,
        iconColor: Color,
        label: String,
        badge: Int = 0,
        c: AppTheme.Colors,
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
            // Capped at 99+ so a noisy account doesn't widen the row.
            if badge > 0 {
                Text(badge > 99 ? "99+" : "\(badge)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppTheme.accent, in: Capsule())
                    .fixedSize()
            }
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

    /// Friendly empty-state replacement for the stats row + driver-level
    /// stack on first-launch (cachedTripCount == 0). Tap routes to the
    /// Tracking tab so the user lands directly on the record screen — that's
    /// the one action that matters before they have any data.
    private func firstTripWelcomeCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentBg)
                        .frame(width: 52, height: 52)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(isRu ? "Запишите первую поездку" : "Record your first trip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(isRu
                         ? "Здесь будут Ваши километры, серии и бейджи."
                         : "Your kilometers, streaks and badges will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
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

    /// Inline Sign-in CTA shown to guests at the top of ProfileView. Tap opens
    /// the same `SignInPromptSheet` used elsewhere — keeps the sign-in UX
    /// consistent across reaction/follow/share gates.
    private func guestSignInCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            signInPrompt = .generic
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 26))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isRu ? "Войдите в TripTrack" : "Sign in to TripTrack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(isRu
                         ? "Синхронизация, реакции, подписки — через Apple ID."
                         : "Cloud sync, reactions, follows — with Apple ID.")
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Edit-avatar mode owns its own grid below — suppress
                            // the gesture there.
                            guard !isEditingAvatar else { return }
                            Haptics.tap()
                            // No name yet (Apple Sign In doesn't redeliver
                            // the name after re-auth) → first tap routes to
                            // the editor instead of preview, so the user
                            // sees "fix your identity" before "see your
                            // public profile". Once a name exists, tap
                            // returns to the preview behaviour.
                            if headerTapShouldEditName {
                                presentNameEditor()
                            } else {
                                previewingOwnProfile = true
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.4) {
                            guard !isEditingAvatar else { return }
                            Haptics.action()
                            presentNameEditor()
                        }
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
            .contentShape(Circle())
            .onTapGesture {
                guard auth.isSignedIn, !isEditingAvatar else { return }
                Haptics.tap()
                previewingOwnProfile = true
            }
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
        let isRu = lang.language == .ru
        let trimmed = auth.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        let hasName = !trimmed.isEmpty
        let isPlaceholder = RandomDisplayName.isPlaceholder(auth.userName)
        // "Identity is unsettled" — placeholder names look real but aren't.
        // The pencil sticks around in both states (always-editable affordance);
        // placeholders get a stronger accent color + sub-hint, real names get
        // a subdued treatment so the chrome doesn't shout when nothing is wrong.
        let needsEditCue = !hasName || isPlaceholder
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(hasName
                     ? (auth.userName ?? "")
                     : (isRu ? "Добавьте имя" : "Add your name"))
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(hasName ? c.text : c.textTertiary)
                    .multilineTextAlignment(.center)
                    // 30-char names + Dynamic Type otherwise wrap to 3 lines
                    // and break the avatar overlap math (`avatarOverlap` =
                    // half avatar size). Cap at 2 lines + scale-fit.
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                // The pencil is its own button — tapping it only opens the
                // editor, never the public-profile preview. Lets the user
                // rename even when their name is a real / accepted one,
                // without forcing them to long-press (which is hidden).
                Button {
                    Haptics.tap()
                    presentNameEditor()
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(needsEditCue ? AppTheme.accent : c.textTertiary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRu ? "Изменить имя" : "Edit name")
            }
            if needsEditCue {
                // Sub-hint sells the affordance — without this, the pencil
                // is easy to miss and users assume the random name is theirs
                // forever. Tone matches the "name yourself" framing in the
                // editor sheet, not "fix something broken".
                Text(isRu ? "Тапните, чтобы изменить" : "Tap to change")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                    .transition(.opacity)
            } else if let email = auth.userEmail {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }
            syncStatusIndicator(c)
                .padding(.top, 4)
        }
        .animation(.easeInOut(duration: 0.2), value: needsEditCue)
    }

    /// Whether tapping the hero header (outside the pencil button) should
    /// open the editor instead of the public-profile preview. Pencil is
    /// always tappable; this only governs the surrounding area. Empty /
    /// placeholder names still route to the editor on hero-tap so a fresh-
    /// install user is nudged to set their name — but real-name users get
    /// the preview, which is the more useful action when identity is set.
    private var headerTapShouldEditName: Bool {
        guard auth.isSignedIn else { return false }
        let trimmed = auth.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty { return true }
        return RandomDisplayName.isPlaceholder(auth.userName)
    }

    private func presentNameEditor() {
        editedName = auth.userName ?? ""
        showNameEditor = true
    }

    @ViewBuilder
    private func syncStatusIndicator(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        let pending = syncQueue.pendingCount
        let syncing = syncQueue.isSyncing
        // Always tappable when sync is on — even on "synced" the sheet is
        // useful as a dashboard ("how much of my data is in the cloud?").
        // When sync is disabled there's nothing meaningful to show, so we
        // leave the pill inert; the user can enable sync via the dedicated
        // Cloud Sync row below.
        let isTappable = settings.cloudSyncEnabled

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
                     ? (isRu ? "синхронизация… \(done)/\(total)" : "syncing… \(done)/\(total)")
                     : (isRu ? "синхронизация…" : "syncing…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .monospacedDigit()
            } else if pending > 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text(isRu ? "\(pending) в очереди" : "\(pending) pending")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.green)
                Text(isRu ? "синхронизировано" : "synced")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            }
            if isTappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, isTappable ? 10 : 0)
        .padding(.vertical, isTappable ? 4 : 0)
        .background(
            isTappable ? AnyShapeStyle(c.cardAlt) : AnyShapeStyle(Color.clear),
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture {
            guard isTappable else { return }
            Haptics.tap()
            showSyncStatus = true
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
