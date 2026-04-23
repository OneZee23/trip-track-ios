import SwiftUI
import OSLog

private let profileLog = Logger(subsystem: "com.triptrack", category: "social.profile")

struct PublicProfileView: View {
    let accountId: UUID
    var preloaded: SocialAuthor?
    /// Provided only by the "preview as others see you" sheet — renders a
    /// close button in the CustomNavBar trailing that dismisses the whole
    /// sheet (distinct from back-button which pops the nav stack).
    var onClose: (() -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var auth = AuthService.shared

    @State private var profile: SocialProfile?
    @State private var isLoading = false
    @State private var isTogglingFollow = false
    @State private var loadError: String?
    @State private var followListMode: FollowListMode?
    @State private var isBlocked = false
    @State private var showBlockConfirm = false
    @State private var showReport = false
    @State private var selectedBadge: Badge?
    /// Gate initial fetch so `.task` — which re-fires on view re-appearance
    /// (e.g. after popping a pushed FollowListView) — doesn't re-run the
    /// sync+fetch cycle every time. Pull-to-refresh remains the explicit
    /// refetch path.
    @State private var didInitialLoad = false
    /// Current in-flight load task. New loads cancel the previous one so
    /// only one request's response can commit to `profile`, preventing the
    /// last-completion-wins race between pull-to-refresh and error recovery.
    @State private var loadTask: Task<Void, Never>?

    /// True when this view is rendering the signed-in user's own profile
    /// (e.g. "preview as others see you"). Hides Follow/Block/Report actions.
    private var isOwnProfile: Bool {
        TokenStore.shared.accountId == accountId
    }

    /// Fallback chain: server profile → preloaded summary → own Apple name
    /// → localized "Driver". The Apple-name step covers users whose server
    /// `displayName` is null because SIWA only returned a name on their
    /// very first sign-in.
    private var resolvedDisplayName: String {
        let isRu = lang.language == .ru
        if let p = profile?.displayName, !p.isEmpty { return p }
        if let p = preloaded?.displayName, !p.isEmpty { return p }
        if isOwnProfile, let n = auth.userName, !n.isEmpty { return n }
        return isRu ? "Водитель" : "Driver"
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        ScrollView {
            VStack(spacing: 16) {
                heroSection(c, isRu: isRu)
                    .padding(.top, 16)

                statsGrid(c, isRu: isRu)
                    .padding(.horizontal, 16)

                activeVehicleCard(c, isRu: isRu)
                    .padding(.horizontal, 16)

                badgesSection(c, isRu: isRu)
                    .padding(.horizontal, 16)

                followCounters(c, isRu: isRu)
                    .padding(.horizontal, 16)

                recentTrips(c, isRu: isRu)
                    .padding(.horizontal, 16)
            }
            // Bottom inset clears the floating CustomTabBar so the last trip
            // card is fully visible. Matches FeedView's 120pt inset. Without
            // this, the tab bar's ~100pt height covers the last card.
            .padding(.bottom, 120)
        }
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            CustomNavBar(title: resolvedDisplayName) {
                if let onClose {
                    // Preview-sheet mode: X dismisses the whole sheet
                    // regardless of nav stack depth.
                    Button {
                        Haptics.tap()
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(c.textTertiary)
                    }
                } else if !isOwnProfile {
                    Menu {
                        Button {
                            Haptics.tap()
                            showReport = true
                        } label: {
                            Label(isRu ? "Пожаловаться" : "Report", systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            Haptics.tap()
                            showBlockConfirm = true
                        } label: {
                            Label(
                                isBlocked
                                    ? (isRu ? "Разблокировать" : "Unblock")
                                    : (isRu ? "Заблокировать" : "Block"),
                                systemImage: isBlocked ? "hand.raised.slash" : "hand.raised.fill"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(c.textTertiary)
                    }
                }
            }
        }
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await refresh()
        }
        .onChange(of: auth.isSignedIn) { _, _ in
            // `.task` does NOT re-fire on state change — we must kick the
            // load manually so sign-out/sign-in flows refresh the view
            // instead of leaving it stuck on the previous account's data.
            profile = nil
            Task { await refresh() }
        }
        .refreshable { await refresh() }
        .overlay {
            if let badge = selectedBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: true,
                    language: lang.language,
                    colorScheme: scheme,
                    onDismiss: { selectedBadge = nil }
                )
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { followListMode != nil },
            set: { if !$0 { followListMode = nil } }
        )) {
            if let m = followListMode {
                FollowListView(accountId: accountId, mode: m)
            }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(target: .user(accountId))
                .environmentObject(lang)
        }
        .alert(
            isBlocked
                ? (lang.language == .ru ? "Разблокировать пользователя?" : "Unblock this user?")
                : (lang.language == .ru ? "Заблокировать пользователя?" : "Block this user?"),
            isPresented: $showBlockConfirm
        ) {
            Button(lang.language == .ru ? "Отмена" : "Cancel", role: .cancel) {}
            Button(
                isBlocked
                    ? (lang.language == .ru ? "Разблокировать" : "Unblock")
                    : (lang.language == .ru ? "Заблокировать" : "Block"),
                role: .destructive
            ) {
                Task { await toggleBlock() }
            }
        } message: {
            Text(isBlocked
                 ? (lang.language == .ru
                    ? "Пользователь снова сможет видеть ваши публичные поездки и подписываться на вас."
                    : "This user will again be able to see your public trips and follow you.")
                 : (lang.language == .ru
                    ? "Пользователь не увидит ваш контент, а его поездки не появятся в вашей ленте. Вы оба автоматически отписываетесь друг от друга."
                    : "This user won't see your content, and their trips won't appear in your feed. Any follows between you will be removed."))
        }
    }

