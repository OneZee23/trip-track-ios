import SwiftUI
import MapKit

/// Read-only detail view for a trip from the social feed.
/// Unlike the local TripDetailView, it shows a friend's trip — no editing,
/// no deletion, no photo picker. 6.1.0 poster layout: square navy hero with
/// the author pill + «Смотреть поездку» CTA, then the shared detail-body
/// sections (stat grid, moving/stops bar, description, photos,
/// achievements) and a compact interactive reactions card.
struct SocialTripDetailView: View {
    /// Initial trip snapshot — used as fallback if the store hasn't loaded
    /// this trip (e.g. direct push). Real rendering reads from
    /// `socialFeed.trips` so optimistic reaction updates re-render.
    let initialTrip: SocialFeedTrip
    var onShare: (() -> Void)?
    /// When present, author-avatar taps push onto this shared path instead
    /// of attaching a local `.navigationDestination`. Keeps us off the
    /// chained isPresented chain that triggers the depth-4 flash.
    var pushPath: Binding<[ProfilePreviewDest]>?

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var auth = AuthService.shared
    @State private var signInPrompt: SignInPromptSheet.Action?
    /// The reaction a guest tapped before signing in, resumed after a
    /// successful sign-in (mirrors FeedView) so the tap isn't silently dropped.
    @State private var pendingReactionEmoji: String?
    /// Set in the prompt's onAuthenticated, consumed in its onDismiss — resume
    /// only after the sheet has fully dismissed.
    @State private var resumeAfterAuth = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var socialFeed = SocialFeedStore.shared
    @State private var selectedAuthor: SocialAuthor?
    @State private var isMapFullscreen = false
    @State private var photos: [SocialTripPhoto] = []
    @State private var selectedPhotoIndex: Int?
    @State private var selectedDetailBadge: Badge?
    /// Full-emoji picker behind the «+» chip of the compact reactions card.
    @State private var showReactionPicker = false
    /// Remote-load failure flags — when the pushed DTO is a stub with no
    /// route geometry AND both loads fail (offline), there is nothing to
    /// render and the full-screen error state takes over. Today's feed
    /// pushes always carry a full trip, so this guards degenerate/deep-link
    /// paths.
    @State private var reactionsLoadFailed = false
    @State private var photosLoadFailed = false
    /// Comment post/delete failure toast (the owner detail view has its own
    /// toast host; this mirrors it for the social screen).
    @State private var toastItem: ToastItem?
    /// Emojis whose chips are currently playing the "burst" animation.
    /// Set on tap-that-adds (not tap-that-removes), cleared 0.7s later.
    @State private var burstingEmojis: Set<String> = []
    /// Route playback for a friend's trip. previewPolyline is RDP-
    /// simplified (sparser points than a local Trip), so the animation
    /// is still smooth but a hair more "stepped" between sample points.
    @StateObject private var routePlayback = RoutePlaybackController()
    /// Cached decode of `trip.previewPolyline`. The base64 + polyline
    /// decode happens once per trip-id, not on every body re-render
    /// (which during playback would mean display-rate decodes).
    @State private var cachedPreviewCoords: [CLLocationCoordinate2D] = []

    /// Always-current view of the trip: prefer store's copy (reflects
    /// optimistic reaction toggles) and fall back to the original snapshot
    /// if the store doesn't have the trip yet.
    private var trip: SocialFeedTrip {
        socialFeed.trips.first(where: { $0.id == initialTrip.id }) ?? initialTrip
    }

    private var isOwnTrip: Bool {
        trip.author.id == TokenStore.shared.accountId
    }

    /// Poster hero: 360pt square canvas below the status bar (Figma
    /// 360×360), navy extending up under the status bar + scrim.
    private var posterHeight: CGFloat { safeAreaTop + 360 }

