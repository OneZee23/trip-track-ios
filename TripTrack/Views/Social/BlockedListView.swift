import SwiftUI
import OSLog

private let blockedLog = Logger(subsystem: "com.triptrack", category: "social.blocked")

struct BlockedListView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var users: [SocialAuthor] = []
    @State private var isLoading = false
    @State private var pendingUnblockId: UUID?

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
        .navigationTitle(isRu ? "Заблокированные" : "Blocked")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { ToolbarItem(placement: .topBarLeading) { NavBackButton() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func emptyState(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.raised.slash")
                .font(.system(size: 32))
                .foregroundStyle(c.textTertiary)
            Text(isRu ? "Вы никого не блокировали" : "You haven't blocked anyone")
                .font(.system(size: 13))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func userRow(_ user: SocialAuthor, c: AppTheme.Colors, isRu: Bool) -> some View {
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

            Button {
                Haptics.tap()
                Task { await unblock(userId: user.id) }
            } label: {
                if pendingUnblockId == user.id {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 90, height: 30)
                } else {
                    Text(isRu ? "Разблокировать" : "Unblock")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(c.text)
                }
            }
            .buttonStyle(.plain)
            .disabled(pendingUnblockId == user.id)
        }
        .padding(10)
        .surfaceCard(cornerRadius: 12)
    }

    // MARK: - Networking

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let res: SocialBlockedListResponse = try await APIClient.shared.post(
                APIEndpoint.socialBlocked, body: EmptyRequest())
            users = res.users
        } catch {
            blockedLog.error("blocked list load failed: \(error.localizedDescription)")
        }
    }

    private func unblock(userId: UUID) async {
        pendingUnblockId = userId
        defer { pendingUnblockId = nil }
        do {
            let req = SocialBlockRequest(targetAccountId: userId)
            let _: SocialBlockResponse = try await APIClient.shared.post(
                APIEndpoint.socialUnblock, body: req)
            users.removeAll { $0.id == userId }
            Haptics.success()
        } catch {
            blockedLog.error("unblock failed: \(error.localizedDescription)")
        }
    }
}
