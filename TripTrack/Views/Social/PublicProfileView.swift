import SwiftUI
import OSLog

private let profileLog = Logger(subsystem: "com.triptrack", category: "social.profile")

struct PublicProfileView: View {
    let accountId: UUID
    /// Optional fallback identity used while the request is in flight.
    var preloaded: SocialAuthor?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var profile: SocialProfile?
    @State private var isLoading = false
    @State private var isTogglingFollow = false
    @State private var loadError: String?
    @State private var followListMode: FollowListMode?
    @State private var isBlocked = false
    @State private var showBlockConfirm = false
    @State private var showReport = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        ScrollView {
            VStack(spacing: 20) {
                heroSection(c, isRu: isRu)
                    .padding(.top, 16)

                statsGrid(c, isRu: isRu)
                    .padding(.horizontal, 16)

                followCounters(c, isRu: isRu)
                    .padding(.horizontal, 16)

                recentTrips(c, isRu: isRu)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(c.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(profile?.displayName ?? preloaded?.displayName ?? (isRu ? "Профиль" : "Profile"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
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
                        .font(.system(size: 16))
                        .foregroundStyle(c.text)
                }
            }
        }
        .task { await loadProfile() }
        .refreshable { await loadProfile() }
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
        VStack(spacing: 12) {
            let emoji = profile?.avatarEmoji ?? preloaded?.avatarEmoji ?? "🚗"
            Circle()
                .fill(AppTheme.accentBg)
                .frame(width: 88, height: 88)
                .overlay { Text(emoji).font(.system(size: 44)) }

            VStack(spacing: 4) {
                Text(profile?.displayName ?? preloaded?.displayName ?? (isRu ? "Пользователь" : "User"))
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.2)
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)

                if let lvl = profile?.profileLevel ?? preloaded?.profileLevel {
                    Text("LVL \(lvl)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .tracking(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.accentBg, in: Capsule())
                        .foregroundStyle(AppTheme.accent)
                }
            }

            if profile?.isFollowing != nil {
                followButton(c, isRu: isRu)
            }
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
                value: profile.map { String($0.profileLevel) } ?? "—",
                label: "LVL",
                c: c
            )
        }
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 14)
    }

    private func statCell(value: String, label: String, c: AppTheme.Colors) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .heavy).monospacedDigit())
                .foregroundStyle(c.text)
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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(isRu ? "Поездки" : "Trips")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                    Text("·")
                        .foregroundStyle(c.textTertiary)
                    Text("\(profile?.stats.tripCount ?? trips.count)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                    Spacer()
                }

                ForEach(trips) { t in
                    recentTripRow(t, c: c, isRu: isRu)
                }
            }
        } else if profile != nil {
            emptyTripsHint(c, isRu: isRu)
        } else if isLoading {
            skeleton(c)
        } else if let err = loadError {
            errorRow(err, c: c, isRu: isRu)
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

    private func skeleton(_ c: AppTheme.Colors) -> some View {
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

    private func loadProfile() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            let p: SocialProfile = try await APIClient.shared.get(
                APIEndpoint.userProfile(accountId.uuidString))
            profile = p
        } catch let e as APIError {
            loadError = String(describing: e)
            profileLog.error("profile load failed: \(String(describing: e))")
        } catch {
            loadError = error.localizedDescription
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
        guard var current = profile else { return }
        let wasFollowing = current.isFollowing ?? false
        isTogglingFollow = true
        defer { isTogglingFollow = false }

        // Optimistic update
        profile = current.with(isFollowing: !wasFollowing,
                               followerCount: current.followerCount + (wasFollowing ? -1 : 1))
        do {
            let req = SocialFollowRequest(targetAccountId: accountId)
            let endpoint = wasFollowing ? APIEndpoint.socialUnfollow : APIEndpoint.socialFollow
            let _: SocialFollowResponse = try await APIClient.shared.post(endpoint, body: req)
        } catch {
            // Revert
            profile = current
            profileLog.error("follow toggle failed: \(error.localizedDescription)")
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
            profileLevel: profileLevel, stats: stats, recentTrips: recentTrips,
            followerCount: followerCount, followingCount: followingCount,
            isFollowing: isFollowing
        )
    }
}