    /// Hero route coordinates — cached decode with a first-render fallback
    /// (`.task` populates the cache after the first body pass). The
    /// fallback decode runs at most a couple of times; playback frames
    /// always hit the cache.
    private var heroCoords: [CLLocationCoordinate2D] {
        cachedPreviewCoords.isEmpty ? trip.previewCoordinates : cachedPreviewCoords
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 47
    }

    private var showLoadError: Bool {
        trip.previewPolyline == nil && reactionsLoadFailed && photosLoadFailed
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack(alignment: .topLeading) {
            if showLoadError {
                loadErrorState(c)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                            .frame(height: posterHeight)

                        detailBody(c)
                            .background(c.bg)
                    }
                    .background(alignment: .top) {
                        PosterPalette.navy
                            .frame(height: posterHeight + 1000)
                            .offset(y: -1000)
                    }
                }
                .scrollIndicators(.hidden)

                // Sticky floating back + «…» — matches TripDetailView pattern.
                HStack {
                    PosterCircleButton(
                        systemImage: "chevron.left",
                        accessibilityLabelText: AppStrings.back(lang.language)
                    ) { dismiss() }
                    Spacer()
                    Menu {
                        Button {
                            Haptics.tap()
                            onShare?()
                        } label: {
                            Label(
                                AppStrings.share(lang.language),
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        // Report entry point stays removed pending a
                        // moderation/admin UI — the server endpoint still
                        // accepts reports, but there's no triage surface for
                        // us to act on them yet. Re-add when moderation is
                        // wired up (ReportSheet.swift lives in this dir).
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel(AppStrings.moreActions(lang.language))
                }
                .padding(.top, safeAreaTop + 8)
                .padding(.horizontal, 16)
            }
        }
        .background(c.bg)
        // `.container` (not the default all-regions) — the keyboard inset
        // must survive so the comments composer rises above the keyboard.
        .ignoresSafeArea(.container)
        .navigationBarHidden(true)
        .toast(item: $toastItem)
        // NavBarKiller force-enables the interactive pop gesture in
        // viewWillAppear — without it, `.navigationBarHidden(true)` here
        // disabled the swipe-back-to-feed gesture (TripDetailView wires
        // this in for the same reason).
        .background(NavBarKiller())
        .modifier(SocialTripDetailLocalDestination(
            selectedAuthor: $selectedAuthor,
            enabled: pushPath == nil
        ))
        .hideAppTabBar()
        .fullScreenCover(isPresented: $isMapFullscreen) {
            FullscreenMapSheet(
                coordinates: trip.previewCoordinates,
                speeds: [],
                fogCutoffDate: nil,
                treatAsPreview: true
            )
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoIndex != nil },
            set: { if !$0 { selectedPhotoIndex = nil } }
        )) {
            if let idx = selectedPhotoIndex {
                SocialPhotoFullScreenView(
                    photos: photos,
                    initialIndex: idx,
                    authorName: trip.author.displayName,
                    authorEmoji: trip.author.avatarEmoji,
                    onDismiss: { selectedPhotoIndex = nil }
                )
            }
        }
        .task {
            // `loadReactions` and `loadPhotos` are independent network calls,
            // so kick them off in parallel — whichever finishes first lets
            // SwiftUI render its section before the other lands.
            async let r: Void = loadReactions()
            async let p: Void = loadPhotos()
            _ = await (r, p)
        }
        .task(id: trip.id) {
            // Decode the base64+polyline once per trip-id instead of on
            // every body re-render. Matters during route playback — the
            // computed `previewCoordinates` getter would otherwise
            // base64-decode at display rate.
            cachedPreviewCoords = trip.previewCoordinates
        }
        .onDisappear { routePlayback.stop() }
        .sheet(item: $signInPrompt, onDismiss: {
            if resumeAfterAuth { resumeAfterAuth = false; resumePendingReaction() }
            else { pendingReactionEmoji = nil }
        }) { action in
            SignInPromptSheet(action: action, onAuthenticated: { resumeAfterAuth = true })
                .environmentObject(lang)
                .environmentObject(auth)
        }
        .overlay {
            // TODO(v6.1-defer): BadgeDetailOverlay modal restyle per Figma
            // 117:1547 (300pt card, tinted 96pt icon circle, share button).
            if let badge = selectedDetailBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: true,
                    language: lang.language,
                    colorScheme: scheme,
                    lastEarnedDate: nil,
                    onDismiss: { selectedDetailBadge = nil }
                )
            }
        }
        .overlay {
            if showReactionPicker {
                ReactionPickerOverlay(
                    currentReaction: trip.myReaction,
                    onPick: { emoji in
                        showReactionPicker = false
                        handleReactionTap(emoji)
                    },
                    onDismiss: { showReactionPicker = false }
                )
            }
        }
    }

    // MARK: - Load error (Figma 519:158)

    private func loadErrorState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Text(AppStrings.tripTitle(lang.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.text)
                HStack {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(c.text)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
            }
            .padding(.top, safeAreaTop)
            .padding(.horizontal, 8)

            TripLoadErrorView(language: lang.language) {
                reactionsLoadFailed = false
                photosLoadFailed = false
                Task {
                    async let r: Void = loadReactions()
                    async let p: Void = loadPhotos()
                    _ = await (r, p)
                }
            }
        }
    }

    // MARK: - Reactions plumbing

    /// Replays a reaction a guest tapped before signing in. Runs from the
    /// prompt's onDismiss, so the sheet is already gone.
    private func resumePendingReaction() {
        guard let emoji = pendingReactionEmoji else { return }
        pendingReactionEmoji = nil
        // The store's optimistic toggle already updates count/breakdown/
        // myReaction — the compact card renders straight from it.
        Task { await socialFeed.toggleReaction(for: trip.id, emoji: emoji) }
    }

    /// Reachability probe: the rendered counts come from SocialFeedStore,
    /// this call only drives `reactionsLoadFailed` for the stub-trip
    /// full-screen error state.
    private func loadReactions() async {
        do {
            let _: SocialReactionsResponse = try await APIClient.shared.post(
                APIEndpoint.socialReactions, body: SocialUnreactRequest(tripId: trip.id),
                requiresAuth: AuthService.shared.isSignedIn)
            reactionsLoadFailed = false
        } catch {
            // Non-fatal for a normal trip — only flags the stub-trip
            // full-screen error state.
            reactionsLoadFailed = true
        }
    }

    private func loadPhotos() async {
        do {
            let res: SocialTripPhotosResponse = try await APIClient.shared.post(
                APIEndpoint.socialTripPhotos,
                body: SocialTripPhotosRequest(tripId: trip.id),
                requiresAuth: AuthService.shared.isSignedIn)
            photos = res.photos
            photosLoadFailed = false
        } catch {
            // Non-fatal — photo strip just stays hidden.
            photosLoadFailed = true
        }
    }

    /// Single reaction entry point shared by the compact chips and the
    /// «+» picker: guest → sign-in prompt with pending-reaction resume,
    /// owner → no-op (Strava rule), otherwise the store's optimistic
    /// toggle (it POSTs and updates count/breakdown/myReaction itself).
    private func handleReactionTap(_ emoji: String) {
        Haptics.selection()
        guard auth.isSignedIn else {
            pendingReactionEmoji = emoji
            signInPrompt = .react
            return
        }
        guard !isOwnTrip else { return }
        // Burst-animate only on the add direction. Tapping again to remove
        // your reaction shouldn't fire the celebratory sprite.
        if trip.myReaction != emoji {
            burstingEmojis.insert(emoji)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                burstingEmojis.remove(emoji)
            }
        }
        Task { await socialFeed.toggleReaction(for: trip.id, emoji: emoji) }
    }

    // MARK: - Poster hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            PosterRouteCanvas(
                // Route from previewPolyline — no per-point speeds in the
                // social DTO, so the poster renders accent-colored (Figma
                // shows speed colors; deviation until the backend ships a
                // speed series).
                coordinates: heroCoords,
                speeds: [],
                playbackCoord: routePlayback.currentCoord,
                playbackTrailIndex: routePlayback.currentTrailIndex
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard heroCoords.count > 1 else { return }
                Haptics.tap()
                isMapFullscreen = true
            }
            // The Canvas is not an a11y element — expose the tap-to-open-map
            // flow to VoiceOver (mirrors the own-trip poster).
            .accessibilityElement()
            .accessibilityLabel(AppStrings.openRouteMapA11y(lang.language))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard heroCoords.count > 1 else { return }
                isMapFullscreen = true
            }

            // Others' poster gets the stronger legibility gradient
            // (Figma: .55 → 0 @28% → 0 @52% → .88).
            PosterLegibilityOverlay(
                topOpacity: 0.55, clearFrom: 0.28, clearTo: 0.52, bottomOpacity: 0.88
            )

            heroTextBlock
        }
        .clipped()
        .overlay(alignment: .top) { PosterTopScrim() }
        .overlay(alignment: .topLeading) {
            authorPill
                .padding(.leading, 16)
                .padding(.top, safeAreaTop + 52)
        }
    }

    /// Author identity on the hero — avatar + name + pixel «ур. N».
    private var authorPill: some View {
        Button {
            Haptics.tap()
            if let pushPath {
                pushPath.wrappedValue.cappedAppend(.profile(trip.author.id, trip.author))
            } else {
                selectedAuthor = trip.author
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0xF4/255, green: 0xF2/255, blue: 0xEE/255))
                    .frame(width: 28, height: 28)
                    .overlay { Text(trip.author.avatarEmoji ?? "🚗").font(.system(size: 16)) }
                Text(trip.author.displayName ?? (lang.language == .ru ? "Без имени" : "No name"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // App-wide LVL convention — every other surface (feed card,
                // follow list, public profile, …) renders uppercase "LVL N"
                // in both languages; «ур. N» here broke the feed→detail hop.
                Text("LVL \(trip.author.profileLevel)")
                    .font(.custom("PressStart2P-Regular", size: 7))
                    .foregroundStyle(Color(red: 0xD9/255, green: 0xDB/255, blue: 0xE5/255).opacity(0.7))
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(.black.opacity(0.42), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var heroTextBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TripDetailFormat.posterDateLine(
                date: trip.startDate, region: trip.region, lang: lang.language))
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(trip.title ?? "—")
                .font(.system(size: 25, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
                .padding(.top, 8)

            if heroCoords.count > 1 {
                Button {
                    Haptics.tap()
                    routePlayback.toggle(
                        coords: heroCoords,
                        timestamps: nil,  // social trips carry no timestamps
                        distanceMeters: trip.distance
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: routePlayback.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(AppStrings.watchTrip(lang.language))
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(PosterPalette.ctaText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.bottom, 20)
    }

    // MARK: - Detail body

    private func detailBody(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return VStack(alignment: .leading, spacing: 22) {
            chipsRow(c)

            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.detailsSection(lang.language))
                metricsGrid(c, isRu: isRu)
            }

            if let driving = trip.drivingTime, let stopped = trip.stoppedTime,
               driving + stopped > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    DetailSectionHeader(text: AppStrings.movingAndStops(lang.language))
                    MovingStopsCard(
                        movingSeconds: TimeInterval(driving),
                        stoppedSeconds: TimeInterval(stopped),
                        language: lang.language
                    )
                }
            }

            descriptionSection(c)

            // Render a photos strip only when the server actually returned
            // any — unlike the owner's detail view which keeps the section
            // as an empty-state "add photos" prompt, there's nothing a
            // viewer can do about a trip without photos, so we just hide it.
            if !photos.isEmpty {
                photosSection(c)
            }

            badgesSection(c)

            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.reactionsTitleN(lang.language, trip.reactionCount))
                reactionsCompactCard(c)
            }

            // «Комментарии · N» (Figma 531:119) — guests read, signed-in
            // users write; the composer gates guests through the same
            // sign-in sheet as reactions.
            TripCommentsSection(
                tripId: trip.id,
                isTripOwner: isOwnTrip,
                initialCount: trip.commentCount,
                onGuestInputTap: { signInPrompt = .comment },
                onError: { msg in
                    toastItem = ToastItem(type: .error, message: msg)
                }
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 80)
    }

    /// Time-range + vehicle chips (no privacy chip on others' trips).
    private func chipsRow(_ c: AppTheme.Colors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                DetailChipSurface {
                    Text(timeRange).monospacedDigit()
                }

                if let v = trip.vehicle {
                    let n = v.name.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty {
                        DetailChipSurface {
                            if v.isPixelAvatar {
                                Image(v.avatarEmoji)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 13, height: 13)
                            } else {
                                Text(v.avatarEmoji)
                                    .font(.system(size: 11))
                            }
                            Text(n).lineLimit(1)
                        }
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func descriptionSection(_ c: AppTheme.Colors) -> some View {
        // Author's notes — the story behind the trip, same card language as
        // the owner side. Empty / null is hidden.
        if let raw = trip.description {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    DetailSectionHeader(text: AppStrings.descriptionSection(lang.language))
                    DetailDescriptionCard(text: trimmed)
                }
            }
        }
    }

    private func metricsGrid(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        // Mirrors the owner-side stat grid minus fuel and cost — they're
        // personal economic data tied to the owner's vehicle config, not
        // relevant to a friend reading the trip. (Figma: 8 cards.)
        let l = lang.language
        let hasMaxSpeed = (trip.maxSpeed ?? 0) > 0
        let hasElevation = (trip.elevation ?? 0) > 0.5
        let hasMaxAltitude = (trip.maxAltitude ?? 0) > 0.5
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            DetailStatCard(
                value: String(format: "%.1f", trip.distanceKm),
                unit: AppStrings.km(l),
                label: AppStrings.distance(l),
                color: AppTheme.green,
                staggerIndex: 0
            )
            DetailStatCard(
                value: TripDetailFormat.hoursMinutes(TimeInterval(trip.duration)),
                label: AppStrings.duration(l),
                color: AppTheme.accent,
                staggerIndex: 1
            )
            if let driving = trip.drivingTime, driving > 0 {
                DetailStatCard(
                    value: TripDetailFormat.hoursMinutes(TimeInterval(driving)),
                    label: AppStrings.statMoving(l),
                    color: AppTheme.blue,
                    staggerIndex: 2
                )
            }
            if let stopped = trip.stoppedTime, stopped > 0 {
                DetailStatCard(
                    value: TripDetailFormat.hoursMinutes(TimeInterval(stopped)),
                    label: AppStrings.statStops(l),
                    color: c.textSecondary,
                    staggerIndex: 3
                )
            }
            DetailStatCard(
                value: String(format: "%.0f", trip.averageSpeedKmh),
                unit: AppStrings.kmh(l),
                label: AppStrings.statAvg(l),
                color: AppTheme.blue,
                staggerIndex: 4
            )
            if hasMaxSpeed {
                DetailStatCard(
                    value: String(format: "%.0f", trip.maxSpeedKmh),
                    unit: AppStrings.kmh(l),
                    label: AppStrings.statMax(l),
                    color: AppTheme.red,
                    staggerIndex: 5
                )
            }
            if hasElevation {
                DetailStatCard(
                    value: String(format: "+%.0f", trip.elevation ?? 0),
                    unit: AppStrings.m(l),
                    label: AppStrings.elevationGain(l),
                    color: AppTheme.green,
                    staggerIndex: 6
                )
            }
            if hasMaxAltitude {
                DetailStatCard(
                    value: String(format: "%.0f", trip.maxAltitude ?? 0),
                    unit: AppStrings.m(l),
                    label: AppStrings.maxAltitude(l),
                    color: AppTheme.teal,
                    staggerIndex: 7
                )
            }
        }
    }

    // MARK: - Photos

    private func photosSection(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(text: "\(AppStrings.photos(lang.language)) · \(photos.count)")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        remoteThumbnail(photo, c: c)
                            .frame(width: 74, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.tap()
                                selectedPhotoIndex = index
                            }
                    }
                }
            }
            .frame(height: 74)
        }
    }

    @ViewBuilder
    private func remoteThumbnail(_ photo: SocialTripPhoto, c: AppTheme.Colors) -> some View {
        // Thumbnail presign first, original second. AsyncImage falls back to
        // a neutral placeholder so the grid doesn't jitter while images load.
        let urlString = photo.thumbnailUrl ?? photo.originalUrl
        if let s = urlString, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle()
                        .fill(c.cardAlt)
                        .overlay {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 18))
                                .foregroundStyle(c.textTertiary)
                        }
                case .empty:
                    Rectangle()
                        .fill(c.cardAlt)
                        .overlay { CarLoadingView(size: .compact) }
                @unknown default:
                    Rectangle().fill(c.cardAlt)
                }
            }
        } else {
            Rectangle()
                .fill(c.cardAlt)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(c.textTertiary)
                }
        }
    }

    // MARK: - Badges («Достижения поездки»)

    @ViewBuilder
    private func badgesSection(_ c: AppTheme.Colors) -> some View {
        let badges = trip.badgeIds.compactMap { id in Badge.all.first { $0.id == id } }
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.tripAchievements(lang.language))
                TripAchievementsGrid(
                    badges: badges,
                    language: lang.language,
                    onTap: { badge in selectedDetailBadge = badge }
                )
            }
        }
    }

    // MARK: - Compact interactive reactions (Figma 467:246)

    /// One card: my-reaction chip tinted, unselected chips neutral, «+»
    /// opens the full emoji picker. No reactor list on others' trips.
    private func reactionsCompactCard(_ c: AppTheme.Colors) -> some View {
        let breakdown = trip.reactionBreakdown
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
        return HStack(spacing: 8) {
            if breakdown.isEmpty {
                Text(isOwnTrip
                     ? AppStrings.noReactionsYet(lang.language)
                     : AppStrings.beFirstToReact(lang.language))
                    .font(.system(size: 13))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(breakdown, id: \.emoji) { tally in
                            reactionChipButton(tally)
                        }
                    }
                }
                .scrollClipDisabled()
            }

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                guard auth.isSignedIn else {
                    signInPrompt = .react
                    return
                }
                guard !isOwnTrip else { return }
                showReactionPicker = true
            } label: {
                Text("+")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 34, height: 28)
                    .background(
                        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
    }

    private func reactionChipButton(_ tally: ReactionTally) -> some View {
        let isMine = trip.myReaction == tally.emoji
        return Button {
            handleReactionTap(tally.emoji)
        } label: {
            ReactionCountChip(
                emoji: tally.emoji,
                count: tally.count,
                style: isMine ? .mine : .unselected
            )
            .overlay(alignment: .top) {
                if burstingEmojis.contains(tally.emoji) {
                    ReactionBurstSprite(emoji: tally.emoji)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMine)
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeRange: String {
        let start = Self.timeFormatter.string(from: trip.startDate)
        if let end = trip.endDate {
            return "\(start) – \(Self.timeFormatter.string(from: end))"
        }
        return start
    }
}

/// Gates the local-state `.navigationDestination` so it's only active when
/// no shared `pushPath` is wired in. Parallel to the gate in FollowListView
/// / PublicProfileView — same depth-4 flash avoidance.
private struct SocialTripDetailLocalDestination: ViewModifier {
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
