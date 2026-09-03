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
    /// Retained for the sheet-root call sites (`PreviewNavigator`), which pass
    /// it unconditionally. The bar no longer draws a close «×» from it: canon
    /// (580:438, 1630:150) gives this screen a back circle and «⋯», and
    /// `NavBackButton` at the root of a `PreviewNavigator` already falls
    /// through to `\.dismiss`, i.e. closes the presenting sheet.
    var onClose: (() -> Void)?
    /// When set, all sub-navigation (follow lists, reactor profiles) is
    /// routed through a shared `NavigationPath` with a depth cap. Without
    /// this binding we fall back to local `@State`-driven
    /// `.navigationDestination(isPresented:)` for main-feed usage.
    var pushPath: Binding<[ProfilePreviewDest]>?
    /// Whether this host renders `.trip` / `.socialTrip` destinations at all.
    /// Feed and the Я stack do; the sheet navigator and Discover don't, and a
    /// trip card that opens nothing there is worse than one that doesn't
    /// invite the tap — so they leave this off and the cards stay inert.
    var opensTrips: Bool = false

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var auth = AuthService.shared
    /// Only ever read in the own-profile preview: username, country and bio
    /// live on the device (the profile DTO carries none of the first two), so
    /// they can be shown for the viewer and for nobody else.
    @ObservedObject private var settings = SettingsManager.shared

    @State private var profile: SocialProfile?
    @State private var isLoading = false
    @State private var isTogglingFollow = false
    @State private var loadError: String?
    /// Последняя ошибка загрузки как ТИП, а не как текст: закрытый профиль
    /// отличается от обрыва связи кодом, и строка эту разницу уже потеряла.
    @State private var loadFailure: APIError?
    @State private var followListMode: FollowListMode?
    @State private var isBlocked = false
    @State private var showBlockConfirm = false
    // Report flow paused until moderation UI exists; state intentionally omitted.
    @State private var selectedBadge: Badge?
    /// Presentation-only grid ↔ list toggle for the trips section (Figma
    /// 117:931 draws the 2-col mini-poster grid as default).
    /// Canon 580:438 opens on the LIST. The grid is the second choice,
    /// not the landing one.
    @State private var tripsAsGrid = false
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
    /// The profile's trips as feed cards. Held apart from `profile` because
    /// reacting rewrites ONE card and `SocialProfile` is a `let`-only DTO —
    /// rebuilding the whole profile to bump a tally would redraw the hero,
    /// the stats and the achievements with it.
    @State private var tripCards: [SocialFeedTrip] = []
    /// Long-pressed a card (or its «Реакция» pill) — the emoji palette.
    @State private var reactionPickerTrip: SocialFeedTrip?
    /// A trip being shared from its card's «…».
    @State private var tripLinkShare: TripLinkShare?
    /// Someone else's trip being reported from its card's «…». Same entry the
    /// feed's cards have — a trip is reportable wherever it is shown, or the
    /// answer to «where do I report this?» becomes «find it in the feed».
    @State private var tripPendingReport: SocialFeedTrip?

    /// `sheet(item:)` payload — the trip plus the link we managed to mint for
    /// it, which may be nil when `/social/share` was unreachable.
    private struct TripLinkShare: Identifiable {
        let id = UUID()
        let trip: SocialFeedTrip
        let url: String?
    }

    /// True when this view is rendering the signed-in user's own profile
    /// (e.g. "preview as others see you"). Hides Follow/Block/Report actions.
    private var isOwnProfile: Bool {
        TokenStore.shared.accountId == accountId
    }

    /// Route follow-list navigation through the shared path when one is
    /// wired in (sheet context) so deep flows stay capped; fall back to
    /// local state push for main-feed usage.
    /// Whether a trip on this page can be opened. Needs a path to push onto
    /// AND a host that renders trip destinations on it.
    ///
    /// A stranger's trip used to be un-openable on any host: the profile
    /// payload was a six-field summary with nothing to render a detail screen
    /// from. It is a full feed item now, so `.socialTrip` carries everything
    /// `TripDetailView` needs — exactly as a tap in the Лента does.
    private var canOpenTrips: Bool { opensTrips && pushPath != nil }

    private func openTrip(_ trip: SocialFeedTrip, focus: TripFocus = .top) {
        guard canOpenTrips else { return }
        Haptics.tap()
        // Own trips open the local copy (edit pencil, privacy toggle, the
        // owner's «…»); everyone else's open from the payload we already hold.
        pushPath?.wrappedValue.cappedAppend(
            isOwnTrip(trip) ? .trip(trip.id, focus: focus) : .socialTrip(trip, focus: focus)
        )
    }

    /// Открыть чужую статистику / карту. Оба экрана живут в том же
    /// NavigationStack, что и профиль, поэтому кнопка «назад» возвращает
    /// именно сюда, а не на корень таба.
    private func openStats() {
        guard let pushPath else { return }
        pushPath.wrappedValue.cappedAppend(.publicStats(accountId, resolvedDisplayName))
    }

    private func openMap() {
        guard let pushPath else { return }
        pushPath.wrappedValue.cappedAppend(.publicMap(accountId, resolvedDisplayName))
    }

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

    /// «Поделиться профилем». Both failures this had — the sheet not opening
    /// at all (raised while the «…» popover was still dismissing) and its
    /// «Скопировать» copying nothing — live in `ShareLinkPresenter` now, which
    /// every link share in the app goes through.
    @MainActor
    private func shareProfile() async {
        guard let url = profileShareURL else { return }
        await ShareLinkPresenter.present(url: url, title: resolvedDisplayName)
    }

    private func copyProfileLink() {
        guard let url = profileShareURL else { return }
        UIPasteboard.general.string = url.absoluteString
        Haptics.success()
        toastItem = ToastItem(type: .success, message: AppStrings.profileLinkCopied(lang.language))
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
                runProfileAction { Task { await shareProfile() } }
            },
            .init(
                title: AppStrings.copyProfileLink(lang.language),
                systemImage: "link",
                accessibilityId: "profile_copy_link"
            ) {
                runProfileAction { copyProfileLink() }
            },
        ]
        // Canon 1630:150 draws the own-profile «⋯» with share and copy-link and
        // nothing else — reporting or blocking yourself is not an action, and
        // both endpoints take a target that can't be the caller.
        guard auth.isSignedIn, !isOwnProfile else { return items }
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
        let lng = lang.language
        if let p = profile?.displayName, !p.isEmpty { return p }
        if let p = preloaded?.displayName, !p.isEmpty { return p }
        if isOwnProfile, let n = auth.userName, !n.isEmpty { return n }
        return AppStrings.publicProfileDriver(lng)
    }

    /// Canon titles the bar «@alexandr» (580:444). The handle is device-local
    /// (`SettingsManager.profileUsername`, no account field behind it yet) and
    /// the profile DTO carries none, so only the viewer's own preview can show
    /// one — everyone else's bar keeps the display name it had.
    private var navTitle: String {
        guard isOwnProfile else { return resolvedDisplayName }
        let handle = settings.profileUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return handle.isEmpty ? resolvedDisplayName : "@\(handle)"
    }

    /// «О себе». The server field only exists on 0.6+, so in the viewer's own
    /// preview fall back to what they typed locally — `refresh()` pushes it up
    /// on this very screen, and a blank line under your own name reads as the
    /// bio having been lost rather than as a server that hasn't shipped yet.
    private var resolvedBio: String? {
        let server = profile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !server.isEmpty { return server }
        guard isOwnProfile else { return nil }
        let local = settings.profileBio.trimmingCharacters(in: .whitespacesAndNewlines)
        return local.isEmpty ? nil : local
    }

    /// True when this preview is showing something the server does not have,
    /// i.e. something no other person can actually see.
    ///
    /// The handle, the flag and the bio are stored on this device only —
    /// `ProfileUpdateRequest` carries none of them yet. Drawing them is right:
    /// they are what the page WILL look like, and blanking them reads as data
    /// loss. Drawing them silently, on a screen whose title is «так ваш профиль
    /// видят другие», is not.
    private var hasDeviceOnlyIdentity: Bool {
        guard isOwnProfile else { return false }
        let localHandle = !settings.profileUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let localCountry = !settings.profileCountry.isEmpty
        let serverBio = profile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localBio = serverBio.isEmpty
            && !settings.profileBio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return localHandle || localCountry || localBio
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let lng = lang.language

        ScrollView {
            VStack(spacing: 0) {
                // Canon 580:438 puts the «так ваш профиль видят другие» cue
                // HERE — a card at the top of the content, under an ordinary
                // nav bar. It used to be gated on `hasDeviceOnlyIdentity`
                // because a persistent orange strip one level up
                // (`PreviewNavigator.selfPreviewBanner`) already carried the
                // mode, and two banners saying the same thing stacked. That
                // strip is gone with the fullScreenCover that hosted it, so
                // this card is now the ONLY thing distinguishing this page
                // from a stranger's — it has to be up whenever the profile
                // on screen is the viewer's own. The device-only caveat
                // stays as its second line, still on its own gate.
                if isOwnProfile {
                    previewBanner(c)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }

                // Skeleton placeholder until the first `loadProfile()`
                // succeeds. Using `ZStack` with opacity-driven transition
                // keeps the scroll offset stable between skeleton and real
                // content — swapping branches via `if/else` would reset the
                // ScrollView state.
                ZStack {
                    if profile != nil {
                        VStack(spacing: 16) {
                            heroSection(c)
                                .padding(.top, 6)

                            // Видимость (0.6.3) действует и на своём экране.
                            // Этот экран для владельца — ПРЕВЬЮ «как видят
                            // другие» (см. previewBanner), и оговорка
                            // «|| isOwnProfile» превратила бы его в ложь:
                            // владелец видел бы блоки, которых у других нет.
                            // Свои полные данные у него в табе «Я».
                            // Карточка рисуется всегда: внутри неё тумблер
                            // гасит только дорожные числа, а счётчики подписок
                            // остаются входом в списки.
                            statsGrid(c, lng: lng)
                                .padding(.horizontal, 16)

                            // Скрытый блок исчезает целиком — ни плашки
                            // «скрыто», ни серой заглушки: прецедент правила
                            // про госномер.
                            if visibility.stats, canOpenHub {
                                statsEntryCard(c, lng: lng)
                                    .padding(.horizontal, 16)
                            }
                            if visibility.map, canOpenHub {
                                mapEntryCard(c, lng: lng)
                                    .padding(.horizontal, 16)
                            }

                            if visibility.achievements {
                                achievementsSection(c)
                                    .padding(.horizontal, 16)
                            }

                            recentTrips(c, lng: lng)
                                .padding(.horizontal, 16)
                        }
                        .transition(.opacity)
                    } else if let failure = loadFailure {
                        // Включая `.transient`: без этой ветки сетевой отказ
                        // рисовал бы скелетон вечно — без слова и без повтора.
                        unavailableScreen(
                            ProfileUnavailableState.from(error: failure, preloaded: preloaded), c)
                    } else {
                        SkeletonProfileView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: profile != nil)
            }
            // Bottom inset clears the floating CustomTabBar so the last trip
            // card is fully visible. Matches FeedView's 120pt inset.
            .padding(.bottom, 120)
            // Pins the content to the scroll view's width. A vertical
            // ScrollView does NOT clamp its content horizontally: one greedy
            // child (the trips grid, sizing its columns off a long title's
            // ideal width) widened EVERY sibling, and the stats card silently
            // grew — which is why its captions changed size when the layout
            // toggle flipped. Nothing above needs to be wider than the screen.
            .containerRelativeFrame(.horizontal)
        }
        // Тот же приём, что в ленте: скролл доходит до физического низа экрана.
        // Без этого он останавливается над домашним индикатором, а плавающий
        // таб-бар безопасную зону игнорирует — и 120pt отступа превращались в
        // 120 + высота индикатора. В ленте этого не видно, потому что до её
        // конца никто не доскроллил; профиль кончается всегда, и пустая
        // полоса под последней карточкой была последним, что человек видит.
        .ignoresSafeArea(edges: .bottom)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            CustomNavBar(title: navTitle) {
                // Single «…» entry point (Figma 117:2367) — sharing on top,
                // moderation below. The block hand used to sit as its own
                // icon right next to «…»: two tiny targets 2pt apart in the
                // same corner, one of them a one-tap path into a destructive
                // confirm.
                //
                // Drawn on every profile now, own preview included (canon
                // 580:445 / 1630:150). It used to be swapped for a close «×»
                // at a sheet root, which is why a profile opened from the
                // companions roster or the comments sheet had no way to share
                // — or to report — at all.
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
            tripCards = []
            Task { await refresh() }
        }
        .refreshable { await refresh() }
        // Commented on a trip from the detail screen pushed off THIS page —
        // the card behind it has to come back with the new count, exactly as
        // the feed's cached cards do. Without it you close the discussion and
        // the card still says what it said before you wrote.
        .onReceive(NotificationCenter.default.publisher(for: .tripCommentCountChanged)) { note in
            guard
                let tripId = note.userInfo?["tripId"] as? UUID,
                let delta = note.userInfo?["delta"] as? Int,
                let idx = tripCards.firstIndex(where: { $0.id == tripId })
            else { return }
            let updated = max(0, tripCards[idx].commentCount + delta)
            tripCards[idx] = tripCards[idx].with(commentCount: updated)
        }
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
        .sheet(item: $tripLinkShare) { share in
            SharedTripLinkSheet(trip: share.trip, shareUrl: share.url)
                .environmentObject(lang)
        }
        .sheet(item: $tripPendingReport) { trip in
            ReportSheet(target: .trip(trip.id))
                .environmentObject(lang)
        }
        .toast(item: $toastItem)
        .overlay {
            // Emoji palette for a long-pressed card. An overlay, not a sheet:
            // it is the same picker the Лента raises over its own cards.
            if let picked = reactionPickerTrip {
                ReactionPickerOverlay(
                    currentReaction: picked.myReaction,
                    onPick: { emoji in
                        Task { await toggleReaction(picked.id, emoji: emoji) }
                        reactionPickerTrip = nil
                    },
                    onDismiss: { reactionPickerTrip = nil }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
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
        .appConfirm(
            isPresented: $showBlockConfirm,
            title: AppStrings.blockProfileConfirmTitle(lang.language, isBlocked: isBlocked),
            message: AppStrings.blockProfileConfirmBody(lang.language, isBlocked: isBlocked),
            actions: [
                // Blocking is destructive; UNblocking is the restorative half of
                // the same button, and painting «Разблокировать» red asks the
                // user to confirm a kindness in the colour of a deletion.
                AppDialogAction(AppStrings.blockProfileAction(lang.language, isBlocked: isBlocked),
                                kind: isBlocked ? .primary : .destructive) {
                    guard auth.isSignedIn else {
                        signInPrompt = .generic
                        return
                    }
                    Task { await toggleBlock() }
                }
            ],
            cancelTitle: AppStrings.cancel(lang.language)
        )
    }

    // MARK: - Профиль не открылся (0.6.3)

    /// Один экран на два случая, и разница между ними — не косметика.
    ///
    /// `.closed` показывает имя и аватар, потому что человека только что видели
    /// в публичной ленте: его существование уже публично, и молчать о нём —
    /// значит выглядеть сломанным приложением без единой выгоды для приватности.
    ///
    /// `.unavailable` — переход по прямой ссылке. Здесь нельзя ни назвать
    /// человека, ни подтвердить, что аккаунт есть: сервер отвечает одинаково на
    /// «нет такого», «закрыт» и «вы заблокированы» именно для того, чтобы по
    /// ссылке нельзя было это проверить.
    @ViewBuilder
    private func unavailableScreen(
        _ state: ProfileUnavailableState, _ c: AppTheme.Colors
    ) -> some View {
        let l = lang.language
        VStack(spacing: 12) {
            switch state {
            case .closed(let name, let avatar):
                Text(avatar ?? "🙂")
                    .font(.system(size: 44))
                    .frame(width: 84, height: 84)
                    .background(c.cardAlt, in: Circle())
                Text(name)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(c.text)
                Image(systemName: "lock")
                    .font(.system(size: 18))
                    .foregroundStyle(c.textTertiary)
                Text(AppStrings.closedProfileTitle(l))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                Text(AppStrings.closedProfileBody(l))
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(c.textTertiary)

            case .unavailable:
                Circle()
                    .fill(c.cardAlt)
                    .frame(width: 84, height: 84)
                Image(systemName: "lock")
                    .font(.system(size: 18))
                    .foregroundStyle(c.textTertiary)
                Text(AppStrings.profileUnavailableTitle(l))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                Text(AppStrings.profileUnavailableBody(l))
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(c.textTertiary)

            case .transient:
                // Отказ загрузки, а не закрытый профиль: ничего не утверждаем
                // про человека и предлагаем повтор.
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(c.textTertiary)
                Text(AppStrings.publicDataLoadFailed(l))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                Button { Task { await loadProfile() } } label: {
                    Text(AppStrings.retry(l))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("profile_unavailable")
    }

    // MARK: - Preview banner

    /// «Так ваш профиль видят другие» (canon 580:544). Only the viewer's own
    /// profile draws it, and it has to stay the first thing on the screen:
    /// everything below is a faithful copy of a stranger's profile, so without
    /// this card there is nothing at all to tell the two apart.
    ///
    /// The title is the same wording the «Я» hub puts on the row that opens
    /// this screen — one flow, one phrase. Canon's second line says what the
    /// screen cannot do, and it says it always: the limits of a preview are
    /// not a per-account fact. The third line is, so it only shows up on an
    /// account that still holds fields on the device.
    private func previewBanner(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                // SF Symbol rather than canon's 👁 emoji — the emoji keeps its
                // own colours in dark mode, where this card is a dark surface.
                Image(systemName: "eye.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(AppStrings.myProfileRowPreview(lang.language))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(c.text)
                    Text(AppStrings.previewBannerSubtitle(lang.language))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textSecondary)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile_preview_banner")

            // Third line, and OUTSIDE the card: the plaque is two lines by
            // design, and this sentence is only true for an account that still
            // holds fields the server has never seen. Inside the card it grew
            // the plaque by half and made a permanent notice out of a
            // conditional one.
            if hasDeviceOnlyIdentity {
                Text(AppStrings.previewBannerBody(lang.language))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("profile_preview_device_only")
            }
        }
    }

    // MARK: - Hero

    /// Avatar, name, level, flag, bio, action — centred straight on the page.
    /// Canon (580:451, 580:579, 1635:119) has no header card and no cover
    /// banner behind the avatar on either the preview or a stranger's profile;
    /// the first surface on the screen is the stats card.
    private func heroSection(_ c: AppTheme.Colors) -> some View {
        let avatarSize: CGFloat = 84
        let emoji = profile?.avatarEmoji ?? preloaded?.avatarEmoji ?? "🚗"

        return VStack(spacing: 0) {
            Text(emoji)
                .font(.system(size: avatarSize * 0.52))
                .frame(width: avatarSize, height: avatarSize)
                .background(Circle().fill(c.cardAlt))

            // Long-press copies the name. It is the one string that can be
            // pasted into Поиск and actually find this person again: the
            // server matches display names, and the @handle is still
            // device-local (no profile field behind it).
            Text(resolvedDisplayName)
                .font(.system(size: 21, weight: .heavy))
                .tracking(-0.21)
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .contentShape(Rectangle())
                .onLongPressGesture {
                    UIPasteboard.general.string = resolvedDisplayName
                    Haptics.success()
                    toastItem = ToastItem(
                        type: .success,
                        message: AppStrings.profileNameCopied(lang.language)
                    )
                }
                .accessibilityIdentifier("profile_display_name")

            // Rank and flag on ONE line, the flag trailing. They are two chips
            // of the same kind — who this driver is — and stacking them put a
            // third centred pill under the name, which made the hero read as a
            // column of badges before the numbers even started.
            HStack(spacing: 8) {
                if let lvl = profile?.profileLevel ?? preloaded?.profileLevel {
                    LvlPill(level: lvl, rankTitle: DriverRank.from(level: lvl).title(lang.language))
                }

                // Country (canon 1717:135). Device-local like the handle, so it
                // renders in the owner's preview and nowhere else — see
                // `countryGlyph`. «Не указывать» has no glyph and draws no pill.
                if let glyph = countryGlyph {
                    Text(countryPillText(glyph))
                        .font(.system(size: 13))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(c.cardAlt, in: Capsule())
                        .accessibilityIdentifier("profile_country")
                }
            }
            .padding(.top, 8)

            // Width-capped so a long line wraps into a centred block instead
            // of running the full screen width.
            if let bio = resolvedBio {
                Text(bio)
                    .font(.system(size: 13.5))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    // The editor accepts 140 characters; at 13.5pt over 290pt
                    // that is three lines, and two clipped a full bio for
                    // every viewer.
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290)
                    .padding(.top, 12)
                    .accessibilityIdentifier("profile_bio")
            }

            heroAction(c)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    /// Canon 1717:135 pairs the flag with the country's name, except for the
    /// neutral flag, which stands for «no country» and has no name to pair.
    private func countryPillText(_ glyph: String) -> String {
        let stored = settings.profileCountry.isEmpty ? nil : settings.profileCountry
        guard let stored, stored != CountryChoice.neutral else { return glyph }
        return "\(glyph) \(CountryChoice.label(for: stored, lang.language))"
    }

    /// The flag for the stored country, or nil for «Не указывать» — and nil on
    /// anybody else's profile, because `profileCountry` is this device's
    /// setting and the profile DTO carries no country at all.
    private var countryGlyph: String? {
        guard isOwnProfile else { return nil }
        return CountryChoice.glyph(for: settings.profileCountry.isEmpty ? nil : settings.profileCountry)
    }

    /// Where a stranger's profile offers «Подписаться», the owner's preview
    /// stands a dead pill of the same shape. Same chrome, same footprint, so
    /// switching between the two views doesn't move anything under the thumb.
    @ViewBuilder
    private func heroAction(_ c: AppTheme.Colors) -> some View {
        if isOwnProfile {
            Text(AppStrings.previewThisIsYou(lang.language))
                .socialActionButton(.inert, colors: c, width: 130)
                .accessibilityIdentifier("profile_this_is_you")
                .accessibilityAddTraits(.isStaticText)
        } else if !auth.isSignedIn || profile?.isFollowing != nil {
            // Guests get the CTA too: the backend omits `isFollowing`
            // for unauthenticated requesters (it decodes nil), so gating
            // on non-nil alone hid the primary Figma CTA (117:931) — and
            // its sign-in funnel — from every signed-out viewer. The
            // button's own guard routes guests to the sign-in prompt.
            followButton(c, lng: lang.language)
        }
    }

    @ViewBuilder
    private func followButton(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
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
                        // Matches the chrome it spins on: the done state is an
                        // accent tint with accent ink, not a grey chip.
                        .tint(isFollowing ? AppTheme.accent : .white)
                }
                Text(isFollowing
                     ? (AppStrings.notificationsInboxFollowing(lng))
                     : (AppStrings.discoverFollow(lng)))
                // Canon 1635:145 puts the tick AFTER the word and draws no
                // glyph at all on the offer — a leading «+» made «Подписаться»
                // read as «add», which is a different promise.
                if isFollowing && !isTogglingFollow {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            // Pinned to canon's 130pt (117:969) so it keeps the footprint of
            // the «Это вы» pill that stands in its place on your own preview.
            .socialActionButton(isFollowing ? .done : .primary, colors: c, width: 130)
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
    private var isPrivacyMode: Bool {
        guard !isOwnProfile, let p = profile else { return false }
        let tripCount = p.stats.tripCount
        return tripCount == 0 && (p.profileLevel > 1 || p.currentStreak > 0 || p.bestStreak > 0)
    }

    private func statsGrid(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        let stats = profile?.stats
        let privacy = isPrivacyMode
        let dots = "•••"
        let tripsValue = privacy ? dots : (stats.map { String($0.tripCount) } ?? "—")
        // Grouped like every other km figure in the app — a bare "%.0f"
        // printed «38420» beside «2 430» two cards away.
        let kmValue = privacy ? dots : (stats.map { GarageFormat.odometer($0.totalKm) } ?? "—")
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
                // Тумблер обещает спрятать «поездки, километры и регионы» — и
                // прячет ровно их. Счётчики подписок остаются: они не дорожные
                // числа, и это ЕДИНСТВЕННЫЙ вход в списки подписок.
                if visibility.counters {
                    HStack(spacing: 0) {
                        statCell(value: tripsValue, label: AppStrings.trips(lang.language), c: c)
                        columnRule(c)
                        statCell(value: kmValue, label: AppStrings.km(lang.language), c: c)
                        columnRule(c)
                        statCell(value: regionsValue, label: AppStrings.statsRegions(lang.language), c: c)
                    }
                    divider(c)
                }
                HStack(spacing: 0) {
                    followCounterCell(
                        count: followerShown,
                        label: AppStrings.followersCaption(lang.language, n: followerShown),
                        mode: .followers, c: c
                    )
                    columnRule(c)
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
                    Text(AppStrings.publicProfileHiddenRoadsThis(lng))
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
        VStack(spacing: 3) {
            // Canon draws these big — they are the point of the card, and at 16
            // they measured the same as the row of chips above and read as a
            // caption. `minimumScaleFactor` rather than a smaller size: only
            // «2 430» in a third of a 360pt phone ever needs to give way.
            Text(value)
                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // Canon (580:467) sets these lowercase and quiet. They were
            // uppercase and tracked, which put more emphasis on «ПОДПИСЧИКОВ»
            // than on the number above it.
            //
            // NO `minimumScaleFactor` here, deliberately: it made the label
            // shrink or not depending on how much width the card happened to
            // get, and the trips grid two sections down was handing out
            // different widths in list and grid mode — so «подписчиков» visibly
            // changed size when the user flipped the layout toggle.
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Hairline between two cells of the same row (canon 580:468 rules every
    /// column but the first). Fixed height rather than full-bleed so it
    /// matches the rule `ProfileStatsStrip` draws on the Я tab.
    private func columnRule(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.border)
            .frame(width: 1, height: 34)
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

    /// Full-width hairline between the two rows of the stats card — heavier
    /// than the column rules, which is how canon (580:474) keeps the road
    /// numbers and the social counters reading as two separate rows.
    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.borderBright)
            .frame(height: 1)
    }

    // MARK: - Хаб: входы в статистику и карту (0.6.3)

    /// Что владелец профиля разрешил показывать. Сервер без этой фичи ключа не
    /// шлёт — тогда открыто всё, ровно как было до 0.6.3.
    private var visibility: SocialProfileVisibility {
        profile?.visibility ?? .open
    }

    /// Есть ли куда открывать хаб-карточки.
    ///
    /// Два хоста показывают профиль без своего пути навигации
    /// (`FollowListView` в старом режиме и `TripDetailView`). Там карточка
    /// нарисовалась бы, но не открывала бы ничего — а мёртвая кнопка хуже её
    /// отсутствия. Тот же приём, что у `canOpenTrips` строкой выше.
    private var canOpenHub: Bool { pushPath != nil }

    /// Карточка-вход. Показывается ТОЛЬКО когда блок открыт — в том числе на
    /// собственном превью: этот экран для владельца и есть «как видят другие»,
    /// и показывать в нём спрятанное значило бы врать про результат настройки.
    /// Свои полные данные у владельца в табе «Я».
    private func hubCard(
        _ c: AppTheme.Colors,
        title: String,
        subtitle: String,
        @ViewBuilder body: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(c.text)
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(c.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(c.textTertiary)
                }
                body()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(c.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Плашки-тизера на карточке «Статистика».
    ///
    /// Только те факты, которые УЖЕ приехали с профилем и которых нет в
    /// карточке счётчиков выше. Рекорды вроде «самой длинной» сюда сознательно
    /// не попали: у нас на руках лишь десяток последних поездок, и назвать
    /// самую длинную ИЗ НИХ самой длинной вообще — это ровно то враньё точной
    /// цифрой, которое аудит профиля заносил в P0.
    private func statsTeaserFacts(
        _ lng: LanguageManager.Language
    ) -> [(value: String, label: String)] {
        guard let p = profile else { return [] }
        var facts: [(String, String)] = []
        if let last = p.recentTrips.first {
            facts.append((ProfileDateFormat.dayMonth(last.startDate, lang: lng),
                          AppStrings.profileTeaserLastTrip(lng)))
        }
        if p.currentStreak > 0 {
            facts.append((AppStrings.daysCount(lng, n: p.currentStreak),
                          AppStrings.profileTeaserStreak(lng)))
        }
        return facts
    }

    private func statsEntryCard(
        _ c: AppTheme.Colors, lng: LanguageManager.Language
    ) -> some View {
        let facts = statsTeaserFacts(lng)
        return hubCard(
            c,
            title: AppStrings.stats(lng),
            subtitle: AppStrings.profileStatsEntrySubtitle(lng),
            body: {
                // График из двух значений красивым не бывает — вместо него
                // компактные плашки, которые работают и при одной поездке.
                if !facts.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                            VStack(spacing: 2) {
                                Text(fact.value)
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(c.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(fact.label)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(c.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            },
            action: { openStats() }
        )
    }

    private func mapEntryCard(
        _ c: AppTheme.Colors, lng: LanguageManager.Language
    ) -> some View {
        hubCard(
            c,
            title: AppStrings.profileMapEntryTitle(lng),
            subtitle: AppStrings.profileMapEntrySubtitle(lng),
            body: {
                VStack(alignment: .leading, spacing: 6) {
                    // Настоящие маршруты, а не серый прямоугольник с системной
                    // иконкой: полилинии уже приехали в `recentTrips`, так что
                    // превью ничего не стоит и показывает именно эту карту.
                    let routes = (profile?.recentTrips ?? [])
                        .map(\.previewCoordinates)
                        .filter { $0.count >= 2 }
                    RoundedRectangle(cornerRadius: 12)
                        .fill(c.cardAlt)
                        .frame(height: 120)
                        .overlay(
                            Group {
                                if routes.isEmpty {
                                    Image(systemName: "map")
                                        .font(.system(size: 26, weight: .light))
                                        .foregroundStyle(c.textTertiary)
                                } else {
                                    // Настоящие тайлы: две линии на пустом
                                    // фоне читаются как график, а не как карта.
                                    // Здесь это одна карточка на экране, а не
                                    // ячейка списка, так что MapKit по силам.
                                    CardMapPreview(routes: routes)
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    // Рамка обязательна: счётчики считаются по ВСЕМ поездкам,
                    // включая приватные, а карта рисует только публичные —
                    // «47 поездок» и карта с двенадцатью маршрутами оказываются
                    // на расстоянии одного тапа.
                    Text(AppStrings.publicRoutesCaption(lng))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                }
            },
            action: { openMap() }
        )
    }

    // MARK: - Achievements

    /// «Достижения» card (canon 1667:206): the rarest award on a wash of its
    /// own tier, then a strip of discs and a «+N» capsule.
    ///
    /// Deliberately NOT `ProfileAchievementsSection`. That component derives
    /// everything from `trips: [Trip]` — the viewer's own CoreData — so on
    /// somebody else's profile it would draw the VIEWER's collection under a
    /// stranger's name. This screen only ever knows `recentBadges`, the id
    /// list the server sends for the account being looked at.
    @ViewBuilder
    private func achievementsSection(_ c: AppTheme.Colors) -> some View {
        let badges = orderedBadges
        if let featured = badges.first {
            let rest = Array(badges.dropFirst())
            let strip = Array(rest.prefix(Self.achievementsStripLimit))
            let overflow = rest.count - strip.count

            VStack(spacing: 12) {
                // Canon prints «12 из 45 ›» opposite the label. It stays off
                // until `/social/profile` sends an unlocked/total pair: the
                // only counts the client holds are its own, and the id list
                // here is a server-truncated "recent", not the collection.
                ProfileSectionLabel(text: AppStrings.achievementsSection(lang.language))
                    .frame(maxWidth: .infinity, alignment: .leading)

                featuredBadgeRow(featured, c)

                if !strip.isEmpty || overflow > 0 {
                    HStack(spacing: 0) {
                        ForEach(strip) { badge in
                            Button {
                                Haptics.tap()
                                selectedBadge = badge
                            } label: {
                                badgeChip(badge, iconSize: 15)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }

                        if overflow > 0 {
                            Text("+\(overflow)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                                .frame(width: 34, height: 30)
                                .background(c.cardAlt, in: Capsule())
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: 16)
            .accessibilityIdentifier("profile_achievements")
        } else {
            // A driver with nothing unlocked yet used to get NO card at all,
            // so their profile silently lost a section every other profile
            // has — which reads as a screen that failed to load its
            // achievements, not as a collection that hasn't started.
            VStack(spacing: 12) {
                ProfileSectionLabel(text: AppStrings.achievementsSection(lang.language))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(c.cardAlt)
                        Image(systemName: "rosette")
                            .font(.system(size: 15))
                            .foregroundStyle(c.textTertiary)
                    }
                    .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppStrings.achievementsEmpty(lang.language))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(c.textSecondary)
                        // Second person for your own preview, third for
                        // somebody else's page — «пока вы ездите» under a
                        // stranger's name is a sentence about the wrong driver.
                        Text(isOwnProfile
                             ? AppStrings.achievementsEmptyHint(lang.language)
                             : AppStrings.achievementsEmptyOtherHint(lang.language))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(cornerRadius: 16)
            .accessibilityIdentifier("profile_achievements_empty")
        }
    }

    /// How many discs fit beside the «+N» capsule at 360pt.
    private static let achievementsStripLimit = 6

    /// Rarest first, catalogue order breaking a tie — so the awards worth
    /// showing are the ones that fit. Ids the client doesn't know (a badge
    /// added server-side after this build) drop out rather than draw blank.
    private var orderedBadges: [Badge] {
        let badges = (profile?.recentBadges ?? []).compactMap { id in
            Badge.all.first(where: { $0.id == id })
        }
        return badges.enumerated()
            .sorted { a, b in
                a.element.displayRarity == b.element.displayRarity
                    ? a.offset < b.offset
                    : a.element.displayRarity > b.element.displayRarity
            }
            .map(\.element)
    }

    /// The one award worth reading a line about — the rest of the card is
    /// discs. No «Закреплено» here: the pin is a local `SettingsManager` key,
    /// so it is only ever true of the viewer, never of the profile shown.
    private func featuredBadgeRow(_ badge: Badge, _ c: AppTheme.Colors) -> some View {
        let rarity = badge.displayRarity
        return Button {
            Haptics.tap()
            selectedBadge = badge
        } label: {
            HStack(spacing: 10) {
                badgeChip(badge, iconSize: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(badge.title(lang.language))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)

                    Text(featuredBadgeSubtitle(badge))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(rarity.chipText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rarity.rowTint, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// «Легендарное · 0,4%» — the global share only when the catalogue carries
    /// one, so a missing part leaves no dangling « · ».
    private func featuredBadgeSubtitle(_ badge: Badge) -> String {
        var parts = [badge.displayRarity.title(lang.language)]
        if let percent = badge.globalUnlockPercent {
            parts.append(Badge.unlockShareText(percent, lang.language) + "%")
        }
        return parts.joined(separator: " · ")
    }

    /// The 30pt rarity disc (canon 1667:213). Two colours only — the glyph
    /// takes the tier's ink, not `badge.color`, so a green glyph never lands
    /// inside a purple ring.
    private func badgeChip(_ badge: Badge, iconSize: CGFloat) -> some View {
        let rarity = badge.displayRarity
        return ZStack {
            Circle().fill(rarity.chipTint)
            Circle().strokeBorder(rarity.chipRing, lineWidth: 1.5)
            Image(systemName: badge.icon)
                .font(.system(size: iconSize))
                .foregroundStyle(rarity.chipText)
        }
        .frame(width: 30, height: 30)
    }

    /// Canon page header (580:490) — the 11pt uppercase tertiary label every
    /// other social screen already uses. Note the achievements CARD titles
    /// itself differently, in 16 heavy inside its own surface (1667:208).
    private func sectionHeader(_ title: String, c: AppTheme.Colors) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.44)
            .textCase(.uppercase)
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Recent trips

    @ViewBuilder
    private func recentTrips(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        if !tripCards.isEmpty {
            let publicCount = profile?.stats.publicTripCount ?? tripCards.count
            let totalCount = profile?.stats.tripCount ?? tripCards.count
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    sectionHeader(
                        tripsHeaderTitle(public: publicCount, total: totalCount, lng: lng),
                        c: c
                    )
                    layoutToggle(c)
                }

                if tripsAsGrid {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(tripCards) { t in
                            openable(t) { tripGridCell(t, c: c, lng: lng) }
                        }
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(tripCards) { t in
                            tripCard(t)
                        }
                    }
                }
            }
        } else if let err = loadError {
            // Error takes priority over the empty state so a failed refresh
            // of an already-loaded profile doesn't silently fall back to
            // "No public trips yet" — user needs to know the fetch failed.
            errorRow(err, c: c, lng: lng)
        } else if profile != nil {
            emptyTripsHint(c, lng: lng)
        } else if isLoading {
            skeleton()
        }
    }

    /// «Поездки · 47 · всего 52» as one label rather than four Texts in three
    /// sizes — canon (117:1339) writes the counts into the header line itself.
    /// The «всего» tail only appears when the owner is holding trips back, so
    /// the public number doesn't read as their whole road history.
    private func tripsHeaderTitle(public publicCount: Int, total: Int, lng: LanguageManager.Language) -> String {
        let head = "\(AppStrings.tripsTab(lng)) · \(publicCount)"
        guard total > publicCount else { return head }
        return head + " · " + AppStrings.publicProfileTripsTotal(lng, total: total)
    }

    /// The Лента's card itself — author line, title, map, metric strip,
    /// reactions, comment count.
    ///
    /// This screen used to draw a card of its own from the six fields the
    /// profile endpoint sent, which is why a trip here was a strictly poorer
    /// object than the identical trip in the feed: no time, no average speed,
    /// nothing to react to and nothing to open. `/users/:id/profile` now
    /// builds its trips with the FEED's item builder, so there is nothing left
    /// to draw differently — and one card means the profile can't drift out of
    /// sync with the feed the next time the card grows a row.
    private func tripCard(_ trip: SocialFeedTrip) -> some View {
        let isOwn = isOwnTrip(trip)
        return SocialFeedCardView(
            trip: trip,
            isOwn: isOwn,
            onTapCard: { openTrip(trip) },
            onTapComments: { openTrip(trip, focus: .comments) },
            // No author tap: this IS that author's page. Pushing it again
            // would stack a second copy of the screen you are already on.
            onReport: isOwn ? nil : {
                // Reporting needs an account — send a guest through sign-in
                // rather than opening a form that will 401.
                if auth.isSignedIn { tripPendingReport = trip }
                else { signInPrompt = .generic }
            },
            onLongPress: {
                guard !isOwn else { return }
                guard auth.isSignedIn else { signInPrompt = .react; return }
                reactionPickerTrip = trip
            },
            onReact: { emoji in
                guard !isOwn else { return }
                guard auth.isSignedIn else { signInPrompt = .react; return }
                Task { await toggleReaction(trip.id, emoji: emoji) }
            },
            onShare: { shareTrip(trip) }
        )
    }

    private func isOwnTrip(_ trip: SocialFeedTrip) -> Bool {
        trip.author.id == TokenStore.shared.accountId
    }

    /// Optimistic exactly like the feed's: flip the pill now, tell the server,
    /// put the card back if the server refuses.
    @MainActor
    private func toggleReaction(_ tripId: UUID, emoji: String) async {
        guard let idx = tripCards.firstIndex(where: { $0.id == tripId }) else { return }
        let before = tripCards[idx]
        tripCards[idx] = before.togglingReaction(emoji)
        do {
            try await SocialReactions.send(
                tripId: tripId, previous: before.myReaction, emoji: emoji
            )
        } catch {
            // Re-find by id: a refresh can replace the whole array while the
            // POST is in flight, and the captured index would then stamp this
            // card over a DIFFERENT trip's slot.
            if let current = tripCards.firstIndex(where: { $0.id == tripId }) {
                tripCards[current] = before
            }
            profileLog.error("profile react failed: \(error.localizedDescription)")
        }
    }

    /// Mint a share link, then hand the trip to the same compact sheet the
    /// feed uses. A refused or unreachable `/social/share` still opens it —
    /// the sheet degrades to the link-less variant rather than to nothing.
    private func shareTrip(_ trip: SocialFeedTrip) {
        Task {
            var link: String?
            do {
                let res: SocialShareResponse = try await APIClient.shared.post(
                    APIEndpoint.socialShare,
                    body: SocialShareRequest(tripId: trip.id, expiresInDays: nil)
                )
                link = res.shareUrl
            } catch {
                profileLog.error("trip share link failed: \(error.localizedDescription)")
            }
            let url = link
            await MainActor.run { tripLinkShare = TripLinkShare(trip: trip, url: url) }
        }
    }

    /// «142», «21,5» — a trailing «.0» on a whole number is the thing that
    /// makes a card look machine-printed.
    private func distanceText(_ km: Double, lng: LanguageManager.Language) -> String {
        GarageFormat.fuel(km, lng: lng)
    }

    /// Wraps a trip tile in a button where a trip can actually be opened, and
    /// leaves it exactly as it is where it can't — see `canOpenTrips`.
    @ViewBuilder
    private func openable<Content: View>(
        _ trip: SocialFeedTrip, @ViewBuilder content: () -> Content
    ) -> some View {
        if canOpenTrips {
            Button { openTrip(trip) } label: {
                content().contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_trip_\(trip.id.uuidString.prefix(8))")
        } else {
            content()
        }
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
    }

    private func layoutToggleButton(
        icon: String, isOn: Bool, c: AppTheme.Colors, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                // Canon draws no plate under either half — the accent alone
                // says which one is on. A chip behind the active icon made the
                // pair read as a segmented control the header does not have.
                .foregroundStyle(isOn ? AppTheme.accent : c.textTertiary)
                .frame(width: 26, height: 22)
                // 44pt of target without 44pt of layout: the same trick
                // `NavCircleIcon` documents.
                .padding(11)
                .contentShape(Rectangle())
                .padding(-11)
        }
        .buttonStyle(.plain)
    }

    /// 2-col mini-poster cell (Figma 117:931): map, title, «дата · км». Three
    /// lines and no more — the tile is the COMPACT half of the toggle, and
    /// time and tallies pushed it into being a small bad card instead of a
    /// good tile (user call 2026-08-14). The full card is one tap away on the
    /// list icon.
    private func tripGridCell(_ trip: SocialFeedTrip, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            gridMap(trip, c: c)

            // `lineLimit(1)` alone still ASKS for the full width of a long
            // title, and a flexible grid column hands it over — the whole
            // scroll content grew wider than the screen, which is what made
            // the stats card's captions change size when the toggle flipped.
            // Truncation is the answer here, not more width.
            Text(TripAutoTitle.localized(
                trip.title, startDate: trip.startDate, language: lang.language
            ) ?? shortDate(trip.startDate, lng: lng))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)

            // Date AND distance: the tile used to carry a bare «142.0 km»,
            // which says nothing about WHEN — the one thing a grid of a
            // person's drives is read for.
            HStack(spacing: 4) {
                // The feed card's own phrasing («14 июн», «Вчера») rather than
                // the full «14 июн 2026» — canon's tile prints «6 апр · 1 240 км»,
                // and a year on every tile is four characters of noise on the
                // narrowest line in the app.
                Text(RelativeTripDate.string(from: trip.startDate, language: lang.language))
                    .foregroundStyle(c.textTertiary)
                Text("·").foregroundStyle(c.textTertiary)
                Text("\(distanceText(trip.distanceKm, lng: lng)) \(AppStrings.km(lang.language))")
                    .foregroundStyle(c.textSecondary)
            }
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func gridMap(_ trip: SocialFeedTrip, c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        if coords.count > 1 {
            // A real map, same as the list — the stylised canvas drew the
            // route as a bare stroke on a beige plate, which reads as a trip
            // whose map failed to load rather than as a poster. `width` is the
            // tile's own slot, not the feed card's 340: rendering wide and
            // cropping to a tile is what put the start dot and the finish flag
            // hard against the edges.
            MapSnapshotPreview(
                coordinates: coords, tripId: trip.id, height: 84, width: 168
            )
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(c.cardAlt)
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .overlay {
                    Image(systemName: "map.slash")
                        .font(.system(size: 16))
                        .foregroundStyle(c.textTertiary)
                }
        }
    }

    private func emptyTripsHint(_ c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "car.fill")
                .font(.system(size: 24))
                .foregroundStyle(c.textTertiary)
            Text(AppStrings.publicProfileNoPublicTrips(lng))
                .font(.system(size: 13))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func skeleton() -> some View {
        SkeletonPlaceholder(shape: .card, count: 2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private func errorRow(_ msg: String, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(.red)
            Text(AppStrings.publicProfileCouldnTLoad(lng))
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
        loadFailure = nil
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
            // The author fallback only matters against a server that still
            // sends the old six-field trip summary — those rows carry no
            // author of their own, and the one they belong to is this page.
            let fallbackAuthor = SocialAuthor(
                id: accountId,
                displayName: p.displayName,
                avatarEmoji: p.avatarEmoji,
                profileLevel: p.profileLevel
            )
            tripCards = p.recentTrips.map { $0.feedTrip(fallbackAuthor: fallbackAuthor) }
            // Trips that arrived without an author came from a server that
            // still sends the old six-field summary — fetch the real items.
            let legacy = p.recentTrips.filter { $0.author == nil }
            if !legacy.isEmpty {
                Task { @MainActor in await hydrateLegacyTrips(legacy) }
            }
            countsLog.debug("loadProfile committed id=\(idPrefix, privacy: .public) state.followingCount=\(p.followingCount, privacy: .public)")
        } catch {
            // Cancellation means `refresh()` replaced us with a newer task —
            // don't surface its error; the newer task owns the outcome.
            if Task.isCancelled { return }
            let msg = (error as? APIError).map { String(describing: $0) }
                ?? error.localizedDescription
            loadError = msg
            loadFailure = error as? APIError
            profileLog.error("profile load failed: \(msg)")
        }
    }

    /// Fills in what a pre-feed-shape profile endpoint left out.
    ///
    /// Such a server sends six fields per trip — no duration, no reactions, no
    /// comment count — and the card would print «0 мин» over somebody's drive.
    /// `/social/trip` is that same feed item for ONE id and has been deployed
    /// far longer, so a handful of small reads make the page whole until the
    /// profile endpoint itself ships. Against a current server this never runs
    /// at all: every trip arrives with its author already on it.
    ///
    /// Failures are silent and per-trip: a card that can't be re-read keeps
    /// what it has rather than disappearing.
    @MainActor
    private func hydrateLegacyTrips(_ legacy: [SocialProfileRecentTrip]) async {
        for trip in legacy {
            if Task.isCancelled { return }
            do {
                let res: SocialTripResponse = try await APIClient.shared.post(
                    APIEndpoint.socialTrip,
                    body: SocialTripRequest(tripId: trip.id, includeTrack: false),
                    requiresAuth: AuthService.shared.isSignedIn
                )
                // Replace BY ID: a refresh may have rebuilt the array while
                // this was in flight, and an index captured before the await
                // could stamp this trip over a different one.
                if let idx = tripCards.firstIndex(where: { $0.id == res.item.id }) {
                    tripCards[idx] = res.item
                }
            } catch {
                profileLog.error("legacy trip hydrate failed: \(error.localizedDescription)")
            }
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

    private func shortDate(_ date: Date, lng: LanguageManager.Language) -> String {
        let f = DateFormatter()
        f.locale = lng.locale
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
            isFollowing: isFollowing, bio: bio, visibility: visibility
        )
    }
}
