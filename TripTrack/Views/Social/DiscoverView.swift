import SwiftUI
import OSLog

private let discoverLog = Logger(subsystem: "com.triptrack", category: "social.discover")

struct DiscoverView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [SocialAuthor] = []
    @State private var suggested: [SocialAuthor] = []
    @State private var followedIds: Set<UUID> = []
    @State private var isSearching = false
    @State private var isLoadingSuggested = false
    @State private var selectedAuthor: SocialAuthor?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField(c, isRu: isRu)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        suggestedSection(c, isRu: isRu)
                    } else {
                        resultsSection(c, isRu: isRu)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(c.bg)
            .navigationTitle(isRu ? "Найти друзей" : "Find friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedAuthor != nil },
                set: { if !$0 { selectedAuthor = nil } }
            )) {
                if let a = selectedAuthor {
                    PublicProfileView(accountId: a.id, preloaded: a)
                }
            }
        }
        .task { await loadSuggested() }
    }

    // MARK: - Search field

    private func searchField(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(c.textTertiary)
            TextField(
                isRu ? "Имя пользователя" : "Search by name",
                text: $query
            )
            .font(.system(size: 15))
            .foregroundStyle(c.text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: query) { _, newValue in
                debouncedSearch(newValue)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(c.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surfaceCard(cornerRadius: 12)
    }

    // MARK: - Suggested

    @ViewBuilder
    private func suggestedSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: isRu ? "Рекомендуем" : "Suggested",
                c: c
            )

            if isLoadingSuggested, suggested.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if suggested.isEmpty {
                Text(isRu ? "Пока никого не можем порекомендовать" : "No suggestions yet")
                    .font(.system(size: 13))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(suggested, id: \.id) { user in
                        userRow(user, c: c, isRu: isRu)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Results

    @ViewBuilder
    private func resultsSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: isRu ? "Результаты" : "Results",
                c: c
            )

            if isSearching, results.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if results.isEmpty {
                Text(isRu ? "Никого не найдено" : "No users found")
                    .font(.system(size: 13))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 8) {
                    ForEach(results, id: \.id) { user in
                        userRow(user, c: c, isRu: isRu)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func sectionHeader(title: String, c: AppTheme.Colors) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(c.textTertiary)
            .textCase(.uppercase)
    }

    // MARK: - User row

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

                followButton(for: user, c: c, isRu: isRu)
            }
            .padding(10)
            .surfaceCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private func followButton(for user: SocialAuthor, c: AppTheme.Colors, isRu: Bool) -> some View {
        let isFollowed = followedIds.contains(user.id)
        return Button {
            Haptics.selection()
            Task { await toggleFollow(for: user.id) }
        } label: {
            Text(isFollowed
                 ? (isRu ? "Подписан" : "Following")
                 : (isRu ? "Подписаться" : "Follow"))
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isFollowed ? c.cardAlt : AppTheme.accent,
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .foregroundStyle(isFollowed ? c.text : .white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Networking

    private func debouncedSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        searchTask = Task { [text = trimmed] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(query: text)
        }
    }

    private func runSearch(query text: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let req = SocialSearchRequest(query: text, limit: 25)
            let res: SocialUsersResponse = try await APIClient.shared.post(
                APIEndpoint.socialSearch, body: req)
            await MainActor.run { results = res.users }
        } catch {
            discoverLog.error("search failed: \(error.localizedDescription)")
        }
    }

    private func loadSuggested() async {
        isLoadingSuggested = true
        defer { isLoadingSuggested = false }
        do {
            let req = SocialSuggestedRequest(limit: 10)
            let res: SocialUsersResponse = try await APIClient.shared.post(
                APIEndpoint.socialSuggested, body: req)
            await MainActor.run { suggested = res.users }
        } catch {
            discoverLog.error("suggested failed: \(error.localizedDescription)")
        }
    }

    private func toggleFollow(for userId: UUID) async {
        let wasFollowing = followedIds.contains(userId)
        if wasFollowing { followedIds.remove(userId) } else { followedIds.insert(userId) }
        do {
            let req = SocialFollowRequest(targetAccountId: userId)
            let endpoint = wasFollowing ? APIEndpoint.socialUnfollow : APIEndpoint.socialFollow
            let _: SocialFollowResponse = try await APIClient.shared.post(endpoint, body: req)
        } catch {
            // Revert on failure
            if wasFollowing { followedIds.insert(userId) } else { followedIds.remove(userId) }
            discoverLog.error("follow toggle failed: \(error.localizedDescription)")
        }
    }
}
