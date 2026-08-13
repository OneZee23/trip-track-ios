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
    /// The feed's copy, when we arrived from there. Used for a trip that is
    /// NOT in our own database — someone else's — which this screen renders
    /// through `Trip(social:)`. A trip of our own ignores it and reads the
    /// local record, which has the full track the server does not send.
    var social: SocialFeedTrip?
    /// The server's copy of someone else's trip as of the last pull-to-refresh.
    /// `social` is what we arrived holding and cannot be written back to (it is
    /// the caller's value); this is where a re-read lands.
    @State private var refreshedSocial: SocialFeedTrip?
    /// The freshest copy of the feed payload — the re-read when there has been
    /// one, otherwise the one we arrived with. Everything on screen that is fed
    /// by the feed's copy reads this, so a refresh moves all of it at once
    /// rather than leaving the author or the comment count a version behind.
    private var liveSocial: SocialFeedTrip? { refreshedSocial ?? social }
    /// This screen is drawn from the server's copy, not from a CoreData row —
    /// someone else's trip, or one of ours this device never recorded. It is
    /// exactly the case where the trip's own fields can change behind our back
    /// and the only case where re-reading them is worth a round trip.
    @State private var isRemoteBacked = false
    /// Someone else's drive, as something that can be PLAYED. The feed's copy
    /// of a trip carries only the preview polyline — a shape with no clock —
    /// so a viewer got a paced crawl with no timecode, no scrubbing and no
    /// speed while the owner of the same trip got all three. `/social/trip`
    /// serves the points; this is where they land.
    @State private var remoteTrack: [SocialTrackPoint] = []
    @State private var trip: Trip?
    /// Photos of someone else's trip live on the server, not in Documents.
    @State private var remotePhotos: [SocialTripPhoto] = []
    /// Ours to edit, delete, publish and photograph. Decided at load: a trip
    /// in our own database is ours whatever the token says, which is what
    /// keeps a cold start from opening our own trip read-only.
    @State private var isOwn = true
    /// Nothing came back from the server for someone else's trip. Neither flag
    /// means much alone — see `showLoadError`.
    /// These coordinates are a simplified preview, not a recorded track — see
    /// `buildCaches`.
    @State private var isPreviewRoute = false
    @State private var reactionsLoadFailed = false
    @State private var photosLoadFailed = false
    /// The reaction WE left on someone else's trip, EXACTLY as the server
    /// spells it. Legacy prod reactions (❤️ 🏎️ 🗺️) display as the icon that
    /// replaced them, but un-reacting has to send back the emoji the server
    /// actually stored — canonicalising it first made "take mine back" read as
    /// "leave a different one".
    @State private var myReaction: String?
    @State private var showReactionPicker = false
    /// The fullscreen cinema replay (canon 117:533).
    @State private var showPhotoPicker = false
    @State private var pickedImages: [UIImage] = []
    @State private var selectedPhotoIndex: Int?
    @State private var selectedDetailBadge: Badge?
    @State private var badgeLastEarnedDates: [String: Date] = [:]
    /// Fix 1: carries enough of a merged `OwnTripPhotosModel.Item` to delete
    /// either a local photo (existing CoreData path) or a remote-only one
    /// (a companion's upload — no local row to delete; goes through
    /// `/photos/delete`, see `deleteOwnPhoto`).
    @State private var photoToDelete: OwnTripPhotosModel.Item?
    @State private var toastItem: ToastItem?
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
    /// «…» popover on the poster header.
    @State private var showTripActions = false
    /// 0 while the map fills the hero, 1 once it has scrolled away — drives
    /// the top bar's glass→toolbar morph. Quantized in steps of 0.05 before
    /// it lands here (see `DetailScrollOffsetKey`'s handler).
    @State private var heroProgress: Double = 0
    /// Bumped by pull-to-refresh; the comments section reloads on change.
    @State private var refreshToken = 0
    /// Fix 3: confirmation for a companion leaving someone else's trip.
    @State private var showLeaveConfirm = false
    /// Fix 3: guards `leaveTrip()` against a double-tap firing two
    /// concurrent `/companions/remove` calls.
    @State private var isLeavingTrip = false
    /// «Редактировать поездку» — name, description, car, access in one sheet.
    @State private var showEditSheet = false
    /// Task 3's candidate picker, opened from `TripCompanionsSection`'s
    /// empty-state «Позвать» affordance via `openCompanionsPicker`. Once a
    /// roster exists, inviting happens inside `CompanionsRosterSheet`
    /// instead, which presents its own copy of this picker.
    @State private var showCompanionsPicker = false
    /// The roster screen behind the companions plaque.
    @State private var showCompanionsRoster = false
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
    /// Drives the «Прожить заново» CTA on the poster. Owned via
    /// `@StateObject` so the timer survives view re-renders and is
    /// stopped cleanly on `.onDisappear`. Since the fullscreen replay
    /// (117:533) shipped, this only runs for preview-only trips whose
    /// track carries no timestamps — the cinema screen needs them.
    /// Presents the fullscreen cinema replay (Figma 117:533). Timestamped
    /// own trips only; preview-only trips fall back to the inline crawl.
    @ObservedObject private var auth = AuthService.shared
    /// Reacting goes through the same store the feed uses, so a reaction left
    /// here shows on the card you came from.
    @ObservedObject private var socialFeed = SocialFeedStore.shared
    /// Task 6: same roster `companionsSection` already fetches for this
    /// trip — `canAddCompanionPhoto` reads it to decide whether the add-
    /// photo control shows on a foreign trip.
    @ObservedObject private var companionsStore = CompanionsStore.shared
    /// Task 6: owns upload-in-progress/error state for a companion's
    /// add-photo control. `@StateObject` because this view creates it.
    @StateObject private var companionPhotoUpload = CompanionPhotoUploadController()
    /// Sign-in prompt for the signed-out edge state (e.g. «keep public and
    /// sign out» leaves own public trips visible): the comments composer
    /// routes guests here instead of letting them post into USER_NOT_AUTH.
    @State private var signInPrompt: SignInPromptSheet.Action?
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

    /// Whether the poster's Share button should be offered at all. Pulled out
    /// as a pure, testable `static func` (`TripTrackTests
    /// /TripDetailSharePrivacyTests.swift`) rather than an inline `if` —
    /// the same reasoning as `CompanionsCardModel`/`WithMeSectionModel`: a
    /// visibility rule worth pinning with a test shouldn't only live inside
    /// a SwiftUI body. Your own trip can always be shared (public or not —
    /// sharing your own private trip is how you'd publish + share in one
    /// motion). Someone else's trip can be shared only if it's public;
    /// `SocialService.share` refuses a non-owner sharing a private trip
    /// server-side (`TripNotPublic`), so offering the button for that case
    /// is offering an action that can only fail.
    static func canOfferShare(isOwn: Bool, isPrivate: Bool) -> Bool {
        isOwn || !isPrivate
    }

    /// The scroll view and everything attached to it.
    ///
    /// Split from `body` for a hard reason, not tidiness: with the refresh
    /// modifier added, the single expression in `body` grew past what the
    /// Swift type-checker will solve in reasonable time and the build failed
    /// outright.
    ///
    /// Pull to refresh is here. Everything on this screen that somebody else
    /// can change — a companion accepting, a reaction, a comment, a photo the
    /// owner added — used to update only on entry, so the way to see it was
    /// to leave the screen and come back. The gesture is made OF the
    /// over-scroll bounce, which is why the bounce suppressor that used to be
    /// attached here is gone; the dark filler above the map (the reason
    /// bounce was suppressed) does that job on its own.
    private func detailScroll(trip: Trip, c: AppTheme.Colors) -> some View {
        ScrollView { scrollContent(trip: trip, c: c) }
            .coordinateSpace(name: "detailScroll")
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refreshDetail() }
    }

    /// The scrollable body, lifted out of `body`.
    ///
    /// Not a style choice: with the refresh modifier added, the single
    /// expression in `body` grew past what the type-checker will solve in
    /// reasonable time and the build failed outright. Splitting it is the
    /// documented fix.
    @ViewBuilder
    private func scrollContent(trip: Trip, c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            heroSection(trip: trip)
                .frame(height: posterHeight)
                // How far the map has scrolled away, for the top bar's
                // glass→toolbar morph. Read from a `Color.clear` in the
                // BACKGROUND, never from inside the map's own subtree: this
                // fires on every frame of a scroll, and the map is an
                // `MKMapView` with a display link running.
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: DetailScrollOffsetKey.self,
                            value: geo.frame(in: .named("detailScroll")).minY
                        )
                    }
                }

            // What the route's colours mean — a line of type in the seam
            // under the map, not a control on it.
            if cachedCoordinates.count > 1, !cachedSpeeds.isEmpty {
                RouteSpeedKeyStrip(language: lang.language)
            }

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

    /// Pull-to-refresh: re-ask the server for everything on this screen that
    /// somebody ELSE can change.
    ///
    /// Deliberately no local reload — trips, photos on disk and the track
    /// itself come from CoreData and cannot go stale behind your back. What
    /// can: the companion roster (someone accepted or declined), reactions,
    /// the discussion, and photos a companion added to your trip.
    ///
    /// A foreign trip's OWN fields — its title, its notes, its privacy — are
    /// the exception, and they are re-read from `/social/trip`: the screen's
    /// only copy of them is the feed payload it was opened with, and the
    /// author can change any of it while it is on screen.
    private func refreshDetail() async {
        await withTaskGroup(of: Void.self) { group in
            if isRemoteBacked {
                group.addTask { @MainActor in await refreshRemoteTrip() }
            }
            if companionsGate == .allowed {
                group.addTask { @MainActor in
                    _ = try? await CompanionsStore.shared.list(
                        tripId: tripId, treatTripNotFoundAsEmpty: isOwn)
                }
            }
            if !(trip?.isPrivate ?? true) || !isOwn {
                group.addTask { @MainActor in await loadReactions() }
            }
            if auth.isSignedIn, trip?.isOnServer == true || !isOwn {
                group.addTask { @MainActor in await loadRemotePhotos() }
            }
            // The comments thread owns its own store, so it is refreshed by
            // bumping the token its load task keys on rather than from here.
            refreshToken &+= 1
        }
    }

    /// What the pinned bar says once the map has scrolled away — the same
    /// answer `titleBlock` gives, so the bar and the heading under it can't
    /// name the trip differently.
    private func barTitle(for trip: Trip) -> String {
        let trimmed = trip.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = (trimmed.map { !$0.isEmpty } ?? false)
            && !TripAutoTitle.isAuto(trimmed, startDate: trip.startDate)
        if named { return trip.title ?? "" }
        if let region = RegionDisplay.localized(trip.region, language: lang.language),
           !region.isEmpty { return region }
        return formattedDateFallback(trip.startDate)
    }

    /// Whose trip this is — shown only on someone else's, where the answer is
    /// not obvious and is the first thing you want to know. Tapping it opens
    /// their profile, the same as tapping the author on a feed card.
    @ViewBuilder
    private var authorPill: some View {
        if let author = liveSocial?.author, !isOwn {
            Button {
                Haptics.tap()
                if let pushPath {
                    pushPath.wrappedValue.cappedAppend(.profile(author.id, author))
                } else {
                    selectedReactorAuthor = author
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: 0xF4/255, green: 0xF2/255, blue: 0xEE/255))
                        .frame(width: 28, height: 28)
                        .overlay { Text(author.avatarEmoji ?? "🚗").font(.system(size: 16)) }
                    Text(author.displayName ?? (lang.language == .ru ? "Без имени" : "No name"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // App-wide LVL convention — uppercase in both languages.
                    Text("LVL \(author.profileLevel)")
                        .font(.custom("PressStart2P-Regular", size: 7))
                        .foregroundStyle(Color(red: 0xD9/255, green: 0xDB/255, blue: 0xE5/255).opacity(0.7))
                }
                .padding(.leading, 5)
                .padding(.trailing, 12)
                .padding(.vertical, 5)
                .background(.black.opacity(0.42), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail_author_pill")
        }
    }

    /// Edit · publish/hide · delete, in that order: the two reversible ones
    /// first, the irreversible one last and in red.
    ///
    /// The popover has to be dismissed before anything is presented from it —
    /// UIKit drops a sheet requested while a popover is still on screen — hence
    /// the short sleep each item shares.
    private func ownerActions(trip: Trip) -> [ActionPopoverList.Item] {
        func present(_ work: @escaping @MainActor () -> Void) {
            showTripActions = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                work()
            }
        }
        return [
            .init(
                title: AppStrings.edit(lang.language), systemImage: "pencil",
                accessibilityId: "detail_action_edit"
            ) {
                present { showEditSheet = true }
            },
            .init(
                title: trip.isPrivate
                    ? AppStrings.publishAction(lang.language)
                    : AppStrings.makePrivateAction(lang.language),
                systemImage: trip.isPrivate ? "globe" : "lock",
                accessibilityId: "detail_action_publish"
            ) {
                present {
                    Haptics.selection()
                    // Publishing puts the trip on a server that has no idea who
                    // we are until we sign in. Offering it to a signed-out
                    // owner produced a confirmation, a spinner and a failure.
                    if trip.isPrivate { requestPublish() } else { requestUnpublish() }
                }
            },
            // Last in the list, and the only destructive entry. It lived as a
            // red button at the foot of the screen for a while; a screen that
            // ENDS on «delete» reads as if that were the conclusion of looking
            // back at a trip.
            .init(
                title: AppStrings.deleteTrip(lang.language),
                systemImage: "trash",
                isDestructive: true,
                accessibilityId: "detail_action_delete"
            ) {
                present { showDeleteConfirm = true }
            },
        ]
    }

    /// Fix 3: whether `myAccountId` is an ACCEPTED companion on a trip it
    /// doesn't own — the only case that earns the «…» leave affordance.
    /// Pulled out as a pure, testable `static func`
    /// (`TripTrackTests/TripDetailSharePrivacyTests.swift`) same reasoning
    /// as `canOfferShare` above: a visibility rule worth pinning with a
    /// test shouldn't only live inside a SwiftUI body. An own trip never
    /// qualifies (an owner isn't a companion of their own trip), and a
    /// signed-out viewer (`myAccountId == nil`) can't be matched against
    /// any roster row.
    static func companionCanLeave(isOwn: Bool, myAccountId: UUID?, companions: [CompanionItem]) -> Bool {
        guard !isOwn, let myAccountId else { return false }
        return companions.contains { $0.accountId == myAccountId && $0.status == .accepted }
    }

    /// Whether the SIGNED-IN viewer is an accepted companion on THIS trip.
    /// Reads the same roster `TripCompanionsSection` already fetches
    /// (`companionsStore.companionsByTrip[tripId]`) rather than issuing a
    /// separate call.
    private var isAcceptedCompanion: Bool {
        TripDetailView.companionCanLeave(
            isOwn: isOwn, myAccountId: TokenStore.shared.accountId,
            companions: companionsStore.companionsByTrip[tripId] ?? [])
    }

    /// Fix 3: the only action a companion has on someone else's trip —
    /// removing themselves (design doc §2.4: "убрать себя из поездки").
    /// Same popover-then-sleep-then-present shape as `ownerActions`, so the
    /// confirmation dialog it triggers isn't dropped by UIKit while the
    /// popover is still dismissing.
    private func companionActions() -> [ActionPopoverList.Item] {
        [
            .init(
                title: AppStrings.companionsLeaveTrip(lang.language),
                systemImage: "rectangle.portrait.and.arrow.right",
                isDestructive: true,
                accessibilityId: "detail_action_leave"
            ) {
                showTripActions = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 260_000_000)
                    showLeaveConfirm = true
                }
            },
        ]
    }

    /// Fix 3: a companion removing themselves from someone else's trip —
    /// `/companions/remove` with the viewer's own account id, which the
    /// server already permits (`CompanionsService.remove`'s `isSelf`
    /// branch). Dismisses the screen on success: the viewer just lost
    /// access to a trip that, if it's private, they can no longer reload.
    private func leaveTrip() {
        guard let myId = TokenStore.shared.accountId, !isLeavingTrip else { return }
        isLeavingTrip = true
        Haptics.action()
        Task {
            do {
                try await companionsStore.remove(tripId: tripId, accountId: myId)
                dismiss()
            } catch {
                isLeavingTrip = false
                toastItem = ToastItem(type: .error, message: AppStrings.companionsLeaveFailed(lang.language))
            }
        }
    }

    /// Someone else's trip whose data never arrived: no route to draw, and
    /// both server calls failed. Our own trips are never in this state — they
    /// come from our own database, and a missing polyline there just means an
    /// old trip.
    private var showLoadError: Bool {
        !isOwn && trip?.previewPolyline == nil && reactionsLoadFailed && photosLoadFailed
    }

    /// «Не удалось загрузить поездку» (canon 519:158). Replaces the whole
    /// screen: a poster with no route, empty stats and no photos is not a trip,
    /// it is a failure pretending to be one.
    private func loadErrorState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            HStack {
                PosterCircleButton(
                    systemImage: "chevron.left",
                    accessibilityLabelText: AppStrings.back(lang.language)
                ) { dismiss() }
                Spacer()
                Text(AppStrings.tripTitle(lang.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.text)
                Spacer()
                // Balances the chevron so the title sits centred.
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, safeAreaTop + 8)

            Spacer()

            Circle()
                .strokeBorder(c.cardAlt, lineWidth: 10)
                .frame(width: 108, height: 108)
                .padding(.bottom, 26)

            Text(AppStrings.tripLoadFailed(lang.language))
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(AppStrings.tripLoadFailedBody(lang.language))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)

            Button {
                Haptics.tap()
                Task {
                    reactionsLoadFailed = false
                    photosLoadFailed = false
                    await loadRemotePhotos()
                    await loadReactions()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .bold))
                    Text(AppStrings.tryAgain(lang.language))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule().fill(AppTheme.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .accessibilityIdentifier("trip_load_retry")

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.bg)
        .ignoresSafeArea()
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack(alignment: .topLeading) {
            if showLoadError {
                loadErrorState(c)
            } else if let trip {
                ScrollViewReader { proxy in
                detailScroll(trip: trip, c: c)
                .task { await scrollToCommentsIfRequested(proxy) }
                }

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
        .onPreferenceChange(DetailScrollOffsetKey.self) { minY in
            // Quantized before it reaches state: at full precision every
            // scrolled point re-renders a body that hosts an MKMapView.
            let span = max(1, posterHeight - safeAreaTop - 52)
            let raw = min(max(-minY / span, 0), 1)
            let stepped = (raw * 20).rounded() / 20
            if stepped != heroProgress { heroProgress = stepped }
        }
        // The one top bar. Pinned to the screen, not to the map, so «Назад»
        // survives scrolling; declared before `PublishStatusOverlay` so the
        // publish toast still stacks above it.
        .overlay(alignment: .top) {
            if let trip, !showLoadError {
                TripDetailTopBar(
                    progress: heroProgress,
                    topInset: safeAreaTop,
                    title: barTitle(for: trip),
                    language: lang.language,
                    showShare: TripDetailView.canOfferShare(
                        isOwn: isOwn, isPrivate: trip.isPrivate),
                    shareDisabled: isGeneratingShare,
                    showActions: isOwn || isAcceptedCompanion,
                    actionsPresented: $showTripActions,
                    onBack: { dismiss() },
                    onShare: { Task { await openStoryShare(for: trip) } },
                    pill: { authorPill },
                    popover: {
                        ActionPopoverList(
                            items: isOwn ? ownerActions(trip: trip) : companionActions())
                    }
                )
            }
        }
        .background(c.bg)
        // Tap anywhere to put the keyboard away; sending a comment
        // deliberately does NOT — that call stays the user's.
        .dismissesKeyboardOnTapAnywhere()
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
            // Replay lives HERE now, not on a screen of its own: you open
            // the map, press play, and watch the drive on the map you were
            // already looking at. Timestamps decide whether it can — a
            // preview route without per-point times gets the plain map.
            // The route is drawn at full resolution; the REPLAY walks the
            // downsampled series (`replayInput`, ≤300 points). The trail
            // overlay is rebuilt every time the playhead passes a waypoint,
            // so handing it a raw ten-hour track would mean tens of thousands
            // of rebuilds of an ever-growing polyline — the exact reason this
            // cap was written in the first place.
            FullscreenMapSheet(
                coordinates: cachedCoordinates,
                speeds: cachedSpeeds,
                timestamps: replayInput.timestamps,
                replayCoordinates: replayInput.coords,
                replaySpeeds: replayInput.speeds,
                distanceMeters: trip?.distance ?? 0,
                isOwnTrip: isOwn,
                fogCutoffDate: trip?.endDate,
                showsFog: isOwn,
                treatAsPreview: isPreviewRoute,
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
        // Fix 3: a companion leaving someone else's trip.
        .confirmationDialog(
            AppStrings.companionsLeaveConfirmTitle(lang.language),
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button(AppStrings.companionsLeaveTrip(lang.language), role: .destructive) { leaveTrip() }
            Button(AppStrings.cancel(lang.language), role: .cancel) {}
        }
        .task(id: tripId) {
            if trip == nil {
                if let local = viewModel.tripDetail(id: tripId) {
                    isOwn = true
                    trip = local
                    buildCaches(for: local)
                    // Fix 1: a companion's photo never gets a local CoreData
                    // row on the owner's device — `/sync/pull` deliberately
                    // excludes photos on trips the account doesn't own (by
                    // design: a foreign trip must never gain a local row).
                    // The owner's own photo section has to read the server
                    // roster too, then union it with `trip.photos` by id
                    // (`OwnTripPhotosModel.merge`) — otherwise the entire
                    // point of the feature, someone else adding photos to
                    // YOUR trip, stays invisible to you. Gated exactly like
                    // `canQueryCompanions`: a trip that was never published
                    // cannot have a companion on it at all (an invite
                    // targets a real server trip id), so asking would just
                    // be a guaranteed `TRIP_NOT_FOUND` round trip for the
                    // overwhelmingly common (cloud sync OFF) case.
                    if auth.isSignedIn, local.isOnServer {
                        await loadRemotePhotos()
                    }
                } else if social == nil {
                    // Nothing to show: no local row and no feed payload. Rather
                    // than a skeleton that shimmers forever with no way back,
                    // treat it as what it is — a trip we cannot load.
                    reactionsLoadFailed = true
                    photosLoadFailed = true
                    isOwn = false
                } else if let social {
                    // Someone else's trip, or one of ours that this device has
                    // never recorded. Everything below works off a `Trip`, so
                    // the feed's copy becomes one.
                    isOwn = social.author.id == TokenStore.shared.accountId
                    isRemoteBacked = true
                    apply(social)
                    // The feed handed us everything except the drive itself.
                    async let track: Void = refreshRemoteTrip()
                    await loadRemotePhotos()
                    await track
                }
                // Earned-on dates come from OUR trip history, so they mean
                // nothing on somebody else's badge — and printing our date
                // under their achievement is worse than printing none.
                if isOwn {
                    badgeLastEarnedDates = BadgeManager.lastEarnedDates(
                        for: trip?.earnedBadgeIds ?? [],
                        using: mapVM.tripManager
                    )
                }
            }
            await loadReactions()
        }
        .onChange(of: trip?.isPrivate) { _, newValue in
            if newValue == false { Task { await loadReactions() } }
            else { reactionEntries = [] }
        }
        .sheet(isPresented: $showPhotoPicker) {
            TripPhotoPicker { images in
                pickedImages = images
            }
            .environmentObject(lang)
            .preferredColorScheme(themeManager.preferredColorScheme)
            // The canon draws a grab handle (117:602). Without one the sheet
            // looked like a pushed screen, and the only way out was «Отмена» —
            // people swiped anyway and could not tell whether it was allowed.
            .presentationDragIndicator(.visible)
        }
        .onChange(of: pickedImages) { newImages in
            guard !newImages.isEmpty else { return }
            // Owner path is UNCHANGED — still writes straight to CoreData via
            // TripManager. A companion has no local TripEntity for this trip
            // (and must never get one), so that path is impossible for them;
            // `isOwn` is exactly the flag that already tells the two apart
            // everywhere else on this screen.
            if isOwn {
                var added = 0
                for image in newImages {
                    if let photo = mapVM.tripManager.addPhoto(to: tripId, image: image) {
                        trip?.photos.append(photo)
                        added += 1
                    }
                }
                pickedImages = []
                // Say it landed. The picker shows the whole library — the
                // photos you just added are in it too — so without this the
                // only difference between "added two" and "changed nothing"
                // was counting tiles in the strip.
                if added > 0 {
                    toastItem = ToastItem(
                        type: .success,
                        message: AppStrings.photosAdded(added, lang.language)
                    )
                }
            } else {
                let images = newImages
                pickedImages = []
                Task { await uploadCompanionPhotos(images) }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoIndex != nil },
            set: { if !$0 { selectedPhotoIndex = nil } }
        )) {
            if let index = selectedPhotoIndex {
                // Ours from disk, someone else's from the server, and (Fix 1)
                // a companion's remote-only upload on OUR OWN trip — one
                // viewer either way, which is what the canon draws
                // (117:1086 and its social twin 117:1589).
                let pages: [PhotoFullScreenView.Page] = isOwn
                    ? ownPhotoItems.map { item in
                        let source: FullScreenPhotoSource
                        switch item.source {
                        case .local(let filename), .missing(let filename):
                            // A missing row goes in as the local page it is —
                            // the viewer's own failure state (broken-photo
                            // glyph) is exactly the right screen, and it is
                            // the one place that offers the bin, so the user
                            // can retire the row themselves.
                            source = .local(filename: filename)
                        case .remote(let thumbnailURL, let originalURL):
                            source = .remote(url: originalURL ?? thumbnailURL)
                        }
                        return .init(id: item.id, source: source, timestamp: item.timestamp)
                    }
                    : remotePhotos.map {
                        .init(
                            id: $0.id,
                            source: .remote(url: $0.originalUrl ?? $0.thumbnailUrl),
                            timestamp: $0.timestamp
                        )
                    }
                PhotoFullScreenView(
                    pages: pages,
                    initialIndex: index,
                    region: trip?.region,
                    language: lang.language,
                    // Deleting was only ever a long press on a thumbnail —
                    // an affordance with nothing on screen to suggest it,
                    // which read as "adding is allowed, deleting isn't".
                    // The viewer is where you actually decide a picture
                    // isn't worth keeping, so the bin lives here too. Own
                    // trips only: on someone else's, deleting isn't ours to
                    // offer (a companion's own upload included — the server
                    // authorises the TRIP owner).
                    onDelete: isOwn ? { pageId in
                        guard let item = ownPhotoItems.first(where: { $0.id == pageId })
                        else { return }
                        selectedPhotoIndex = nil
                        deleteOwnPhoto(item)
                    } : nil,
                    onDismiss: { selectedPhotoIndex = nil }
                )
            }
        }
        .overlay {
            if showReactionPicker {
                ReactionPickerOverlay(
                    currentReaction: myReaction,
                    onPick: { emoji in
                        showReactionPicker = false
                        react(with: emoji)
                    },
                    onDismiss: { showReactionPicker = false }
                )
            }
        }
        .overlay {
            if let badge = selectedDetailBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: true,
                    language: lang.language,
                    colorScheme: scheme,
                    // Our own tally, so it is gated exactly like the earned-on
                    // date below — «получен 3 раза» under someone else's badge
                    // would be counting our drives on their card.
                    earnCount: isOwn && badge.isRepeatable
                        ? BadgeManager.earnCount(for: badge.id)
                        : nil,
                    lastEarnedDate: badgeLastEarnedDates[badge.id],
                    // «47.3 км» under «проедьте 42.2 км». The card has drawn
                    // this line since it was written, but no call site ever
                    // passed a value — and this is one of the two screens that
                    // holds the earning trip, so it can.
                    recordValue: trip.flatMap {
                        badge.recordValue(for: $0, language: lang.language)
                    },
                    // The trip is what earned it, and it is the trip we are
                    // standing on — so the card can name it.
                    earnedOnTripTitle: trip?.title,
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
                if let item = photoToDelete {
                    Haptics.action()
                    deleteOwnPhoto(item)
                }
                photoToDelete = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { storyShare != nil },
            set: { if !$0 { storyShare = nil } }
        )) {
            if let share = storyShare {
                // The sheet sizes its own detent from its measured content.
                StoryShareSheet(data: share.data, shareUrl: share.url)
                    .presentationDragIndicator(.visible)
                    .environmentObject(lang)
                    // Sheets are separate presentations — the app-root
                    // preferredColorScheme does not reach them.
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
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
        .sheet(isPresented: $showEditSheet) {
            if let t = trip {
                TripEditSheet(
                    trip: t,
                    vehicles: settings.vehicles,
                    onSave: { newTitle, newNotes, newVehicleId, newIsPrivate in
                        let saved = applyEdits(
                            title: newTitle, notes: newNotes,
                            vehicleId: newVehicleId, to: t
                        )
                        // Access last, and only once the text is safely written:
                        // publishing and hiding both raise a confirmation, and
                        // this screen owns them. Asking BEFORE saving is what
                        // used to throw away everything the user had typed.
                        guard saved, newIsPrivate != t.isPrivate else { return }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 260_000_000)
                            if newIsPrivate { requestUnpublish() } else { requestPublish() }
                        }
                    }
                )
                .environmentObject(lang)
                .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showCompanionsPicker) {
            if let t = trip {
                CompanionsPickerSheet(tripId: t.id)
                    .environmentObject(lang)
                    .environmentObject(themeManager)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .sheet(isPresented: $showCompanionsRoster) {
            if let t = trip {
                CompanionsRosterSheet(
                    tripId: t.id, isOwn: isOwn, cachedCompanions: t.companions
                )
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
            }
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

            // Distance travelled at every point. Computed from the coordinates
            // directly rather than through CLLocation objects — a ten-hour
            // trip is tens of thousands of points, and that many allocations
            // are felt as a stutter when the screen opens.
            var cumulativeKm = [Double](repeating: 0, count: pts.count)
            var running = 0.0
            for i in 1..<pts.count {
                running += GeometryUtils.haversineDistance(
                    cachedCoordinates[i - 1], cachedCoordinates[i]
                )
                cumulativeKm[i] = running / 1000
            }
            let totalKm = running / 1000

            let altitudes = pts.map(\.altitude)
            let speedsKmh = pts.map { max(0, $0.speed * 3.6) }
            // The timestamps ride along so a touch on either chart can say
            // when that kilometre happened.
            let elevBuckets = ChartSeriesBuilder.buckets(
                cumulativeKm: cumulativeKm, values: altitudes,
                dates: cachedTimestamps, totalKm: totalKm
            )
            let speedBuckets = ChartSeriesBuilder.buckets(
                cumulativeKm: cumulativeKm, values: speedsKmh,
                dates: cachedTimestamps, totalKm: totalKm
            )
            let elev = elevBuckets.enumerated().map { i, b in
                DetailChartPoint(id: i, x: b.km, y: b.mean, date: b.date, yMin: b.low, yMax: b.high)
            }
            let spd = speedBuckets.enumerated().map { i, b in
                DetailChartPoint(id: i, x: b.km, y: b.mean, date: b.date, yMin: b.low, yMax: b.high)
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
            // Remember WHERE these coordinates came from. A preview polyline is
            // RDP-simplified, so on a motorway its points sit kilometres apart —
            // and RouteMapView's 1km gap-splitting reads every one of those as a
            // break in the track, drops each singleton segment, and ends up with
            // nothing to draw and no bounds to zoom to. A stranger's intercity
            // trip opened onto a world map with two pins on it.
            isPreviewRoute = true
        }
    }

    /// Numbers a remote trip carries as fields rather than as track points.
    ///
    /// `buildCaches` derives these by walking the track; the server sends the
    /// answers instead. Without this the movement split, the elevation gain and
    /// the peak altitude simply vanished from someone else's trip — the four
    /// tiles the canon puts between «время» and «топливо».
    /// The replay canvas is documented as taking at most ~300 points and it
    /// repaints at display-link rate; the raw track of a long drive is tens of
    /// thousands. Computed here rather than inline in the presentation, which
    /// the type-checker could not chew through.
    private var replayInput: (
        coords: [CLLocationCoordinate2D],
        speeds: [Double],
        timestamps: [Date]
    ) {
        // Someone else's trip has no local track at all, so its playable
        // series is whatever the server sent. Already sampled there; sampled
        // again here only if a future server ever raises its own cap.
        if !remoteTrack.isEmpty {
            return Self.downsampledForReplay(
                coords: remoteTrack.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                },
                speeds: remoteTrack.map(\.speed),
                timestamps: remoteTrack.map(\.t)
            )
        }
        return Self.downsampledForReplay(
            coords: cachedCoordinates,
            speeds: cachedSpeeds,
            timestamps: cachedTimestamps
        )
    }

    /// Every Nth point, index-aligned across all three arrays.
    private static func downsampledForReplay(
        coords: [CLLocationCoordinate2D],
        speeds: [Double],
        timestamps: [Date]
    ) -> (coords: [CLLocationCoordinate2D], speeds: [Double], timestamps: [Date]) {
        let limit = 300
        guard coords.count > limit else { return (coords, speeds, timestamps) }
        let step = max(1, coords.count / limit)
        var idx = Array(stride(from: 0, to: coords.count, by: step))
        if idx.last != coords.count - 1 { idx.append(coords.count - 1) }
        return (
            idx.map { coords[$0] },
            speeds.count == coords.count ? idx.map { speeds[$0] } : [],
            timestamps.count == coords.count ? idx.map { timestamps[$0] } : []
        )
    }

    private func seedCaches(from social: SocialFeedTrip) {
        cachedDrivingTime = Double(social.drivingTime ?? 0)
        cachedStoppedTime = Double(social.stoppedTime ?? 0)
        cachedElevationGain = social.elevation ?? 0
        cachedMaxAltitude = social.maxAltitude ?? 0
    }

    /// Draws the screen from a copy of the feed's payload — on arrival, and
    /// again after a refresh. One function for both so a re-read can never
    /// update half of what the first render set.
    private func apply(_ item: SocialFeedTrip) {
        refreshedSocial = item
        myReaction = item.myReaction
        let adapted = Trip(social: item)
        trip = adapted
        buildCaches(for: adapted)
        seedCaches(from: item)
    }

    /// Re-reads someone else's trip from the server.
    ///
    /// The owner can rename it, rewrite its notes or make it private while we
    /// are looking at it, and none of that reaches a screen whose only copy is
    /// the feed payload it was opened with. `/social/trip` is the feed's own
    /// item shape for a single id, behind the feed's own visibility gate.
    ///
    /// Failure is deliberately silent and total: on a refused or unreachable
    /// re-read the screen keeps showing what it already had. A trip made
    /// private mid-view is a `TRIP_NOT_PUBLIC` here, and tearing the screen
    /// down under someone in the middle of reading is a worse answer than
    /// letting them finish with the copy they arrived holding — the next
    /// opening of it, from a feed that no longer lists it, is where that
    /// belongs.
    private func refreshRemoteTrip() async {
        guard let res: SocialTripResponse = try? await APIClient.shared.post(
            APIEndpoint.socialTrip,
            body: SocialTripRequest(tripId: tripId, includeTrack: true),
            requiresAuth: AuthService.shared.isSignedIn
        ) else { return }
        if let track = res.track { remoteTrack = track }
        // Nothing changed is the ordinary case for a refresh, and applying an
        // identical copy is not free: it rebuilds the trip, re-decodes the
        // route and hands the map a new object to fit itself to. Comparing
        // first keeps a pull that finds no news from visibly redrawing.
        guard res.item != liveSocial else { return }
        apply(res.item)
    }

    private func loadRemotePhotos() async {
        do {
            let res: SocialTripPhotosResponse = try await APIClient.shared.post(
                APIEndpoint.socialTripPhotos,
                body: SocialTripPhotosRequest(tripId: tripId),
                requiresAuth: AuthService.shared.isSignedIn
            )
            remotePhotos = res.photos
            photosLoadFailed = false
        } catch {
            // Non-fatal: the strip stays hidden rather than the screen failing.
            remotePhotos = []
            photosLoadFailed = true
        }
    }

    /// Task 6: a companion's pick goes straight to the server —
    /// `CompanionPhotoUploadController` never touches `remotePhotos`
    /// itself, so this function is the ONLY place that can change what the
    /// strip shows, and it only ever does so by reloading from source of
    /// truth (never an optimistic local append). `succeededAny` is exactly
    /// "at least one image landed on the server" — on a wholly-failed pick
    /// this stays `false`, `loadRemotePhotos()` never runs, and the strip
    /// is left exactly as it was: no phantom thumbnail, no half-state.
    ///
    /// Review fix: the reload that follows a successful upload is its OWN
    /// network call and can itself fail — previously that meant
    /// `loadRemotePhotos()`'s own failure path (`remotePhotos = []`) wiped
    /// out photos that were already on screen before this pick, with no
    /// message at all. Captures the strip's contents beforehand and
    /// restores them if the reload comes back failed, so a transient
    /// second-call blip never blanks anything that was already visible.
    private func uploadCompanionPhotos(_ images: [UIImage]) async {
        let succeededAny = await companionPhotoUpload.upload(tripId: tripId, images: images)

        var reloadFailed = false
        if succeededAny {
            let photosBeforeReload = remotePhotos
            await loadRemotePhotos()
            if photosLoadFailed {
                // `loadRemotePhotos()` just set `remotePhotos = []` — that's
                // correct for ITS OWN failure path (nothing has ever loaded
                // yet), but wrong here: we know good data existed a moment
                // ago. `resolvedPhotosAfterReload` is the pure, tested rule;
                // also un-flip `photosLoadFailed` so it doesn't drift out of
                // sync with `remotePhotos` for any other reader of that flag
                // on this screen.
                remotePhotos = CompanionPhotoUploadModel.resolvedPhotosAfterReload(
                    previous: photosBeforeReload, reloaded: remotePhotos, reloadFailed: true)
                photosLoadFailed = false
                reloadFailed = true
            }
        }

        if reloadFailed {
            // The upload itself may have fully succeeded — this toast is
            // about the SEPARATE refresh call, not the upload, so it must
            // never be conflated with (or overwritten by) the batch outcome
            // toast below.
            toastItem = ToastItem(type: .error, message: AppStrings.companionPhotoReloadFailed(lang.language))
            return
        }

        // Degraded/partial are NOT the same as an outright failure — the
        // photo(s) ARE on the trip, just not all at full quality or not
        // all of them at all — so each gets its own distinct wording,
        // never collapsed into a flat "couldn't upload".
        switch companionPhotoUpload.lastBatchOutcome {
        case .allFull, nil:
            break
        case .allSucceededSomeDegraded:
            toastItem = ToastItem(type: .info, message: AppStrings.companionPhotoUploadDegraded(lang.language))
        case .partial(let succeeded, let total):
            toastItem = ToastItem(type: .info, message: AppStrings.companionPhotoUploadPartial(succeeded, total, lang.language))
        case .allFailed:
            toastItem = ToastItem(type: .error, message: AppStrings.companionPhotoUploadFailed(lang.language))
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
    // The Figma poster/cinema treatment now lives in the fullscreen map.

    @ViewBuilder
    private func heroSection(trip: Trip) -> some View {
        let c = AppTheme.colors(for: scheme)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if cachedCoordinates.count > 1 {
                    RouteMapView(
                        coordinates: cachedCoordinates,
                        speeds: cachedSpeeds,
                        // Deliberately NOT interactive, and the expand button
                        // below is why: panning happens fullscreen. While this
                        // map took drags it also ate the only one that could
                        // ever start a pull to refresh — the scroll sits at the
                        // top exactly where this map is, so the gesture had
                        // nowhere to begin and the refresh looked broken.
                        isInteractive: false,
                        // Our own territory fog has no business over someone
                        // else's route.
                        fogCutoffDate: trip.endDate,
                        showsFog: isOwn,
                        treatAsPreview: isPreviewRoute,
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

            // The map's only control. «Прожить заново» moved into the panel
            // below (it was a wide white pill colliding with this button in
            // the same corner) and the speed legend became a strip under the
            // map, so from the bar down to the Apple attribution the route
            // is now uninterrupted.
            if cachedCoordinates.count > 1 {
                MapChromeButton(
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    accessibilityLabelText: AppStrings.openRouteMapA11y(lang.language)
                ) {
                    Haptics.tap()
                    isMapFullscreen = true
                }
                .accessibilityIdentifier("detail_map_expand")
                .padding(.trailing, 8)
                .padding(.bottom, 8)
            }
        }
    }

    /// Date-region line + title, on the theme background below the map.
    ///
    /// Read-only. Editing used to be scattered across this screen — a pencil on
    /// the title, a chevron on the car chip, a tap on the privacy pill — each
    /// its own flow, none of them where you would look for "change this trip".
    /// «…» → «Редактировать» now holds all of it, and one door is better than
    /// four half-hidden ones.
    private func titleBlock(trip: Trip, c: AppTheme.Colors) -> some View {
        // A named trip and an unnamed one need different headers, or the same
        // date is printed three times in fifty points of screen — once in the
        // pixel line, once as the heading, once in the chip below it.
        //
        //   named    → «14 ИЮНЯ · КРАСНОДАР. КРАЙ» over «Дорога к морю»
        //   unnamed  → «14 ИЮНЯ» over «Краснодарский край»
        //
        // Either way every line carries something the others do not.
        // An auto-stamped date is not a name — see `TripAutoTitle.isAuto`.
        // Treating it as one is what printed the same date three times.
        let trimmed = trip.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = (trimmed.map { !$0.isEmpty } ?? false)
            && !TripAutoTitle.isAuto(trimmed, startDate: trip.startDate)
        let region = RegionDisplay.localized(trip.region, language: lang.language)
        let eyebrow = TripDetailFormat.posterDateLine(
            date: trip.startDate,
            region: named ? trip.region : nil,
            lang: lang.language
        )
        let heading: String = {
            if named { return trip.title ?? "" }
            if let region, !region.isEmpty { return region }
            return formattedDateFallback(trip.startDate)
        }()

        // 4, not 6: the pixel line is the title's eyebrow, not a line of its
        // own. The block reads as one heading only when the gap inside it is
        // smaller than the gap to the chips under it.
        return VStack(alignment: .leading, spacing: 4) {
            // The pixel face, as the canon sets it (117:1078). It is the app's
            // signature marker for "this is a trip", and it appears here and on
            // the feed card and nowhere else — rendered in the system font it
            // was just another grey caption.
            Text(eyebrow)
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(heading)
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.52)
                .foregroundStyle(c.text)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - Info Panel

    @ViewBuilder
    private func infoPanel(trip: Trip, c: AppTheme.Colors) -> some View {
        // Single source of vertical rhythm (22pt per Figma detail-body gap)
        // so conditional sections (charts, badges, reactions) don't produce
        // uneven spacing when they appear/disappear.
        VStack(alignment: .leading, spacing: 22) {
            // Heading and chips are one block — they describe the same thing.
            // At the body's 22pt rhythm they read as two separate sections with
            // a hole between them.
            VStack(alignment: .leading, spacing: 10) {
                titleBlock(trip: trip, c: c)
                chipsRow(trip: trip, c: c)
            }

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

            companionsSection(trip: trip)

            notesSection(trip: trip, c: c)

            photosSection(c)

            badgesSection(trip: trip, c: c)

            // Reactions:
            //   * Public → the «Реакции · N» card, for everyone. Reading them
            //     needs no account; the canon draws no signed-in precondition,
            //     and a signed-out visitor opening a public trip saw a screen
            //     with the discussion cut out of it.
            //   * Private + ours → the locked card that explains why.
            //   * Private + not ours → nothing; it is not our business.
            if !trip.isPrivate || isOwn {
                reactionsArea(trip: trip, c: c)
            }

            // «Комментарии» — the section is always here; what changes is
            // whether there is anything to comment on. A private trip used to
            // drop it silently, so the one place that could explain why there
            // is no discussion said nothing at all (canon 545:499
            // «КОММЕНТАРИИ · ПРИВАТНАЯ ПОЕЗДКА»).
            if trip.isPrivate, isOwn {
                VStack(alignment: .leading, spacing: 10) {
                    DetailSectionHeader(text: AppStrings.comments(lang.language))
                    lockedSocialCard(
                        title: AppStrings.publishForCommentsTitle(lang.language),
                        body: AppStrings.publishForCommentsBody(lang.language),
                        identifier: "comments_locked_card",
                        c: c
                    )
                }
            }

            if !trip.isPrivate {
                TripCommentsSection(
                    tripId: trip.id,
                    isTripOwner: isOwn,
                    // The header states the server-known total; without it the
                    // section opened as «Комментарии · 0» over a list of
                    // comments.
                    initialCount: liveSocial?.commentCount ?? 0,
                    // Own public trips ARE reachable signed-out («keep
                    // public and sign out» / dead session) — without this
                    // the composer looks active but every send dies with
                    // USER_NOT_AUTH. Mirrors the social screen's gate.
                    onGuestInputTap: { signInPrompt = .comment },
                    onOpenProfile: { author in
                        Haptics.tap()
                        if let pushPath {
                            pushPath.wrappedValue.cappedAppend(.profile(author.id, author))
                        } else {
                            selectedReactorAuthor = author
                        }
                    },
                    onError: { msg in
                        toastItem = ToastItem(type: .error, message: msg)
                    },
                    highlightCommentId: highlightedCommentId,
                    refreshToken: refreshToken
                )
                .id(Self.commentsAnchor)
            }

        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        // Enough to clear the home indicator and let the last card breathe.
        // It used to reserve 90pt for a tab bar this screen does not show.
        .padding(.bottom, safeAreaBottom + 20)
        .background(c.bg)
    }

    // MARK: - Chips row

    private func chipsRow(trip: Trip, c: AppTheme.Colors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Hours only. The day used to ride along here because the
                // poster line above scrolls away — but that line now sits
                // forty points up, in the same block, and printing «14 июня»
                // under «14 ИЮНЯ» was two thirds of why this block read as
                // noise.
                DetailChipSurface {
                    Text(timeRange(trip))
                        .monospacedDigit()
                }

                vehicleChip(trip: trip, c: c)

                // Privacy chip is per-trip and works independently of global
                // Cloud Sync (privacy-first model: publishing one trip should
                // NOT require turning on full-account mirror).
                if auth.isSignedIn, isOwn {
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
    @ViewBuilder
    private func vehicleChip(trip: Trip, c: AppTheme.Colors) -> some View {
        if !isOwn {
            // Someone else's car is a name and an avatar the server rendered,
            // not a row in our garage — and it is not ours to reassign.
            if let v = liveSocial?.vehicle {
                DetailChipSurface {
                    // A pixel avatar is an asset name, not a glyph — drawn as
                    // text it reads «pixel_car_white».
                    if v.isPixelAvatar {
                        Image(v.avatarEmoji)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    } else {
                        Text(v.avatarEmoji).font(.system(size: 12))
                    }
                    Text(v.name).lineLimit(1)
                }
            }
        } else {
            ownVehicleChip(trip: trip, c: c)
        }
    }

    /// Which car this was, stated and nothing more — reassignment lives in the
    /// edit sheet, next to the name and the description, where the canon puts
    /// it (Figma 543:119 «Машина для поездки»).
    private func ownVehicleChip(trip: Trip, c: AppTheme.Colors) -> some View {
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
        }
    }

    /// Who can see this trip. A state, not a switch: publishing and hiding both
    /// have consequences worth a confirmation, and they are one tap away in
    /// «…» and in the edit sheet. A chip that silently flipped either way was
    /// the most dangerous control on the screen and looked like a label.
    private func privacyChip(trip: Trip, c: AppTheme.Colors) -> some View {
        let isPrivate = trip.isPrivate
        return DetailChipSurface {
            Image(systemName: isPrivate ? "lock.fill" : "globe")
                .font(.system(size: 10, weight: .semibold))
            Text(isPrivate
                 ? AppStrings.privacyOnlyMe(lang.language)
                 : AppStrings.privacyPublic(lang.language))
        }
    }

    /// Writes back only what actually changed — each setter enqueues a sync
    /// operation, and saving three fields that nobody touched would push three
    /// updates for a sheet the user opened and closed.
    /// Returns false when the content filter rejected the name or the note, so
    /// the caller knows not to carry on to the access change.
    @discardableResult
    private func applyEdits(title: String, notes: String, vehicleId: UUID?, to t: Trip) -> Bool {
        // The inline editors this sheet replaced ran everything through
        // `ContentFilter` first — a published trip's name and description are
        // shown to strangers. Saving straight from the sheet would have been a
        // way around a check the old path always made.
        if title != (t.title ?? ""), !title.isEmpty {
            if let err = ContentFilter.validate(title, field: .tripTitle, language: lang.language) {
                toastItem = ToastItem(type: .error, message: err)
                return false
            }
        }
        if notes != (t.tripDescription ?? "") {
            if let err = ContentFilter.validate(notes, field: .tripNote, language: lang.language) {
                toastItem = ToastItem(type: .error, message: err)
                return false
            }
        }
        if title != (t.title ?? ""), !title.isEmpty {
            mapVM.tripManager.updateTitle(for: tripId, title: title)
        }
        if notes != (t.tripDescription ?? "") {
            mapVM.tripManager.updateNotes(for: tripId, notes: notes)
        }
        if vehicleId != t.vehicleId {
            mapVM.tripManager.updateVehicle(for: tripId, vehicleId: vehicleId)
        }
        // Same reason as in `applyPrivacyChange`: only a local trip has a row
        // to re-read. Editing is owner-only, so in practice this always finds
        // one — the fallback is there so it can never blank the screen.
        if let local = viewModel.tripDetail(id: tripId) {
            trip = local
        } else {
            trip?.title = title.isEmpty ? trip?.title : title
            trip?.tripDescription = notes
            trip?.vehicleId = vehicleId
        }
        Haptics.success()
        return true
    }


    // MARK: - Companions («Попутчики»)

    /// Server-backed roster (Task 1's `CompanionsStore`). The section owns
    /// its own header, loading/error states and three-way own/read-only/
    /// hidden rendering — see `TripCompanionsSection`'s doc comment.
    /// Fix 2: whether it's worth even ASKING the server for this trip's
    /// companion roster — and when it isn't, which blocker to name. A
    /// `trip_companion` row can only ever exist for a trip that's actually
    /// on the server, so a trip that was never published (cloud sync starts
    /// OFF; new trips are created private, which is the app's DEFAULT
    /// state, not an edge case) categorically cannot have one, and every
    /// `/companions/*` call on it 404s with the same `TRIP_NOT_FOUND` a
    /// genuinely missing trip would. A non-owner never reaches this screen
    /// for a trip that isn't already server-side (it arrived via the feed,
    /// a share link, or a companion invite — all of which imply a server
    /// row), so only the own-trip path is gated.
    ///
    /// Signed-out wins over not-published when both are true: signing in is
    /// the first step either way, and it's the only one of the two the card
    /// can offer to do something about. Conflating them is what made a
    /// signed-out owner of an already-PUBLIC trip read "publish it first".
    private var companionsGate: CompanionsCardModel.Gate {
        guard isOwn else { return .allowed }
        guard auth.isSignedIn else { return .signedOut }
        return (trip?.isOnServer ?? false) ? .allowed : .notPublished
    }

    private func companionsSection(trip: Trip) -> some View {
        TripCompanionsSection(
            tripId: trip.id,
            isOwn: isOwn,
            gate: companionsGate,
            // Task 7: whatever this trip's last successful `/companions/list`
            // cached locally (empty for a trip that never had one, or one
            // that isn't ours — see `TripCompanion`'s doc comment). Only
            // consulted when today's fetch fails and nothing survived in
            // memory either.
            cachedCompanions: trip.companions,
            onInvite: openCompanionsPicker,
            onOpenRoster: { showCompanionsRoster = true },
            // Signing in flips `companionsGate` to `.allowed`, which is the
            // section's `.task` identity — so the roster loads by itself as
            // soon as the sheet closes on a real session.
            onSignIn: { signInPrompt = .companions }
        )
    }

    /// Same navigation the reactor rows and the author pill on this screen
    /// already use: a shared `pushPath` when we're inside a
    /// `PreviewNavigator` stack, or the local `selectedReactorAuthor` +
    /// `TripDetailLocalReactorDestination` fallback otherwise.
    private func openProfile(_ author: SocialAuthor) {
        if let pushPath {
            pushPath.wrappedValue.cappedAppend(.profile(author.id, author))
        } else {
            selectedReactorAuthor = author
        }
    }

    /// Task 3: presents the companion candidate picker.
    private func openCompanionsPicker() {
        showCompanionsPicker = true
    }

    // MARK: - Description («Описание»)

    /// «Описание» — the text, and on our own trip an invitation to write one
    /// when there is none. Both open the same edit sheet as «…» →
    /// «Редактировать», so the description is never edited two different ways.
    @ViewBuilder
    private func notesSection(trip: Trip, c: AppTheme.Colors) -> some View {
        let notes = trip.tripDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.descriptionSection(lang.language))
                DetailDescriptionCard(text: notes, showsEditHint: false)
            }
        } else if isOwn {
            // An empty section would just be a header over nothing; the prompt
            // is the only thing worth the space, and it is how an owner finds
            // out the field exists at all.
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.descriptionSection(lang.language))
                Button {
                    Haptics.tap()
                    showEditSheet = true
                } label: {
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
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail_add_description")
            }
        }
    }

    // MARK: - Reactions

    /// Composite reactions block that picks the right surface for the current
    /// trip state — breakdown when there are reactions, a publish nudge for
    /// private trips, or a quiet "no reactions yet" line for public trips.
    @ViewBuilder
    private func reactionsArea(trip: Trip, c: AppTheme.Colors) -> some View {
        if !trip.isPrivate, !reactionTallies.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.reactionsTitleN(lang.language, totalReactions))
                reactionsCard(c)
            }
        } else if trip.isPrivate {
            // Header included, like every other section. Without it the locked
            // card sat headerless between «Достижения поездки» and
            // «Обсуждение», so it read as the tail of the achievements block
            // rather than as the reactions section being closed.
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.chipReactions(lang.language))
                publishNudgeCard(trip: trip, c: c)
            }
        } else {
            // Public, zero reactions (canon: «РЕАКЦИИ · ПУСТО»): the section
            // keeps its header and its card, and the card says the quiet part.
            // A bare grey line under a heading read as a rendering failure —
            // the section looked like it had lost its content rather than like
            // it was waiting for someone to react.
            VStack(alignment: .leading, spacing: 10) {
                DetailSectionHeader(text: AppStrings.chipReactions(lang.language))
                // Left-aligned icon + line, the same rhythm as every other
                // empty card on this screen. It used to be a lone sentence
                // centred in an otherwise empty card, which reads as
                // something that failed to arrive rather than as a state.
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(c.cardAlt).frame(width: 36, height: 36)
                        Image(systemName: "heart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                    Text(AppStrings.noReactionsYet(lang.language))
                        .font(.system(size: 14.5))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    // Somebody has to be first, and on someone else's trip that
                    // is the whole point of the section. Without this the «+»
                    // only existed once a reaction was already there — you
                    // could join a crowd but never start one.
                    if !isOwn {
                        Button {
                            Haptics.tap()
                            guard auth.isSignedIn else { signInPrompt = .react; return }
                            showReactionPicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .bold))
                                Text(AppStrings.beFirstToReact(lang.language))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(AppTheme.accent.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reaction_add_first")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard(cornerRadius: 14)
            }
        }
    }

    /// Leave, move or take back our reaction on someone else's trip.
    ///
    /// Goes through `SocialFeedStore` so the feed card behind us updates with
    /// the same optimistic bump — reacting here and finding the card unchanged
    /// when you go back would read as the tap not having worked.
    private func react(with emoji: String) {
        Haptics.tap()
        guard auth.isSignedIn else {
            signInPrompt = .react
            return
        }
        let tapped = ReactionEmoji.canonical(emoji)
        let previous = myReaction
        let wasMine = ReactionEmoji.canonical(previous ?? "") == tapped
        // Taking one back must name the emoji the server has, not the one we
        // draw for it.
        let payload = wasMine ? (previous ?? tapped) : tapped
        myReaction = wasMine ? nil : tapped
        Task {
            await socialFeed.toggleReaction(for: tripId, emoji: payload)
            await loadReactions()
            // The reload is the source of truth; if it could not reach the
            // server, put the optimistic guess back rather than leaving the
            // chip lit for a reaction that never landed.
            if reactionsLoadFailed { myReaction = previous }
        }
    }

    /// Reaction tallies to draw: the server's list once it lands, and until
    /// then whatever the feed already knew. Without the fallback a stranger's
    /// trip with 23 reactions opened claiming «Пока никто не отреагировал»
    /// for as long as the request took.
    private var reactionTallies: [(emoji: String, count: Int)] {
        if !reactionEntries.isEmpty {
            return Self.tallies(
                Dictionary(grouping: reactionEntries, by: { ReactionEmoji.canonical($0.emoji) })
                    .mapValues(\.count)
            )
        }
        guard let breakdown = liveSocial?.reactionBreakdown, !breakdown.isEmpty else { return [] }
        return Self.tallies(
            Dictionary(grouping: breakdown, by: { ReactionEmoji.canonical($0.emoji) })
                .mapValues { $0.reduce(0) { $0 + $1.count } }
        )
    }

    /// Orders the reaction row: most-reacted first, and the emoji itself as
    /// the tiebreak.
    ///
    /// The tiebreak is not cosmetic. Sorting on the count alone leaves equally
    /// popular reactions in whatever order a `Dictionary` iterates in, which is
    /// no order at all — and the row is now redrawn from a re-read of the trip
    /// every time the screen is pulled down. Without a total order, refreshing
    /// a trip whose reactions are level shuffles them under the finger that
    /// pulled, which reads as the tally changing when nothing has.
    static func tallies(_ counts: [String: Int]) -> [(emoji: String, count: Int)] {
        counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (emoji: $0.key, count: $0.value) }
    }

    private var totalReactions: Int {
        reactionEntries.isEmpty
            ? (liveSocial?.reactionCount ?? 0)
            : reactionEntries.count
    }

    /// Publishing needs an account. Every entry point goes through here so the
    /// gate cannot be forgotten on one of them — it already had been, twice.
    private func requestPublish() {
        guard auth.isSignedIn else {
            signInPrompt = .publish
            return
        }
        showPublishSheet = true
    }

    /// Taking a trip back out of the feed needs the same session publishing
    /// needed, for the same reason pointed the other way: the copy everyone
    /// else can see lives on the server, and a signed-out owner cannot reach
    /// it. Without this the flip was purely local — the trip vanished from
    /// this device's feed, came back on the next refresh, and stayed public to
    /// everyone else the whole time, which is the one thing «сделать
    /// приватной» must never do quietly. A trip that never reached the server
    /// has nothing to take back and is flipped on the spot.
    private func requestUnpublish() {
        guard auth.isSignedIn || !(trip?.isOnServer ?? false) else {
            signInPrompt = .publish
            return
        }
        unpublishConfirm = true
    }

    /// The canon's locked-section card: a trip nobody else can see cannot
    /// collect reactions or comments, and the screen says so instead of
    /// dropping the section on the floor.
    private func lockedSocialCard(
        title: String,
        body: String,
        identifier: String,
        c: AppTheme.Colors
    ) -> some View {
        Button {
            Haptics.tap()
            requestPublish()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.leading)
                    Text(body)
                        .font(.system(size: 12.5))
                        .foregroundStyle(c.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// «Опубликуйте, чтобы получить реакции» (canon 545:499).
    ///
    /// The old copy spelled out the whole privacy scope here — «поездку увидят
    /// другие пользователи в общей ленте» — which is the sentence the publish
    /// confirmation exists to say, at the moment consent is actually given.
    /// Saying it twice made the card an argument rather than an offer.
    private func publishNudgeCard(trip: Trip, c: AppTheme.Colors) -> some View {
        lockedSocialCard(
            title: AppStrings.publishForReactionsTitle(lang.language),
            body: AppStrings.publishForReactionsBody(lang.language),
            identifier: "reactions_locked_card",
            c: c
        )
    }

    /// «Реакции · N» — one card: breakdown chips row, then reactor rows
    /// (avatar / name / LVL / their emoji / chevron → profile).
    private func reactionsCard(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        // Group by CANONICAL key so legacy prod reactions (❤️ 🏎️ 🗺️) fold
        // into the drawn icon that replaced them instead of spawning a
        // twin chip next to it.
        let breakdown = reactionTallies
        return VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(breakdown, id: \.emoji) { emoji, count in
                        // On someone else's trip a chip is a control, not a
                        // tally: tapping the one you already left takes it
                        // back, tapping another moves your reaction to it.
                        // Ours stays a read-out — you cannot react to yourself.
                        if isOwn {
                            ReactionCountChip(emoji: emoji, count: count, style: .breakdown)
                        } else {
                            Button {
                                react(with: emoji)
                            } label: {
                                ReactionCountChip(
                                    emoji: emoji,
                                    count: count,
                                    style: ReactionEmoji.canonical(myReaction ?? "") == emoji
                                        ? .mine
                                        : .unselected
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // «+» — the way in for a reaction that is not on the card
                    // yet (canon 467:259). Without it the only reactions a
                    // viewer could leave were the ones somebody had already
                    // left, which is not a reaction picker, it is a poll.
                    if !isOwn {
                        Button {
                            Haptics.tap()
                            guard auth.isSignedIn else { signInPrompt = .react; return }
                            showReactionPicker = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(c.textSecondary)
                                .frame(width: 34, height: 28)
                                .background(Capsule().fill(c.cardAlt))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("reaction_add")
                        .accessibilityLabel(AppStrings.addReaction(lang.language))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }

            // Who reacted is the owner's view of their own trip; on someone
            // else's the canon card is the chips alone.
            if isOwn {
                ForEach(Array(reactionEntries.enumerated()), id: \.offset) { idx, entry in
                    Rectangle()
                        .fill(c.border)
                        .frame(height: 1)
                        .padding(.leading, idx == 0 ? 0 : 14)
                    reactionRow(entry, c: c, isRu: isRu)
                }
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
        // No auth gate: reactions on a public trip are public.
        guard let t = trip, !t.isPrivate else { return }
        do {
            let res: SocialReactionsResponse = try await APIClient.shared.post(
                APIEndpoint.socialReactions, body: SocialUnreactRequest(tripId: t.id))
            await MainActor.run {
                reactionEntries = res.reactions
                reactionsLoadFailed = false
            }
        } catch {
            // Non-fatal on its own — the section stays hidden. Together with a
            // failed photo load and a trip that arrived without a route, it is
            // how we know nothing came back at all.
            await MainActor.run { reactionsLoadFailed = true }
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
        // Re-read from the database only if that is where this trip came from.
        // A trip opened from the feed has no local row, so the fetch returns
        // nil — and assigning that blanked the whole screen the moment its
        // privacy changed.
        if let local = viewModel.tripDetail(id: tripId) {
            self.trip = local
        } else {
            self.trip?.isPrivate = newValue
        }
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
                segments: TripDetailFormat.durationSegments(trip.duration, lang: l),
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
                    segments: TripDetailFormat.durationSegments(cachedDrivingTime, lang: l),
                    label: AppStrings.statMoving(l),
                    color: AppTheme.blue,
                    staggerIndex: 2
                )
                DetailStatCard(
                    segments: TripDetailFormat.durationSegments(cachedStoppedTime, lang: l),
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
                    // Canon writes «23.4 л» and «1 310 ₽». The «~» we used to
                    // prefix said "estimated", which every number on this
                    // screen is — and it made the tile read like a warning.
                    value: TripDetailFormat.fuelVolume(fuel.volume),
                    unit: fuel.volUnit,
                    label: AppStrings.statFuel(l),
                    color: AppTheme.yellow,
                    staggerIndex: 8
                )
                DetailStatCard(
                    value: TripDetailFormat.money(fuel.cost),
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

    /// Task 6: whether THIS device — a companion, not the owner — may add a
    /// photo to this trip. `false` for a stranger, a still-pending or
    /// declined invite, or while signed out; `true` only once the roster
    /// carries our own account id with `.accepted`. See
    /// `CompanionPhotoUploadModel.canAddPhoto`'s own doc comment.
    private var canAddCompanionPhoto: Bool {
        CompanionPhotoUploadModel.canAddPhoto(
            isOwn: isOwn,
            companions: companionsStore.companionsByTrip[tripId] ?? [],
            viewerAccountId: TokenStore.shared.accountId
        )
    }

    @ViewBuilder
    private func photosSection(_ c: AppTheme.Colors) -> some View {
        if !isOwn {
            // Someone else's photos: served from R2. Nothing here to delete
            // even for a companion — only Task 6's add control, gated by
            // `canAddCompanionPhoto`.
            if !remotePhotos.isEmpty || canAddCompanionPhoto {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        DetailSectionHeader(text: remotePhotos.isEmpty
                            ? AppStrings.photos(lang.language)
                            : "\(AppStrings.photos(lang.language)) · \(remotePhotos.count)")
                        if canAddCompanionPhoto {
                            Spacer()
                            companionAddPhotoButton
                        }
                    }
                    if !remotePhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(remotePhotos.enumerated()), id: \.element.id) { index, photo in
                                    RemoteThumbnailView(
                                        urlString: photo.thumbnailUrl,
                                        fallbackURLString: photo.originalUrl
                                    )
                                    .frame(width: 74, height: 74)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedPhotoIndex = index }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            ownPhotosSection(c)
        }
    }

    /// Task 6: the companion's add-photo control — same glyph/identifier as
    /// the owner's (`ownPhotosSection`'s), swapped for a spinner and
    /// disabled while `companionPhotoUpload.isUploading`, so the upload's
    /// progress is visible right where the tap happened.
    private var companionAddPhotoButton: some View {
        Button {
            Haptics.tap()
            showPhotoPicker = true
        } label: {
            if companionPhotoUpload.isUploading {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .disabled(companionPhotoUpload.isUploading)
        .accessibilityIdentifier("detail_add_photo")
        .accessibilityLabel(AppStrings.addPhotos(lang.language))
    }

    /// Fix 1: local `trip.photos` UNIONED with the server roster
    /// (`remotePhotos`, loaded on the owner path too — see `.task(id:
    /// tripId)`) by photo id — see `OwnTripPhotosModel` for why this is the
    /// only way a companion's upload ever becomes visible to the owner.
    /// The file-system probe is passed in because a local row can name a JPEG
    /// this device never had (sync pull writes photo rows but downloads no
    /// bytes; a backup restore leaves `TripPhotos/` behind) — see
    /// `OwnTripPhotosModel.merge`. `PhotoStorageService.localFileExists`
    /// caches, so asking once per body pass is a dictionary hit.
    private var ownPhotoItems: [OwnTripPhotosModel.Item] {
        OwnTripPhotosModel.merge(
            local: trip?.photos ?? [],
            remote: remotePhotos,
            localFileExists: { PhotoStorageService.localFileExists(filename: $0) }
        )
    }

    private func ownPhotosSection(_ c: AppTheme.Colors) -> some View {
        let items = ownPhotoItems
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                DetailSectionHeader(text: !items.isEmpty
                    ? "\(AppStrings.photos(lang.language)) · \(items.count)"
                    : AppStrings.photos(lang.language))
                Spacer()
                Button { showPhotoPicker = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityIdentifier("detail_add_photo")
                .accessibilityLabel(AppStrings.addPhotos(lang.language))
            }

            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ownPhotoThumbnail(item, c)
                                .frame(width: 74, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                // No "+N" badge. It was written for a strip
                                // that stopped at four tiles; this strip
                                // scrolls and draws every photo, so the
                                // badge blacked out the fourth picture to
                                // announce photos that were already on
                                // screen beside it — five photos rendered as
                                // four plus a «+2» over the fourth. The
                                // header («Фото · 5») is where the count
                                // belongs.
                                .onTapGesture {
                                    selectedPhotoIndex = index
                                }
                                // Delete on a long press, not on a badge over
                                // every thumbnail. The canon strip is bare
                                // pictures (465:145-148), and a row of little
                                // ✕ marks turned a memory into an inbox.
                                // Works for a remote-only (companion's) photo
                                // too — see `deleteOwnPhoto`.
                                .onLongPressGesture {
                                    Haptics.action()
                                    photoToDelete = item
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

    /// One tile of the owner's merged strip — a local file for anything
    /// this device has on disk, a presigned R2 URL for a remote-only
    /// (companion's) photo, and a stated blank for a row whose picture is
    /// nowhere. The blank is deliberate: dropping the item instead would
    /// quietly shrink the strip and the «Фото · N» header, so a photo the
    /// user remembers taking would look like one they never took. A tile
    /// that admits it is empty is the only version they can act on — tap it
    /// and the viewer offers the bin (`onDelete`), which is the ONLY way one
    /// of these rows is ever removed. Nothing here deletes on its own.
    @ViewBuilder
    private func ownPhotoThumbnail(_ item: OwnTripPhotosModel.Item, _ c: AppTheme.Colors) -> some View {
        switch item.source {
        case .local(let filename):
            AsyncThumbnailView(filename: filename)
        case .remote(let thumbnailURL, let originalURL):
            RemoteThumbnailView(urlString: thumbnailURL, fallbackURLString: originalURL)
        case .missing:
            // Same glyph the full-screen viewer already shows for a page it
            // could not load (`PhotoFullScreenView`), so the tile and what
            // it opens into say the same thing.
            Rectangle()
                .fill(c.cardAlt)
                .overlay {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 20))
                        .foregroundStyle(c.textTertiary)
                }
        }
    }

    /// Fix 1: routes the delete through whichever mechanism the photo
    /// actually has a home in. A local item keeps the existing CoreData
    /// path (`TripManager.deletePhoto`, which also enqueues the server-side
    /// delete once synced). A remote-only item — a companion's upload,
    /// which never gets a local row by design — has nothing local to
    /// remove, so it goes straight through `/photos/delete`; the server
    /// authorises this because the caller owns the TRIP, not because they
    /// own the photo (`PhotosService.assertCanDelete`).
    ///
    /// The branch is chosen by whether a local ROW exists, not by which
    /// picture the tile happened to draw. Since a row whose file is gone can
    /// now render from its server twin (`OwnTripPhotosModel.merge`), keying
    /// off `.remote` would have sent that one down the server-only path and
    /// left the local row behind — to reappear as a missing tile on the next
    /// reload. `.missing` lands here too: the row IS local, only its file is
    /// gone, and removing a path with nothing behind it is a no-op followed
    /// by the row delete we want. Only ever called from the long-press
    /// confirmation or the viewer's bin — nothing deletes on its own.
    private func deleteOwnPhoto(_ item: OwnTripPhotosModel.Item) {
        let hasLocalRow = trip?.photos.contains { $0.id == item.id } ?? false
        if hasLocalRow {
            mapVM.tripManager.deletePhoto(id: item.id, from: tripId)
            trip?.photos.removeAll { $0.id == item.id }
            remotePhotos.removeAll { $0.id == item.id }
            toastItem = ToastItem(type: .success, message: AppStrings.photoDeleted(lang.language))
        } else {
            // Optimistic: drop it from the strip immediately, restore (via a
            // fresh reload) if the server call fails.
            let previous = remotePhotos
            remotePhotos.removeAll { $0.id == item.id }
            Task { await deleteRemoteOwnPhoto(item.id, previous: previous) }
        }
    }

    private func deleteRemoteOwnPhoto(_ photoId: UUID, previous: [SocialTripPhoto]) async {
        struct DeleteReq: Encodable { let photoId: UUID }
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.photoDelete, body: DeleteReq(photoId: photoId))
            toastItem = ToastItem(type: .success, message: AppStrings.photoDeleted(lang.language))
        } catch {
            remotePhotos = previous
            toastItem = ToastItem(type: .error, message: AppStrings.companionPhotoDeleteFailed(lang.language))
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

    private static let dayMonthFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMMM"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMMM"
        return (ru, en)
    }()

    private func formattedDateFallback(_ date: Date) -> String {
        let fmts = Self.dateTimeFormatters
        return (lang.language == .ru ? fmts.ru : fmts.en).string(from: date)
    }

    /// «12:31 – 13:18», and «22:00 – 15 июня, 05:00» when the drive crosses
    /// midnight — the heading above already states the day it STARTED, so a
    /// bare «22:00 – 05:00» under it reads as seventeen hours run backwards.
    private func timeRange(_ trip: Trip) -> String {
        let start = Self.timeFormatter.string(from: trip.startDate)
        guard let end = trip.endDate else { return start }
        let endTime = Self.timeFormatter.string(from: end)
        guard !Calendar.current.isDate(trip.startDate, inSameDayAs: end) else {
            return "\(start) – \(endTime)"
        }
        let fmts = Self.dayMonthFormatters
        let day = (lang.language == .ru ? fmts.ru : fmts.en).string(from: end)
        return "\(start) – \(day), \(endTime)"
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

/// How far the hero has scrolled, published from a `Color.clear` behind the
/// map (never from inside the map's own subtree — this fires on every frame
/// of a scroll, and the hero hosts an `MKMapView` with a display link).
struct DetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
