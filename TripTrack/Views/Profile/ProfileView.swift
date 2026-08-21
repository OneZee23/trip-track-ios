import SwiftUI
import OSLog

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// «Я» tab — 0.6.0 canon (Figma 580:122 list / 755:119 grid, 127:896 guest).
/// Self-hosts a `NavigationStack` (ContentView mounts the tab bare) and pushes
/// Статистика, Уровни, Достижения, «Как видят другие» + trip details (all hide
/// the tab bar via the existing preference). Order: hero → Достижения → Гараж →
/// История (header row, calendar filter, then the trips).
///
/// The canon header and stat strip are now ONE object, `ProfileHeroCard` — the
/// screen opened as four stacked greys and read as a settings page. The grey
/// sync line that sat under the name went to «Настройки → Аккаунт и
/// синхронизация», the row that can actually do something about it.
///
/// Pre-0.6.0 features that are NOT here: everything that moved into the
/// settings sheet (gear) or into Уровни (LVL pill), plus three the user cut
/// outright — the follower/following counter card, «Год в кадре» / Wrapped,
/// and the «Моменты» rail.
struct ProfileView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared

    /// True when hosted as the «Я» tab (0.6.0) — the floating tab bar needs
    /// scroll clearance. False when presented as the legacy Feed sheet.
    private let hostedInTab: Bool

    init(hostedInTab: Bool = false) {
        self.hostedInTab = hostedInTab
    }

    /// Typed destinations for the Я stack.
    private enum MeDest: Hashable {
        case stats
        /// «Мой профиль» — the hub behind the header (avatar + name/handle/bio
        /// /level/stats rows). Its five row editors are NOT cases here: four
        /// of them are sheets this view presents, and the fifth is Статистика,
        /// which already has one.
        case myProfile
        /// «Уровни» (canon 888:3848) — a pushed screen, not the bottom sheet it
        /// used to be, reached from the header LVL pill and from «Мой профиль»'s
        /// «Уровень» row. One surface, two entry points: whichever way it was
        /// opened, the back chevron goes where the user came from.
        case levels
        /// Флаг страны — a pushed screen (`CountryPickerView` draws its own
        /// `CustomNavBar` and pops itself), so it belongs in this path rather
        /// than in a sheet.
        ///
        /// One entry point: the «Страна» row of «Мой профиль» (`onTapCountry`).
        /// The country is profile data, not app configuration, so the settings
        /// sheet no longer carries a second copy of the row.
        case country
        /// The whole award list, and one award. `Badge` cannot be the payload
        /// — it carries the `checkUnlocked` closure and so isn't `Hashable` —
        /// so the path holds the catalogue id and the destination resolves it
        /// against `Badge.all`. That is also what keeps a rebuilt path
        /// pointing at the right badge instead of at a stale copy of one.
        case achievements
        case achievement(String)
        /// «Как видят другие» — the viewer's own public profile. An ORDINARY
        /// pushed screen (canon 580:438: back circle, «@username», «⋯»), not
        /// the fullScreenCover over a hand-rolled ZStack navigator it used to
        /// be: that cover had no fixed header, so the whole page — floating
        /// orange «Готово» band included — moved as one loose sheet and read
        /// as a web page rather than as a screen of this app.
        ///
        /// Payload is the same pair `ProfilePreviewDest.profile` carries, so
        /// `socialPath` can bridge the two: a stranger opened from a follow
        /// list arrives with the summary the list already had.
        case publicProfile(UUID, SocialAuthor?)
        /// Подписчики / подписки of whichever profile is on top. Only ever
        /// reached from `.publicProfile`.
        case followList(UUID, FollowListMode)
        case trip(UUID)
        /// A «Со мной» trip — NOT in the local database (someone else's),
        /// so it carries its own `SocialFeedTrip` payload rather than just
        /// an id, exactly like `ProfilePreviewDest.socialTrip` does for the
        /// feed. Kept as a separate case (rather than reusing that shared
        /// enum for `mePath`) because `mePath`'s type predates it and this
        /// is the only spot in the Я stack that needs a non-owned trip.
        case companionTrip(SocialFeedTrip)
    }

    /// How История draws its trips — canon 580:122 (list) / 755:119 (grid).
    private enum HistoryMode: String {
        case list
        case grid
    }

    @State private var mePath: [MeDest] = []
    @State private var showSettings = false
    @State private var showGarage = false
    /// Presented here rather than from «Мой профиль» itself, for the same
    /// reason the three field editors are: one host owns every presentation
    /// this stack raises.
    @State private var showBackgroundPicker = false
    /// The three field editors behind «Мой профиль». The hub only reports the
    /// tap; presenting them here keeps every editor on one host, which is what
    /// keeps them all on one host — a
    /// sheet is a separate presentation and does not inherit the app root's.
    @State private var showNameEditor = false
    @State private var showUsernameEditor = false
    @State private var showAboutEditor = false
    /// Client-side aggregates. Since 0.6.0 they feed exactly two things: the
    /// strip's region count and the «data has landed» gate — everything
    /// История draws comes out of `allTrips` instead.
    @State private var agg: MeAggregates?
    /// Every completed trip, newest first. `agg.recentTrips` stops at 10,
    /// which made a date filter over История meaningless.
    @State private var allTrips: [Trip] = []
    /// `allTrips` after the calendar range. See `refreshVisibleTrips`.
    @State private var visibleTrips: [Trip] = []
    /// Which awards are earned — the one thing `AchievementDetailView` needs
    /// that a badge id cannot carry. Resolved by the award destinations
    /// themselves (`refreshUnlockedBadges`) rather than in `loadAggregates`:
    /// that path runs on every trip save and every sync pull, and this walk is
    /// only worth paying for once someone actually opens an award.
    @State private var unlockedBadgeIds: Set<String> = []
    /// Σ km per calendar day and the busiest of those days — the calendar's
    /// heat ramp. Walked once per load in `loadAggregates`, never in `body`:
    /// it touches every trip.
    @State private var kmByDay: [Date: Double] = [:]
    @State private var maxKmDay: Double = 0
    @State private var dateFrom: Date?
    @State private var dateTo: Date?
    /// `@AppStorage` cannot hold the enum itself, so the raw value is what
    /// persists and `historyMode` maps it back (unknown value → canon list).
    @AppStorage("profileHistoryMode") private var historyModeRaw = HistoryMode.list.rawValue

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        NavigationStack(path: $mePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero()

                    if mapVM.cachedTripCount == 0 {
                        // First-launch welcome — zeros read as broken, so the
                        // strip/achievements/history stay hidden until ≥1 trip.
                        firstTripWelcomeCard(c)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        if !auth.isSignedIn {
                            guestSignInCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                        // Zero trips does not mean zero cars: the Гараж is
                        // where a new user names the thing they drive, and
                        // it is the one section here that has something to
                        // do before the first kilometre.
                        garageSection(c)
                    } else {
                        if !auth.isSignedIn {
                            guestSignInCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }

                        // Достижения and История both read local CoreData —
                        // nothing here touches a session, so both stay up for
                        // guests. The gate is data, not auth: a guest with 40
                        // trips must not see the strip, the sign-in card, and
                        // then nothing.
                        if !allTrips.isEmpty {
                            ProfileAchievementsSection(
                                trips: allTrips,
                                onTapAll: { push(.achievements) },
                                // Straight to the award, not to the list: a
                                // tappable chip that opens a grid the user has
                                // to find the same badge in again is a chip
                                // that may as well not be tappable.
                                onTapBadge: { push(.achievement($0.id)) }
                            )
                            // Resolved HERE, not at the award destination: the
                            // chips open one directly, and a set that is still
                            // empty on the destination's first frame paints an
                            // earned badge as «Ещё не открыто» (a hidden one as
                            // «? ? ?») before flipping. Only runs while the
                            // section is actually on screen.
                            .task(id: allTrips.count) { await refreshUnlockedBadges() }
                            .padding(.bottom, 12)
                        }

                        // Above История on purpose: История is an endless
                        // list, and anything under it is a place nobody
                        // scrolls to — which is exactly where the Гараж spent
                        // 0.6.0 (at the foot of a settings sheet). The chain
                        // below is split around this call so the section keeps
                        // its place whether the library is empty, loading, or
                        // full.
                        garageSection(c)

                        if !allTrips.isEmpty {
                            historyBlock(c)
                        } else if agg != nil {
                            // No trips at all: canon empty card. Before this
                            // the section simply wasn't rendered, so a fresh
                            // user saw the Я tab end after the stat grid with
                            // nothing telling them what happens next.
                            noTripsCard(c)
                        } else {
                            // Nil aggregates with no trips means the library
                            // has not been read yet — a different thing from
                            // an empty one, and until now they looked the
                            // same: the page simply ended.
                            ProfileHistorySkeleton(isGrid: historyMode == .grid)
                        }

                        // «Со мной» — trips the user rode as an accepted
                        // companion. Signed-out users can't be a companion
                        // on anything (the endpoint needs a token), so this
                        // never even asks while signed out. Draws nothing of
                        // its own when there's nothing to show — see
                        // `WithMeSectionModel`.
                        if auth.isSignedIn {
                            WithMeSection(onTapTrip: { push(.companionTrip($0)) })
                        }
                    }
                }
                // As a tab (0.6.0), leave room for the floating tab bar so the
                // last row can scroll clear of it; as a sheet there is no bar.
                .padding(.bottom, hostedInTab ? 120 : 40)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MeDest.self) { dest in
                switch dest {
                case .stats:
                    // Push onto THIS stack. Without the callback the screen
                    // falls back to the app-wide `.openTripDetail` channel,
                    // which switches to the Лента tab and opens the trip there
                    // — so «назад» from a trip you opened in Статистика landed
                    // in the feed, and the only way back to the list you were
                    // reading was Я → Статистика → scroll down and find it again.
                    StatsScreenView(
                        tripManager: mapVM.tripManager,
                        onOpenTrip: { push(.trip($0)) }
                    )
                case .myProfile:
                    myProfileHub()
                case .levels:
                    LevelsView()
                case .country:
                    CountryPickerView(
                        // "" is this app's «not set»; the picker speaks nil.
                        selection: settings.profileCountry.isEmpty ? nil : settings.profileCountry,
                        onSelect: { settings.profileCountry = $0 ?? "" }
                    )
                case .achievements:
                    // Fed the already-loaded library, not a second CoreData
                    // read. The walk runs here too so the answer is ready
                    // before the user can tap a tile out of the grid.
                    AchievementsView(trips: allTrips) { badge in
                        push(.achievement(badge.id))
                    }
                    .task(id: allTrips.count) { await refreshUnlockedBadges() }
                case .achievement(let id):
                    achievementDetail(id)
                case .publicProfile(let id, let author):
                    // The same screen strangers get from the Лента (canon
                    // 580:579) — it decides for itself that the viewer is
                    // looking at their own account and swaps «Подписаться»
                    // for «Это вы» plus the preview notice card. Nothing
                    // about the CHROME differs: one nav bar, drawn by the
                    // screen, pinned above the scroll.
                    PublicProfileView(
                        accountId: id,
                        preloaded: author,
                        pushPath: socialPath,
                        // The Я stack renders `.trip` and `.companionTrip`,
                        // which is what `socialPath` folds trip pushes into —
                        // so a card on the preview opens like one in the feed.
                        opensTrips: true
                    )
                    .hideAppTabBar()
                case .followList(let id, let mode):
                    FollowListView(accountId: id, mode: mode, pushPath: socialPath)
                        .hideAppTabBar()
                case .trip(let id):
                    // Same construction FeedView uses; TripDetailView manages
                    // its own chrome and hides the tab bar itself.
                    // KNOWN LIMITATION: no pushPath is passed, so deep
                    // chains from here (trip → reactor profile → followers
                    // → profile, depth ≥4) use TripDetailView's legacy
                    // isPresented fallback and can show the cosmetic
                    // nav-bar «Back» flash. A typed mixed-path stack would
                    // fix it; deferred — История's primary flow is 1 deep.
                    TripDetailView(
                        tripId: id,
                        viewModel: TripsViewModel(tripManager: mapVM.tripManager)
                    )
                case .companionTrip(let trip):
                    // Same construction FeedView's `.socialTrip` destination
                    // uses: `social:` feeds the screen someone else's trip,
                    // rendered through `Trip(social:)` instead of a local
                    // CoreData read.
                    TripDetailView(
                        tripId: trip.id,
                        viewModel: TripsViewModel(tripManager: mapVM.tripManager),
                        social: trip
                    )
                }
            }
        }
        .onAppear {
            settings.reloadGamificationState()
        }
        // The other half of `refreshVisibleTrips`'s contract: the library moves
        // in `loadAggregates`, the range moves here.
        .onChange(of: dateFrom) { _, _ in refreshVisibleTrips() }
        .onChange(of: dateTo) { _, _ in refreshVisibleTrips() }
        .task {
            await loadAggregates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripRecordingEnded)) { _ in
            Task { await loadAggregates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncPullCompleted)) { _ in
            Task { await loadAggregates() }
        }
        // История pushes TripDetailView, where trips get deleted or flip
        // privacy — without these the popped-back list keeps a ghost row
        // (tapping it lands on an empty detail with no back affordance).
        // StatsCache MUST be dropped first: its only invalidation keys are
        // trip count + last startDate, so a privacy flip (neither changes)
        // would make loadAggregates recompute over the stale cached [Trip]
        // array and keep the old globe/lock icon.
        .onReceive(NotificationCenter.default.publisher(for: .tripDeleted)) { _ in
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripPrivacyChanged)) { _ in
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        // Pop-back from TripDetailView: title renames post no notification
        // and change neither StatsCache key — refresh over a dropped cache
        // so История picks up edits made inside the detail screen.
        .onChange(of: mePath) { oldPath, newPath in
            guard newPath.count < oldPath.count,
                  let popped = oldPath.last, case .trip = popped else { return }
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGarageReady)) { _ in
            // Second phase of VehiclePickerSheet's «Управлять в Гараже»:
            // ContentView switched to the Я tab, waited for this view to
            // mount, then re-posted.
            showGarage = true
        }
        .sheet(isPresented: $showSettings) {
            ProfileSettingsSheet()
                .environmentObject(lang)
                .environment(\.navBarInSheet, true)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showGarage) {
            GarageView()
        }
        .sheet(isPresented: $showBackgroundPicker) {
            ProfileBackgroundPickerSheet()
                .environmentObject(lang)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNameEditor) {
            NameEditorSheet(
                initialName: auth.userName ?? "",
                isPlaceholder: RandomDisplayName.isPlaceholder(auth.userName),
                onSave: { newName in
                    Task { await auth.updateUserName(newName) }
                }
            )
            .environmentObject(lang)
        }
        .sheet(isPresented: $showUsernameEditor) {
            UsernameEditorSheet(
                initialUsername: settings.profileUsername,
                // SHIPPING BLOCKER: there is no handle on the server and no
                // endpoint to ask, so every lookup answers "не удалось
                // проверить" — the editor's own degraded branch, which still
                // lets the user save. Two accounts CAN claim the same handle
                // until the backend lands `/social/username-available`.
                // No endpoint to ask yet — the editor hides its verdict line
                // instead of printing a failure the user cannot act on, and
                // still lets them save. Two accounts CAN claim the same handle
                // until the backend lands `/social/username-available`.
                canCheckAvailability: false,
                checkAvailability: { _ in nil },
                onSave: { settings.profileUsername = $0 }
            )
            .environmentObject(lang)
        }
        .sheet(isPresented: $showAboutEditor) {
            AboutEditorSheet(
                initialText: settings.profileBio,
                onSave: { settings.profileBio = $0 }
            )
            .environmentObject(lang)
        }
        // House dialog, never the system's — see «Dialogs» in CLAUDE.md.
        // Acknowledgement only: «ОК» is the single way out, so there is no
        // cancel row under it.
        .appConfirm(
            isPresented: Binding(
                get: { auth.lastAuthError != nil },
                set: { if !$0 { auth.lastAuthError = nil } }),
            title: AppStrings.signInFailedTitle(lang.language),
            // Generic localized copy — same defence as SignInPromptSheet:
            // never echo `String(describing: APIError)` because the
            // `unknownServer.message` case would surface server-controlled
            // text into the dialog. The house card changes nothing about that
            // rule: the error object stays out of the copy.
            message: AppStrings.signInPromptAppleFailed(lang.language),
            actions: [AppDialogAction(AppStrings.ok(lang.language))],
            cancelTitle: nil
        )
    }

    /// Extracted from the `.myProfile` destination: eight trailing closures in
    /// one expression inside a `switch` inside a `navigationDestination` put
    /// the type-checker over its time limit («unable to type-check this
    /// expression in reasonable time»).
    @ViewBuilder
    private func myProfileHub() -> some View {
        MyProfileView(
            onTapName: { showNameEditor = true },
            onTapUsername: { showUsernameEditor = true },
            onTapAbout: { showAboutEditor = true },
            // The same screen the LVL pill in the header opens.
            onTapLevel: { push(.levels) },
            onTapCountry: { push(.country) },
            onTapBackground: { showBackgroundPicker = true },
            onTapStats: { push(.stats) },
            // Straight onto THIS stack — the same destination the
            // public profile's counters reach, minus the detour
            // through a preview of yourself.
            onTapFollowList: { mode in
                guard let accountId = TokenStore.shared.accountId else { return }
                push(.followList(accountId, mode))
            },
            // Signed out there is no public profile to preview —
            // the endpoint needs an account id. The hub hides the
            // row too; this is the second lock.
            onTapPreview: {
                guard let accountId = TokenStore.shared.accountId else { return }
                navLog.debug("push own-profile preview onto mePath (depth \(mePath.count))")
                push(.publicProfile(accountId, nil))
            }
        )

    }

    // MARK: - Navigation

    /// Idempotent push — a fast double-tap must not stack two copies of the
    /// same screen.
    private func push(_ dest: MeDest) {
        guard mePath.last != dest else { return }
        mePath.append(dest)
    }

    /// The social sub-stack (profile → follow list → profile → …) seen as the
    /// `[ProfilePreviewDest]` binding `PublicProfileView` and `FollowListView`
    /// already take. Reads project the social tail of `mePath`, writes fold it
    /// back — so every tap inside «как видят другие» is a REAL push on the Я
    /// stack (one back chevron, one swipe-back gesture, one place the path
    /// lives), and `cappedAppend`'s depth cap still bounds the chain.
    ///
    /// Handing those screens the binding — rather than letting them fall back
    /// to their own `.navigationDestination(isPresented:)` — is also what keeps
    /// this stack out of the isPresented-inside-a-typed-path bug documented on
    /// `ProfilePreviewDest`: with the binding wired in, both screens disable
    /// their local destinations.
    private var socialPath: Binding<[ProfilePreviewDest]> {
        Binding(
            get: { mePath.compactMap(Self.socialDest) },
            set: { newValue in
                // Everything up to the first social entry is untouched; the
                // social entries are contiguous at the tail, because the only
                // way into one is «Как видят другие» and the only thing you
                // reach from there is another social screen.
                let head = mePath.prefix { Self.socialDest($0) == nil }
                mePath = Array(head) + newValue.map(Self.meDest)
            }
        )
    }

    private static func socialDest(_ dest: MeDest) -> ProfilePreviewDest? {
        switch dest {
        case .publicProfile(let id, let author): return .profile(id, author)
        case .followList(let id, let mode): return .followList(id, mode)
        case .stats, .myProfile, .levels, .country, .achievements,
             .achievement, .trip, .companionTrip:
            return nil
        }
    }

    /// The other half of the bridge. `.trip` / `.socialTrip` are unreachable
    /// through it today — neither the profile nor a follow list pushes a trip
    /// — but they are mapped rather than dropped so a future push lands on the
    /// Я stack's own trip destinations instead of vanishing.
    private static func meDest(_ dest: ProfilePreviewDest) -> MeDest {
        switch dest {
        case .profile(let id, let author): return .publicProfile(id, author)
        case .followList(let id, let mode): return .followList(id, mode)
        case .trip(let id, _): return .trip(id)
        case .socialTrip(let trip, _): return .companionTrip(trip)
        }
    }

    /// One award. The path carries only the id, so the badge is resolved here
    /// and «earned?» is re-derived instead of being frozen into the path: a
    /// flag captured at push time would be stale the moment the library moved
    /// underneath it. `Badge.all` is compiled in, so the lookup can only miss
    /// if a path outlives a catalogue rename — nothing to draw beats a crash.
    @ViewBuilder
    private func achievementDetail(_ id: String) -> some View {
        if let badge = Badge.all.first(where: { $0.id == id }) {
            AchievementDetailView(badge: badge, isUnlocked: unlockedBadgeIds.contains(id))
                .task(id: allTrips.count) { await refreshUnlockedBadges() }
        }
    }

    /// `computeStats` reads the streak row off the CoreData view context, so the
    /// trip walk stays on the main actor; only the pure pass over the badge
    /// catalogue goes off it. Same split as `ProfileAchievementsSection.load`.
    private func refreshUnlockedBadges() async {
        let stats = BadgeManager.computeStats(from: allTrips)
        let ids = await Task.detached(priority: .userInitiated) {
            Set(BadgeManager.unlockedBadges(for: stats).map(\.id))
        }.value
        guard !Task.isCancelled else { return }
        unlockedBadgeIds = ids
    }

    // MARK: - Hero (was the flat canon header, Figma 150:1244)

    /// Avatar, name, rank, the three lifetime numbers and the gear — one
    /// coloured card, wearing the background picked in «Мой профиль». See
    /// `ProfileHeroCard` for why the canon header stack was retired.
    ///
    /// No accessibility id on the card itself: an id on a container makes
    /// SwiftUI treat it as ONE element and swallow the buttons inside it, which
    /// takes the avatar, the pill and the gear away from VoiceOver and from the
    /// UI tests alike. The ids live on those buttons.
    private func hero() -> some View {
        ProfileHeroCard(
            background: ProfileBackground.from(settings.profileBackground),
            avatarEmoji: settings.avatarEmoji,
            name: headerDisplayName,
            // A signed-in account with no name shows «Добавьте имя» — a prompt,
            // drawn dimmer so it can't be mistaken for what the user is called.
            isNamePlaceholder: auth.isSignedIn
                && (auth.userName?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty,
            level: settings.profileLevel,
            rankTitle: DriverRank.from(level: settings.profileLevel).title(lang.language),
            trips: mapVM.cachedTripCount,
            km: mapVM.cachedTotalKm,
            regions: agg?.regionsAllTime ?? 0,
            showsStats: mapVM.cachedTripCount > 0,
            // Guests included, and on purpose: the avatar on the hub is local
            // state anyone can edit, and gating the tap would take the emoji
            // picker away from signed-out users, who had it before.
            onTapProfile: { push(.myProfile) },
            onTapLevel: { push(.levels) },
            onTapStats: { push(.stats) },
            onTapSettings: { showSettings = true }
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// The name in the header. When a signed-in account has no name yet this is
    /// a PROMPT, not a name — which is why the cards don't reuse it.
    private var headerDisplayName: String {
        guard auth.isSignedIn else { return AppStrings.meGuestName(lang.language) }
        let trimmed = auth.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !trimmed.isEmpty else { return AppStrings.meAddYourName(lang.language) }
        return trimmed
    }

    /// The author name printed on every История card. Same source as the header
    /// once a real name exists, but a nameless account falls back to «Вы» —
    /// a card captioned «Добавьте имя · 8 км» reads as the trip's title and
    /// advertises an unfinished profile back at its own owner.
    private var cardAuthorName: String {
        let trimmed = auth.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard auth.isSignedIn, !trimmed.isEmpty else {
            return AppStrings.meGuestName(lang.language)
        }
        return trimmed
    }

    /// «Здесь появятся ваши поездки» (canon). The point of the copy is the
    /// second line: recording is automatic and needs no account — that's the
    /// product's whole pitch, and the empty state is where it lands.
    private func noTripsCard(_ c: AppTheme.Colors) -> some View {
        let lng = lang.language
        return VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(c.cardAlt)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }

            Text(AppStrings.profileYourTripsWill(lng))
                .font(.inter(17, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(AppStrings.profileRecordingStartsBy(lng))
                .font(.inter(14))
                .lineSpacing(4)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Button {
                Haptics.tap()
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            } label: {
                Text(AppStrings.recordTripCta(lang.language))
                    .font(.inter(15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 15)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .surfaceCard(cornerRadius: 18)
        .padding(.horizontal, 16)
    }

    // MARK: - Гараж (promoted onto the Я tab)

    /// The Гараж used to be a row at the foot of the settings sheet — behind a
    /// gear, under a card of switches, four scrolls down. It is not a setting:
    /// it is a place with things in it that people open for pleasure, and it
    /// belongs on the screen about them.
    ///
    /// The section shows what the garage HAS (so the row is worth a look even
    /// when nobody taps it) and every tap lands on `GarageView` — the list,
    /// from the top. Deep-linking straight into one vehicle would need a new
    /// parameter on a screen this view does not own, and a push fired on a
    /// sheet's first frame is the kind of thing that lands on an empty stack.
    @ViewBuilder
    private func garageSection(_ c: AppTheme.Colors) -> some View {
        let l = lang.language

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProfileSectionLabel(text: AppStrings.garage(l))

                Spacer(minLength: 8)

                Button {
                    Haptics.tap()
                    showGarage = true
                } label: {
                    HStack(spacing: 5) {
                        // NOT «3 машины»: the app has no countable noun for
                        // transport (its own cap reads «5 единиц транспорта»),
                        // and pluralising it would lie about a moped.
                        Text(AppStrings.garageAllVehicles(l))
                            .font(.system(size: 13, weight: .semibold))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(c.textSecondary)
                    // The text is ~16pt tall; the target has to be 44. Grown
                    // with a frame and pulled back out of layout by the same
                    // amount, so the header keeps canon's 4/8 rhythm.
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -14)
                }
                .buttonStyle(.plain)
                // Kept verbatim from the settings row this replaces — the row
                // moved, so its identifier moved with it.
                .accessibilityIdentifier("settings_garage")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            Group {
                if settings.vehicles.isEmpty {
                    garageEmptyCard(c, l)
                } else {
                    garageVehiclesCard(c, l)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    /// ONE row: the vehicle currently selected as the main one.
    ///
    /// It listed all of them at first — five is the app's cap, so the card
    /// «could never run long» — but five rows is ~330pt of transport standing
    /// between the profile and История, which is the section people actually
    /// come back for. The rest are one tap away behind «Весь транспорт ›», and
    /// the header is where that promise belongs.
    @ViewBuilder
    private func garageVehiclesCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        // No explicit selection (a garage filled before the picker existed, or
        // a deleted main) falls back to the first vehicle — the same fallback
        // the rest of the app reads `selectedVehicleId` with, so the ✓ here
        // can't disagree with the one inside the Гараж.
        if let main = settings.vehicles.first(where: { $0.id == settings.selectedVehicleId })
            ?? settings.vehicles.first {
            garageVehicleRow(main, isMain: true, c: c, l: l)
                .surfaceCard(cornerRadius: 16)
                .accessibilityIdentifier("profile_garage_card")
        }
    }

    private func garageVehicleRow(
        _ vehicle: Vehicle,
        isMain: Bool,
        c: AppTheme.Colors,
        l: LanguageManager.Language
    ) -> some View {
        Button {
            Haptics.tap()
            showGarage = true
        } label: {
            HStack(spacing: 12) {
                VehicleSpritePlate(
                    assetName: vehicle.avatarImageName,
                    fallbackEmoji: vehicle.isPixelAvatar ? nil : vehicle.avatarEmoji,
                    plateSize: 44,
                    spriteSize: 30,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vehicle.name.isEmpty ? AppStrings.unnamedVehicle(l) : vehicle.name)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // The owner's only cue that others cannot see this one
                        // — same lock the Гараж card wears, same reason.
                        if !vehicle.visibleToOthers {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(c.textTertiary)
                                .accessibilityLabel(AppStrings.vehicleHiddenFromOthers(l))
                        }

                        if isMain {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                                .accessibilityLabel(AppStrings.vehicleMainLabel(l))
                        }
                    }

                    Text("\(GarageFormat.odometer(vehicle.odometerKm)) \(AppStrings.km(l))")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VehicleLevelPill(level: vehicle.level, size: 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Nothing in the garage yet: one row that says what a vehicle is FOR here
    /// (it levels up with you), because «Гараж пуст» on its own is a dead end.
    private func garageEmptyCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            showGarage = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.accentBg)
                        .frame(width: 44, height: 44)
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.garageEmptyTitle(l))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(AppStrings.garageEmptyBody(l))
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("profile_garage_empty")
    }

    // MARK: - История (Figma 580:172 header · 580:122 list · 755:119 grid)

    /// Header row, calendar filter, then the trips themselves. Canon goes
    /// straight from the calendar into the cards — the month headings the
    /// pre-0.6.0 list drew are gone, the calendar names the dates now.
    @ViewBuilder
    private func historyBlock(_ c: AppTheme.Colors) -> some View {
        // One filtered array for both consumers: the calendar prints the count,
        // the list draws the rows, and they must never disagree about what
        // "matched" means.
        let trips = visibleTrips

        historyHeader(c)

        ProfileHistoryCalendar(
            dateFrom: $dateFrom,
            dateTo: $dateTo,
            kmByDay: kmByDay,
            maxKmDay: maxKmDay,
            filteredCount: trips.count
        )
        .padding(.horizontal, 16)
        // Canon's 16pt gap to the first card. As padding rather than a spacer
        // so it survives a filter that matches nothing, where the calendar
        // would otherwise butt straight into «Со мной».
        .padding(.bottom, 16)

        // A filter matching nothing draws NOTHING here: the «здесь появятся
        // ваши поездки» card would be a lie about a library that has trips,
        // and the calendar's own «сбросить» row is already the way out.
        if !trips.isEmpty {
            switch historyMode {
            case .grid:
                LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                    ForEach(trips) { trip in
                        ProfileTripTile(
                            trip: trip,
                            onTap: { push(.trip(trip.id)) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                // Breathing room before «Со мной», whose own label only
                // carries a 4pt top pad.
                .padding(.bottom, 12)
            case .list:
                LazyVStack(spacing: 12) {
                    ForEach(trips) { trip in
                        ProfileTripCardView(
                            trip: trip,
                            authorName: cardAuthorName,
                            authorAvatar: settings.avatarEmoji,
                            level: settings.profileLevel,
                            onTap: { push(.trip(trip.id)) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    /// Two flexible columns inside the 14pt margins. Static so a scroll
    /// doesn't rebuild the descriptors on every redraw.
    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 2
    )

    private var historyMode: HistoryMode {
        HistoryMode(rawValue: historyModeRaw) ?? .list
    }

    private func historyHeader(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            ProfileSectionLabel(text: AppStrings.historySection(lang.language))

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                historyModeButton(
                    .grid,
                    systemImage: "square.grid.2x2.fill",
                    label: AppStrings.historyModeGrid(lang.language),
                    identifier: "profile_history_grid",
                    c: c
                )
                historyModeButton(
                    .list,
                    // Canon 749:125 is three PLAIN bars. `list.bullet` adds
                    // dots, which at 16pt reads as a different control.
                    systemImage: "line.3.horizontal",
                    label: AppStrings.historyModeList(lang.language),
                    identifier: "profile_history_list",
                    c: c
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func historyModeButton(
        _ mode: HistoryMode,
        systemImage: String,
        label: String,
        identifier: String,
        c: AppTheme.Colors
    ) -> some View {
        let isActive = historyMode == mode
        return Button {
            guard !isActive else { return }
            Haptics.tap()
            historyModeRaw = mode.rawValue
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? AppTheme.accent : c.textSecondary)
                // Grown to 44pt tall for the touch target, then taken back out
                // of layout so the row keeps canon's height. The width claims
                // only half of the 10pt gap on each side: a literal 44pt-wide
                // target would overlap its neighbour's, and the neighbour —
                // drawn later — would steal the taps landing on this glyph's
                // own right edge.
                .frame(width: 26, height: 44)
                .contentShape(Rectangle())
                .padding(.horizontal, -5)
                .padding(.vertical, -12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// `allTrips` narrowed to the calendar range, both ends inclusive and
    /// compared on `startOfDay` so a trip that began at 23:50 still belongs to
    /// the day the user tapped. No range → the whole list, without walking it.
    ///
    /// Held in state rather than computed in `body`: this view observes
    /// `SyncQueue`, so a sync draining a hundred items republishes a hundred
    /// times, and each pass would re-walk the entire library building a fresh
    /// array. Recomputed only when the library or the range actually moves.
    private static func filter(_ trips: [Trip], from: Date?, to: Date?) -> [Trip] {
        guard let from else { return trips }
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        // A half-set range (first tap only) is a single day, which is what the
        // calendar itself highlights while you pick the second end.
        let end = cal.startOfDay(for: to ?? from)
        return trips.filter { trip in
            let day = cal.startOfDay(for: trip.startDate)
            return day >= start && day <= end
        }
    }

    private func refreshVisibleTrips() {
        visibleTrips = Self.filter(allTrips, from: dateFrom, to: dateTo)
    }

    // MARK: - Guest sign-in card (Figma 424:128 — kept byte-identical)

    /// Guest sync card: explains sync and signs in DIRECTLY via the shared
    /// Apple button — no sheet hop. The footnote is the "можно позже"
    /// affordance; the card just stays.
    private func guestSignInCard(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Figma 424:130 — the cloud sits on a 30×30 pale-peach
                // rounded-square tile (same treatment as SettingsIconRow),
                // not as a bare floating glyph.
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accentBg)
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.syncCardKicker(lang.language))
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.22)
                        .foregroundStyle(c.textTertiary)
                    Text(AppStrings.syncCardTitle(lang.language))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(c.text)
                    Text(AppStrings.syncCardBody(lang.language))
                        .font(.system(size: 12.5))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }

            AppleSignInButton(
                cornerRadius: 999,
                height: 43,
                onError: { _ in
                    // ProfileView's existing alert (driven by lastAuthError)
                    // is this card's error surface; make sure ASAuthorization
                    // failures reach it too (API failures already set it).
                    if auth.lastAuthError == nil {
                        auth.lastAuthError = .transport("Apple sign-in failed")
                    }
                }
            )

            Text(AppStrings.syncCardLater(lang.language))
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
        }
        .padding(14)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        .accessibilityIdentifier("profile_guest_signin")
    }

    // MARK: - First-trip welcome (0 trips)

    /// Friendly empty-state replacement for the stats stack on first launch
    /// (cachedTripCount == 0). Tap routes to the Tracking tab — the one
    /// action that matters before any data exists.
    private func firstTripWelcomeCard(_ c: AppTheme.Colors) -> some View {
        let lng = lang.language
        return Button {
            Haptics.tap()
            NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentBg)
                        .frame(width: 52, height: 52)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.profileRecordYourFirst(lng))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(AppStrings.profileYourKilometersStreaks(lng))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    /// Everything История needs out of the raw trip list, built in ONE pass:
    /// the km-per-day walk touches every trip, so it belongs here — off the
    /// main actor, once per load — and never in `body`.
    private struct HistoryData {
        let trips: [Trip]
        let kmByDay: [Date: Double]
        let maxKmDay: Double

        init(trips: [Trip], calendar: Calendar) {
            // The repository already sorts newest-first; re-sorting costs
            // nothing on an ordered array and keeps История right if that
            // ever stops being true (a test double, another fetch path).
            self.trips = trips.sorted { $0.startDate > $1.startDate }
            var byDay: [Date: Double] = [:]
            for trip in self.trips {
                byDay[calendar.startOfDay(for: trip.startDate), default: 0] += trip.distanceKm
            }
            self.kmByDay = byDay
            self.maxKmDay = byDay.values.max() ?? 0
        }
    }

    /// Fetch (StatsCache-aware, main) → crunch (detached) → publish (@State).
    private func loadAggregates() async {
        let tripManager = mapVM.tripManager
        let count = tripManager.fetchTripCount()
        let lastDate = tripManager.fetchLastTripDate()
        let trips: [Trip]
        if let cached = StatsCache.tripsIfValid(currentCount: count, currentLastDate: lastDate) {
            trips = cached
        } else {
            // ASYNC on purpose. `loadAggregates` runs on the MainActor (it is
            // a view's `.task`), so the synchronous read decoded every
            // polyline in the library on the main thread — the whole Я tab,
            // its scroll and the tab bar under it, frozen until the last trip
            // came back. The crunch below was already detached; this is the
            // half that was not.
            trips = await tripManager.fetchTripsAsync()
            StatsCache.update(trips: trips, count: count, lastDate: lastDate)
        }
        // Same fetch feeds both — История must not open a second read of the
        // library just to show more than the aggregates' last 10.
        let calendar = Calendar.current
        let crunched = await Task.detached(priority: .userInitiated) {
            () -> (aggregates: MeAggregates, history: HistoryData) in
            let aggregates = MeAggregates.compute(trips: trips, now: Date(), calendar: calendar)
            return (aggregates, HistoryData(trips: trips, calendar: calendar))
        }.value
        guard !Task.isCancelled else { return }
        agg = crunched.aggregates
        allTrips = crunched.history.trips
        kmByDay = crunched.history.kmByDay
        maxKmDay = crunched.history.maxKmDay
        // Every path that reloads the library lands here — a deleted trip has
        // to leave the filtered list too, or its card stays and opens an empty
        // detail screen.
        refreshVisibleTrips()
    }
}
