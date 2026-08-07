import SwiftUI
import OSLog

enum FeedMode: Hashable { case all, following }

struct FeedView: View {
    // Shared, not @StateObject: the tab switch destroys this view and a
    // view-owned VM would reset filters/calendar/sections every hop.
    @ObservedObject private var feedVM: FeedViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var socialFeed = SocialFeedStore.shared
    /// «Подписки» — the following-only feed instance (Figma 141:1081).
    @ObservedObject private var followingFeed = SocialFeedStore.following
    /// Drives the connectivity banner — when ops accumulate in `failed`,
    /// the network is genuinely broken and we surface that to the user.
    @ObservedObject private var syncQueue = SyncQueue.shared
    /// Drives the offline strip + the "you're offline" flavour of the error
    /// state. Shared instance — CacheManager owns the only monitor.
    @ObservedObject private var network = CacheManager.shared.networkMonitor
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTab: AppTab
    @State private var didLoad = false
    @State private var showBadges = false
    @State private var showNotifications = false
    @State private var showGarage = false
    /// Persisted so the chosen segment survives tab switches (the switch
    /// destroys this view) and relaunches. Fresh key: the old value tracked
    /// the retired «Мои» segment.
    @AppStorage("feedSegmentFollowingV2") private var feedModeIsFollowing = false
    @State private var feedMode: FeedMode = .all
    /// Cached "does the user have at least one private trip" flag.
    /// Read in `socialEmptyState` to gate the "Publish one of your
    /// trips" CTA. We cache rather than calling
    /// `tripManager.hasAnyPrivateTrip()` from `body` because the latter
    /// hits CoreData synchronously during body, and at cold launch
    /// that competes with the migration batches firing inside
    /// `MapViewModel.init`, producing an `AttributeGraph: cycle
    /// detected` warning + extra body invalidations.
    @State private var hasAnyPrivateTrip: Bool = false
    /// Shared path for the profile → follow list → profile chain. Using a
    /// typed `NavigationPath`-style array with `cappedAppend` keeps depth
    /// ≤ `previewDepthCap`, which dodges the SwiftUI bug that flashes a
    /// default back button at stack depth 4+. Replaces the previous
    /// `@State selectedAuthor` + chained `.navigationDestination(isPresented:)`
    /// that let depth compound unbounded through nested pushes.
    @State private var authorPath: [ProfilePreviewDest] = []
    @State private var reactionPickerTrip: SocialFeedTrip?
    /// Long-pressed a tally pill — «кто отреагировал» sheet, opened on the
    /// emoji that was pressed.
    @State private var reactorsPeek: ReactorsPeek?
    /// Own trip awaiting delete confirmation from the card's «…».
    @State private var tripPendingDelete: SocialFeedTrip?
    /// Own trip awaiting «сделать приватной» confirmation. Unpublishing is
    /// destructive to everything attached to the trip socially, so it asks
    /// first like the delete does.
    @State private var tripPendingPrivate: SocialFeedTrip?
    /// Someone else's trip being reported from its card «…».
    @State private var tripPendingReport: SocialFeedTrip?
    /// Compact link-share sheet for someone else's trip.
    @State private var linkShareData: LinkShare?
    /// Undo window after «Да» in the hide/delete alert. The mutation is
    /// DEFERRED into `onCommit` — canon: nothing happens on the server until
    /// the ten seconds are up.
    @State private var undoToast: UndoToast?
    @State private var showDiscover = false
    /// Poster studio payload. `url` is optional: a failed share-link call
    /// shouldn't block exporting the card itself.
    @State private var shareSheetData: (data: StoryShareData, url: String?)?
    @State private var signInPrompt: SignInPromptSheet.Action?

    /// Payload for the compact «поделиться чужой» sheet.
    private struct LinkShare: Identifiable {
        let trip: SocialFeedTrip
        let url: String?
        var id: UUID { trip.id }
    }

    /// Long-press peek payload — the trip whose reactor list to show and
    /// which emoji chip to land on.
    private struct ReactorsPeek: Identifiable {
        let trip: SocialFeedTrip
        let emoji: String
        var id: String { "\(trip.id.uuidString)-\(emoji)" }
    }

    /// A guest-tapped social action that needs an account. Captured before we
    /// present the sign-in prompt so the action can be RESUMED on success
    /// instead of silently dropped (the old behaviour: prompt appeared, login
    /// worked, nothing happened). Cleared when the prompt is dismissed without
    /// signing in.
    private enum PendingSocialAction {
        case share(SocialFeedTrip)
        case react(SocialFeedTrip, emoji: String)
        case reactionPicker(SocialFeedTrip)
        /// Guest tapped the bell — open the notifications inbox after a
        /// successful sign-in instead of dead-ending ("login worked, nothing
        /// happened" — the exact failure the resume pattern exists to avoid).
        case openInbox
    }
    @State private var pendingSocialAction: PendingSocialAction?
    /// Set in the prompt's onAuthenticated; consumed in its onDismiss. We
    /// resume AFTER the sheet has fully dismissed (not in onAuthenticated,
    /// which fires before dismiss) so presenting the share sheet can't collide
    /// with the sign-in sheet still animating away.
    @State private var resumeAfterAuth = false

