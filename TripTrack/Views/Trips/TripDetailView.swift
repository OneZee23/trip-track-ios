import SwiftUI
import MapKit

struct TripDetailView: View {
    let tripId: UUID
    @ObservedObject var viewModel: TripsViewModel
    /// When present, reactor-avatar taps push onto this shared path
    /// (capped via `cappedAppend`) instead of attaching a local
    /// `.navigationDestination(isPresented:)`. Using the typed path dodges
    /// the SwiftUI NavigationStack flash at depth 4+ that the chained
    /// isPresented approach was triggering from Feed → Trip → Profile → …
    var pushPath: Binding<[ProfilePreviewDest]>?
    /// Where to land: top (default), the discussion, or one specific
    /// comment that also gets highlighted on arrival.
    var focus: TripFocus = .top
    @State private var trip: Trip?
    @State private var showPhotoPicker = false
    @State private var pickedImages: [UIImage] = []
    @State private var selectedPhotoIndex: Int?
    @State private var selectedDetailBadge: Badge?
    @State private var badgeLastEarnedDates: [String: Date] = [:]
    @State private var photoToDelete: TripPhoto?
    @State private var toastItem: ToastItem?
    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var originalTitle: String = ""
    @State private var showNotesEditor = false
    @State private var editedNotes: String = ""
    @State private var cachedCoordinates: [CLLocationCoordinate2D] = []
    @State private var cachedSpeeds: [Double] = []
    /// Per-trackpoint timestamps for time-driven route playback (the
    /// car lingers in traffic, zips on the highway). Empty when the
    /// trip only has a preview polyline — playback falls back to a
    /// uniform-speed crawl in that case.
    @State private var cachedTimestamps: [Date] = []
    /// Downsampled (≤300 pts) coords/speeds/timestamps for the poster hero
    /// canvas + playback. The canvas repaints at display-link rate during
    /// «Прожить заново», so it must never chew through raw 10k-point tracks.
    /// Downsampled (≤200 pts) chart series — empty when the trip carries
    /// no full trackPoints (sync-pulled preview-only trips) so the chart
    /// sections hide themselves.
    @State private var elevationSeries: [DetailChartPoint] = []
    @State private var speedSeries: [DetailChartPoint] = []
    /// Movement split + altitude stats cached once per trip load —
    /// `Trip.drivingTime` walks every trackPoint per call, which the body
    /// must not do on every playback frame.
    @State private var cachedDrivingTime: TimeInterval = 0
    @State private var cachedStoppedTime: TimeInterval = 0
    @State private var cachedElevationGain: Double = 0
    @State private var cachedMaxAltitude: Double = 0
    @State private var storyShare: (data: StoryShareData, url: String?)?
    @State private var isGeneratingShare = false
    @State private var showDeleteConfirm = false
    /// Publish confirmation sheet (Figma 533:119) — replaces the old plain
    /// alert. The user consciously acknowledges the visibility change and
    /// can attach an optional description in the same step.
    @State private var showPublishSheet = false
    /// Drives the «Публикуется…» / publish-error toast overlay after the
    /// user confirms a publish. Watches SyncQueue for the trip's upload op.
    @State private var publishWatchActive = false
    /// Going public→private is also gated: once a trip has been seen by
    /// others, demoting it isn't undoable in the social-record sense
    /// (reactions/comments don't survive a republish). One-shot confirm.
    @State private var unpublishConfirm = false
    @State private var reactionEntries: [SocialReactionEntry] = []
    @State private var selectedReactorAuthor: SocialAuthor?
    @State private var isMapFullscreen = false
    @State private var showVehiclePicker = false
    /// Drives the «Прожить заново» CTA on the poster. Owned via
    /// `@StateObject` so the timer survives view re-renders and is
    /// stopped cleanly on `.onDisappear`. Since the fullscreen replay
    /// (117:533) shipped, this only runs for preview-only trips whose
    /// track carries no timestamps — the cinema screen needs them.
    @StateObject private var routePlayback = RoutePlaybackController()
    /// Presents the fullscreen cinema replay (Figma 117:533). Timestamped
    /// own trips only; preview-only trips fall back to the inline crawl.
    @ObservedObject private var auth = AuthService.shared
    /// Sign-in prompt for the signed-out edge state (e.g. «keep public and
    /// sign out» leaves own public trips visible): the comments composer
    /// routes guests here instead of letting them post into USER_NOT_AUTH.
    @State private var signInPrompt: SignInPromptSheet.Action?
    @FocusState private var isTitleFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var settings = SettingsManager.shared

