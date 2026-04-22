import SwiftUI
import OSLog

private let followListLog = Logger(subsystem: "com.triptrack", category: "social.followlist")

enum FollowListMode {
    case followers
    case following
}

struct FollowListView: View {
    let accountId: UUID
    let mode: FollowListMode

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var users: [SocialAuthor] = []
    @State private var isLoading = false
    @State private var selectedAuthor: SocialAuthor?
    /// Gate initial fetch — `.task` re-fires on every view re-appearance
    /// (e.g. popping back from a pushed profile), so without this the same
    /// list would be fetched twice for each navigation round-trip.
    @State private var didInitialLoad = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        ScrollView {
            VStack(spacing: 10) {
                if isLoading, users.isEmpty {
                    ProgressView()
                        .padding(.vertical, 60)
                } else if users.isEmpty {
                    emptyState(c, isRu: isRu)
                } else {
                    ForEach(users, id: \.id) { user in
                        userRow(user, c: c, isRu: isRu)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(c.bg)
        .navigationTitle(titleString(isRu: isRu))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .topBarLeading) { NavBackButton() } }
        .navigationDestination(isPresented: Binding(
            get: { selectedAuthor != nil },
            set: { if !$0 { selectedAuthor = nil } }
        )) {
            if let a = selectedAuthor {
                PublicProfileView(accountId: a.id, preloaded: a)
            }
        }
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await load()
        }
        .refreshable { await load() }
    }

    private func titleString(isRu: Bool) -> String {
        switch mode {
        case .followers: return isRu ? "Подписчики" : "Followers"
        case .following: return isRu ? "Подписки" : "Following"
        }
    }

    private func emptyState(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 32))
                .foregroundStyle(c.textTertiary)
            Text(emptyMessage(isRu: isRu))
                .font(.system(size: 13))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func emptyMessage(isRu: Bool) -> String {
        switch mode {
        case .followers: return isRu ? "Пока никто не подписался" : "No followers yet"
        case .following: return isRu ? "Пока ни на кого не подписаны" : "Not following anyone yet"
        }
    }

    private func userRow(_ user: SocialAuthor, c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            selectedAuthor = user
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.accentBg)
                    .frame(width: 42, height: 42)
                    .overlay { Text(user.avatarEmoji ?? "🚗").font(.system(size: 22)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text("LVL \(user.profileLevel)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(10)
            .surfaceCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let endpoint = mode == .followers ? APIEndpoint.socialFollowers : APIEndpoint.socialFollowing
            let req = SocialFollowersRequest(accountId: accountId, limit: 100, offset: 0)
            let res: SocialFollowersResponse = try await APIClient.shared.post(endpoint, body: req)
            users = res.users
        } catch {
            followListLog.error("load failed: \(error.localizedDescription)")
        }
    }
}