    init(tripManager: TripManager, selectedTab: Binding<AppTab>) {
        feedVM = FeedViewModel.shared(tripManager: tripManager)
        _selectedTab = selectedTab
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack(alignment: .bottom) {
        NavigationStack(path: $authorPath) {
            VStack(spacing: 0) {
                // Custom header (Figma 140:945) — replaces the system nav bar.
                // Rendered unconditionally, once, above the paged TabView so it
                // stays mounted in both segments (same principle as the old
                // always-rendered ToolbarItems: conditional chrome forces a nav
                // rebuild and a visible hop when switching Лента ↔ Мои).
                feedHeader(c)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                    .background(c.bg)

                // Offline strip (Figma «Лента · Офлайн»): sits between the
                // title and the segment, above BOTH pages, because it's a
                // statement about the app, not about one feed.
                if network.isOffline {
                    offlineStrip(c)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Pinned outside the paged TabView so the pill row stays put while the
                // content underneath slides horizontally.
                feedModeSwitcher(c)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .background(c.bg)

                // Native page-style TabView gives us smooth horizontal slide with
                // iOS's own physics — much nicer than our cross-fade or manual drag
                // gesture. The pills above stay fixed, only the content below slides.
                TabView(selection: $feedMode) {
                    allFeedPage(c)
                        .ignoresSafeArea(edges: .bottom)
                        .tag(FeedMode.all)
                    followingFeedPage(c)
                        .ignoresSafeArea(edges: .bottom)
                        .tag(FeedMode.following)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // THE BLACK-BAND ROOT CAUSE (iOS 26, dark theme): the pager
                // host (UIKitPagingView) is laid out only down to the SAFE
                // AREA edge, and the zone below it shows the NavigationStack
                // HostingView's opaque systemBackground — pure black in dark
                // mode (in light it's white-on-cream and near-invisible,
                // which is why iOS 18/light sims never caught it). Extending
                // the pager itself under the home indicator removes the gap;
                // the pages' own bottom padding keeps content clear of the
                // tab bar.
                .ignoresSafeArea(edges: .bottom)
                // Belt-and-braces: theme bg painted behind the pager.
                .background(c.bg.ignoresSafeArea())
                // Disable the rubber-band bounce when swiping past the first or last
                // page — the underlying UIPageViewController uses a UIScrollView that
                // bounces by default, which shows the black background on edges.
                .background(PageViewBounceDisabler())
                .onChange(of: feedMode) { _, newMode in
                    feedModeIsFollowing = newMode == .following
                    if newMode == .all {
                        // `loadIfNeeded` (not `refresh`) — tab switches
                        // shouldn't cancel an in-flight fetch. Pull-to-
                        // refresh below stays explicit.
                        Task { await socialFeed.loadIfNeeded() }
                    } else if newMode == .following, auth.isSignedIn {
                        // Guests never fetch the following feed — the page
                        // shows its sign-in CTA instead.
                        Task { await followingFeed.loadIfNeeded() }
                    }
                }
                .onAppear {
                    // Restore the persisted segment once per mount (@State
                    // can't seed from @AppStorage in init).
                    if feedModeIsFollowing && feedMode == .all { feedMode = .following }
                }
            }
            // Paint the theme bg across the ENTIRE NavigationStack content,
            // safe areas included. The stack's HostingView is opaque
            // systemBackground (black in dark mode) and shows through any
            // region the layout leaves uncovered — this is the second layer
            // of the home-indicator black-band fix.
            .background(c.bg.ignoresSafeArea())
            // Single typed destination for every push out of Feed. Mixing a
            // `NavigationStack(path:)` with `.navigationDestination(isPresented:)`
            // made the isPresented-pushed Trip view disappear whenever the typed
            // path mutated (setting path=[.profile] told SwiftUI the full stack
            // was just [.profile] and the older trip push got collapsed, which
            // is why "back" jumped straight to Feed instead of TripDetail).
            .navigationDestination(for: ProfilePreviewDest.self) { dest in
                switch dest {
                case .profile(let id, let author):
                    PublicProfileView(accountId: id, preloaded: author, pushPath: $authorPath)
                case .followList(let id, let mode):
                    FollowListView(accountId: id, mode: mode, pushPath: $authorPath)
                case .trip(let id, let focus):
                    TripDetailView(
                        tripId: id,
                        viewModel: TripsViewModel(tripManager: feedVM.tripManager),
                        pushPath: $authorPath,
                        focus: focus
                    )
                case .socialTrip(let t, let focus):
                    SocialTripDetailView(
                        initialTrip: t,
                        onShare: {
                            if auth.isSignedIn { shareSocialTrip(t) }
                            else { pendingSocialAction = .share(t); signInPrompt = .share }
                        },
                        pushPath: $authorPath,
                        focus: focus
                    )
                }
            }
            // Custom header above owns the top chrome — hide the system bar.
            // Pushed destinations manage their own chrome (TripDetailView /
            // SocialTripDetailView via NavBarKiller, PublicProfileView /
            // FollowListView via CustomNavBar + their own hidden-bar flags).
            .toolbar(.hidden, for: .navigationBar)
        }
        // Per-page refreshable modifiers live inside allFeedPage / mineFeedPage so
        // pull-to-refresh fires in the correct ScrollView (TabView hosts each page
        // in its own scroll container).
        .onAppear {
            // Refresh on every appearance (tab switches, back-from-detail, etc.) so the
            // feed always reflects server state. Each refresh only fetches the first
            // page (limit=20) — extra pages load lazily via loadMoreIfNeeded when the
            // user scrolls, so the cost stays bounded even with a large feed.
            feedVM.language = lang.language
            feedVM.loadTrips()
            // Cache the private-trip flag here (not in body) — see the
            // @State declaration for the AttributeGraph rationale.
            hasAnyPrivateTrip = feedVM.tripManager.hasAnyPrivateTrip()
            // Initial load via `loadIfNeeded` — if the user previously
            // saw the feed (data is cached), this no-ops and lets any
            // earlier in-flight refresh complete. Avoids the
            // request-storm pattern on slow LAN where every view
            // appear cancelled the previous fetch.
            Task { await socialFeed.loadIfNeeded() }
            if feedMode == .following, auth.isSignedIn {
                Task { await followingFeed.loadIfNeeded() }
            }
            feedVM.retryGeocodingIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripRecordingEnded)) { _ in
            // New trip → may flip the "has any private trip" cache.
            hasAnyPrivateTrip = feedVM.tripManager.hasAnyPrivateTrip()
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // Sign-in state flipped (in either direction) — re-fetch so the
            // feed switches between personalized (followed users) and
            // trending without a manual pull. The following feed only exists
            // for signed-in users; sign-out already cleared it in AuthService.
            Task {
                await socialFeed.refresh()
                if signedIn { await followingFeed.refresh() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-entering the app from background → refresh the feed so it's
            // current on entry ("обновлять ленту, когда заходим в приложение").
            // `loadIfNeeded` is staleness-gated, so a quick app-switch won't
            // force a full re-fetch — only a stale or empty feed reloads. The
            // cold-launch empty-feed race is recovered separately in the store.
            if newPhase == .active {
                Task { await socialFeed.loadIfNeeded() }
                if feedMode == .following, auth.isSignedIn {
                    Task { await followingFeed.loadIfNeeded() }
                }
            }
        }
        // Trip filters + the «Мои» local-trips page removed per design
        // decisions (2026-08-05): filters looked off-design and
        // underdelivered; local trips live on the Я tab (История +
        // Статистика). The second segment is now «Подписки» per Figma.
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTrip)) { notif in
            if let link = notif.object as? TripDeepLink {
                authorPath = [.trip(link.tripId, focus: link.focus)]
            } else if let tripId = notif.object as? UUID {
                authorPath = [.trip(tripId)]
            }
        }
        // Privacy flipped on a trip the user owns. If it just went private, drop the
        // card from the feed immediately with a fade — waiting 2–3s for the sync push
        // to reach the server and come back through /social/feed felt laggy. Either way
        // we still trigger a delayed refresh so the server's authoritative state
        // (including any trips that got added by going public) reconciles.
        .onReceive(NotificationCenter.default.publisher(for: .tripPrivacyChanged)) { notif in
            guard auth.isSignedIn else { return }
            if let payload = notif.object as? PrivacyChangePayload, payload.isPrivate {
                withAnimation(.easeInOut(duration: 0.35)) {
                    socialFeed.removeOptimistically(tripId: payload.tripId)
                    followingFeed.removeOptimistically(tripId: payload.tripId)
                }
            }
            // Flipping a trip private↔public can change "has any private
            // trip" — keep the empty-state CTA cache in sync.
            hasAnyPrivateTrip = feedVM.tripManager.hasAnyPrivateTrip()
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await socialFeed.refresh()
                await followingFeed.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripDeleted)) { _ in
            // Trip deletion can drop the last private trip — refresh
            // the cache so the CTA doesn't keep pointing at nothing.
            hasAnyPrivateTrip = feedVM.tripManager.hasAnyPrivateTrip()
        }
        .sheet(isPresented: $showNotifications) {
            // Self-contained sheet with its own NavigationStack — same
            // presentation the Profile tab uses for the inbox.
            NotificationsInboxView()
                .environmentObject(lang)
                .environment(\.navBarInSheet, true)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        // Reset the resume flag whenever a NEW sign-in prompt presents. The
        // login Task outlives the sheet (dismissal doesn't cancel it), so a
        // dismiss-during-login followed by a late success sets
        // `resumeAfterAuth = true` AFTER onDismiss already consumed it —
        // without this reset that stale `true` survives a later sign-out and
        // replays the next captured action for a guest.
        .onChange(of: signInPrompt) { _, newValue in
            if newValue != nil { resumeAfterAuth = false }
        }
        .sheet(item: $signInPrompt, onDismiss: {
            // `auth.isSignedIn` guard: `resumeAfterAuth` alone isn't proof —
            // see the onChange above for how it can go stale.
            if resumeAfterAuth && auth.isSignedIn {
                resumeAfterAuth = false
                // Defer until the sign-in sheet has finished dismissing. The
                // resumed action can itself present a sheet (reaction picker,
                // share) — doing that synchronously from onDismiss races the
                // dismissal animation and SwiftUI silently drops the second
                // presentation, so the user authenticates and then nothing
                // happens. The short sleep clears the in-flight transition.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    resumePendingSocialAction()
                }
            } else {
                resumeAfterAuth = false
                pendingSocialAction = nil
            }
        }) { action in
            SignInPromptSheet(action: action, onAuthenticated: { resumeAfterAuth = true })
                .environmentObject(lang)
                .environmentObject(auth)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        // Canon uses centred ALERTS for both irreversible-ish actions, with a
        // «Нет» / «Да, …» pair rather than a generic Отмена/Удалить — the
        // second word tells you what «Да» will do.
        .alert(
            AppStrings.hideFromFeedAlertTitle(lang.language),
            isPresented: Binding(
                get: { tripPendingPrivate != nil },
                set: { if !$0 { tripPendingPrivate = nil } }
            )
        ) {
            Button(AppStrings.no(lang.language), role: .cancel) { tripPendingPrivate = nil }
            Button(AppStrings.hideFromFeedAlertConfirm(lang.language), role: .destructive) {
                if let trip = tripPendingPrivate { makeTripPrivate(trip) }
                tripPendingPrivate = nil
            }
        } message: {
            Text(AppStrings.hideFromFeedAlertBody(lang.language))
        }
        .alert(
            AppStrings.deleteTripAlertTitle(lang.language),
            isPresented: Binding(
                get: { tripPendingDelete != nil },
                set: { if !$0 { tripPendingDelete = nil } }
            )
        ) {
            Button(AppStrings.no(lang.language), role: .cancel) { tripPendingDelete = nil }
            Button(AppStrings.deleteTripAlertConfirm(lang.language), role: .destructive) {
                if let trip = tripPendingDelete { deleteOwnTrip(trip) }
                tripPendingDelete = nil
            }
        } message: {
            Text(AppStrings.deleteTripAlertBody(lang.language))
        }
        .sheet(isPresented: Binding(
            get: { tripPendingReport != nil },
            set: { if !$0 { tripPendingReport = nil } }
        )) {
            if let trip = tripPendingReport {
                ReportSheet(target: .trip(trip.id))
                    .environmentObject(lang)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .sheet(item: $linkShareData) { share in
            SharedTripLinkSheet(trip: share.trip, shareUrl: share.url)
                .environmentObject(lang)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(item: $reactorsPeek) { peek in
            ReactionsListSheet(
                tripId: peek.trip.id,
                initialEmoji: peek.emoji,
                onSelectUser: { author in
                    reactorsPeek = nil
                    // Push in the feed's own stack once the sheet is gone —
                    // presenting and pushing in the same runloop drops one.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 260_000_000)
                        authorPath.cappedAppend(.profile(author.id, author))
                    }
                }
            )
            .environmentObject(lang)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverView()
                .presentationDetents([.large])
                .environment(\.navBarInSheet, true)
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: Binding(
            get: { shareSheetData != nil },
            set: { if !$0 { shareSheetData = nil } }
        )) {
            if let share = shareSheetData {
                // The sheet sizes its own detent from its measured content.
                StoryShareSheet(data: share.data, shareUrl: share.url)
                    .presentationDragIndicator(.visible)
                    .environmentObject(lang)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showGarage) {
            GarageView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }

        // Undo toast sits above the floating tab bar (canon).
        if let toast = undoToast {
            UndoToastView(
                toast: toast,
                undoLabel: AppStrings.undoAction(lang.language),
                onClose: { undoToast = nil }
            )
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(200)
        }

        // Recording banner overlay
        if mapVM.isRecording {
            RecordingBanner(
                distance: mapVM.distance,
                duration: mapVM.duration,
                onTap: { selectedTab = .record }
            )
            .padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: mapVM.isRecording)
        }

        // Reaction picker (iMessage-style) — appears on long-press of a feed card
        if let picked = reactionPickerTrip {
            ReactionPickerOverlay(
                currentReaction: picked.myReaction,
                onPick: { emoji in
                    Task { await owningStore(for: picked.id).toggleReaction(for: picked.id, emoji: emoji) }
                    reactionPickerTrip = nil
                },
                onDismiss: { reactionPickerTrip = nil }
            )
            .transition(.opacity)
            .zIndex(100)
        }
        } // ZStack
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: undoToast?.id)
    }

    // MARK: - Header (Figma 140:945)

    private func feedHeader(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            // Title doubles as scroll-to-top — preserves the old principal
            // toolbar button behavior.
            Button {
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
            } label: {
                Text(AppStrings.feed(lang.language))
                    .font(.inter(28, weight: .heavy))
                    .tracking(-0.56)
                    .foregroundStyle(c.text)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed_title")

            Spacer()

            headerCircleButton(icon: "magnifyingglass", c: c) {
                // Discover (search + suggested) works for guests too —
                // the social API endpoints are public-readable. Only
                // tapping Follow inside opens the sign-in prompt.
                showDiscover = true
            }
            .accessibilityIdentifier("feed_search")

            if auth.isSignedIn {
                headerCircleButton(icon: "bell", c: c) {
                    showNotifications = true
                }
                .accessibilityIdentifier("feed_bell")
            } else {
                // Canon «Лента · Гость»: a guest gets one clear call to
                // action in the corner instead of a bell that can only bounce
                // them into a sign-in prompt. Search stays — Discover is
                // genuinely usable signed-out, so removing it would cost the
                // guest the one thing they CAN do here.
                Button {
                    Haptics.tap()
                    signInPrompt = .generic
                } label: {
                    Text(AppStrings.signInShort(lang.language))
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feed_sign_in")
            }
        }
    }

    private func headerCircleButton(
        icon: String, c: AppTheme.Colors, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
                .frame(width: 34, height: 34)
                .background(c.card, in: Circle())
                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed Mode Switcher

    private func feedModeSwitcher(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 3) {
            modePill(.all, label: AppStrings.all(lang.language), c: c)
                .accessibilityIdentifier("feed_segment_all")
            modePill(.following, label: AppStrings.feedSegmentFollowing(lang.language), c: c)
                .accessibilityIdentifier("feed_segment_following")
        }
        .padding(3)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 11))
    }

    private func modePill(_ mode: FeedMode, label: String, c: AppTheme.Colors) -> some View {
        let active = feedMode == mode
        return Button {
            Haptics.selection()
            let wasActive = active
            withAnimation(.easeInOut(duration: 0.2)) { feedMode = mode }
            // Switching tabs: scroll to top so the content change is
            // obvious. Tapping the ALREADY-ACTIVE pill: Strava-style
            // "scroll to top + refresh" — gives the user a way to
            // explicitly request fresh data without pulling. The
            // .onChange(of: feedMode) below handles the load for the
            // tab-switch case (and no-ops here since value didn't
            // change), so we only fire the refresh on active-tap.
            if !wasActive {
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
            } else {
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
                if mode == .all {
                    Task { await socialFeed.refresh() }
                } else if auth.isSignedIn {
                    Task { await followingFeed.refresh() }
                }
            }
        } label: {
            Text(label)
                .font(.inter(13, weight: .bold))
                .foregroundStyle(active ? c.text : c.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    active
                    ? c.card
                    : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .shadow(color: active ? Color.black.opacity(0.03) : Color.clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        // The active segment is only signalled by fill/color — expose it to
        // VoiceOver too, or both pills read as identical plain buttons.
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Feed Pages (paged TabView content)

    @ViewBuilder
    private func allFeedPage(_ c: AppTheme.Colors) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Figma 140:933 rhythm: switcher(38) → 10 → first card. The
                // switcher's own bottom padding carries the 10, so the page
                // content adds ZERO on top — the old zero-height scroll
                // anchor + top paddings stacked ~18pt of extra gap that made
                // «Лента»→switcher and switcher→cards visibly uneven.
                LazyVStack(spacing: 12) {
                    connectivityBanner(c)
                    socialFeedContent(c, store: socialFeed, isFollowing: false)
                }
                .id("feedTopAll")
                .padding(.horizontal, 14)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .refreshable { await socialFeed.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .feedScrollToTop)) { _ in
                if !authorPath.isEmpty { authorPath.removeAll() }
                else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("feedTopAll", anchor: .top)
                    }
                }
            }
        }
    }

