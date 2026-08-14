import SwiftUI
import OSLog

private let profileLog = Logger(subsystem: "com.triptrack", category: "social.profile")
/// Dedicated channel for the follower/following count trace so it's easy to
/// filter in Console.app while chasing the "counter shows 0 but list has
/// users" regression. Covers both the decoded network value and the rendered
/// `@State profile` value — mismatch means state got stale between them.
private let countsLog = Logger(subsystem: "com.triptrack", category: "profile.counts")

struct PublicProfileView: View {
    let accountId: UUID
    var preloaded: SocialAuthor?
    /// Provided only by the "preview as others see you" sheet — renders a
    /// close button in the CustomNavBar trailing that dismisses the whole
    /// sheet (distinct from back-button which pops the nav stack).
    var onClose: (() -> Void)?
    /// When set, all sub-navigation (follow lists, reactor profiles) is
    /// routed through a shared `NavigationPath` with a depth cap. Without
    /// this binding we fall back to local `@State`-driven
    /// `.navigationDestination(isPresented:)` for main-feed usage.
    var pushPath: Binding<[ProfilePreviewDest]>?

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
    // Report flow paused until moderation UI exists; state intentionally omitted.
    @State private var selectedBadge: Badge?
    /// Presentation-only grid ↔ list toggle for the trips section (Figma
    /// 117:931 draws the 2-col mini-poster grid as default).
    @State private var tripsAsGrid = true
    /// Gate initial fetch so `.task` — which re-fires on view re-appearance
    /// (e.g. after popping a pushed FollowListView) — doesn't re-run the
    /// sync+fetch cycle every time. Pull-to-refresh remains the explicit
    /// refetch path.
    @State private var didInitialLoad = false
    /// Current in-flight load task. New loads cancel the previous one so
    /// only one request's response can commit to `profile`, preventing the
    /// last-completion-wins race between pull-to-refresh and error recovery.
    @State private var loadTask: Task<Void, Never>?
    @State private var signInPrompt: SignInPromptSheet.Action?
    /// «…» menu → «Пожаловаться» (Figma 117:2335) — presents `ReportSheet`.
    @State private var showReportSheet = false
    /// «…» action sheet (report / block). See the button for why this is a
    /// confirmation dialog rather than a `Menu`.
    @State private var showProfileActions = false
    /// Guest tapped Follow → signed in via the prompt. Mirrors FeedView's
    /// `pendingSocialAction` one-shot resume: set in `onAuthenticated`,
    /// consumed in the sheet's `onDismiss` so the follow the guest originally
    /// tapped isn't silently dropped after a successful sign-in.
    @State private var resumeFollowAfterAuth = false
    /// Confirms «Скопировать ссылку» — the pasteboard is silent otherwise and
    /// the popover has already closed by the time the copy happens.
    @State private var toastItem: ToastItem?

    /// True when this view is rendering the signed-in user's own profile
    /// (e.g. "preview as others see you"). Hides Follow/Block/Report actions.
    private var isOwnProfile: Bool {
        TokenStore.shared.accountId == accountId
    }

    /// Route follow-list navigation through the shared path when one is
    /// wired in (sheet context) so deep flows stay capped; fall back to
    /// local state push for main-feed usage.
    private func openFollowList(_ mode: FollowListMode) {
        if let pushPath {
            pushPath.wrappedValue.cappedAppend(.followList(accountId, mode))
        } else {
            followListMode = mode
        }
    }

