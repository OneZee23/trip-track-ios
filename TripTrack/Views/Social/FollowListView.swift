import SwiftUI
import OSLog

private let followListLog = Logger(subsystem: "com.triptrack", category: "social.followlist")

enum FollowListMode {
    case followers
    case following
}

struct FollowListView: View {
    let accountId: UUID
    /// Provided only when this view is the root of a `PreviewNavigator`
    /// stack — renders an X button in the CustomNavBar trailing that
    /// dismisses the hosting sheet.
    var onClose: (() -> Void)?
    /// When present, user-tap routes through this shared NavigationPath
    /// with a depth cap (sheet context); otherwise we push locally via
    /// `.navigationDestination(isPresented:)` (main-feed context).
    var pushPath: Binding<[ProfilePreviewDest]>?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    /// 0.6.0 (Figma 123:864): the followers/following switch lives in a
    /// segment header, so the mode is view state seeded from the init param —
    /// flipping it reloads the list in place instead of re-presenting.
    @State private var currentMode: FollowListMode
    @State private var users: [SocialAuthor] = []
    @State private var isLoading = false
    @State private var selectedAuthor: SocialAuthor?
    @State private var loadError: String?
    /// Both counts of the viewed account for the segment labels — fetched
    /// from the profile endpoint (real numbers or plain labels, never fake).
    @State private var counts: (followers: Int, following: Int)?
    /// Viewed account's display name — the nav title per Figma 123:864
    /// («whose list is this»); the mode itself lives in the segment chips.
    @State private var accountName: String?
    /// Gate initial fetch — `.task` re-fires on every view re-appearance
    /// (e.g. popping back from a pushed profile), so without this the same
    /// list would be fetched twice for each navigation round-trip.
    @State private var didInitialLoad = false