    /// «Подписки» (Figma 141:1081): followed users + own public trips.
    /// Guests never fetch — the page IS the sign-in pitch.
    @ViewBuilder
    private func followingFeedPage(_ c: AppTheme.Colors) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Same zero-top rhythm as the All page (Figma 140:933).
                LazyVStack(spacing: 12) {
                    connectivityBanner(c)
                    if auth.isSignedIn {
                        socialFeedContent(c, store: followingFeed, isFollowing: true)
                    } else {
                        // One CTA, not two: the banner repeated what the
                        // header button and this empty state already say.
                        followingGuestState(c)
                    }
                }
                .id("feedTopFollowing")
                .padding(.horizontal, 14)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .refreshable {
                if auth.isSignedIn { await followingFeed.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .feedScrollToTop)) { _ in
                if !authorPath.isEmpty { authorPath.removeAll() }
                else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("feedTopFollowing", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Social Feed Content

    @ViewBuilder
    private func socialFeedContent(
        _ c: AppTheme.Colors, store: SocialFeedStore, isFollowing: Bool
    ) -> some View {
        let isRu = lang.language == .ru

        // Suggested-users carousel moved out of the feed into DiscoverView
        // (search tab) — keeps the feed focused on activity and avoids
        // empty-state awkwardness when there are no recommendations.

        if store.isLoading, store.trips.isEmpty {
            PixelCarLoader(
                label: isRu ? "Загружаем ленту…" : "Loading feed…"
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
        } else if store.lastError != nil, store.trips.isEmpty {
            socialErrorState(c, isRu: isRu, store: store)
        } else if store.trips.isEmpty {
            if isFollowing {
                followingEmptyState(c)
            } else {
                socialEmptyState(c, isRu: isRu)
            }
        } else {
            ForEach(store.trips) { trip in
                let isOwn = isOwnSocialTrip(trip)
                SocialFeedCardView(
                    trip: trip,
                    isOwn: isOwn,
                    onTapCard: {
                        // Own trips open the regular TripDetailView (vehicle-based header,
                        // edit pencil, privacy toggle) — same experience as from "Мои".
                        if isOwn {
                            authorPath.cappedAppend(.trip(trip.id))
                        } else {
                            authorPath.cappedAppend(.socialTrip(trip))
                        }
                    },
                    onTapComments: {
                        // Same routing as a card tap, but the detail screen
                        // lands on the discussion — tapping a comment count
                        // and getting the poster made you scroll for it.
                        if isOwn {
                            authorPath.cappedAppend(.trip(trip.id, focus: .comments))
                        } else {
                            authorPath.cappedAppend(.socialTrip(trip, focus: .comments))
                        }
                    },
                    onTapAuthor: { authorPath.cappedAppend(.profile(trip.author.id, trip.author)) },
                    onPeekReactors: { emoji in
                        reactorsPeek = ReactorsPeek(trip: trip, emoji: emoji)
                    },
                    onEdit: isOwn ? {
                        // Editing lives on the trip's own detail screen —
                        // one editor, not a second one inlined in the feed.
                        authorPath.cappedAppend(.trip(trip.id))
                    } : nil,
                    onMakePrivate: isOwn ? { tripPendingPrivate = trip } : nil,
                    onDelete: isOwn ? { tripPendingDelete = trip } : nil,
                    onReport: isOwn ? nil : {
                        // Guests can't report — the endpoint needs an
                        // account, so send them through sign-in first
                        // instead of opening a form that will 401.
                        if auth.isSignedIn { tripPendingReport = trip }
                        else { signInPrompt = .generic }
                    },
                    onLongPress: {
                        // Owners can't react to their own trip (Strava rule)
                        // — long-press becomes a no-op there instead of
                        // surfacing a useless emoji palette.
                        guard !isOwn else { return }
                        if auth.isSignedIn { reactionPickerTrip = trip }
                        else { pendingSocialAction = .reactionPicker(trip); signInPrompt = .react }
                    },
                    onReact: { emoji in
                        guard !isOwn else { return }
                        if auth.isSignedIn {
                            Task { await store.toggleReaction(for: trip.id, emoji: emoji) }
                        } else {
                            pendingSocialAction = .react(trip, emoji: emoji)
                            signInPrompt = .react
                        }
                    },
                    onShare: {
                        if auth.isSignedIn { shareSocialTrip(trip) }
                        else { pendingSocialAction = .share(trip); signInPrompt = .share }
                    }
                )
                .onAppear {
                    Task { await store.loadMoreIfNeeded(currentItem: trip) }
                }
                // Smooth fade + collapse when a card is removed (e.g. after the user
                // flips their own trip back to private).
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.92)).combined(with: .move(edge: .leading))
                ))
            }
            // Deliberately NO implicit `.animation(value: trips.map(\.id))` here.
            // It animated the WHOLE list diff on every trips change — including
            // infinite-scroll APPENDS — so loading the next page mid-swipe made
            // ~20 cards animate in while the scroll was moving → chaotic lurching.
            // Card REMOVAL still animates: the privacy path wraps
            // `removeOptimistically` in `withAnimation` (see .tripPrivacyChanged),
            // which drives the card's `.transition` without animating appends.

            if store.isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
            }
        }
    }

    /// Signed-in following feed with zero trips — the state Figma draws
    /// with the «find people» CTA: nobody followed yet (or the followed
    /// users have no public trips).
    private func followingEmptyState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            FeedIdleRing()
                .padding(.top, 36)
            Text(AppStrings.followingEmptyTitle(lang.language))
                .font(.inter(19, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Text(AppStrings.followingEmptyBody(lang.language))
                .font(.inter(14))
                .lineSpacing(6)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 8)
            Button {
                Haptics.tap()
                showDiscover = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                    Text(AppStrings.findPeople(lang.language))
                        .font(.inter(14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("following_empty_find_people")
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Guest visiting «Подписки» — no fetch happens; the page pitches
    /// signing in (the banner above provides the actual CTA).
    private func followingGuestState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            FeedIdleRing()
                .padding(.top, 36)
            Text(AppStrings.followingGuestTitle(lang.language))
                .font(.inter(19, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            Text(AppStrings.followingGuestBody(lang.language))
                .font(.inter(14))
                .lineSpacing(6)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 8)

            Button {
                Haptics.tap()
                signInPrompt = .generic
            } label: {
                Text(AppStrings.signInShort(lang.language))
                    .font(.inter(14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Surfaced when the SyncQueue has parked one or more ops in `failedQueue`.
    /// The cause can be either a network outage or a server-side error
    /// (UNKNOWN_SERVER_ERROR, 5xx, etc) — they reach the same failed bucket.
    /// We split the copy: if the network monitor says we're offline → network
    /// language; otherwise → generic "sync issue" language. Saying "server
    /// unreachable" while connectivity is fine and the server is just
    /// returning 200-envelope errors is misleading. Auto-dismisses when the
    /// queue drains, so no manual close button.
    @ViewBuilder
    private func connectivityBanner(_ c: AppTheme.Colors) -> some View {
        if !syncQueue.failed.isEmpty {
            let isNetworkDown = CacheManager.shared.isOffline
            HStack(spacing: 12) {
                Image(systemName: isNetworkDown ? "wifi.exclamationmark" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bannerTitle(isNetworkDown: isNetworkDown))
                        .font(.inter(14, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(bannerSubtitle(isNetworkDown: isNetworkDown))
                        .font(.inter(12))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
    }

    private func bannerTitle(isNetworkDown: Bool) -> String {
        if isNetworkDown {
            return lang.language == .ru ? "Нет связи с сервером" : "Server unreachable"
        }
        return lang.language == .ru ? "Не всё синхронизировано" : "Sync incomplete"
    }

    private func bannerSubtitle(isNetworkDown: Bool) -> String {
        if isNetworkDown {
            return lang.language == .ru
                ? "Попробуйте сменить сеть или подождите — мы повторим автоматически."
                : "Try a different network or wait — we'll retry automatically."
        }
        return lang.language == .ru
            ? "Несколько операций не загрузились на сервер. Мы повторим автоматически — также можно нажать «Повторить» в настройках синхронизации."
            : "A few items didn't upload. We'll retry automatically — or tap Retry in sync settings."
    }

    /// Compact "Sign in to follow & react" pill at the top of the public feed
    /// for guests. Replaces the old full-screen empty state — the feed is now
    /// genuinely populated (trending public trips), so we just want a low-key
    /// reminder that signing in unlocks personal interactions.
    private func guestSignInBanner(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            signInPrompt = .generic
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.guestFeedBanner(lang.language))
                        .font(.inter(14, weight: .semibold))
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("guest_signin_banner")
    }

    /// «Нет сети · поездки сохраняются локально» (Figma «Лента · Офлайн»).
    private func offlineStrip(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return HStack(spacing: 8) {
            Image(systemName: "airplane")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            Text(isRu ? "Нет сети · поездки сохраняются локально"
                      : "Offline · trips are saved on your phone")
                .font(.inter(12, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(AppTheme.accentBg)
        )
        .overlay(Capsule().strokeBorder(AppTheme.accent.opacity(0.35), lineWidth: 1))
        .accessibilityIdentifier("feed_offline_strip")
    }

    /// Canon «Лента · Ошибка сети»: the same ring the empty state uses, in a
    /// neutral tint, then title / explanation / retry. It used to be a bare
    /// red glyph, which read as a crash rather than as "no signal".
    private func socialErrorState(_ c: AppTheme.Colors, isRu: Bool, store: SocialFeedStore) -> some View {
        VStack(spacing: 14) {
            FeedStateRing(systemImage: "wifi.slash")
                .padding(.top, 40)

            Text(isRu ? "Не удалось загрузить ленту" : "Couldn't load feed")
                .font(.inter(19, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(isRu
                 ? "Проверьте подключение к интернету и попробуйте ещё раз."
                 : "Check your internet connection and try again.")
                .font(.inter(14))
                .lineSpacing(6)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 280)

            Button {
                Haptics.tap()
                Task { await store.refresh() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text(isRu ? "Попробовать снова" : "Try again")
                        .font(.inter(14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed_error_retry")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    /// Empty social-feed state (Figma 141:1103). Two jobs:
    ///   1. Friendly hero so the page never reads as "broken / no data",
    ///      with «Найти людей» routing into Discover (suggestions moved
    ///      there — no inline carousel; the empty state stays calm).
    ///   2. First-publish nudge for signed-in users who have private
    ///      trips locally. Without this, the feed only ever fills via
    ///      "follow someone" — but a user who already has trips can
    ///      seed the feed themselves by publishing one.
    @ViewBuilder
    private func socialEmptyState(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        // `hasAnyPrivateTrip` is cached in `@State` and refreshed on
        // `.task` + on `tripRecordingEnded`. Reading it here is a
        // plain @State read — no CoreData fetch during body, so no
        // AttributeGraph cycle.
        let hasPrivateTrips = hasAnyPrivateTrip
        let signedIn = auth.isSignedIn
        VStack(spacing: 14) {
            FeedIdleRing()
                .padding(.top, 40)

            Text(AppStrings.feedEmptyTitle(lang.language))
                .font(.inter(19, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(AppStrings.feedEmptyBody(lang.language))
                .font(.inter(14))
                .lineSpacing(6)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 280)

            Button {
                Haptics.tap()
                showDiscover = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                    Text(AppStrings.findPeople(lang.language))
                        .font(.inter(14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("feed_empty_find_people")

            // Signed-in user with private trips: nudge them to publish.
            // We don't deep-link to a specific trip — sending them to
            // the Я tab (История) lets them pick which one to share.
            // Avoids a "we picked your most recent" surprise. Kept as a
            // quiet secondary text button (retains the cold-start seeding
            // fix — deliberate deviation from the Figma frame).
            if signedIn && hasPrivateTrips {
                Button {
                    Haptics.tap()
                    selectedTab = .profile
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isRu
                             ? "Опубликовать свою поездку"
                             : "Publish one of your trips")
                            .font(.inter(14, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    /// Reactions must go through the store that owns the trip's card so its
    /// UI updates optimistically. Toggling on both stores would double-POST
    /// (toggle semantics → the second call reverts the first). Prefer the
    /// active page; fall back to whichever store has the trip.
    private func owningStore(for tripId: UUID) -> SocialFeedStore {
        let active = feedMode == .following ? followingFeed : socialFeed
        if active.trips.contains(where: { $0.id == tripId }) { return active }
        let other = feedMode == .following ? socialFeed : followingFeed
        if other.trips.contains(where: { $0.id == tripId }) { return other }
        return active
    }

    /// True when a feed card refers to the signed-in user's own trip. Used to route
    /// taps to the regular TripDetailView (with edit pencil + privacy toggle) instead
    /// of the read-only SocialTripDetailView.
    private func isOwnSocialTrip(_ trip: SocialFeedTrip) -> Bool {
        TokenStore.shared.accountId == trip.author.id
    }

    /// Runs the social action a guest tapped before signing in. Consumes the
    /// captured action (one-shot) so it can't re-fire on a later login. The
    /// share path is async (network) so its sheet presents after the sign-in
    /// sheet has already dismissed — no "present while presenting" collision.
    private func resumePendingSocialAction() {
        guard let pending = pendingSocialAction else { return }
        pendingSocialAction = nil
        // Never replay a captured action for a guest — a stale resume flag
        // (see the sheet's onChange) or a sign-out between capture and resume
        // would otherwise run a signed-in-only action that 401s.
        guard auth.isSignedIn else { return }
        switch pending {
        case .share(let t):
            shareSocialTrip(t)
        case .react(let t, let emoji):
            Task { await owningStore(for: t.id).toggleReaction(for: t.id, emoji: emoji) }
        case .reactionPicker(let t):
            reactionPickerTrip = t
        case .openInbox:
            showNotifications = true
        }
    }

    /// Flip an own trip back to private straight from the card. Mirrors the
    /// detail screen's privacy chip: local write, then the same notification
    /// the rest of the app listens to (feed removal, store invalidation).
    /// Card leaves the feed immediately; the actual privacy flip waits for
    /// the undo window to close (canon toast rules).
    private func makeTripPrivate(_ trip: SocialFeedTrip) {
        Haptics.action()
        withAnimation(.easeInOut(duration: 0.3)) {
            socialFeed.removeOptimistically(tripId: trip.id)
            followingFeed.removeOptimistically(tripId: trip.id)
        }
        undoToast = UndoToast(
            message: AppStrings.tripHiddenToast(lang.language),
            onCommit: {
                feedVM.tripManager.updatePrivacy(for: trip.id, isPrivate: true)
                NotificationCenter.default.post(
                    name: .tripPrivacyChanged,
                    object: PrivacyChangePayload(tripId: trip.id, isPrivate: true)
                )
            },
            onUndo: { Task { await socialFeed.refresh() } }
        )
    }

    private func deleteOwnTrip(_ trip: SocialFeedTrip) {
        Haptics.action()
        withAnimation(.easeInOut(duration: 0.3)) {
            socialFeed.removeOptimistically(tripId: trip.id)
            followingFeed.removeOptimistically(tripId: trip.id)
        }
        undoToast = UndoToast(
            message: AppStrings.tripDeletedToast(lang.language),
            onCommit: {
                feedVM.tripManager.deleteTrip(id: trip.id)
                NotificationCenter.default.post(name: .tripDeleted, object: trip.id)
            },
            // Nothing was destroyed yet — a refresh brings the card back.
            onUndo: { Task { await socialFeed.refresh() } }
        )
    }

    /// Own trip → the poster studio (your card, your numbers, your formats).
    /// Someone else's → the compact link sheet (canon): passing a trip on is
    /// about the link, not about exporting a card that isn't yours.
    private func shareSocialTrip(_ trip: SocialFeedTrip) {
        let isOwn = isOwnSocialTrip(trip)
        Task {
            var url: String?
            do {
                let req = SocialShareRequest(tripId: trip.id, expiresInDays: nil)
                let res: SocialShareResponse = try await APIClient.shared.post(
                    APIEndpoint.socialShare, body: req)
                url = res.shareUrl
            } catch {
                // No link (offline / server hiccup): the studio still works
                // without one, the compact sheet degrades to share-less copy.
            }
            let link = url
            await MainActor.run {
                if isOwn {
                    shareSheetData = (StoryShareData.from(trip, lang: lang.language), link)
                } else {
                    linkShareData = LinkShare(trip: trip, url: link)
                }
            }
        }
    }

}

// MARK: - Feed idle ring (Figma 141:1103)

/// Empty-state hero: quiet outer ring + accent inner ring around the
/// pixel-art car. Sibling of `SignInIdleRing` (SignInPromptSheet) which
/// uses a translucent accent disc — deliberately separate, not extracted
/// into a shared component.
/// Neutral sibling of `FeedIdleRing` for non-empty states (network error):
/// same double ring, no accent, an SF glyph instead of the car.
private struct FeedStateRing: View {
    let systemImage: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack {
            Circle()
                .stroke(c.border, lineWidth: 2)
                .frame(width: 100, height: 100)
            ZStack {
                Circle().stroke(c.borderBright, lineWidth: 2)
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(c.textTertiary)
            }
            .frame(width: 82, height: 82)
        }
        .frame(width: 100, height: 100)
    }
}

private struct FeedIdleRing: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack {
            Circle()
                .stroke(c.border, lineWidth: 2)
                .frame(width: 100, height: 100)
            ZStack {
                Circle()
                    .stroke(AppTheme.accent, lineWidth: 2)
                Image("PixelCar")
                    .resizable()
                    .interpolation(.none)
                    // The sprite asset is non-square — without fit it
                    // squeezes into the 46×46 box.
                    .scaledToFit()
                    .frame(width: 46, height: 46)
            }
            .frame(width: 82, height: 82)
        }
        .frame(width: 100, height: 100)
    }
}

// MARK: - Page TabView bounce disable

/// Walks up the UIKit hierarchy to find the UIScrollView hosting the paged TabView
/// and disables its bounce so swiping past the first/last page doesn't reveal the
/// black background behind the TabView.
private struct PageViewBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> PageBounceFinderView { PageBounceFinderView() }
    func updateUIView(_ uiView: PageBounceFinderView, context: Context) {}
}

private final class PageBounceFinderView: UIView {
    private static let pagerLog = Logger(subsystem: "com.triptrack", category: "pager")

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.disableBounce() }
    }

    private func disableBounce() {
        var candidate: UIView? = self
        while let v = candidate {
            if let scroll = v as? UIScrollView {
                neutralize(scroll)
                return
            }
            if let found = findScroll(in: v) {
                neutralize(found)
                return
            }
            candidate = v.superview
        }
    }

    /// Kills the UIPageViewController artifacts at the source:
    ///  * edge bounce;
    ///  * the opaque black backdrops — iOS 26 paints them on SEVERAL views
    ///    of the pager subtree, not just the queuing scroll view, so clear
    ///    the whole subtree plus the ancestor chain;
    ///  * the bottom safe-area inset the iOS 26 pager applies to its pages
    ///    (contentInsetAdjustment) — it clipped page content at the
    ///    safe-area line, leaving a black band under the home indicator.
    private func neutralize(_ scroll: UIScrollView) {
        scroll.bounces = false
        scroll.contentInsetAdjustmentBehavior = .never
        clearBackgrounds(in: scroll)
        // Ancestors up to (and including) the pager's hosting container.
        var up: UIView? = scroll.superview
        var hops = 0
        while let v = up, hops < 4 {
            logView(v, label: "ancestor\(hops)")
            v.backgroundColor = .clear
            up = v.superview
            hops += 1
        }
    }

    /// Clears backgroundColor on the scroll view and its container subviews
    /// (page wrappers), logging what was there for diagnostics.
    private func clearBackgrounds(in root: UIView, depth: Int = 0) {
        logView(root, label: "subtree\(depth)")
        root.backgroundColor = .clear
        guard depth < 3 else { return }
        for sub in root.subviews {
            clearBackgrounds(in: sub, depth: depth + 1)
        }
    }

    private func logView(_ v: UIView, label: String) {
        let bg = v.backgroundColor.map { String(describing: $0) } ?? "nil"
        Self.pagerLog.notice("[pager.\(label, privacy: .public)] \(String(describing: type(of: v)), privacy: .public) bg=\(bg, privacy: .public) frame=\(String(describing: v.frame), privacy: .public) safeInsets=\(String(describing: v.safeAreaInsets), privacy: .public)")
    }

    private func findScroll(in view: UIView) -> UIScrollView? {
        for sub in view.subviews {
            if let scroll = sub as? UIScrollView { return scroll }
            if let nested = findScroll(in: sub) { return nested }
        }
        return nil
    }
}
