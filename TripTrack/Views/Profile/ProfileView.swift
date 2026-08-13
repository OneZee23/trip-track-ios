import SwiftUI
import OSLog

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// «Я» tab — 6.1.0 canon (Figma 150:1244 signed-in / 127:896 guest).
/// Self-hosts a `NavigationStack` (ContentView mounts the tab bare), pushes
/// Статистика + trip details (both hide the tab bar via the existing
/// preference), and re-homes every pre-6.1.0 feature into the settings sheet
/// (gear) or the rank sheet (LVL pill) — nothing is deleted.
struct ProfileView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    @ObservedObject private var syncQueue = SyncQueue.shared

    /// True when hosted as the «Я» tab (6.1.0) — the floating tab bar needs
    /// scroll clearance. False when presented as the legacy Feed sheet.
    private let hostedInTab: Bool

    init(hostedInTab: Bool = false) {
        self.hostedInTab = hostedInTab
    }

    /// Typed destinations for the Я stack.
    private enum MeDest: Hashable {
        case stats
        case trip(UUID)
        /// A «Со мной» trip — NOT in the local database (someone else's),
        /// so it carries its own `SocialFeedTrip` payload rather than just
        /// an id, exactly like `ProfilePreviewDest.socialTrip` does for the
        /// feed. Kept as a separate case (rather than reusing that shared
        /// enum for `mePath`) because `mePath`'s type predates it and this
        /// is the only spot in the Я stack that needs a non-owned trip.
        case companionTrip(SocialFeedTrip)
    }

    // Profile avatar
    @State private var selectedAvatar: String = "😎"
    @State private var isEditingAvatar = false
    @State private var avatarBounce = false

    @State private var mePath: [MeDest] = []
    @State private var showSettings = false
    @State private var showRankSheet = false
    @State private var showGarage = false
    @State private var showSyncStatus = false
    @State private var showNameEditor = false
    @State private var showWrappedStory = false
    @State private var socialProfile: SocialProfile?
    @State private var followListMode: FollowListMode?
    @State private var previewingOwnProfile = false
    /// Nav path for the preview-sheet NavigationStack. Kept alongside the
    /// sheet's `isPresented` so every deep navigation inside the sheet
    /// (profile ↔ followers) shares one path and the `cappedAppend` helper
    /// can enforce a max depth of 3 — preventing the SwiftUI NavigationStack
    /// bug that surfaces a default "← Back" flash at depth 4+.
    @State private var previewPath: [ProfilePreviewDest] = []
    /// Same idea as `previewPath` but for the follow-list sheet. A separate
    /// path lets us reset depth to 0 when the sheet closes without touching
    /// the preview flow's path.
    @State private var followListPath: [ProfilePreviewDest] = []
    /// Client-side aggregates feeding the strip regions, YearHero gating,
    /// Моменты and История (§3 — real numbers only).
    @State private var agg: MeAggregates?

    /// 16-emoji preset grid (4×4) — broadened from the original 8 so
    /// users have a real personality choice instead of "pick a guy".
    /// Backend regex (`AVATAR_EMOJI_PATTERN`) accepts any non-whitespace
    /// 1–16 char string, so this list could grow further without a
    /// schema change. Personas first, then activities, then small set
    /// of "iconic" non-people emojis.
    private let profileAvatars = [
        "😎", "🤓", "🤠", "🥸",
        "🧔", "🥷", "🧑‍💻", "👨‍🚀",
        "🏂", "🎸", "🎮", "📷",
        "🌅", "🐱", "🐶", "🚀",
    ]

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        NavigationStack(path: $mePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(c)

                    if auth.isSignedIn {
                        syncStatusIndicator(c)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                    }

                    if isEditingAvatar {
                        avatarGrid(c)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    if mapVM.cachedTripCount == 0 {
                        // First-launch welcome — zeros read as broken, so the
                        // strip/hero/moments/history stay hidden until ≥1 trip.
                        firstTripWelcomeCard(c)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        if !auth.isSignedIn {
                            guestSignInCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                    } else {
                        ProfileStatsStrip(
                            trips: mapVM.cachedTripCount,
                            km: mapVM.cachedTotalKm,
                            regions: agg?.regionsAllTime ?? 0
                        ) {
                            // Idempotent — a fast double-tap must not
                            // stack two Статистика screens.
                            if mePath.last != .stats { mePath.append(.stats) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        if auth.isSignedIn {
                            // FK-11: canon drops the counters, but this card is
                            // the only entry to the follow lists — kept.
                            socialCountersRow(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        } else {
                            guestSignInCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }

                        // Every number in the hero and in Моменты comes out of
                        // MeAggregates.compute over local CoreData — nothing
                        // here touches a session. Gating both on isSignedIn
                        // meant a guest with 40 trips saw the stat strip, the
                        // sign-in card, then История, with their whole year
                        // missing; the data-driven gates below are the real
                        // ones.
                        if let agg, agg.yearTripCount > 0 {
                            yearHero(agg, c)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 12)
                        }

                        if let agg {
                            momentsSection(agg, c)
                        }

                        if let agg, !agg.recentTrips.isEmpty {
                            historySection(agg, c)
                        } else if agg != nil {
                            // No trips at all: canon empty card. Before this
                            // the section simply wasn't rendered, so a fresh
                            // user saw the Я tab end after the stat grid with
                            // nothing telling them what happens next.
                            noTripsCard(c)
                        }

                        // «Со мной» — trips the user rode as an accepted
                        // companion. Signed-out users can't be a companion
                        // on anything (the endpoint needs a token), so this
                        // never even asks while signed out. Draws nothing of
                        // its own when there's nothing to show — see
                        // `WithMeSectionModel`.
                        if auth.isSignedIn {
                            WithMeSection(onTapTrip: { trip in
                                mePath.append(.companionTrip(trip))
                            })
                        }
                    }
                }
                // As a tab (6.1.0), leave room for the floating tab bar so the
                // last row can scroll clear of it; as a sheet there is no bar.
                .padding(.bottom, hostedInTab ? 120 : 40)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MeDest.self) { dest in
                switch dest {
                case .stats:
                    StatsScreenView(tripManager: mapVM.tripManager)
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
            selectedAvatar = settings.avatarEmoji
            settings.reloadGamificationState()
        }
        .task {
            await loadOwnSocialProfile()
        }
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
        // so История/Моменты pick up edits made inside the detail screen.
        .onChange(of: mePath) { oldPath, newPath in
            guard newPath.count < oldPath.count,
                  let popped = oldPath.last, case .trip = popped else { return }
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        // The one-shot .task ran while signed out (its guard no-ops), and
        // the guest card on this very screen signs users in inline — reload
        // the social profile on the flip or the follower/following counters
        // stay «0/0» until a tab bounce remounts the view.
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn {
                Task { await loadOwnSocialProfile() }
            } else {
                socialProfile = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGarageReady)) { _ in
            // Second phase of VehiclePickerSheet's «Управлять в Гараже»:
            // ContentView switched to the Я tab, waited for this view to
            // mount, then re-posted.
            showGarage = true
        }
        // Pure-SwiftUI navigator rooted at the follow list — replaces the
        // previous sheet-hosted `NavigationStack { FollowListView }` that
        // exhibited the depth-4+ flash when users chained profile↔follower
        // pushes inside it. Same navigator the preview flow uses.
        .fullScreenCover(isPresented: Binding(
            get: { followListMode != nil },
            set: { if !$0 { followListMode = nil } }
        ), onDismiss: {
            navLog.debug("follow list dismissed — clearing path (had depth=\(followListPath.count))")
            followListPath = []
        }) {
            if let mode = followListMode,
               let accountId = TokenStore.shared.accountId {
                PreviewNavigator(
                    rootDest: .followList(accountId, mode),
                    path: $followListPath,
                    onCloseSheet: { followListMode = nil }
                )
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        // Was `.sheet`, switched to `.fullScreenCover` to sidestep a
        // SwiftUI bug where the system nav bar flashes during pushes inside
        // a sheet-hosted NavigationStack. Research ref: sheet's animating
        // container re-lays-out the UIHostingController, which lets UIKit's
        // `_pushViewController` run a CAAnimation on the bar's presentation
        // layer that KVO / lifecycle hooks cannot intercept. fullScreenCover
        // doesn't trigger the same relayout. UX trade-off: no grabber, no
        // swipe-to-dismiss — users close via the X button wired into
        // `CustomNavBar` (`onClose` already passed below).
        .fullScreenCover(isPresented: $previewingOwnProfile, onDismiss: {
            navLog.debug("preview dismissed — clearing path (had depth=\(previewPath.count))")
            previewPath = []
        }) {
            if let accountId = TokenStore.shared.accountId {
                // Custom ZStack-based navigator — no `NavigationStack`, no
                // underlying `UINavigationController`, no nav-bar flash.
                // `PreviewNavigator` slides destinations in/out and bridges
                // `NavBackButton` via `\.previewPop` environment.
                PreviewNavigator(
                    rootDest: .profile(accountId, nil),
                    path: $previewPath,
                    onCloseSheet: { previewingOwnProfile = false }
                )
                .environmentObject(lang)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
        .fullScreenCover(isPresented: $showWrappedStory) {
            if let agg {
                WrappedStoryView(aggregates: agg)
                    .environmentObject(lang)
            }
        }
        .sheet(isPresented: $showSettings) {
            ProfileSettingsSheet()
                .environmentObject(lang)
                .environment(\.navBarInSheet, true)
                .environmentObject(themeManager)
                // Sheets are separate presentations — the app-root
                // preferredColorScheme does not reach them.
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showRankSheet) {
            RankProgressSheet()
                .environmentObject(lang)
                .environmentObject(mapVM)
                // themeManager is required: the rank sheet re-applies the
                // scheme override to its own nested presentations (Награды).
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showGarage) {
            GarageView()
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showSyncStatus) {
            SyncStatusSheetView()
                .environmentObject(lang)
                .environmentObject(themeManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
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
            .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .alert(AppStrings.signInFailedTitle(lang.language),
               isPresented: Binding(
                 get: { auth.lastAuthError != nil },
                 set: { if !$0 { auth.lastAuthError = nil } })
        ) {
            Button(AppStrings.ok(lang.language), role: .cancel) {}
        } message: {
            // Generic localized copy — same defence as SignInPromptSheet:
            // never echo `String(describing: APIError)` because the
            // `unknownServer.message` case would surface server-controlled
            // text into a system alert.
            Text(AppStrings.signInPromptAppleFailed(lang.language))
        }
    }

    // MARK: - Header (Figma 150:1244)

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Avatar/64 — tap opens the inline emoji grid.
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) { isEditingAvatar.toggle() }
            } label: {
                Text(selectedAvatar)
                    .font(.system(size: 33))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(c.cardAlt))
                    .scaleEffect(avatarBounce ? 1.12 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: avatarBounce)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_avatar")

            VStack(alignment: .leading, spacing: 6) {
                nameView(c)

                Button {
                    Haptics.tap()
                    showRankSheet = true
                } label: {
                    LvlPill(
                        level: settings.profileLevel,
                        rankTitle: DriverRank.from(level: settings.profileLevel).title(lang.language)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile_lvl_pill")
            }

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(c.text)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_gear")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .accessibilityIdentifier("profile_header")
    }

    @ViewBuilder
    private func nameView(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        let trimmed = auth.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        let hasName = !trimmed.isEmpty
        let displayName: String = auth.isSignedIn
            ? (hasName ? trimmed : (isRu ? "Добавьте имя" : "Add your name"))
            : AppStrings.meGuestName(lang.language)

        Text(displayName)
            .font(.system(size: 20, weight: .heavy))
            .tracking(-0.2)
            .foregroundStyle(auth.isSignedIn && !hasName ? c.textTertiary : c.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentShape(Rectangle())
            .onTapGesture {
                guard auth.isSignedIn, !isEditingAvatar else { return }
                Haptics.tap()
                // No name yet (Apple Sign In doesn't redeliver the name
                // after re-auth) → tap routes to the editor instead of the
                // public-profile preview, so the user sees "fix your
                // identity" before "see your public profile". Once a real
                // name exists, tap opens preview-as-others (FK-1 kept).
                if headerTapShouldEditName {
                    presentNameEditor()
                } else {
                    previewingOwnProfile = true
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard auth.isSignedIn, !isEditingAvatar else { return }
                Haptics.action()
                presentNameEditor()
            }
    }

    /// Whether tapping the name should open the editor instead of the
    /// public-profile preview. Empty / placeholder names route to the editor
    /// so a fresh-install user is nudged to set their name — but real-name
    /// users get the preview, the more useful action once identity is set.
    private var headerTapShouldEditName: Bool {
        guard auth.isSignedIn else { return false }
        let trimmed = auth.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty { return true }
        return RandomDisplayName.isPlaceholder(auth.userName)
    }

    private func presentNameEditor() {
        showNameEditor = true
    }

    // MARK: - Year Hero (Figma 150:1244)

    private func yearHero(_ agg: MeAggregates, _ c: AppTheme.Colors) -> some View {
        let slideCount = WrappedStoryView.slides(from: agg, lang: lang.language).count

        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [AppTheme.accent, AppTheme.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle white wave texture (vector not exportable from Figma —
            // sine approximation, α0.12).
            Canvas { ctx, size in
                for (midFactor, ampFactor) in [(0.45, 0.16), (0.62, 0.20)] {
                    var path = Path()
                    let amp = size.height * ampFactor
                    let midY = size.height * midFactor
                    path.move(to: CGPoint(x: 0, y: midY))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let y = midY + sin(x / size.width * .pi * 2 + midFactor * 4) * amp
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 4
                    }
                    ctx.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 14)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.wrappedKicker(lang.language))
                    .font(.custom("PressStart2P-Regular", size: 9))
                    .foregroundStyle(.white.opacity(0.85))

                Text(AppStrings.wrappedHeroTitle(lang.language, year: agg.year))
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Haptics.action()
                    // <2 real slides → the story would be an empty shell;
                    // route to Статистика instead (§2.5 runtime fallback).
                    if slideCount >= 2 {
                        showWrappedStory = true
                    } else if mePath.last != .stats {
                        mePath.append(.stats)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                        Text(AppStrings.wrappedWatch(lang.language))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.22)))
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityIdentifier("profile_wrapped_cta")
            }
            .padding(16)
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .topTrailing) {
            Image("PixelCar")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(height: 30)
                .opacity(0.95)
                .padding(14)
        }
        .accessibilityIdentifier("profile_year_hero")
    }

    // MARK: - Моменты

    private struct Moment {
        let title: String
        let subtitle: String
        let colors: [Color]
    }

    private func moments(_ agg: MeAggregates) -> [Moment] {
        let l = lang.language
        var result: [Moment] = []

        if let t = agg.yearAgoTrip {
            result.append(Moment(
                title: AppStrings.momentYearAgo(l),
                subtitle: "\(momentTripName(t)) · \(GarageFormat.odometer(t.distanceKm)) \(AppStrings.km(l))",
                colors: [AppTheme.blue, AppTheme.teal]
            ))
        }
        if let t = agg.longestYearTrip {
            result.append(Moment(
                title: AppStrings.momentLongest(l),
                // Plain «X км» — the mock's "за день" is sample copy; this
                // number is per-trip, don't misclaim.
                subtitle: "\(momentTripName(t)) · \(GarageFormat.odometer(t.distanceKm)) \(AppStrings.km(l))",
                colors: [AppTheme.green, AppTheme.teal]
            ))
        }
        if let region = agg.newRegion {
            result.append(Moment(
                title: AppStrings.momentNewRegion(l),
                subtitle: AppStrings.momentRegionOpened(l, name: region),
                colors: [AppTheme.teal, AppTheme.blue]
            ))
        }
        return result
    }

    private func momentTripName(_ trip: Trip) -> String {
        if let t = trip.title, !t.isEmpty { return t }
        if let r = trip.region, !r.isEmpty { return r }
        return ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)
    }

    @ViewBuilder
    private func momentsSection(_ agg: MeAggregates, _ c: AppTheme.Colors) -> some View {
        let cards = moments(agg)
        if !cards.isEmpty {
            ProfileSectionLabel(text: AppStrings.momentsSection(lang.language))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { idx, card in
                        MomentCard(
                            title: card.title,
                            subtitle: card.subtitle,
                            gradient: LinearGradient(
                                colors: card.colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .accessibilityIdentifier("profile_moment_card_\(idx)")
                    }
                }
                .padding(.horizontal, 14)
            }
            // 6, not 12: the rail is 98 in canon (92 card + 6) — at 12 the
            // section carried dead space under cards that were themselves
            // 28pt taller than their content.
            .padding(.bottom, 6)
        }
    }

    /// «Здесь появятся ваши поездки» (canon). The point of the copy is the
    /// second line: recording is automatic and needs no account — that's the
    /// product's whole pitch, and the empty state is where it lands.
    private func noTripsCard(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(c.cardAlt)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }

            Text(isRu ? "Здесь появятся ваши поездки" : "Your trips will show up here")
                .font(.inter(17, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(isRu
                 ? "Запись начнётся автоматически, когда вы поедете. Аккаунт не нужен."
                 : "Recording starts by itself once you drive. No account needed.")
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

    // MARK: - История

    @ViewBuilder
    private func historySection(_ agg: MeAggregates, _ c: AppTheme.Colors) -> some View {
        ProfileSectionLabel(text: AppStrings.historySection(lang.language))
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

        ForEach(historyGroups(agg.recentTrips), id: \.key) { group in
            Text(group.key)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            ForEach(group.trips) { trip in
                ProfileTripRow(
                    trip: trip,
                    vehicleName: vehicleName(for: trip),
                    onTap: { mePath.append(.trip(trip.id)) }
                )
                .accessibilityIdentifier("profile_trip_row")
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
    }

    /// Consecutive month groups over the (already newest-first) trips.
    /// Months of previous years get a year suffix so «Апрель» is never
    /// ambiguous across year boundaries.
    private func historyGroups(_ trips: [Trip]) -> [(key: String, trips: [Trip])] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        var groups: [(key: String, trips: [Trip])] = []
        for trip in trips {
            var key = ProfileDateFormat.monthName(trip.startDate, lang: lang.language)
            let year = cal.component(.year, from: trip.startDate)
            if year != currentYear {
                key += " \(year)"
            }
            if groups.last?.key == key {
                groups[groups.count - 1].trips.append(trip)
            } else {
                groups.append((key, [trip]))
            }
        }
        return groups
    }

    private func vehicleName(for trip: Trip) -> String? {
        guard let id = trip.vehicleId else { return nil }
        return settings.vehicles.first { $0.id == id }?.name
    }

    // MARK: - Social Counters Row (followers / following, FK-11)

    private func socialCountersRow(_ c: AppTheme.Colors) -> some View {
        // Captions use the AppStrings plural funcs so «1 подписчик /
        // 2 подписчика / 5 подписчиков» agrees with the number — same
        // grammar FollowListView renders one tap deeper.
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                followListMode = .followers
            } label: {
                VStack(spacing: 3) {
                    Text("\(socialProfile?.followerCount ?? 0)")
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(c.text)
                    Text(AppStrings.followersCaption(lang.language, n: socialProfile?.followerCount ?? 0))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(c.borderBright).frame(width: 1, height: 34)

            Button {
                Haptics.tap()
                followListMode = .following
            } label: {
                VStack(spacing: 3) {
                    Text("\(socialProfile?.followingCount ?? 0)")
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(c.text)
                    Text(AppStrings.followingCaption(lang.language, n: socialProfile?.followingCount ?? 0))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 16)
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
        let isRu = lang.language == .ru
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
                    Text(isRu ? "Запишите первую поездку" : "Record your first trip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(isRu
                         ? "Здесь будут Ваши километры, серии и бейджи."
                         : "Your kilometers, streaks and badges will appear here.")
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

    // MARK: - Sync pill (FK-6 — kept despite canon absence; load-bearing UX)

    @ViewBuilder
    private func syncStatusIndicator(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        let pending = syncQueue.pendingCount
        let syncing = syncQueue.isSyncing
        // Always tappable when sync is on — even on "synced" the sheet is
        // useful as a dashboard ("how much of my data is in the cloud?").
        // When sync is disabled there's nothing meaningful to show, so we
        // leave the pill inert; the user can enable sync via Настройки →
        // Аккаунт и синхронизация.
        let isTappable = settings.cloudSyncEnabled

        HStack(spacing: 6) {
            if !settings.cloudSyncEnabled {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(c.textTertiary)
                Text(isRu ? "Синхронизация выключена" : "Sync disabled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            } else if syncing {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
                let total = syncQueue.batchTotal
                let done = syncQueue.batchProcessed
                Text(total > 0
                     ? (isRu ? "синхронизация… \(done)/\(total)" : "syncing… \(done)/\(total)")
                     : (isRu ? "синхронизация…" : "syncing…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .monospacedDigit()
            } else if pending > 0 {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text(isRu ? "\(pending) в очереди" : "\(pending) pending")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.green)
                Text(isRu ? "синхронизировано" : "synced")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            }
            if isTappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .padding(.leading, 2)
            }
        }
        // Pin a min height so the pill doesn't pop in/out as states swap (off vs syncing vs synced have different glyph sizes)
        .frame(minHeight: 22)
        .padding(.horizontal, isTappable ? 10 : 0)
        .padding(.vertical, isTappable ? 4 : 0)
        .background(
            isTappable ? AnyShapeStyle(c.cardAlt) : AnyShapeStyle(Color.clear),
            in: Capsule()
        )
        .contentShape(Capsule())
        .onTapGesture {
            guard isTappable else { return }
            Haptics.tap()
            showSyncStatus = true
        }
        .animation(.easeInOut(duration: 0.2), value: syncing)
        .animation(.easeInOut(duration: 0.2), value: pending)
        .accessibilityIdentifier("profile_sync_pill")
    }

    // MARK: - Avatar Grid

    private func avatarGrid(_ c: AppTheme.Colors) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(profileAvatars, id: \.self) { emoji in
                Button {
                    Haptics.tap()
                    selectedAvatar = emoji
                    settings.avatarEmoji = emoji
                    settings.saveSettings()
                    Task { await auth.syncProfileToServer() }
                    // Bounce the main avatar
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        avatarBounce = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        avatarBounce = false
                    }
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedAvatar == emoji ? AppTheme.accentBg : c.cardAlt)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedAvatar == emoji ? AppTheme.accent : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Data

    private func loadOwnSocialProfile() async {
        guard auth.isSignedIn, let accountId = TokenStore.shared.accountId else { return }
        do {
            let p: SocialProfile = try await APIClient.shared.get(
                APIEndpoint.userProfile(accountId.uuidString))
            socialProfile = p
        } catch {
            // Silent — social counters just won't populate
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
            trips = tripManager.fetchTrips()
            StatsCache.update(trips: trips, count: count, lastDate: lastDate)
        }
        let computed = await Task.detached(priority: .userInitiated) {
            MeAggregates.compute(trips: trips, now: Date(), calendar: Calendar.current)
        }.value
        guard !Task.isCancelled else { return }
        agg = computed
    }
}