    init(
        accountId: UUID,
        mode: FollowListMode,
        onClose: (() -> Void)? = nil,
        pushPath: Binding<[ProfilePreviewDest]>? = nil
    ) {
        self.accountId = accountId
        self.onClose = onClose
        self.pushPath = pushPath
        _currentMode = State(initialValue: mode)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let lng = lang.language

        ScrollView {
            VStack(spacing: 10) {
                segmentHeader(c)

                if isLoading, users.isEmpty {
                    SkeletonPlaceholder(shape: .row, count: 6)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else if let err = loadError, users.isEmpty {
                    errorState(err, c: c, lng: lng)
                } else if users.isEmpty {
                    emptyState(c, lng: lng)
                } else {
                    ForEach(users, id: \.id) { user in
                        userRow(user, c: c, lng: lng)
                    }
                    // Depth-cap footnote — only meaningful in the navigator
                    // context where `cappedAppend` actually enforces it.
                    if pushPath != nil {
                        Text(AppStrings.followDepthNote(lang.language))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        // См. PublicProfileView: скролл обязан доходить до физического низа,
        // иначе к 120pt отступа прибавляется домашний индикатор, а плавающий
        // таб-бар безопасную зону игнорирует — под последней строкой остаётся
        // пустая полоса.
        .ignoresSafeArea(edges: .bottom)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            CustomNavBar(title: titleString(lng: lng)) {
                if let onClose {
                    Button {
                        Haptics.tap()
                        onClose()
                    } label: {
                        NavCircleIcon(systemImage: "xmark")
                    }
                }
            }
        }
        // Local-state push used only when no shared `pushPath` is wired in
        // (i.e. we're inside a real NavigationStack — Discover, TripDetail).
        // Inside `PreviewNavigator` there is no stack, so attaching this
        // modifier would log a "misplaced navigationDestination" warning and
        // get ignored anyway.
        .modifier(FollowListLocalDestination(
            selectedAuthor: $selectedAuthor,
            enabled: pushPath == nil
        ))
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await load()
            await loadCounts()
        }
        .onAppear {
            let id = accountId.uuidString.prefix(8)
            let ctx = pushPath == nil ? "local" : "shared"
            let depth = pushPath?.wrappedValue.count ?? -1
            NavFlashDebug.log.debug("FollowListView.onAppear id=\(id, privacy: .public) mode=\(String(describing: self.currentMode), privacy: .public) ctx=\(ctx, privacy: .public) pathDepth=\(depth)")
        }
        .onDisappear {
            let id = accountId.uuidString.prefix(8)
            NavFlashDebug.log.debug("FollowListView.onDisappear id=\(id, privacy: .public) mode=\(String(describing: self.currentMode), privacy: .public)")
        }
        .refreshable { await load() }
    }

    // MARK: - Segment header (Figma 123:864)

    private func segmentHeader(_ c: AppTheme.Colors) -> some View {
        let l = lang.language
        let followersLabel = counts.map { AppStrings.followersCount(l, n: $0.followers) }
            ?? (AppStrings.followListFollowers(l))
        let followingLabel = counts.map { AppStrings.followingCountLabel(l, n: $0.following) }
            ?? (AppStrings.feedSegmentFollowing(l))

        return HStack(spacing: 0) {
            segmentChip(label: followersLabel, mode: .followers, c: c)
            segmentChip(label: followingLabel, mode: .following, c: c)
        }
        .padding(3)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("follow_segment")
    }

    private func segmentChip(label: String, mode: FollowListMode, c: AppTheme.Colors) -> some View {
        let isActive = currentMode == mode
        return Button {
            guard !isActive else { return }
            Haptics.selection()
            currentMode = mode
            users = []
            loadError = nil
            Task { await load() }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isActive ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(isActive ? c.text : c.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(c.card)
                            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.06), radius: 3, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func titleString(lng: LanguageManager.Language) -> String {
        // Figma titles the screen with the account's name; the mode word
        // would just duplicate the segment chip right below it.
        if let accountName, !accountName.isEmpty { return accountName }
        switch currentMode {
        case .followers: return AppStrings.followListFollowers(lng)
        case .following: return AppStrings.feedSegmentFollowing(lng)
        }
    }

    private func emptyState(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(spacing: 10) {
            EmptyStateIllustration(name: "empty_followers", size: 148)
            Text(emptyMessage(lng: lng))
                .font(.system(size: 13))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func emptyMessage(lng: LanguageManager.Language) -> String {
        switch currentMode {
        case .followers: return AppStrings.followListNoFollowersYet(lng)
        case .following: return AppStrings.followListNotFollowingAnyone(lng)
        }
    }

    private func errorState(_ msg: String, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(spacing: 10) {
            EmptyStateIllustration(name: "error_generic", size: 140)
            Text(AppStrings.followListCouldnTLoad(lng))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
            Button(AppStrings.retry(lng)) {
                Haptics.tap()
                Task { await load() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 24)
    }

    // Restyled to Figma 123:864: 36pt avatar, 13.5 bold name, «ур. N» sub.
    // No follow/unfollow button — the list DTO carries no per-user follow
    // state, so a button would fabricate it; follow lives one tap deeper on
    // the profile itself.
    private func userRow(_ user: SocialAuthor, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            if let pushPath {
                pushPath.wrappedValue.cappedAppend(.profile(user.id, user))
            } else {
                selectedAuthor = user
            }
        } label: {
            HStack(spacing: 11) {
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
                    // App-wide LVL convention (feed cards, garage, profile).
                    Text("LVL \(user.profileLevel)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }
                // Claim leftover space — without this short names left a gap
                // before the chevron while long names crowded it, breaking
                // visual rhythm across rows in the list.
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(11)
            .surfaceCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("follow_row")
    }

}

/// Gates the local-state `.navigationDestination` so SwiftUI only sees it
/// when we're actually inside a `NavigationStack`. Without the gate,
/// attaching it inside `PreviewNavigator` (pure-SwiftUI, no stack) triggers
/// a runtime warning and the modifier gets dropped anyway.
private struct FollowListLocalDestination: ViewModifier {
    @Binding var selectedAuthor: SocialAuthor?
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(isPresented: Binding(
                get: { selectedAuthor != nil },
                set: { if !$0 { selectedAuthor = nil } }
            )) {
                if let a = selectedAuthor {
                    PublicProfileView(accountId: a.id, preloaded: a)
                }
            }
        } else {
            content
        }
    }
}

extension FollowListView {
    fileprivate func load() async {
        // No isLoading bail: the segment can flip mid-flight and the fresh
        // mode MUST still fetch. Stale responses are dropped by the mode
        // check below instead of being serialized away.
        let mode = currentMode
        isLoading = true
        defer { if mode == currentMode { isLoading = false } }
        do {
            let endpoint = mode == .followers ? APIEndpoint.socialFollowers : APIEndpoint.socialFollowing
            let req = SocialFollowersRequest(accountId: accountId, limit: 100, offset: 0)
            let res: SocialFollowersResponse = try await APIClient.shared.post(
                endpoint, body: req,
                requiresAuth: AuthService.shared.isSignedIn)
            guard mode == currentMode else { return }
            users = res.users
            loadError = nil
        } catch {
            guard mode == currentMode else { return }
            loadError = error.localizedDescription
            followListLog.error("load failed: \(error.localizedDescription)")
        }
    }

    /// Segment counts — one profile GET for the viewed account. On failure
    /// the chips silently fall back to count-less labels.
    fileprivate func loadCounts() async {
        do {
            let p: SocialProfile = try await APIClient.shared.get(
                APIEndpoint.userProfile(accountId.uuidString))
            counts = (p.followerCount, p.followingCount)
            accountName = p.displayName?.trimmingCharacters(in: .whitespaces)
        } catch {
            followListLog.debug("counts load failed: \(error.localizedDescription)")
        }
    }
}