    // MARK: - Hero

    private func heroSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let bg = ProfileBackground.from(profile?.profileBackground)
        let avatarSize: CGFloat = 100
        let bannerHeight: CGFloat = 140
        let avatarOverlap = avatarSize / 2
        let emoji = profile?.avatarEmoji ?? preloaded?.avatarEmoji ?? "🚗"

        return VStack(spacing: 0) {
            ZStack {
                if bg == .none {
                    c.cardAlt
                } else {
                    bg.view()
                }
            }
            .frame(height: bannerHeight)
            .frame(maxWidth: .infinity)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 18
            ))

            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    Text(resolvedDisplayName)
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.center)

                    if let lvl = profile?.profileLevel ?? preloaded?.profileLevel {
                        HStack(spacing: 6) {
                            Text(DriverRank.from(level: lvl).title(lang.language))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                            Text("·")
                                .foregroundStyle(c.textTertiary)
                            Text("LVL \(lvl)")
                                .font(.custom("PressStart2P-Regular", size: 9))
                                .tracking(1)
                                .foregroundStyle(AppTheme.accent)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentBg, in: Capsule())
                    }
                }

                if !isOwnProfile, profile?.isFollowing != nil {
                    followButton(c, isRu: isRu)
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
        .overlay(alignment: .top) {
            Text(emoji)
                .font(.system(size: avatarSize * 0.55))
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(c.card))
                .overlay(Circle().stroke(c.card, lineWidth: 5))
                .padding(.top, bannerHeight - avatarOverlap)
        }
    }

    @ViewBuilder
    private func followButton(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let isFollowing = profile?.isFollowing ?? false
        Button {
            Haptics.action()
            Task { await toggleFollow() }
        } label: {
            HStack(spacing: 6) {
                if isTogglingFollow {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(isFollowing ? c.text : .white)
                } else {
                    Image(systemName: isFollowing ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .bold))
                }
                Text(isFollowing
                     ? (isRu ? "Подписан" : "Following")
                     : (isRu ? "Подписаться" : "Follow"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minWidth: 140)
            .background(isFollowing ? c.cardAlt : AppTheme.accent, in: Capsule())
            .foregroundStyle(isFollowing ? c.text : .white)
        }
        .buttonStyle(.plain)
        .disabled(isTogglingFollow)
    }

    // MARK: - Stats

    private func statsGrid(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let stats = profile?.stats
        let streakValue = profile?.currentStreak ?? 0
        return HStack(spacing: 0) {
            statCell(
                value: stats.map { String($0.tripCount) } ?? "—",
                label: isRu ? "поездок" : "trips",
                c: c
            )
            divider(c)
            statCell(
                value: stats.map { String(format: "%.0f", $0.totalKm) } ?? "—",
                label: "км",
                c: c
            )
            divider(c)
            statCell(
                value: stats.map { String($0.regionsCount) } ?? "—",
                label: isRu ? "регионов" : "regions",
                c: c
            )
            divider(c)
            statCell(
                value: profile == nil ? "—" : "\(streakValue)",
                // Spelled out "day streak" so the icon+number doesn't look
                // like a generic score — it's specifically consecutive days
                // of recording trips.
                label: isRu ? "дней подряд" : "day streak",
                c: c,
                accent: streakValue > 0 ? AppTheme.accent : nil,
                iconSystemName: streakValue > 0 ? "flame.fill" : nil
            )
        }
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 14)
    }

    private func statCell(
        value: String,
        label: String,
        c: AppTheme.Colors,
        accent: Color? = nil,
        iconSystemName: String? = nil
    ) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon = iconSystemName {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent ?? c.text)
                }
                Text(value)
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(accent ?? c.text)
            }
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.border)
            .frame(width: 0.5, height: 28)
    }

    // MARK: - Active vehicle

    /// "Your car" card that mirrors the one on the private ProfileView — same
    /// hierarchy (avatar, name, level title, odometer progress bar) so the
    /// public view feels consistent with how the user sees their own garage.
    /// Uses VehicleLevelSystem directly instead of `VehicleCardView` because
    /// the server returns a leaner DTO without stickers/consumption.
    @ViewBuilder
    private func activeVehicleCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        if let v = profile?.activeVehicle {
            let progress = VehicleLevelSystem.progressToNext(km: v.odometerKm, level: v.level)
            let title = VehicleLevelSystem.title(level: v.level, lang: lang.language)
            let frame = vehicleFrameColor(level: v.level)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(frame.opacity(0.12))
                        .frame(width: 52, height: 52)
                    if v.isPixelAvatar {
                        Image(v.avatarEmoji)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                    } else {
                        Text(v.avatarEmoji.isEmpty ? "🏎️" : v.avatarEmoji)
                            .font(.system(size: 26))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.name.isEmpty ? (isRu ? "Авто" : "Car") : v.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)

                        Spacer()

                        Text("LVL \(v.level)")
                            .font(.custom("PressStart2P-Regular", size: 9))
                            .foregroundStyle(frame)
                    }

                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(frame)

                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(c.cardAlt).frame(height: 6)
                                Capsule()
                                    .fill(frame)
                                    .frame(width: max(3, geo.size.width * progress), height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text(formatOdometer(v.odometerKm))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                            .fixedSize()
                    }
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func vehicleFrameColor(level: Int) -> Color {
        switch level {
        case 1...2: return .gray
        case 3: return Color(red: 205/255, green: 127/255, blue: 50/255)
        case 4...5: return Color(red: 192/255, green: 192/255, blue: 192/255)
        case 6: return Color(red: 255/255, green: 215/255, blue: 0/255)
        case 7...8: return Color(red: 180/255, green: 210/255, blue: 230/255)
        default: return AppTheme.accent
        }
    }

    private func formatOdometer(_ km: Double) -> String {
        if km >= 1000 {
            return String(format: "%.1fK km", km / 1000)
        }
        return String(format: "%.0f km", km)
    }

    // MARK: - Badges

    /// Recent badges the profile owner has earned. Horizontal scroll so the
    /// row never gets truncated when a user has more than fits on screen —
    /// same interaction model as the trip reaction palette. Tapping a badge
    /// opens the same detail overlay as `BadgesView`.
    @ViewBuilder
    private func badgesSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let ids = profile?.recentBadges ?? []
        if !ids.isEmpty {
            let badges = ids.compactMap { id in Badge.all.first(where: { $0.id == id }) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(isRu ? "Ачивки" : "Achievements")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                    Text("·")
                        .foregroundStyle(c.textTertiary)
                    Text("\(badges.count)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                    Spacer()
                }

                // Wrap ScrollView in a rounded container that owns both the
                // background and the clip shape. Applying `surfaceCard` directly
                // to the ScrollView worked for the fill but didn't clip the
                // scroll content — items bled past the rounded corners and the
                // card looked broken when content overflowed horizontally.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(badges) { badge in
                            badgeCell(badge, c: c)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func badgeCell(_ badge: Badge, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            selectedBadge = badge
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(badge.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: badge.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(badge.color)
                }
                Text(badge.title(lang.language))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 72)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Follow counters

    private func followCounters(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                followListMode = .followers
            } label: {
                VStack(spacing: 3) {
                    Text("\(profile?.followerCount ?? 0)")
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
                    Text("\(profile?.followingCount ?? 0)")
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

    // MARK: - Recent trips

    @ViewBuilder
    private func recentTrips(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        if let trips = profile?.recentTrips, !trips.isEmpty {
            let publicCount = profile?.stats.publicTripCount ?? trips.count
            let totalCount = profile?.stats.tripCount ?? trips.count
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(isRu ? "Поездки" : "Trips")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                    Text("·")
                        .foregroundStyle(c.textTertiary)
                    Text(isRu ? "Публичные \(publicCount)" : "\(publicCount) public")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textSecondary)
                    if totalCount > publicCount {
                        Text("·")
                            .foregroundStyle(c.textTertiary)
                        Text(isRu ? "всего \(totalCount)" : "\(totalCount) total")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(c.textTertiary)
                    }
                    Spacer()
                }

                ForEach(trips) { t in
                    recentTripRow(t, c: c, isRu: isRu)
                }
            }
        } else if let err = loadError {
            // Error takes priority over the empty state so a failed refresh
            // of an already-loaded profile doesn't silently fall back to
            // "No public trips yet" — user needs to know the fetch failed.
            errorRow(err, c: c, isRu: isRu)
        } else if profile != nil {
            emptyTripsHint(c, isRu: isRu)
        } else if isLoading {
            skeleton()
        }
    }

    private func recentTripRow(_ trip: SocialProfileRecentTrip, c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 12) {
            if trip.previewCoordinates.count > 1 {
                MapSnapshotPreview(
                    coordinates: trip.previewCoordinates,
                    tripId: trip.id,
                    height: 52
                )
                .frame(width: 80, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(c.cardAlt)
                    .frame(width: 80, height: 52)
                    .overlay {
                        Image(systemName: "map")
                            .font(.system(size: 16))
                            .foregroundStyle(c.textTertiary)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title ?? shortDate(trip.startDate, isRu: isRu))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(String(format: "%.1f км", trip.distanceKm))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textSecondary)
                    if let region = trip.region, !region.isEmpty {
                        Text("·").foregroundStyle(c.textTertiary)
                        Text(region)
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .surfaceCard(cornerRadius: 12)
    }

    private func emptyTripsHint(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "car.fill")
                .font(.system(size: 24))
                .foregroundStyle(c.textTertiary)
            Text(isRu ? "Пока нет публичных поездок" : "No public trips yet")
                .font(.system(size: 13))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func skeleton() -> some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
    }

    private func errorRow(_ msg: String, c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(.red)
            Text(isRu ? "Не удалось загрузить профиль" : "Couldn't load profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Networking

    /// Single entry point for syncing + fetching the profile. Cancels any
    /// previous in-flight refresh so concurrent callers (pull-to-refresh,
    /// auth change, toggle-follow error recovery) don't race on the final
    /// `profile = p` assignment — only the latest request can commit.
    private func refresh() async {
        loadTask?.cancel()
        let task = Task {
            if isOwnProfile {
                await AuthService.shared.syncProfileToServer()
            }
            if Task.isCancelled { return }
            await loadProfile()
        }
        loadTask = task
        await task.value
    }

    private func loadProfile() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            let p: SocialProfile = try await APIClient.shared.get(
                APIEndpoint.userProfile(accountId.uuidString))
            if Task.isCancelled { return }
            profile = p
        } catch {
            // Cancellation means `refresh()` replaced us with a newer task —
            // don't surface its error; the newer task owns the outcome.
            if Task.isCancelled { return }
            let msg = (error as? APIError).map { String(describing: $0) }
                ?? error.localizedDescription
            loadError = msg
            profileLog.error("profile load failed: \(msg)")
        }
    }

    private func toggleBlock() async {
        let wasBlocked = isBlocked
        isBlocked = !wasBlocked
        do {
            let req = SocialBlockRequest(targetAccountId: accountId)
            let endpoint = wasBlocked ? APIEndpoint.socialUnblock : APIEndpoint.socialBlock
            let _: SocialBlockResponse = try await APIClient.shared.post(endpoint, body: req)
            if !wasBlocked {
                // After blocking, clear isFollowing both ways (backend already does this)
                if var p = profile {
                    p = p.with(isFollowing: false, followerCount: p.followerCount)
                    profile = p
                }
            }
        } catch {
            isBlocked = wasBlocked
            profileLog.error("block toggle failed: \(error.localizedDescription)")
        }
    }

    private func toggleFollow() async {
        guard let current = profile else { return }
        let wasFollowing = current.isFollowing ?? false
        isTogglingFollow = true
        defer { isTogglingFollow = false }

        profile = current.with(isFollowing: !wasFollowing,
                               followerCount: current.followerCount + (wasFollowing ? -1 : 1))
        do {
            let req = SocialFollowRequest(targetAccountId: accountId)
            let endpoint = wasFollowing ? APIEndpoint.socialUnfollow : APIEndpoint.socialFollow
            let _: SocialFollowResponse = try await APIClient.shared.post(endpoint, body: req)
        } catch {
            profileLog.error("follow toggle failed: \(error.localizedDescription)")
            // Re-fetch to reconcile with server truth. `refresh()` cancels
            // any in-flight pull-to-refresh so only our recovery response
            // commits — avoids last-completion-wins racing.
            await refresh()
        }
    }

    private func shortDate(_ date: Date, isRu: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: isRu ? "ru_RU" : "en_US")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }
}

private extension SocialProfile {
    func with(isFollowing: Bool, followerCount: Int) -> SocialProfile {
        SocialProfile(
            id: id, displayName: displayName, avatarEmoji: avatarEmoji,
            profileLevel: profileLevel, profileBackground: profileBackground,
            currentStreak: currentStreak, bestStreak: bestStreak,
            stats: stats, activeVehicle: activeVehicle, recentBadges: recentBadges,
            recentTrips: recentTrips,
            followerCount: followerCount, followingCount: followingCount,
            isFollowing: isFollowing
        )
    }
}
