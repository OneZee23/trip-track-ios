import SwiftUI
import OSLog

private let suggestedLog = Logger(subsystem: "com.triptrack", category: "social.suggested")

/// Horizontal scrolling row of suggested users to follow.
/// Loads from /social/suggested on appear; updates on follow/unfollow via local state.
struct SuggestedUsersCarousel: View {
    var onTapUser: (SocialAuthor) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var users: [SocialAuthor] = []
    @State private var followed: Set<UUID> = []
    @State private var pendingFollow: Set<UUID> = []
    @State private var didLoad = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(alignment: .leading, spacing: 10) {
            if !users.isEmpty {
                HStack {
                    Text(isRu ? "Рекомендуем подписаться" : "Suggested")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(c.textTertiary)
                        .textCase(.uppercase)
                    Spacer()
                }
                .padding(.horizontal, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(users, id: \.id) { user in
                            card(user, c: c, isRu: isRu)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .task {
            if !didLoad { didLoad = true; await load() }
        }
    }

    private func card(_ user: SocialAuthor, c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 10) {
            Circle()
                .fill(AppTheme.accentBg)
                .frame(width: 62, height: 62)
                .overlay { Text(user.avatarEmoji ?? "🚗").font(.system(size: 32)) }

            VStack(spacing: 2) {
                Text(user.displayName ?? (isRu ? "Пользователь" : "User"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Text("LVL \(user.profileLevel)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(c.textTertiary)
            }

            followButton(user, c: c, isRu: isRu)
        }
        .frame(width: 120)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .surfaceCard(cornerRadius: 14)
        .onTapGesture {
            Haptics.tap()
            onTapUser(user)
        }
    }

    private func followButton(_ user: SocialAuthor, c: AppTheme.Colors, isRu: Bool) -> some View {
        let isFollowed = followed.contains(user.id)
        let isPending = pendingFollow.contains(user.id)
        return Button {
            Haptics.selection()
            Task { await toggleFollow(user.id) }
        } label: {
            Group {
                if isPending {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(isFollowed ? c.text : .white)
                } else {
                    Text(isFollowed
                         ? (isRu ? "Подписан" : "Following")
                         : (isRu ? "Подписаться" : "Follow"))
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(isFollowed ? c.text : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isFollowed ? c.cardAlt : AppTheme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPending)
    }

    // MARK: - Networking

    private func load() async {
        do {
            let req = SocialSuggestedRequest(limit: 10)
            let res: SocialUsersResponse = try await APIClient.shared.post(
                APIEndpoint.socialSuggested, body: req)
            await MainActor.run { users = res.users }
        } catch {
            suggestedLog.error("suggested load failed: \(error.localizedDescription)")
        }
    }

    private func toggleFollow(_ userId: UUID) async {
        pendingFollow.insert(userId)
        defer { pendingFollow.remove(userId) }
        let wasFollowing = followed.contains(userId)
        if wasFollowing { followed.remove(userId) } else { followed.insert(userId) }
        do {
            let req = SocialFollowRequest(targetAccountId: userId)
            let endpoint = wasFollowing ? APIEndpoint.socialUnfollow : APIEndpoint.socialFollow
            let _: SocialFollowResponse = try await APIClient.shared.post(endpoint, body: req)
            // Once followed, drop the user from the carousel (they'll appear in main feed now)
            if !wasFollowing {
                await MainActor.run {
                    users.removeAll { $0.id == userId }
                }
            }
        } catch {
            // Revert optimistic
            if wasFollowing { followed.insert(userId) } else { followed.remove(userId) }
            suggestedLog.error("follow toggle failed: \(error.localizedDescription)")
        }
    }
}
