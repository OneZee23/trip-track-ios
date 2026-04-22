import SwiftUI

enum FeedMode: Hashable { case all, mine }

struct FeedView: View {
    @StateObject private var feedVM: FeedViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var socialFeed = SocialFeedStore.shared
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Binding var selectedTab: Int
    @State private var selectedTripId: UUID?
    @State private var didLoad = false
    @State private var showStats = false
    @State private var showBadges = false
    @State private var showProfile = false
    @State private var showGarage = false
    @State private var tripToDelete: Trip?
    @State private var collapsedSections: Set<String> = []
    @State private var feedMode: FeedMode = .all
    @State private var selectedAuthor: SocialAuthor?
    @State private var selectedSocialTrip: SocialFeedTrip?
    @State private var reactionPickerTrip: SocialFeedTrip?
    @State private var showDiscover = false
    @State private var shareSheetData: (data: StoryShareData, url: String)?

    init(tripManager: TripManager, selectedTab: Binding<Int>) {
        _feedVM = StateObject(wrappedValue: FeedViewModel(tripManager: tripManager))
        _selectedTab = selectedTab
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack(alignment: .bottom) {
        NavigationStack {
            VStack(spacing: 0) {
                // Pinned outside the paged TabView so the pill row stays put while the
                // content underneath slides horizontally.
                feedModeSwitcher(c)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .background(c.bg)

                // Native page-style TabView gives us smooth horizontal slide with
                // iOS's own physics — much nicer than our cross-fade or manual drag
                // gesture. The pills above stay fixed, only the content below slides.
                TabView(selection: $feedMode) {
                    allFeedPage(c)
                        .tag(FeedMode.all)
                    mineFeedPage(c)
                        .tag(FeedMode.mine)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Disable the rubber-band bounce when swiping past the first or last
                // page — the underlying UIPageViewController uses a UIScrollView that
                // bounces by default, which shows the black background on edges.
                .background(PageViewBounceDisabler())
                .onChange(of: feedMode) { _, newMode in
                    if newMode == .all, auth.isSignedIn {
                        Task { await socialFeed.refresh() }
                    } else if newMode == .mine {
                        feedVM.language = lang.language
                        feedVM.loadTrips()
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedTripId != nil },
                set: { if !$0 { selectedTripId = nil } }
            )) {
                if let id = selectedTripId {
                    TripDetailView(tripId: id, viewModel: TripsViewModel(tripManager: feedVM.tripManager))
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedAuthor != nil },
                set: { if !$0 { selectedAuthor = nil } }
            )) {
                if let author = selectedAuthor {
                    PublicProfileView(accountId: author.id, preloaded: author)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedSocialTrip != nil },
                set: { if !$0 { selectedSocialTrip = nil } }
            )) {
                if let t = selectedSocialTrip {
                    SocialTripDetailView(
                        trip: t,
                        onReact: { emoji in
                            Task { await socialFeed.toggleReaction(for: t.id, emoji: emoji) }
                            // Keep the current view in sync with optimistic update
                            if let updated = socialFeed.trips.first(where: { $0.id == t.id }) {
                                selectedSocialTrip = updated
                            }
                        },
                        onShare: { shareSocialTrip(t) }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image("PixelCar")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            VStack(spacing: 1) {
                                Text("ROAD  TRIP")
                                    .font(.custom("PressStart2P-Regular", size: 10))
                                    .foregroundStyle(AppTheme.accent)
                                Text("TRACKER")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(c.textTertiary)
                                    .tracking(2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        Text(settings.avatarEmoji)
                            .font(.system(size: 22))
                            .frame(width: 38, height: 38)
                            .background(c.cardAlt, in: Circle())
                    }
                }
                // Keep the trailing slot rendered in both tabs even when the user
                // is signed out — conditionally toggling ToolbarItem presence forces
                // SwiftUI to rebuild the nav bar and causes a visible hop/strip when
                // switching Лента ↔ Мои.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if auth.isSignedIn { showDiscover = true }
                        else { showProfile = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .foregroundStyle(c.text)
                            .background(c.cardAlt, in: Circle())
                    }
                }
            }
            // Pin the nav bar's background so it stays painted regardless of scroll
            // position or tab transitions. Without `.visible`, SwiftUI defaults to
            // "automatic" which fades the background in/out based on scroll — the
            // re-fade on tab switch is the subtle "drop" users see.
            .toolbarBackground(c.bg.opacity(0.95), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .toast(item: $feedVM.toastItem)
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
            if auth.isSignedIn {
                Task { await socialFeed.refresh() }
            }
            feedVM.retryGeocodingIfNeeded()
        }
        .onChange(of: auth.isSignedIn) { _, newValue in
            // User just signed in — load combined feed
            if newValue, socialFeed.trips.isEmpty {
                Task { await socialFeed.refresh() }
            }
        }
        .sheet(isPresented: $feedVM.showFilters) {
            FilterSheetView(
                filters: $feedVM.filters,
                regions: feedVM.uniqueRegions,
                onApply: {
                    feedVM.applyFilters()
                    feedVM.showFilters = false
                },
                onResetSecondary: {
                    feedVM.resetSecondaryFilters()
                    feedVM.showFilters = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStats) {
            StatsView(tripManager: feedVM.tripManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTrip)) { notif in
            if let tripId = notif.object as? UUID {
                selectedTripId = tripId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToFeedWithRegionFilter)) { notif in
            if let region = notif.object as? String {
                feedVM.setRegionFilter(region)
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
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await socialFeed.refresh()
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: Binding(
            get: { shareSheetData != nil },
            set: { if !$0 { shareSheetData = nil } }
        )) {
            if let share = shareSheetData {
                StoryShareSheet(data: share.data, shareUrl: share.url)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(lang)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showGarage) {
            GarageView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            AppStrings.deleteTrip(lang.language),
            isPresented: Binding(
                get: { tripToDelete != nil },
                set: { if !$0 { tripToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(lang.language), role: .destructive) {
                if let trip = tripToDelete {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        feedVM.softDeleteTrip(trip)
                    }
                }
                tripToDelete = nil
            }
            Button(AppStrings.cancel(lang.language), role: .cancel) {
                tripToDelete = nil
            }
        }

        // Recording banner overlay
        if mapVM.isRecording {
            RecordingBanner(
                distance: mapVM.distance,
                duration: mapVM.duration,
                onTap: { selectedTab = 1 }
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
                    Task { await socialFeed.toggleReaction(for: picked.id, emoji: emoji) }
                    reactionPickerTrip = nil
                },
                onDismiss: { reactionPickerTrip = nil }
            )
            .transition(.opacity)
            .zIndex(100)
        }
        } // ZStack
    }

    // MARK: - Feed Mode Switcher

    private func feedModeSwitcher(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return HStack(spacing: 3) {
            modePill(.all, label: isRu ? "Лента" : "Feed", c: c)
            modePill(.mine, label: isRu ? "Мои" : "Mine", c: c)
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
            // When switching tabs, scroll back to top so the content change is obvious —
            // otherwise the ScrollView preserves offset and can leave the user staring at
            // the bottom of the previous tab's content.
            if !wasActive {
                NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
            }
            if mode == .all, auth.isSignedIn {
                Task { await socialFeed.refresh() }
            } else if mode == .mine {
                feedVM.language = lang.language
                feedVM.loadTrips()
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? c.text : c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    active
                    ? c.card
                    : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .shadow(color: active ? Color.black.opacity(0.04) : Color.clear, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feed Pages (paged TabView content)

    @ViewBuilder
    private func allFeedPage(_ c: AppTheme.Colors) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    Color.clear.frame(height: 0).id("feedTopAll")
                    if auth.isSignedIn {
                        socialFeedContent(c).padding(.top, 6)
                    } else {
                        guestFriendsState(c).padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .refreshable {
                if auth.isSignedIn { await socialFeed.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .feedScrollToTop)) { _ in
                if selectedTripId != nil { selectedTripId = nil }
                else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("feedTopAll", anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mineFeedPage(_ c: AppTheme.Colors) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    Color.clear.frame(height: 0).id("feedTopMine")
                    ContributionCalendarView(
                        dateFrom: Binding(
                            get: { feedVM.filters.dateFrom },
                            set: { newDate in
                                feedVM.setDateRange(from: newDate, to: feedVM.filters.dateTo)
                            }
                        ),
                        dateTo: Binding(
                            get: { feedVM.filters.dateTo },
                            set: { newDate in
                                feedVM.setDateRange(from: feedVM.filters.dateFrom, to: newDate)
                            }
                        ),
                        language: lang.language,
                        maxKmDay: feedVM.maxKmDay,
                        kmByDay: { feedVM.kmByDay(for: $0) }
                    )

                    quickStats(c)

                    filterBar(c)
                        .padding(.top, 2)

                    tripSections(c)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .refreshable {
                feedVM.language = lang.language
                feedVM.loadTrips()
            }
            .onReceive(NotificationCenter.default.publisher(for: .feedScrollToTop)) { _ in
                if selectedTripId != nil { selectedTripId = nil }
                else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("feedTopMine", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Social Feed Content

    @ViewBuilder
    private func socialFeedContent(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru

        // Suggested users always on top (carousel hides itself if nothing to recommend)
        SuggestedUsersCarousel(onTapUser: { user in
            selectedAuthor = user
        })
        .padding(.bottom, 6)

        if socialFeed.isLoading, socialFeed.trips.isEmpty {
            PixelCarLoader(
                label: isRu ? "Загружаем ленту…" : "Loading feed…"
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
        } else if socialFeed.lastError != nil, socialFeed.trips.isEmpty {
            socialErrorState(c, isRu: isRu)
        } else if socialFeed.trips.isEmpty {
            socialEmptyState(c, isRu: isRu)
        } else {
            ForEach(socialFeed.trips) { trip in
                let isOwn = isOwnSocialTrip(trip)
                let ownVehicle = isOwn ? ownVehicleFor(tripId: trip.id) : nil
                SocialFeedCardView(
                    trip: trip,
                    isOwn: isOwn,
                    ownVehicle: ownVehicle,
                    onTapCard: {
                        // Own trips open the regular TripDetailView (vehicle-based header,
                        // edit pencil, privacy toggle) — same experience as from "Мои".
                        if isOwn {
                            selectedTripId = trip.id
                        } else {
                            selectedSocialTrip = trip
                        }
                    },
                    onTapAuthor: { selectedAuthor = trip.author },
                    onLongPress: { reactionPickerTrip = trip },
                    onReact: { emoji in
                        Task { await socialFeed.toggleReaction(for: trip.id, emoji: emoji) }
                    },
                    onShare: {
                        shareSocialTrip(trip)
                    }
                )
                .onAppear {
                    Task { await socialFeed.loadMoreIfNeeded(currentItem: trip) }
                }
                // Smooth fade + collapse when a card is removed (e.g. after the user
                // flips their own trip back to private).
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .scale(scale: 0.92)).combined(with: .move(edge: .leading))
                ))
            }
            .animation(.easeInOut(duration: 0.35), value: socialFeed.trips.map(\.id))

            if socialFeed.isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
            }
        }
    }

    private func guestFriendsState(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return VStack(spacing: 16) {
            PixelCarLoader(label: nil, height: 100)
                .allowsHitTesting(false)
                .padding(.top, 24)

            VStack(spacing: 8) {
                Text(isRu ? "Друзья в TripTrack" : "Friends on TripTrack")
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(-0.2)
                    .foregroundStyle(c.text)
                Text(isRu
                     ? "Войдите через Apple ID, чтобы подписаться на друзей и видеть их поездки."
                     : "Sign in with Apple to follow friends and see their trips.")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Haptics.tap()
                showProfile = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 14))
                    Text(isRu ? "Войти через Apple" : "Sign in with Apple")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func socialErrorState(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.red.opacity(0.8))
                .padding(.top, 60)
            Text(isRu ? "Не удалось загрузить ленту" : "Couldn't load feed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.text)
            Text(isRu
                 ? "Проверьте соединение с интернетом и попробуйте снова."
                 : "Check your connection and try again.")
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Haptics.tap()
                Task { await socialFeed.refresh() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isRu ? "Попробовать снова" : "Try again")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.accent, in: Capsule())
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    private func socialEmptyState(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(c.textTertiary)
                .padding(.top, 40)
            Text(isRu ? "Здесь появятся поездки друзей" : "Friends' trips will appear here")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(isRu
                 ? "Подпишитесь на кого-нибудь выше, чтобы видеть их поездки."
                 : "Follow someone above to see their trips.")
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }

    /// True when a feed card refers to the signed-in user's own trip. Used to route
    /// taps to the regular TripDetailView (with edit pencil + privacy toggle) instead
    /// of the read-only SocialTripDetailView.
    private func isOwnSocialTrip(_ trip: SocialFeedTrip) -> Bool {
        TokenStore.shared.accountId == trip.author.id
    }

    /// Looks up the local vehicle attached to a trip (by id) so own-trip cards in the
    /// feed render with the same vehicle header as in the "Мои" tab.
    private func ownVehicleFor(tripId: UUID) -> Vehicle? {
        guard let trip = feedVM.tripManager.tripDetail(id: tripId),
              let vid = trip.vehicleId else { return nil }
        return settings.vehicles.first { $0.id == vid }
    }

    private func shareSocialTrip(_ trip: SocialFeedTrip) {
        Task {
            do {
                let req = SocialShareRequest(tripId: trip.id, expiresInDays: nil)
                let res: SocialShareResponse = try await APIClient.shared.post(
                    APIEndpoint.socialShare, body: req)
                await MainActor.run {
                    shareSheetData = (
                        StoryShareData.from(trip, lang: lang.language),
                        res.shareUrl
                    )
                }
            } catch {
                // Ignore errors silently for MVP
            }
        }
    }

    // MARK: - Trip Sections

    @ViewBuilder
    private func tripSections(_ c: AppTheme.Colors) -> some View {
        if feedVM.trips.isEmpty {
            FeedEmptyStateView(
                hasFilters: feedVM.filters.isActive,
                onStartTrip: { selectedTab = 1 },
                onResetFilters: { feedVM.resetFilters() }
            )
        } else {
            ForEach(feedVM.sections) { section in
                sectionHeader(section, c: c)

                if !collapsedSections.contains(section.id) {
                    ForEach(section.trips) { trip in
                        tripCard(trip, c: c)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: TripSection, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.25)) {
                if collapsedSections.contains(section.id) {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        } label: {
            HStack {
                Text(section.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(c.textTertiary)
                    .tracking(0.5)
                Spacer()
                Image(systemName: collapsedSections.contains(section.id) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func vehicleForTrip(_ trip: Trip) -> Vehicle? {
        if let vid = trip.vehicleId {
            return settings.vehicles.first { $0.id == vid }
        }
        return nil
    }

    private func tripCard(_ trip: Trip, c: AppTheme.Colors) -> some View {
        let vehicle = vehicleForTrip(trip)
        // Swipe-to-delete has been retired — it collided with the horizontal
        // Feed ↔ Mine page swipe and made accidental deletions too easy. Delete
        // lives in the trip detail view now (menu with a confirmation step).
        return FeedTripCardView(
            trip: trip,
            vehicleName: vehicle?.name,
            vehicleEmoji: vehicle?.avatarEmoji ?? settings.avatarEmoji,
            vehicle: vehicle,
            fuelCurrency: trip.fuelCurrency ?? FuelCurrency.current
        )
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            selectedTripId = trip.id
        }
        .onAppear {
            feedVM.loadMoreIfNeeded(currentTrip: trip)
        }
    }

    // MARK: - Quick Stats

    private func quickStats(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                showStats = true
            } label: {
                statPill(
                    label: AppStrings.trips(lang.language),
                    value: "\(feedVM.totalTripCount)",
                    color: AppTheme.accent,
                    c: c
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                showStats = true
            } label: {
                statPill(
                    label: AppStrings.km(lang.language),
                    value: String(format: "%.0f", feedVM.totalKm),
                    color: c.text,
                    c: c
                )
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                showStats = true
            } label: {
                statPill(
                    label: AppStrings.time(lang.language),
                    value: feedVM.formattedTotalTime,
                    color: c.text,
                    c: c
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func statPill(label: String, value: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 12)
    }

    // MARK: - Filter Bar

    private func filterBar(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            Button {
                feedVM.showFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14))
                    .glassPill(isActive: feedVM.filters.isActive)
            }
            .buttonStyle(.plain)

            if let region = feedVM.filters.region {
                Button {
                    feedVM.setRegionFilter(nil)
                } label: {
                    HStack(spacing: 4) {
                        Text(region)
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .glassPill(isActive: true)
                }
                .buttonStyle(.plain)
            }

            if feedVM.filters.hasDateFilter {
                Button {
                    feedVM.setDateRange(from: nil, to: nil)
                } label: {
                    HStack(spacing: 4) {
                        Text(dateChipText)
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .glassPill(isActive: true)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Empty State (replaced by FeedEmptyStateView)

    // MARK: - Helpers

    private func animationDelay(for trip: Trip) -> Double {
        guard let index = feedVM.trips.firstIndex(where: { $0.id == trip.id }) else { return 0 }
        return min(Double(index) * 0.05, 0.5)
    }

    private static let chipDateFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM"
        return (ru, en)
    }()

    private var dateChipText: String {
        let formatter = lang.language == .ru ? Self.chipDateFormatters.ru : Self.chipDateFormatters.en
        guard let from = feedVM.filters.dateFrom else { return "" }
        let fromStr = formatter.string(from: from)
        guard let to = feedVM.filters.dateTo else { return fromStr }
        if Calendar.current.isDate(from, inSameDayAs: to) {
            return fromStr
        }
        return "\(fromStr) – \(formatter.string(from: to))"
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
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.disableBounce() }
    }

    private func disableBounce() {
        var candidate: UIView? = self
        while let v = candidate {
            if let scroll = v as? UIScrollView {
                scroll.bounces = false
                return
            }
            if let found = findScroll(in: v) {
                found.bounces = false
                return
            }
            candidate = v.superview
        }
    }

    private func findScroll(in view: UIView) -> UIScrollView? {
        for sub in view.subviews {
            if let scroll = sub as? UIScrollView { return scroll }
            if let nested = findScroll(in: sub) { return nested }
        }
        return nil
    }
}