    /// Poster hero: 380pt of canvas below the status bar (Figma 360×380),
    /// with the navy canvas extending up under the status bar + scrim.
    /// Release map-hero height: ~45% of the screen (same as pre-6.1).
    private var posterHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.bounds.height ?? 844) * 0.45
    }

    /// Scroll target for the «Комментарии» block.
    private static let commentsAnchor = "comments"

    /// See `SocialTripDetailView.scrollToCommentsIfRequested`.
    private func scrollToCommentsIfRequested(_ proxy: ScrollViewProxy) async {
        // `.comment` lands on the section too — the comments block then
        // homes in on the exact row once it has found it in a page.
        guard focus != .top else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        withAnimation(.easeOut(duration: 0.45)) {
            proxy.scrollTo(Self.commentsAnchor, anchor: .top)
        }
    }

    /// Comment id to spotlight, when we were opened from its notification.
    private var highlightedCommentId: UUID? {
        if case .comment(let id) = focus { return id }
        return nil
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack(alignment: .topLeading) {
            if let trip {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        heroSection(trip: trip)
                            .frame(height: posterHeight)

                        // Bottom info panel
                        infoPanel(trip: trip, c: c)
                            .background(c.bg)
                    }
                    .background(alignment: .top) {
                        // Over-scroll filler above the map (release value).
                        Color(UIColor(white: 0.12, alpha: 1.0))
                            .frame(height: posterHeight + 1000)
                            .offset(y: -1000)
                    }
                }
                .coordinateSpace(name: "detailScroll")
                .scrollIndicators(.hidden)
                .background(ScrollBounceDisabler())
                .task { await scrollToCommentsIfRequested(proxy) }
                }

                // Sticky back + (⋯ delete) + share — floating over the poster.
                HStack(spacing: 8) {
                    PosterCircleButton(
                        systemImage: "chevron.left",
                        accessibilityLabelText: AppStrings.back(lang.language)
                    ) { dismiss() }

                    Spacer()

                    Menu {
                        Button(role: .destructive) {
                            Haptics.action()
                            showDeleteConfirm = true
                        } label: {
                            Label(
                                AppStrings.delete(lang.language),
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .accessibilityLabel(AppStrings.moreActions(lang.language))

                    PosterCircleButton(
                        systemImage: "square.and.arrow.up",
                        accessibilityLabelText: AppStrings.share(lang.language)
                    ) {
                        Task { await openStoryShare(for: trip) }
                    }
                    .disabled(isGeneratingShare)
                }
                .padding(.top, safeAreaTop + 8)
                .padding(.horizontal, 16)
            } else {
                // Loading skeleton
                VStack(spacing: 0) {
                    c.cardAlt
                        .frame(height: posterHeight)
                        .shimmer()
                        .overlay { CarLoadingView() }
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 200, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 160, height: 20)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16).fill(c.cardAlt).frame(height: 80)
                            }
                        }
                    }
                    .padding(16)
                    .shimmer()
                    Spacer()
                }
            }
        }
        .background(c.bg)
        .background(NavBarKiller())
        // `.container` (not the default all-regions) — the keyboard inset
        // must survive so the comments composer rises above the keyboard.
        .ignoresSafeArea(.container)
        .navigationBarHidden(true)
        .modifier(TripDetailLocalReactorDestination(
            selectedReactorAuthor: $selectedReactorAuthor,
            enabled: pushPath == nil
        ))
        .hideAppTabBar()
        .fullScreenCover(isPresented: $isMapFullscreen) {
            FullscreenMapSheet(
                coordinates: cachedCoordinates,
                speeds: cachedSpeeds,
                fogCutoffDate: trip?.endDate,
                language: lang.language
            )
        }
        .confirmationDialog(
            AppStrings.deleteTrip(lang.language),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(lang.language), role: .destructive) {
                mapVM.tripManager.deleteTrip(id: tripId)
                NotificationCenter.default.post(name: .tripDeleted, object: tripId)
                dismiss()
            }
            Button(AppStrings.cancel(lang.language), role: .cancel) {}
        }
        .onDisappear { routePlayback.stop() }
        .task(id: tripId) {
            if trip == nil {
                trip = viewModel.tripDetail(id: tripId)
                if let t = trip { buildCaches(for: t) }
                badgeLastEarnedDates = BadgeManager.lastEarnedDates(for: trip?.earnedBadgeIds ?? [], using: mapVM.tripManager)
            }
            await loadReactions()
        }
        .onChange(of: trip?.isPrivate) { _, newValue in
            if newValue == false { Task { await loadReactions() } }
            else { reactionEntries = [] }
        }
        .sheet(isPresented: $showPhotoPicker) {
            // TODO(v6.1-defer): Figma 117:587 specs a custom photo-picker
            // grid with orange order badges; the system picker ships v1.
            PhotoPickerView(selectedImages: $pickedImages)
        }
        .onChange(of: pickedImages) { newImages in
            for image in newImages {
                if let photo = mapVM.tripManager.addPhoto(to: tripId, image: image) {
                    trip?.photos.append(photo)
                }
            }
            pickedImages = []
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoIndex != nil },
            set: { if !$0 { selectedPhotoIndex = nil } }
        )) {
            if let photos = trip?.photos, let index = selectedPhotoIndex {
                PhotoFullScreenView(
                    photos: photos,
                    initialIndex: index,
                    region: trip?.region,
                    language: lang.language,
                    onDismiss: { selectedPhotoIndex = nil }
                )
            }
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
                    lastEarnedDate: badgeLastEarnedDates[badge.id],
                    onDismiss: { selectedDetailBadge = nil }
                )
            }
        }
        .toast(item: $toastItem)
        .overlay(alignment: .top) {
            PublishStatusOverlay(
                tripId: tripId,
                isActive: $publishWatchActive,
                language: lang.language
            )
            .padding(.horizontal, 12)
            // Below the floating back/⋯/share row (Figma 522:119 puts the
            // toast at y≈110) — at +8 it covered the buttons and swallowed
            // their taps for the whole publish window.
            .padding(.top, safeAreaTop + 56)
        }
        .confirmationDialog(
            AppStrings.deletePhoto(lang.language),
            isPresented: Binding(
                get: { photoToDelete != nil },
                set: { if !$0 { photoToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(lang.language), role: .destructive) {
                if let photo = photoToDelete {
                    Haptics.action()
                    mapVM.tripManager.deletePhoto(id: photo.id, from: tripId)
                    trip?.photos.removeAll { $0.id == photo.id }
                    toastItem = ToastItem(
                        type: .success,
                        message: AppStrings.photoDeleted(lang.language)
                    )
                }
                photoToDelete = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { storyShare != nil },
            set: { if !$0 { storyShare = nil } }
        )) {
            if let share = storyShare {
                StoryShareSheet(data: share.data, shareUrl: share.url)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(lang)
                    // Sheets are separate presentations — the app-root
                    // preferredColorScheme does not reach them.
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showNotesEditor) {
            NotesEditorView(text: $editedNotes, onSave: { commitNotesEdit() })
                .environmentObject(lang)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showPublishSheet) {
            PublishTripSheet(
                language: lang.language,
                message: publishConfirmMessage,
                descriptionText: trip?.tripDescription ?? "",
                onPublish: { desc in handlePublishConfirm(descriptionText: desc) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(item: $signInPrompt) { action in
            SignInPromptSheet(action: action)
                .environmentObject(lang)
                .environmentObject(auth)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .alert(
            lang.language == .ru ? "Сделать поездку приватной?" : "Make trip private?",
            isPresented: $unpublishConfirm
        ) {
            Button(AppStrings.cancel(lang.language), role: .cancel) {}
            Button(lang.language == .ru ? "Сделать приватной" : "Make private") {
                applyPrivacyChange(isPrivate: true)
            }
        } message: {
            Text(lang.language == .ru
                 ? "Поездка пропадёт из общей ленты и из профилей других пользователей. Её увидите только Вы.\n\nРеакции и комментарии не сохранятся, если Вы потом снова сделаете её публичной."
                 : "This trip will disappear from the social feed and from other users' profiles. Only you will see it.\n\nReactions and comments won't be preserved if you make it public again later.")
        }
    }

    // MARK: - Caches

    /// One-pass derivation of everything the body must not recompute per
    /// frame: full coords for the fullscreen map, downsampled poster/
    /// playback series, chart series and the movement/altitude stats.
    private func buildCaches(for t: Trip) {
        let pts = t.trackPoints
        if pts.count > 1 {
            cachedCoordinates = pts.map(\.coordinate)
            cachedSpeeds = pts.map(\.speed)
            cachedTimestamps = pts.map(\.timestamp)

            // Chart series over cumulative distance (≤200 pts).
            let chartStep = max(1, pts.count / 200)
            var elev: [DetailChartPoint] = []
            var spd: [DetailChartPoint] = []
            var cumulative = 0.0
            var lastLoc: CLLocation?
            for (i, p) in pts.enumerated() {
                let loc = CLLocation(latitude: p.latitude, longitude: p.longitude)
                if let prev = lastLoc { cumulative += loc.distance(from: prev) }
                lastLoc = loc
                if i % chartStep == 0 || i == pts.count - 1 {
                    let km = cumulative / 1000
                    elev.append(DetailChartPoint(id: elev.count, x: km, y: p.altitude))
                    spd.append(DetailChartPoint(id: spd.count, x: km, y: max(0, p.speed * 3.6)))
                }
            }
            // A dead-flat altitude series (simulator, barometer-less data)
            // renders as a meaningless line — hide the section instead.
            let altValues = elev.map(\.y)
            let flat = (altValues.max() ?? 0) - (altValues.min() ?? 0) <= 0.5
            elevationSeries = flat ? [] : elev
            speedSeries = spd

            cachedDrivingTime = t.drivingTime
            cachedStoppedTime = t.stoppedTime
            var gain: Double = 0
            for i in 1..<pts.count {
                let delta = pts[i].altitude - pts[i - 1].altitude
                if delta > 0 { gain += delta }
            }
            cachedElevationGain = gain
            cachedMaxAltitude = pts.map(\.altitude).max() ?? 0
        } else if let preview = t.previewPolyline {
            // Trips synced down via /sync/pull only carry metadata + the
            // preview polyline (server doesn't return full trackPoints).
            // The poster renders the simplified polyline accent-colored;
            // charts and the moving/stops bar stay hidden (no series).
            cachedCoordinates = Trip.decodePolyline(preview)
            cachedSpeeds = []
        }
    }

    // MARK: - Story Share

    private func openStoryShare(for trip: Trip) async {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true
        defer { isGeneratingShare = false }

        let authorName = AuthService.shared.userName
            ?? (lang.language == .ru ? "Моя поездка" : "My trip")
        let authorEmoji = settings.avatarEmoji
        let data = StoryShareData.from(trip, authorName: authorName, authorEmoji: authorEmoji, lang: lang.language)

        // If signed in, try to generate a public share link via the server.
        // If offline or not signed in — fall back to image-only share.
        var url: String?
        if AuthService.shared.isSignedIn {
            do {
                let req = SocialShareRequest(tripId: trip.id, expiresInDays: nil)
                let res: SocialShareResponse = try await APIClient.shared.post(
                    APIEndpoint.socialShare, body: req)
                url = res.shareUrl
            } catch {
                url = nil
            }
        }

        storyShare = (data, url)
    }

    // MARK: - Map hero
    // Release-style hero restored by explicit user decision (2026-08-06):
    // real interactive street map with the speed-colored route, inline
    // playback + fullscreen expand — NOT the Figma navy poster with the
    // pixel car («что за машинка по маршруту? Надо как в релизной версии»).
    // The Figma poster/cinema treatment stays only in TripReplayView.

    @ViewBuilder
    private func heroSection(trip: Trip) -> some View {
        let c = AppTheme.colors(for: scheme)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if cachedCoordinates.count > 1 {
                    RouteMapView(
                        coordinates: cachedCoordinates,
                        speeds: cachedSpeeds,
                        isInteractive: true,
                        fogCutoffDate: trip.endDate,
                        playbackCarCoord: routePlayback.currentCoord,
                        playbackTrailIndex: routePlayback.currentTrailIndex
                    )
                } else {
                    c.cardAlt
                        .overlay {
                            Image(systemName: "map")
                                .font(.largeTitle)
                                .foregroundStyle(c.textTertiary)
                        }
                }
            }

            if cachedCoordinates.count > 1 {
                HStack(spacing: 8) {
                    RoutePlaybackButton(isPlaying: routePlayback.isPlaying) {
                        routePlayback.toggle(
                            coords: cachedCoordinates,
                            timestamps: cachedTimestamps.isEmpty ? nil : cachedTimestamps,
                            distanceMeters: trip.distance
                        )
                    }
                    Button {
                        Haptics.tap()
                        isMapFullscreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityIdentifier("detail_map_expand")
                    .accessibilityLabel(AppStrings.openRouteMapA11y(lang.language))
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
        // Speed-colour legend — collapsed pill below the floating back
        // button; only when the route is speed-coloured. Corners are
        // otherwise taken: back (top-left), ⋯/share (top-right), Apple
        // attribution (bottom-left), play/expand (bottom-right).
        .overlay(alignment: .topLeading) {
            if cachedCoordinates.count > 1, !cachedSpeeds.isEmpty {
                SpeedLegendView(language: lang.language, initiallyExpanded: false)
                    .padding(.leading, 12)
                    .padding(.top, safeAreaTop + 56)
            }
        }
    }

    /// Date-region line + editable title, on the theme background below the
    /// map (the release layout). Replaces the poster text block.
    private func titleBlock(trip: Trip, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TripDetailFormat.posterDateLine(
                date: trip.startDate, region: trip.region, lang: lang.language))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            heroTitle(trip: trip, c: c)
        }
        .animation(.easeInOut(duration: 0.25), value: isEditingTitle)
    }

    /// Hero title with the inline edit flow carried over from the pre-6.1
    /// identity block — tap the title (or the pencil) to edit in place.
    @ViewBuilder
    private func heroTitle(trip: Trip, c: AppTheme.Colors) -> some View {
        if isEditingTitle {
            HStack(spacing: 10) {
                TextField(
                    AppStrings.tripTitlePlaceholder(lang.language),
                    text: $editedTitle
                )
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .focused($isTitleFieldFocused)
                .onSubmit { commitTitleEdit() }

                Button {
                    Haptics.tap()
                    cancelTitleEdit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(c.textTertiary)
                }
                Button {
                    Haptics.action()
                    commitTitleEdit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.green)
                }
            }
            .transition(.opacity)
        } else {
            Button {
                Haptics.tap()
                editedTitle = trip.title ?? ""
                originalTitle = editedTitle
                withAnimation(.easeInOut(duration: 0.25)) {
                    isEditingTitle = true
                }
                isTitleFieldFocused = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trip.title ?? formattedDateFallback(trip.startDate))
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.52)
                        .foregroundStyle(c.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                    // The small pencil keeps the title-edit flow
                    // discoverable.
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
            .buttonStyle(.plain)
            // VoiceOver otherwise reads the title text with no clue that
            // activating it starts the rename flow.
            .accessibilityLabel(trip.title ?? formattedDateFallback(trip.startDate))
            .accessibilityHint(AppStrings.editTitleA11y(lang.language))
            .transition(.opacity)
        }
    }

    // MARK: - Info Panel

    @ViewBuilder
    private func infoPanel(trip: Trip, c: AppTheme.Colors) -> some View {
        // Single source of vertical rhythm (22pt per Figma detail-body gap)
        // so conditional sections (charts, badges, reactions) don't produce
        // uneven spacing when they appear/disappear.
        VStack(alignment: .leading, spacing: 22) {
            titleBlock(trip: trip, c: c)

            chipsRow(trip: trip, c: c)

            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.detailsSection(lang.language))
                statsGrid(trip: trip, c: c)
            }

            if elevationSeries.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    DetailSectionHeader(text: AppStrings.elevationProfile(lang.language))
                    ElevationChartCard(
                        series: elevationSeries,
                        language: lang.language,
                        summary: AppStrings.chartMaxElev(
                            lang.language,
                            max: "\(Int(cachedMaxAltitude)) \(AppStrings.m(lang.language))",
                            gain: "\(Int(cachedElevationGain)) \(AppStrings.m(lang.language))"
                        ),
                        leftLabel: trip.region ?? "",
                        rightLabel: "\(Int(trip.distanceKm.rounded())) \(AppStrings.km(lang.language))"
                    )
                }
            }

            if speedSeries.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    DetailSectionHeader(text: AppStrings.speedSection(lang.language))
                    SpeedChartCard(
                        series: speedSeries,
                        language: lang.language,
                        summary: AppStrings.chartMaxAvg(
                            lang.language,
                            max: "\(Int(trip.maxSpeedKmh))",
                            avg: "\(Int(trip.displayAverageSpeedKmh(settings.avgSpeedMode)))"
                        )
                    )
                }
            }

            if (cachedDrivingTime + cachedStoppedTime) > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    DetailSectionHeader(text: AppStrings.movingAndStops(lang.language))
                    MovingStopsCard(
                        movingSeconds: cachedDrivingTime,
                        stoppedSeconds: cachedStoppedTime,
                        language: lang.language
                    )
                }
            }

            notesSection(trip: trip, c: c)

            photosSection(c)

            badgesSection(trip: trip, c: c)

            // Reactions surface — Strava-style:
            //   * Public + has reactions → «Реакции · N» card.
            //   * Public + 0 reactions → ghost line ("No reactions yet").
            //   * Private (signed-in) → publish nudge card to convert.
            //   * Guest (private fallback) — nothing, no payoff to show.
            if auth.isSignedIn {
                reactionsArea(trip: trip, c: c)
            }

            // «Комментарии · N» (Figma 549:129) — PUBLIC trips only.
            // Comments live server-side against the published trip; a
            // private trip has no social surface to comment on, so the
            // section hides entirely (no ghost card).
            if !trip.isPrivate {
                TripCommentsSection(
                    tripId: trip.id,
                    isTripOwner: true,
                    // Own public trips ARE reachable signed-out («keep
                    // public and sign out» / dead session) — without this
                    // the composer looks active but every send dies with
                    // USER_NOT_AUTH. Mirrors the social screen's gate.
                    onGuestInputTap: { signInPrompt = .comment },
                    onError: { msg in
                        toastItem = ToastItem(type: .error, message: msg)
                    },
                    highlightCommentId: highlightedCommentId
                )
                .id(Self.commentsAnchor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, safeAreaBottom + 90)
        .background(c.bg)
    }

    // MARK: - Chips row

    private func chipsRow(trip: Trip, c: AppTheme.Colors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                DetailChipSurface {
                    Text(timeRange(trip))
                        .monospacedDigit()
                }

                vehicleChip(trip: trip, c: c)

                // Privacy chip is per-trip and works independently of global
                // Cloud Sync (privacy-first model: publishing one trip should
                // NOT require turning on full-account mirror).
                if auth.isSignedIn {
                    privacyChip(trip: trip, c: c)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var tripVehicle: Vehicle? {
        if let vid = trip?.vehicleId {
            return settings.vehicles.first { $0.id == vid }
        }
        return nil
    }

    /// Tappable vehicle chip. Presents a picker of the garage vehicles plus
    /// a "no vehicle" clear option. Reassignment is metadata-only (see
    /// TripRepository.updateVehicle) — odometer/stats are not rebalanced,
    /// matching how title/notes edits behave.
    private func vehicleChip(trip: Trip, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.selection()
            showVehiclePicker = true
        } label: {
            DetailChipSurface {
                if let v = tripVehicle {
                    Text(v.displayEmoji)
                        .font(.system(size: 12))
                    Text(v.name)
                        .lineLimit(1)
                } else {
                    Image(systemName: "car")
                        .font(.system(size: 11, weight: .medium))
                    Text(AppStrings.noVehicle(lang.language))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            AppStrings.tripVehicle(lang.language),
            isPresented: $showVehiclePicker,
            titleVisibility: .visible
        ) {
            ForEach(settings.vehicles) { v in
                Button("\(v.displayEmoji) \(v.name)") {
                    applyVehicleChange(v.id)
                }
            }
            Button(AppStrings.noVehicle(lang.language), role: .destructive) {
                applyVehicleChange(nil)
            }
            Button(AppStrings.cancel(lang.language), role: .cancel) {}
        }
    }

    @ViewBuilder
    private func privacyChip(trip: Trip, c: AppTheme.Colors) -> some View {
        let isPrivate = trip.isPrivate
        // Plain chip + onTapGesture instead of Button — Button + custom
        // background inside a ScrollView often loses its hit-region in
        // SwiftUI 17/18. The tap gesture on a contentShape'd chip is
        // dependable.
        DetailChipSurface {
            Image(systemName: isPrivate ? "lock.fill" : "globe")
                .font(.system(size: 10, weight: .semibold))
            Text(isPrivate
                 ? AppStrings.privacyOnlyMe(lang.language)
                 : AppStrings.privacyPublic(lang.language))
        }
        .contentShape(Capsule())
        .onTapGesture {
            Haptics.selection()
            // Both directions surface a one-shot confirm — going public has
            // privacy implications (visible to strangers), going private
            // discards reactions/comments accrued while public.
            if isPrivate {
                showPublishSheet = true
            } else {
                unpublishConfirm = true
            }
        }
    }

    private func applyVehicleChange(_ vehicleId: UUID?) {
        Haptics.selection()
        mapVM.tripManager.updateVehicle(for: tripId, vehicleId: vehicleId)
        trip = viewModel.tripDetail(id: tripId)
    }

    // MARK: - Description («Описание»)

    /// Free-text note for the trip (road conditions, detours, fuel stops) —
    /// editable by the owner via `NotesEditorView`. Persists through the same
    /// path as the title (`updateNotes` → repository + sync) and is already
    /// surfaced to others on the social trip view.
    @ViewBuilder
    private func notesSection(trip: Trip, c: AppTheme.Colors) -> some View {
        let notes = trip.tripDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(alignment: .leading, spacing: 10) {
            DetailSectionHeader(text: AppStrings.descriptionSection(lang.language))
            Button {
                Haptics.tap()
                editedNotes = trip.tripDescription ?? ""
                showNotesEditor = true
            } label: {
                if notes.isEmpty {
                    // Inviting empty-state CTA: an accent dashed-border button
                    // reads as "tap to add a description", not disabled
                    // metadata — so owners discover the feature. (Figma has no
                    // empty state for this section — existing CTA kept.)
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15, weight: .semibold))
                        Text(AppStrings.addNotesCTA(lang.language))
                            .font(.system(size: 14, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                AppTheme.accent.opacity(0.35),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
                    .contentShape(Rectangle())
                } else {
                    DetailDescriptionCard(text: notes, showsEditHint: true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Reactions

    /// Composite reactions block that picks the right surface for the current
    /// trip state — breakdown when there are reactions, a publish nudge for
    /// private trips, or a quiet "no reactions yet" line for public trips.
    @ViewBuilder
    private func reactionsArea(trip: Trip, c: AppTheme.Colors) -> some View {
        if !trip.isPrivate, !reactionEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.reactionsTitleN(lang.language, reactionEntries.count))
                reactionsCard(c)
            }
        } else if trip.isPrivate {
            publishNudgeCard(trip: trip, c: c)
        } else {
            // Public, zero reactions — quiet line, no CTA. Owner already
            // chose to share; spamming them with a "share more!" prompt
            // would be tone-deaf.
            HStack(spacing: 8) {
                Image(systemName: "face.dashed")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textTertiary)
                Text(AppStrings.noReactionsYet(lang.language))
                    .font(.system(size: 13))
                    .foregroundStyle(c.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    private func publishNudgeCard(trip: Trip, c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return Button {
            Haptics.tap()
            showPublishSheet = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 24, alignment: .center)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isRu ? "Опубликуйте, чтобы получить реакции" : "Publish to get reactions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.leading)
                    // Scope must match the publish sheet: publishing puts
                    // the trip into the PUBLIC feed (visible to everyone),
                    // not a followers-only feed.
                    Text(isRu
                         ? "Поездку увидят другие пользователи в общей ленте. Сейчас она только у Вас."
                         : "Other users will see this trip in the public feed. Right now it's just yours.")
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    /// «Реакции · N» — one card: breakdown chips row, then reactor rows
    /// (avatar / name / LVL / their emoji / chevron → profile).
    private func reactionsCard(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        // Group by CANONICAL key so legacy prod reactions (❤️ 🏎️ 🗺️) fold
        // into the drawn icon that replaced them instead of spawning a
        // twin chip next to it.
        let breakdown = Dictionary(grouping: reactionEntries, by: { ReactionEmoji.canonical($0.emoji) })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(breakdown, id: \.key) { emoji, count in
                        ReactionCountChip(emoji: emoji, count: count, style: .breakdown)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }

            ForEach(Array(reactionEntries.enumerated()), id: \.offset) { idx, entry in
                Rectangle()
                    .fill(c.border)
                    .frame(height: 1)
                    .padding(.leading, idx == 0 ? 0 : 14)
                reactionRow(entry, c: c, isRu: isRu)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
    }

    private func reactionRow(_ entry: SocialReactionEntry, c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            if let pushPath {
                pushPath.wrappedValue.cappedAppend(.profile(entry.user.id, entry.user))
            } else {
                selectedReactorAuthor = entry.user
            }
        } label: {
            HStack(spacing: 11) {
                Circle()
                    .fill(c.cardAlt)
                    .frame(width: 36, height: 36)
                    .overlay { Text(entry.user.avatarEmoji ?? "🚗").font(.system(size: 18)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.user.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text("LVL \(entry.user.profileLevel)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }
                Spacer()
                ReactionIconView(emoji: entry.emoji, size: 18)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    private func loadReactions() async {
        guard let t = trip, !t.isPrivate, auth.isSignedIn else { return }
        do {
            let res: SocialReactionsResponse = try await APIClient.shared.post(
                APIEndpoint.socialReactions, body: SocialUnreactRequest(tripId: t.id))
            await MainActor.run { reactionEntries = res.reactions }
        } catch {
            // Non-fatal — reactions section just stays hidden
        }
    }

    // MARK: - Publish flow

    /// Commit point of the publish sheet: optional description first (via
    /// the same validated notes path as the editor), then the privacy flip,
    /// then the SyncQueue watch that drives the «Публикуется…» toast.
    private func handlePublishConfirm(descriptionText: String) {
        let trimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptionRejected = false
        if trimmed != (trip?.tripDescription ?? "") {
            if trimmed.isEmpty {
                // The field is PREFILLED with the stored description, so an
                // emptied field is an explicit deletion — persist the clear
                // (same contract as commitNotesEdit), don't silently keep
                // the old text on the published trip.
                mapVM.tripManager.updateNotes(for: tripId, notes: "")
            } else if let err = ContentFilter.validate(trimmed, field: .tripNote, language: lang.language) {
                // Publish proceeds — only the invalid description is dropped.
                descriptionRejected = true
                toastItem = ToastItem(type: .error, message: err)
            } else {
                mapVM.tripManager.updateNotes(for: tripId, notes: trimmed)
            }
        }
        // The toast slot is single — a first-publish congratulation must not
        // replace the "your description was dropped" error.
        applyPrivacyChange(isPrivate: false, suppressSuccessToast: descriptionRejected)
        publishWatchActive = true
    }

    /// Performs the actual privacy mutation + side effects. Extracted from
    /// the privacy chip and the publish nudge so both code paths share
    /// the same notification + first-publish toast behavior, and so the
    /// publish-confirmation flow has a single commit point.
    private func applyPrivacyChange(isPrivate newValue: Bool, suppressSuccessToast: Bool = false) {
        let isRu = lang.language == .ru
        mapVM.tripManager.updatePrivacy(for: tripId, isPrivate: newValue)
        self.trip = viewModel.tripDetail(id: tripId)
        NotificationCenter.default.post(
            name: .tripPrivacyChanged,
            object: PrivacyChangePayload(tripId: tripId, isPrivate: newValue)
        )
        let wentPublic = newValue == false
        let firstPublishKey = "com.triptrack.firstPublishToastShown"
        if wentPublic && !suppressSuccessToast && !UserDefaults.standard.bool(forKey: firstPublishKey) {
            UserDefaults.standard.set(true, forKey: firstPublishKey)
            toastItem = ToastItem(
                type: .success,
                message: isRu
                    ? "Первая публичная поездка! Поездки с фото получают больше реакций"
                    : "Your first public trip! Trips with photos get more reactions")
        }
    }

    private func commitTitleEdit() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let err = ContentFilter.validate(trimmed, field: .tripTitle, language: lang.language) {
                toastItem = ToastItem(type: .error, message: err)
                cancelTitleEdit()
                return
            }
            mapVM.tripManager.updateTitle(for: tripId, title: trimmed)
            trip = viewModel.tripDetail(id: tripId)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditingTitle = false
        }
        isTitleFieldFocused = false
    }

    private func cancelTitleEdit() {
        editedTitle = originalTitle
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditingTitle = false
        }
        isTitleFieldFocused = false
    }

    private func commitNotesEdit() {
        let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Dismiss first so a validation toast isn't hidden behind the sheet.
        showNotesEditor = false
        if let err = ContentFilter.validate(trimmed, field: .tripNote, language: lang.language) {
            toastItem = ToastItem(type: .error, message: err)
            return
        }
        mapVM.tripManager.updateNotes(for: tripId, notes: trimmed)
        trip = viewModel.tripDetail(id: tripId)
    }

    /// Body of the "Publish trip?" confirmation sheet. Extracted so the
    /// sheet closure stays type-checker friendly.
    private var publishConfirmMessage: String {
        let isRu = lang.language == .ru
        let baseCopy: String
        if isRu {
            baseCopy = "Поездка появится в общей ленте — её увидят другие пользователи. Вы всегда сможете вернуть её в приватные."
        } else {
            baseCopy = "The trip will appear in the public feed — other users will see it. You can switch it back to private anytime."
        }
        if settings.cloudSyncEnabled { return baseCopy }
        let cloudOff: String
        if isRu {
            cloudOff = "\n\nОблачная синхронизация выключена — на сервер уйдёт только эта поездка, остальные останутся локально."
        } else {
            cloudOff = "\n\nCloud sync is off — only this trip will be sent to our server, every other trip stays on your device."
        }
        return baseCopy + cloudOff
    }

    // MARK: - Stats grid («Детали»)

    private func statsGrid(trip: Trip, c: AppTheme.Colors) -> some View {
        let l = lang.language
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
                value: TripDetailFormat.hoursMinutes(trip.duration),
                label: AppStrings.duration(l),
                color: AppTheme.accent,
                staggerIndex: 1
            )
            // Movement split surfaces "actually driving" vs "stationary
            // with engine on" — the only honest answer to the recurring
            // "why does my fuel feel off in traffic?" question. Hidden
            // when the trip has no usable track-point data.
            if (cachedDrivingTime + cachedStoppedTime) > 0 {
                DetailStatCard(
                    value: TripDetailFormat.hoursMinutes(cachedDrivingTime),
                    label: AppStrings.statMoving(l),
                    color: AppTheme.blue,
                    staggerIndex: 2
                )
                DetailStatCard(
                    value: TripDetailFormat.hoursMinutes(cachedStoppedTime),
                    label: AppStrings.statStops(l),
                    color: c.textSecondary,
                    staggerIndex: 3
                )
            }
            DetailStatCard(
                value: String(format: "%.0f", trip.displayAverageSpeedKmh(settings.avgSpeedMode)),
                unit: AppStrings.kmh(l),
                label: AppStrings.statAvg(l),
                color: AppTheme.blue,
                staggerIndex: 4
            )
            DetailStatCard(
                value: String(format: "%.0f", trip.maxSpeedKmh),
                unit: AppStrings.kmh(l),
                label: AppStrings.statMax(l),
                color: AppTheme.red,
                staggerIndex: 5
            )
            DetailStatCard(
                value: String(format: "+%.0f", cachedElevationGain),
                unit: AppStrings.m(l),
                label: AppStrings.elevationGain(l),
                color: AppTheme.green,
                staggerIndex: 6
            )
            DetailStatCard(
                value: String(format: "%.0f", cachedMaxAltitude),
                unit: AppStrings.m(l),
                label: AppStrings.maxAltitude(l),
                color: AppTheme.teal,
                staggerIndex: 7
            )

            // Fuel consumption (if vehicle configured)
            if let fuel = tripFuelInfo(trip) {
                DetailStatCard(
                    value: String(format: "~%.1f", fuel.volume),
                    unit: fuel.volUnit,
                    label: AppStrings.statFuel(l),
                    color: AppTheme.yellow,
                    staggerIndex: 8
                )
                DetailStatCard(
                    value: String(format: "~%.0f", fuel.cost),
                    unit: fuel.currency,
                    label: AppStrings.statCost(l),
                    color: AppTheme.accent,
                    staggerIndex: 9
                )
            }
        }
    }

    private func tripFuelInfo(_ trip: Trip) -> (volume: Double, cost: Double, volUnit: String, currency: String)? {
        let vehicle: Vehicle?
        if let vid = trip.vehicleId {
            vehicle = settings.vehicles.first { $0.id == vid }
        } else {
            vehicle = nil
        }
        guard let v = vehicle, v.cityConsumption > 0, trip.distanceKm > 0.1 else { return nil }
        let fuel = v.fuelCost(distanceKm: trip.distanceKm, avgSpeedKmh: trip.averageSpeedKmh)

        let volumeUnit = UserDefaults.standard.string(forKey: "volumeUnit") ?? "liters"
        let currency = trip.fuelCurrency ?? FuelCurrency.current
        let volShort = volumeUnit == "gallons" ? (lang.language == .ru ? "гал" : "gal") : (lang.language == .ru ? "л" : "L")

        let volume: Double
        if volumeUnit == "gallons" {
            volume = fuel.liters / 3.78541
        } else {
            volume = fuel.liters
        }

        return (volume, fuel.cost, volShort, currency)
    }

    // MARK: - Badges Section («Достижения поездки»)

    @ViewBuilder
    private func badgesSection(trip: Trip, c: AppTheme.Colors) -> some View {
        if !trip.earnedBadgeIds.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.tripAchievements(lang.language))
                TripAchievementsGrid(
                    badges: trip.earnedBadges,
                    language: lang.language,
                    onTap: { badge in selectedDetailBadge = badge }
                )
            }
        }
    }

    // MARK: - Photos Section

    private func photosSection(_ c: AppTheme.Colors) -> some View {
        let count = trip?.photos.count ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(text: count > 0
                    ? "\(AppStrings.photos(lang.language)) · \(count)"
                    : AppStrings.photos(lang.language))
                Spacer()
                Button { showPhotoPicker = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.accent)
                }
            }

            if let photos = trip?.photos, !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            AsyncThumbnailView(filename: photo.filename)
                                .frame(width: 74, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    selectedPhotoIndex = index
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photoToDelete = photo
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(3)
                                }
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .foregroundStyle(c.textTertiary)
                        Text(AppStrings.addPhotos(lang.language))
                            .font(.system(size: 12))
                            .foregroundStyle(c.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
                .surfaceCard(cornerRadius: 12)
                .onTapGesture { showPhotoPicker = true }
            }
        }
    }

    // MARK: - Helpers

    private static let dateTimeFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM, HH:mm"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM, HH:mm"
        return (ru, en)
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formattedDateFallback(_ date: Date) -> String {
        let fmts = Self.dateTimeFormatters
        return (lang.language == .ru ? fmts.ru : fmts.en).string(from: date)
    }

    private func timeRange(_ trip: Trip) -> String {
        let start = Self.timeFormatter.string(from: trip.startDate)
        if let end = trip.endDate {
            return "\(start) – \(Self.timeFormatter.string(from: end))"
        }
        return start
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 59
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }
}

// MARK: - Disable ScrollView Bounce

private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollBounceFinderView {
        ScrollBounceFinderView()
    }
    func updateUIView(_ uiView: ScrollBounceFinderView, context: Context) {}
}

private class ScrollBounceFinderView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        var current: UIView? = self
        while let parent = current?.superview {
            if let scrollView = parent as? UIScrollView {
                scrollView.bounces = false
                return
            }
            current = parent
        }
    }
}

/// Gates the local-state reactor `.navigationDestination` so SwiftUI only
/// sees it in contexts where we don't have a shared `pushPath` (i.e. the
/// legacy path — which no live flow hits today). When a parent provides a
/// `pushPath`, attaching this modifier would register a second destination
/// on the same NavigationStack and re-expose the depth-4 flash bug.
private struct TripDetailLocalReactorDestination: ViewModifier {
    @Binding var selectedReactorAuthor: SocialAuthor?
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(isPresented: Binding(
                get: { selectedReactorAuthor != nil },
                set: { if !$0 { selectedReactorAuthor = nil } }
            )) {
                if let author = selectedReactorAuthor {
                    PublicProfileView(accountId: author.id, preloaded: author)
                }
            }
        } else {
            content
        }
    }
}
