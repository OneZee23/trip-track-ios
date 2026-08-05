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
    /// Typed path with `cappedAppend` — same pattern as FeedView. Replaces
    /// the previous `selectedAuthor` + chained `.navigationDestination(isPresented:)`
    /// which let depth compound past 4 and exposed the SwiftUI back-button flash.
    @State private var authorPath: [ProfilePreviewDest] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var signInPrompt: SignInPromptSheet.Action?
    @ObservedObject private var auth = AuthService.shared
    /// Injected by the presenter (FeedView) — needed to re-apply the in-app
    /// theme override on the nested sign-in sheet (nested sheets are separate
    /// presentations; the override on the Discover sheet doesn't reach them).
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack(path: $authorPath) {
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
            .navigationTitle(AppStrings.findPeople(lang.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SheetCloseButton() }
            }
            .navigationDestination(for: ProfilePreviewDest.self) { dest in
                switch dest {
                case .profile(let id, let author):
                    PublicProfileView(accountId: id, preloaded: author, pushPath: $authorPath)
                case .followList(let id, let mode):
                    FollowListView(accountId: id, mode: mode, pushPath: $authorPath)
                case .trip, .socialTrip:
                    // Discover never pushes trip destinations; render empty if
                    // the path somehow gets one to stay type-exhaustive.
                    EmptyView()
                }
            }
        }
        .task { await loadSuggested() }
        .sheet(item: $signInPrompt) { action in
            SignInPromptSheet(action: action)
                .environmentObject(lang)
                .environmentObject(auth)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
    }

    // MARK: - Search field

    private func searchField(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(c.textTertiary)
            TextField(
                text: $query,
                // «Поиск по имени» per Figma 117:287 («Имя пользователя» was
                // both off-canon and wrong — the app has no usernames).
                prompt: Text(isRu ? "Поиск по имени" : "Search by name")
                    .foregroundStyle(c.textTertiary)
            ) {
                Text(AppStrings.findPeople(lang.language))
            }
            .font(.system(size: 15))
            .foregroundStyle(c.text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .accessibilityIdentifier("discover_search_field")
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
                title: AppStrings.suggestedByRegions(lang.language),
                c: c
            )

            if isLoadingSuggested, suggested.isEmpty {
                PixelCarLoader(label: nil, height: 80)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if suggested.isEmpty {
                emptyStateCard(
                    icon: "person.2.wave.2",
                    title: isRu ? "Пока некого рекомендовать" : "No suggestions yet",
                    subtitle: isRu
                        ? "Когда в приложении появятся новые водители — увидите их здесь."
                        : "When new drivers join, they'll show up here.",
                    c: c
                )
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
                PixelCarLoader(label: nil, height: 80)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if results.isEmpty {
                emptyStateCard(
                    icon: "magnifyingglass",
                    title: isRu ? "Никого не нашли" : "No users found",
                    subtitle: isRu
                        ? "Попробуйте другое имя или проверьте раскладку."
                        : "Try a different name or check your spelling.",
                    c: c
                )
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
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.44)
            .foregroundStyle(c.textTertiary)
            .textCase(.uppercase)
    }

    // MARK: - User row

    private func emptyStateCard(
        icon: String, title: String, subtitle: String, c: AppTheme.Colors,
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(c.textTertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 20)
    }

    private func userRow(_ user: SocialAuthor, c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            authorPath.cappedAppend(.profile(user.id, user))
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(c.cardAlt)
                    .frame(width: 36, height: 36)
                    .overlay { Text(user.avatarEmoji ?? "🚗").font(.system(size: 19)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Context line / mileage only when the DTO carries them —
                    // the suggestion DTO ships level only, so that's what we
                    // render (no fabricated data).
                    Text("LVL \(user.profileLevel)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }
                // Claim leftover horizontal space — without this the follow
                // button would shift x-position depending on display-name
                // length, especially noticeable when toggling Follow ↔
                // Following (different label widths).
                .frame(maxWidth: .infinity, alignment: .leading)

                followButton(for: user, c: c, isRu: isRu)
            }
            .padding(12)
            .surfaceCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func followButton(for user: SocialAuthor, c: AppTheme.Colors, isRu: Bool) -> some View {
        let isFollowed = followedIds.contains(user.id)
        return Button {
            Haptics.selection()
            guard auth.isSignedIn else {
                signInPrompt = .follow
                return
            }
            Task { await toggleFollow(for: user.id) }
        } label: {
            Text(isFollowed
                 ? (isRu ? "Подписан" : "Following")
                 : (isRu ? "Подписаться" : "Follow"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.vertical, 8)
                // Fixed footprint (Figma: 122pt) — "Подписаться" (11 chars)
                // vs "Подписан" (8 chars) caused visible row-content jump on
                // toggle. Pinning width keeps the row stable between states.
                .frame(width: 122)
                .background(
                    isFollowed ? c.cardAlt : AppTheme.accent,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isFollowed ? c.borderBright : Color.clear, lineWidth: 1.5)
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
                APIEndpoint.socialSearch, body: req,
                requiresAuth: AuthService.shared.isSignedIn)
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
                APIEndpoint.socialSuggested, body: req,
                requiresAuth: AuthService.shared.isSignedIn)
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
