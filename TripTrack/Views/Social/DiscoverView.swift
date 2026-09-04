import SwiftUI
import OSLog

private let discoverLog = Logger(subsystem: "com.triptrack", category: "social.discover")

struct DiscoverView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [SocialAuthor] = []
    /// Suggestions carry a rationale + mileage the plain `SocialAuthor` of
    /// the search results doesn't — see `SocialSuggestedUser`.
    @State private var suggested: [SocialSuggestedUser] = []
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

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let lng = lang.language

        NavigationStack(path: $authorPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField(c, lng: lng)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        suggestedSection(c, lng: lng)
                    } else {
                        resultsSection(c, lng: lng)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(c.bg)
            // Same bar as every other social screen (canon 117:275) instead
            // of the system one: matching height, matching circle buttons,
            // title on the same baseline as the close button. The system bar
            // put a differently-styled close glyph above the title line.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                CustomNavBar(
                    title: AppStrings.findPeople(lang.language),
                    showsBack: false
                ) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        NavCircleIcon(systemImage: "xmark")
                    }
                    .accessibilityLabel(AppStrings.closeSheet(lang.language))
                }
            }
            .navigationDestination(for: ProfilePreviewDest.self) { dest in
                switch dest {
                case .profile(let id, let author):
                    PublicProfileView(accountId: id, preloaded: author, pushPath: $authorPath)
                case .followList(let id, let mode):
                    FollowListView(accountId: id, mode: mode, pushPath: $authorPath)
                case .publicStats(let id, let name):
                    StatsScreenView(
                        tripManager: mapVM.tripManager,
                        source: RemoteTripSource(accountId: id),
                        ownerName: name
                    )
                case .publicMap(let id, let name):
                    PublicMapView(accountId: id, ownerName: name)
                case .publicGarage(let id, let name):
                    PublicGarageView(accountId: id, ownerName: name)
                case .publicVehicle(let id, let vid, let name):
                    PublicVehicleView(accountId: id, vehicleId: vid, ownerName: name)
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
        }
    }

    // MARK: - Search field

    private func searchField(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(c.textTertiary)
            TextField(
                text: $query,
                // «Поиск по имени» per Figma 117:287 («Имя пользователя» was
                // both off-canon and wrong — the app has no usernames).
                prompt: Text(AppStrings.discoverSearchByName(lng))
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
    private func suggestedSection(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: AppStrings.suggestedByRegions(lang.language),
                c: c
            )

            if isLoadingSuggested, suggested.isEmpty {
                SkeletonPlaceholder(shape: .row, count: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else if suggested.isEmpty {
                emptyStateCard(
                    icon: "person.2.wave.2",
                    title: AppStrings.discoverNoSuggestionsYet(lng),
                    subtitle: AppStrings.discoverWhenNewDrivers(lng),
                    c: c
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(suggested, id: \.id) { user in
                        userRow(
                            user.author, c: c, lng: lng,
                            reason: user.reason, totalKm: user.totalKm
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Results

    @ViewBuilder
    private func resultsSection(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: AppStrings.discoverResults(lng),
                c: c
            )

            if isSearching, results.isEmpty {
                SkeletonPlaceholder(shape: .row, count: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            } else if results.isEmpty {
                emptyStateCard(
                    icon: "magnifyingglass",
                    illustration: "empty_search",
                    title: AppStrings.discoverNoUsersFound(lng),
                    subtitle: AppStrings.discoverTryADifferent(lng),
                    c: c
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(results, id: \.id) { user in
                        userRow(user, c: c, lng: lng)
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

    /// `illustration` wins when there is one; `icon` is the system fallback for
    /// the states whose scene has not been drawn yet, so the screen degrades to
    /// what it looked like before rather than to a blank.
    private func emptyStateCard(
        icon: String, illustration: String? = nil,
        title: String, subtitle: String, c: AppTheme.Colors,
    ) -> some View {
        VStack(spacing: 10) {
            if let illustration {
                EmptyStateIllustration(name: illustration, size: 132)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(c.textTertiary)
            }
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

    /// `reason` / `totalKm` are the suggestion-only extras (Figma 117:291);
    /// search results pass neither and the row collapses back to the
    /// name + level it has always drawn.
    private func userRow(
        _ user: SocialAuthor, c: AppTheme.Colors, lng: LanguageManager.Language,
        reason: SuggestionMatchReason? = nil, totalKm: Double? = nil
    ) -> some View {
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
                    Text(user.displayName ?? (AppStrings.blockedListUser(lng)))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Line 2 — WHY this person is being suggested. Drawn
                    // only for a reason key this build recognises: an
                    // unknown one (a newer server's invention) drops the
                    // line rather than printing `sharedRegion` at the user.
                    if let reason {
                        Text(reason.label(lang.language))
                            .font(.system(size: 11.5))
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    // Line 3 — level, plus lifetime mileage when the DTO
                    // carries it. Search results and pre-0.6 servers send no
                    // mileage, so this stays the bare "LVL n" it was (no
                    // fabricated data).
                    Text(levelLine(user.profileLevel, totalKm: totalKm))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }
                // Claim leftover horizontal space — without this the follow
                // button would shift x-position depending on display-name
                // length, especially noticeable when toggling Follow ↔
                // Following (different label widths).
                .frame(maxWidth: .infinity, alignment: .leading)

                followButton(for: user, c: c, lng: lng)
            }
            .padding(12)
            .surfaceCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    /// «LVL 4» alone, or «LVL 4 · 38 420 км» once the server ships mileage.
    /// Zero km counts as no data — a suggestion whose whole rationale is
    /// how much they drive shouldn't advertise «0 км».
    private func levelLine(_ level: Int, totalKm: Double?) -> String {
        let head = "LVL \(level)"
        guard let km = totalKm, km > 0 else { return head }
        return "\(head) · \(GarageFormat.odometer(km, lng: lang.language)) \(AppStrings.km(lang.language))"
    }

    private func followButton(for user: SocialAuthor, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
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
                 ? (AppStrings.notificationsInboxFollowing(lng))
                 : (AppStrings.discoverFollow(lng)))
                // Fixed footprint (canon 117:298 draws 122pt) — "Подписаться"
                // (11 chars) vs "Подписан" (8 chars) caused visible
                // row-content jump on toggle. Pinning width keeps the row
                // stable between states.
                .socialActionButton(
                    isFollowed ? .done : .primary, colors: c, width: 122
                )
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
            // `SocialSuggestedResponse`, not the shared `SocialUsersResponse`:
            // same `{users:[…]}` envelope, but its rows keep the rationale
            // and mileage this endpoint alone returns.
            let res: SocialSuggestedResponse = try await APIClient.shared.post(
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