    /// Close the «…» popover, then run its action. The gap matters: an alert
    /// or sheet raised in the same runloop as the dismissal races the
    /// transition and SwiftUI silently drops the second presentation — the
    /// same one-shot-resume problem FeedView hits after sign-in.
    private func runProfileAction(_ action: @escaping () -> Void) {
        showProfileActions = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            action()
        }
    }

    /// Public profile link. Built the same way the settings sheet's
    /// «Поделиться профилем» row builds the owner's own — there is no
    /// server-issued profile URL in any DTO, and that row is the only place
    /// the client has ever written one.
    private var profileShareURL: URL? {
        URL(string: "https://trip-track.app/u/\(accountId.uuidString)")
    }

    private func shareProfile() {
        guard let url = profileShareURL else { return }
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        topPresentedViewController()?.present(av, animated: true)
    }

    private func copyProfileLink() {
        guard let url = profileShareURL else { return }
        UIPasteboard.general.string = url.absoluteString
        Haptics.success()
        toastItem = ToastItem(type: .success, message: AppStrings.profileLinkCopied(lang.language))
    }

    /// The profile is often on screen inside a sheet (Discover, the inbox),
    /// and asking the root controller to present over one drops the activity
    /// sheet on the floor. Same walk as `SharedTripLinkSheet`.
    private func topPresentedViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    /// «…» rows: share and copy-link first, then moderation. Sharing is open
    /// to guests too — passing a profile on is not a moderation action, and
    /// the whole button used to be hidden from signed-out viewers because the
    /// menu held nothing but report/block. Those two still need an account:
    /// for a guest they'd only detour through the sign-in sheet.
    private func profileActionItems() -> [ActionPopoverList.Item] {
        var items: [ActionPopoverList.Item] = [
            .init(
                // Same label as the settings row — one action, one wording.
                title: AppStrings.settingsShareProfile(lang.language),
                systemImage: "square.and.arrow.up",
                accessibilityId: "profile_share"
            ) {
                runProfileAction { shareProfile() }
            },
            .init(
                title: AppStrings.copyProfileLink(lang.language),
                systemImage: "link",
                accessibilityId: "profile_copy_link"
            ) {
                runProfileAction { copyProfileLink() }
            },
        ]
        guard auth.isSignedIn else { return items }
        items.append(.init(
            title: AppStrings.reportProfileAction(lang.language),
            systemImage: "exclamationmark.bubble"
        ) {
            runProfileAction { showReportSheet = true }
        })
        items.append(.init(
            title: AppStrings.blockProfileAction(lang.language, isBlocked: isBlocked),
            systemImage: isBlocked ? "hand.raised.slash" : "hand.raised.fill",
            isDestructive: !isBlocked
        ) {
            runProfileAction { showBlockConfirm = true }
        })
        return items
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
            // Skeleton placeholder until the first `loadProfile()` succeeds.
            // Using `ZStack` with opacity-driven transition keeps the scroll
            // offset stable between skeleton and real content — swapping
            // branches via `if/else` would reset the ScrollView state.
            ZStack {
                if profile != nil {
                    VStack(spacing: 16) {
                        heroSection(c, isRu: isRu)
                            .padding(.top, 16)

                        statsGrid(c, isRu: isRu)
                            .padding(.horizontal, 16)

                        activeVehicleCard(c, isRu: isRu)
                            .padding(.horizontal, 16)

                        badgesSection(c, isRu: isRu)
                            .padding(.horizontal, 16)

                        recentTrips(c, isRu: isRu)
                            .padding(.horizontal, 16)
                    }
                    .transition(.opacity)
                } else {
                    SkeletonProfileView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: profile != nil)
            // Bottom inset clears the floating CustomTabBar so the last trip
            // card is fully visible. Matches FeedView's 120pt inset.
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
                        NavCircleIcon(systemImage: "xmark")
                    }
                } else if !isOwnProfile {
                    // Single «…» entry point (Figma 117:2367) — sharing on
                    // top, moderation below. The block hand used to sit as
                    // its own icon right next to «…»: two tiny targets 2pt
                    // apart in the same corner, one of them a one-tap path
                    // into a destructive confirm.
                    //
                    // Anchored popover, NOT a `Menu` — see `ActionPopoverList`
                    // for the plate artifact a Menu leaves behind on close.
                    Button {
                        Haptics.tap()
                        showProfileActions = true
                    } label: {
                        NavCircleIcon(systemImage: "ellipsis")
                    }
                    .accessibilityLabel(AppStrings.moreActions(lang.language))
                    .accessibilityIdentifier("profile_more")
                    .popover(isPresented: $showProfileActions, arrowEdge: .top) {
                        ActionPopoverList(items: profileActionItems())
                    }
                }
            }
        }
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await refresh()
        }
        .onAppear {
            let id = accountId.uuidString.prefix(8)
            let ctx = pushPath == nil ? "local" : "shared"
            let depth = pushPath?.wrappedValue.count ?? -1
            NavFlashDebug.log.debug("PublicProfileView.onAppear id=\(id, privacy: .public) ctx=\(ctx, privacy: .public) pathDepth=\(depth)")
        }
        .onDisappear {
            let id = accountId.uuidString.prefix(8)
            NavFlashDebug.log.debug("PublicProfileView.onDisappear id=\(id, privacy: .public)")
        }
        .onChange(of: auth.isSignedIn) { _, _ in
            // `.task` does NOT re-fire on state change — we must kick the
            // load manually so sign-out/sign-in flows refresh the view
            // instead of leaving it stuck on the previous account's data.
            profile = nil
            Task { await refresh() }
        }
        .refreshable { await refresh() }
        .sheet(item: $signInPrompt, onDismiss: {
            guard resumeFollowAfterAuth else { return }
            resumeFollowAfterAuth = false
            // Resume AFTER the sheet has fully dismissed (same rationale as
            // FeedView's pendingSocialAction consume-in-onDismiss). By now
            // the auth flip's `.onChange` has nilled `profile` and kicked a
            // refresh — the resume POSTs directly so it depends on neither.
            Task { await resumeFollowAfterSignIn() }
        }) { action in
            SignInPromptSheet(action: action, onAuthenticated: {
                if action == .follow { resumeFollowAfterAuth = true }
            })
                .environmentObject(lang)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(target: .user(accountId))
                .environmentObject(lang)
        }
        .toast(item: $toastItem)
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
        // Gated same as in `FollowListView` — only attach when we're inside
        // a real `NavigationStack`. Inside `PreviewNavigator` follow-list
        // navigation goes through `pushPath` and the local state is unused.
        .modifier(PublicProfileLocalDestination(
            accountId: accountId,
            followListMode: $followListMode,
            enabled: pushPath == nil
        ))
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
                guard auth.isSignedIn else {
                    signInPrompt = .generic
                    return
                }
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
        let avatarSize: CGFloat = 84
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
                        .font(.system(size: 21, weight: .heavy))
                        .tracking(-0.21)
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.center)

                    if let lvl = profile?.profileLevel ?? preloaded?.profileLevel {
                        // LvlPill (Figma 117:931) — star + rank-colored pixel
                        // LVL + rank title on a warm pill. `c.cardAlt` stands
                        // in for Figma #F7EFDE (nearest adaptive token).
                        let rank = DriverRank.from(level: lvl)
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(rank.color)
                            Text("LVL \(lvl)")
                                .font(.custom("PressStart2P-Regular", size: 9))
                                .tracking(1)
                                .foregroundStyle(rank.color)
                            Text("·")
                                .foregroundStyle(c.textTertiary)
                            Text(rank.title(lang.language))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(c.cardAlt, in: Capsule())
                    }

                    // Last-trip pill — shows a relative "N days ago"
                    // derived from the most recent PUBLIC trip the
                    // server returned. Hidden when the account is in
                    // privacy mode (already shows "Hidden roads" lower
                    // down) or has no public trips at all.
                    //
                    // The streak sits next to it rather than in the stats
                    // card: canon (117:975) has no «дней подряд» cell, and a
                    // flame among the road totals read as a fourth number of
                    // the same kind. Beside the last-drive line it stays what
                    // it is — a note about habit, not a total.
                    let lastDrive = isPrivacyMode ? nil : profile?.recentTrips.first?.startDate
                    let streak = isPrivacyMode ? 0 : (profile?.currentStreak ?? 0)
                    if lastDrive != nil || streak > 0 {
                        HStack(spacing: 6) {
                            if let lastDrive {
                                heroPill(
                                    icon: "road.lanes",
                                    text: lastActivityCopy(lastDrive, isRu: isRu),
                                    c: c
                                )
                            }
                            if streak > 0 {
                                heroPill(
                                    icon: "flame.fill",
                                    text: AppStrings.streakDaysInARow(lang.language, n: streak),
                                    c: c,
                                    accent: AppTheme.accent
                                )
                            }
                        }
                        .padding(.top, 2)
                    }

                    // «О себе» (Figma 117:966). Server 6.1+ only: the field
                    // decodes as nil against today's production, and a user
                    // who cleared their bio sends back a blank string —
                    // both draw nothing rather than an empty gap under the
                    // pills. Width-capped so a long line wraps into a
                    // centred block instead of running the full card width.
                    if let bio = profile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !bio.isEmpty {
                        Text(bio)
                            .font(.system(size: 13))
                            .foregroundStyle(c.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 290)
                            .padding(.top, 4)
                            .accessibilityIdentifier("profile_bio")
                    }
                }

                // Guests get the CTA too: the backend omits `isFollowing`
                // for unauthenticated requesters (it decodes nil), so gating
                // on non-nil alone hid the primary Figma CTA (117:931) — and
                // its sign-in funnel — from every signed-out viewer. The
                // button's own guard routes guests to the sign-in prompt.
                if !isOwnProfile, !auth.isSignedIn || profile?.isFollowing != nil {
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

    /// Small capsule under the name (last drive, streak). `accent` tints both
    /// the glyph and the label so the streak's flame doesn't read as a muted
    /// timestamp next to it.
    private func heroPill(
        icon: String, text: String, c: AppTheme.Colors, accent: Color? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent ?? c.textTertiary)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent ?? c.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(c.cardAlt, in: Capsule())
    }

    @ViewBuilder
    private func followButton(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let isFollowing = profile?.isFollowing ?? false
        Button {
            Haptics.action()
            guard auth.isSignedIn else {
                signInPrompt = .follow
                return
            }
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
            }
            // Hugs its label like canon (117:969, 130×41) — nothing sits
            // beside it, so there's no row for a width change to disturb.
            .socialActionButton(isFollowing ? .secondary : .primary, colors: c)
        }
        .buttonStyle(.plain)
        .disabled(isTogglingFollow)
    }

    // MARK: - Stats

    /// Account is signed in + has gamification activity (level / streak)
    /// but zero trips on the server. Two ways to land here:
    ///   1. Cloud Sync OFF — drives are happening locally but never synced
    ///      (profile metadata is pushed unconditionally by `syncProfileToServer`).
    ///   2. User wiped server data via "Clear my server data" but kept the
    ///      account.
    /// Either way, showing "0 поездок · 0 км · 0 регионов" reads as a bug
    /// to the viewer. Replace the numbers with placeholder dots and a
    /// gentle "private routes" footnote — the LVL pill above still
    /// signals the account is active. Owner-side view is untouched
    /// (they see their own truth, which is just the zero state).
    /// Builds the "last on the road N ago" copy from the most recent
    /// public trip's start date. Uses the existing `RelativeTripDate`
    /// formatter so the wording matches every other date pill in the
    /// app ("3 days ago" / "вчера" / "только что").
    private func lastActivityCopy(_ date: Date, isRu: Bool) -> String {
        let rel = RelativeTripDate.string(from: date, language: isRu ? .ru : .en)
        return isRu ? "На дороге · \(rel)" : "On the road · \(rel)"
    }

    private var isPrivacyMode: Bool {
        guard !isOwnProfile, let p = profile else { return false }
        let tripCount = p.stats.tripCount
        return tripCount == 0 && (p.profileLevel > 1 || p.currentStreak > 0 || p.bestStreak > 0)
    }

    private func statsGrid(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let stats = profile?.stats
        let privacy = isPrivacyMode
        let dots = "•••"
        let tripsValue = privacy ? dots : (stats.map { String($0.tripCount) } ?? "—")
        let kmValue = privacy ? dots : (stats.map { String(format: "%.0f", $0.totalKm) } ?? "—")
        let regionsValue = privacy ? dots : (stats.map { String($0.regionsCount) } ?? "—")
        // Trace what the UI is ACTUALLY rendering right now. Compare with the
        // `loadProfile decoded` line to spot the stale-state / wrong-field
        // case. Runs on every body rebuild — noisy, but that's the point.
        let followerShown = profile?.followerCount ?? 0
        let followingShown = profile?.followingCount ?? 0
        let loaded = profile != nil
        countsLog.debug("render statsGrid counters id=\(self.accountId.uuidString.prefix(8), privacy: .public) loaded=\(loaded, privacy: .public) followerShown=\(followerShown, privacy: .public) followingShown=\(followingShown, privacy: .public)")
        return VStack(spacing: 8) {
            // One card, two rows (Figma 117:975): the road numbers on top, the
            // social counters under a full-width hairline. The counters used
            // to be a card of their own two sections down, which read as a
            // second, unrelated set of stats — and let the trips grid drift
            // that much further off the fold.
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    statCell(value: tripsValue, label: isRu ? "поездок" : "trips", c: c)
                    statCell(value: kmValue, label: AppStrings.km(lang.language), c: c)
                    statCell(value: regionsValue, label: isRu ? "регионов" : "regions", c: c)
                }
                divider(c)
                HStack(spacing: 0) {
                    followCounterCell(
                        count: followerShown,
                        label: AppStrings.followersCaption(lang.language, n: followerShown),
                        mode: .followers, c: c
                    )
                    followCounterCell(
                        count: followingShown,
                        label: AppStrings.followingCaption(lang.language, n: followingShown),
                        mode: .following, c: c
                    )
                }
            }
            .padding(.vertical, 18)
            .surfaceCard(cornerRadius: 16)

            if privacy {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(c.textTertiary)
                    Text(isRu
                         ? "Тайные дороги — водитель оставил поездки приватными"
                         : "Hidden roads — this driver keeps their trips private")
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Both rows of the card use this — the `accent` + icon overload it used
    /// to carry existed only for the streak cell, which canon doesn't have.
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

    /// Follower / following half of the stats card. Still a button — the
    /// counts are the only way into the follow lists.
    private func followCounterCell(
        count: Int, label: String, mode: FollowListMode, c: AppTheme.Colors
    ) -> some View {
        Button {
            Haptics.tap()
            openFollowList(mode)
        } label: {
            statCell(value: "\(count)", label: label, c: c)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Full-width hairline between the two rows of the stats card. Was a
    /// vertical 28pt rule between columns back when the card was a 2×2 grid;
    /// canon rules the ROWS apart and leaves the columns to their own spacing.
    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.border)
            .frame(height: 1)
    }

    // MARK: - Active vehicle

    /// "Your car" card that mirrors the garage's vehicle chrome — same
    /// hierarchy (avatar, name, level, odometer progress bar) so the
    /// public view feels consistent with how the user sees their own garage.
    /// Uses VehicleLevelSystem directly because the server returns a leaner
    /// DTO without stickers/consumption.
    @ViewBuilder
    private func activeVehicleCard(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        if let v = profile?.activeVehicle {
            let progress = VehicleLevelSystem.progressToNext(km: v.odometerKm, level: v.level)
            let frame = VehicleLevelSystem.color(for: v.level)

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
                            .truncationMode(.tail)

                        Spacer()

                        Text("LVL \(v.level)")
                            .font(.custom("PressStart2P-Regular", size: 9))
                            .foregroundStyle(frame)
                            .fixedSize()
                    }

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
                // Claim leftover space so long vehicle names truncate
                // instead of pushing the LVL pill off-screen.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }


    /// «38 420 км» / "38 420 km" — same convention as the private stats
    /// strip (GarageFormat space grouping + localized unit). Replaces the
    /// old hardcoded "%.1fK km" which leaked Latin "K km" and a decimal
    /// point into the otherwise fully-RU card.
    private func formatOdometer(_ km: Double) -> String {
        "\(GarageFormat.odometer(km)) \(AppStrings.km(lang.language))"
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
                sectionHeader("\(AppStrings.badges(lang.language)) · \(badges.count)", c: c)

                // No card behind the cells (canon 117:1321 lays them straight
                // on the page): each badge already carries its own tinted
                // disc, so a second surface under them boxed one set of round
                // shapes inside another for no gain.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(badges) { badge in
                            badgeCell(badge, c: c)
                        }
                    }
                }
            }
        }
    }

    /// Canon section header (Figma 117:1319 / 117:1338) — the 11pt uppercase
    /// tertiary label every other social screen already uses. This screen set
    /// its two headers 15pt bold mixed-case in primary, so they carried more
    /// weight than the profile name they sat under.
    private func sectionHeader(_ title: String, c: AppTheme.Colors) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.44)
            .textCase(.uppercase)
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badgeCell(_ badge: Badge, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            selectedBadge = badge
        } label: {
            // 74×74 cell (Figma 117:931): 46pt tinted icon disc + tier-colored
            // caption.
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(badge.color.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: badge.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(badge.color)
                }
                Text(badge.title(lang.language))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(badge.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 74)
            }
            .frame(width: 74)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent trips

    @ViewBuilder
    private func recentTrips(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        if let trips = profile?.recentTrips, !trips.isEmpty {
            let publicCount = profile?.stats.publicTripCount ?? trips.count
            let totalCount = profile?.stats.tripCount ?? trips.count
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    sectionHeader(
                        tripsHeaderTitle(public: publicCount, total: totalCount, isRu: isRu),
                        c: c
                    )
                    layoutToggle(c)
                }

                if tripsAsGrid {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(trips) { t in
                            tripGridCell(t, c: c, isRu: isRu)
                        }
                    }
                } else {
                    ForEach(trips) { t in
                        recentTripRow(t, c: c, isRu: isRu)
                    }
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

    /// «Поездки · 47 · всего 52» as one label rather than four Texts in three
    /// sizes — canon (117:1339) writes the counts into the header line itself.
    /// The «всего» tail only appears when the owner is holding trips back, so
    /// the public number doesn't read as their whole road history.
    private func tripsHeaderTitle(public publicCount: Int, total: Int, isRu: Bool) -> String {
        let head = isRu ? "Поездки · \(publicCount)" : "Trips · \(publicCount)"
        guard total > publicCount else { return head }
        return head + (isRu ? " · всего \(total)" : " · \(total) total")
    }

    /// Grid ↔ list segmented mini-toggle in the trips header.
    private func layoutToggle(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 2) {
            layoutToggleButton(icon: "square.grid.2x2", isOn: tripsAsGrid, c: c) {
                tripsAsGrid = true
            }
            layoutToggleButton(icon: "list.bullet", isOn: !tripsAsGrid, c: c) {
                tripsAsGrid = false
            }
        }
        .padding(2)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 8))
    }

    private func layoutToggleButton(
        icon: String, isOn: Bool, c: AppTheme.Colors, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? c.text : c.textTertiary)
                .frame(width: 26, height: 22)
                .background(isOn ? c.card : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// 2-col mini-poster cell (Figma 117:931): cinema route canvas + title
    /// + distance.
    private func tripGridCell(_ trip: SocialProfileRecentTrip, c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if trip.previewCoordinates.count > 1 {
                PosterRouteCanvas(
                    coordinates: trip.previewCoordinates,
                    speeds: [],
                    style: .cinema,
                    showsCar: false
                )
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(c.cardAlt)
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Image(systemName: "map")
                            .font(.system(size: 16))
                            .foregroundStyle(c.textTertiary)
                    }
            }

            Text(trip.title ?? shortDate(trip.startDate, isRu: isRu))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)

            Text("\(GarageFormat.oneDecimal(trip.distanceKm, isRu: isRu)) \(AppStrings.km(lang.language))")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(c.textTertiary)
        }
        .padding(10)
        .surfaceCard(cornerRadius: 14)
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
                    Text("\(GarageFormat.oneDecimal(trip.distanceKm, isRu: isRu)) \(AppStrings.km(lang.language))")
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
        PixelCarLoader(label: nil, height: 80)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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
        let idPrefix = accountId.uuidString.prefix(8)
        countsLog.debug("loadProfile start id=\(idPrefix, privacy: .public) own=\(self.isOwnProfile, privacy: .public)")
        do {
            let p: SocialProfile = try await APIClient.shared.get(
                APIEndpoint.userProfile(accountId.uuidString),
                requiresAuth: AuthService.shared.isSignedIn)
            countsLog.debug("loadProfile decoded id=\(idPrefix, privacy: .public) followerCount=\(p.followerCount, privacy: .public) followingCount=\(p.followingCount, privacy: .public) isFollowing=\(String(describing: p.isFollowing), privacy: .public)")
            if Task.isCancelled {
                countsLog.debug("loadProfile cancelled AFTER decode id=\(idPrefix, privacy: .public) — NOT committing to @State")
                return
            }
            profile = p
            countsLog.debug("loadProfile committed id=\(idPrefix, privacy: .public) state.followingCount=\(p.followingCount, privacy: .public)")
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

    /// Runs the follow a guest tapped before signing in. POSTs directly
    /// instead of going through `toggleFollow()`: the auth flip's `.onChange`
    /// just nilled `profile` and kicked a refresh, so the optimistic-update
    /// path would no-op on its `guard let current = profile`. The trailing
    /// `refresh()` reconciles the UI with server truth either way.
    private func resumeFollowAfterSignIn() async {
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        do {
            let req = SocialFollowRequest(targetAccountId: accountId)
            let _: SocialFollowResponse = try await APIClient.shared.post(
                APIEndpoint.socialFollow, body: req)
        } catch {
            profileLog.error("post-auth follow resume failed: \(error.localizedDescription)")
        }
        await refresh()
    }

    private func shortDate(_ date: Date, isRu: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: isRu ? "ru_RU" : "en_US")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }
}

/// Gates the local-state `.navigationDestination` so SwiftUI only sees it
/// when we're actually inside a `NavigationStack`. Without the gate,
/// attaching it inside `PreviewNavigator` triggers a runtime warning and
/// the modifier gets dropped anyway.
private struct PublicProfileLocalDestination: ViewModifier {
    let accountId: UUID
    @Binding var followListMode: FollowListMode?
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(isPresented: Binding(
                get: { followListMode != nil },
                set: { if !$0 { followListMode = nil } }
            )) {
                if let m = followListMode {
                    FollowListView(accountId: accountId, mode: m)
                }
            }
        } else {
            content
        }
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
            isFollowing: isFollowing, bio: bio
        )
    }
}
