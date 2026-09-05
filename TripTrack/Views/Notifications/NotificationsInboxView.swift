import SwiftUI

/// Strava/Twitter-style notifications inbox. Lists reactions and follows
/// triggered against the signed-in user, newest first. Tapping a row
/// marks it read and navigates to the trip / actor profile via the same
/// shared `pushPath` pattern the social feed uses.
struct NotificationsInboxView: View {
    @ObservedObject private var store = NotificationsInboxStore.shared
    /// Backs the `companion_invite` decision rows: `respondedStatus(for:)`
    /// (session-persistent, survives this sheet being dismissed and
    /// reopened) and `myTrips` (for opening a just-accepted invite's trip
    /// — see `openAcceptedInviteTrip`).
    @ObservedObject private var companionsStore = CompanionsStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    /// Injected by both presenters (FeedView, ProfileSettingsSheet) — needed
    /// to re-apply the in-app theme override on the nested prefs sheet.
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// Capped path so deep navigation (Notifications → Trip → Profile →
    /// Trip) doesn't trigger SwiftUI's navigation-stack flash bug we hit
    /// on Discover before. Same pattern as DiscoverView / FeedView.
    @State private var path: [ProfilePreviewDest] = []
    @State private var showPreferences = false
    /// Client-side chip filter over already-loaded items. Pure in-memory —
    /// store, pagination and markAllRead are untouched. Unknown-kind rows
    /// stay visible under «Все».
    @State private var chipFilter: InboxChipFilter = .all
    /// Ids the recipient follows: seeded from the server flag on load, then
    /// kept in sync by the toggle. Session-local state alone showed «В
    /// ответ» to people you already followed, and the tap then died on the
    /// server's AlreadyFollowing.

    @State private var followedBack: Set<UUID> = []
    /// `CompanionsStore.invitePreview(tripId:)` result per notification id.
    /// Cached HERE, not in the store — `invitePreview` is deliberately
    /// stateless (see its doc comment: no cached state, the caller renders
    /// its own failure state) — so a row scrolled off-screen and back
    /// within this sheet's lifetime doesn't refetch. Reopening the sheet
    /// starts fresh, which is fine: a still-pending invite SHOULD refetch
    /// for current data; it's only re-fetching mid-scroll this guards
    /// against.
    @State private var invitePreviews: [UUID: NotificationInviteRowModel.PreviewState] = [:]
    /// A just-accepted invite's trip, looked up from `companionsStore
    /// .myTrips` lazily on tap (see `openAcceptedInviteTrip`) and cached
    /// so a second tap doesn't re-fetch.
    @State private var acceptedInviteTrips: [UUID: SocialFeedTrip] = [:]
    /// Fix 11: trip ids `openAcceptedInviteTrip` is currently paging
    /// through `/companions/my-trips` to resolve, so `infoRow` can show a
    /// spinner instead of leaving a tap that fires up to five requests
    /// with no on-screen sign anything is happening.
    @State private var resolvingAcceptedTripIds: Set<UUID> = []
    @State private var toastItem: ToastItem?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let lng = lang.language

        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header(c: c, lng: lng)
                if !store.items.isEmpty {
                    chipsRow(c: c)
                }
                content(c: c, lng: lng)
            }
                .background(c.bg)
                // Custom header above owns the chrome (Figma 117:1841 draws
                // a push; the sheet keeps its own bar-less stack). Pushed
                // PublicProfileView / FollowListView hide the system bar
                // themselves via CustomNavBar.
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showPreferences) {
                    NotificationPreferencesView()
                        .environmentObject(lang)
                        // .medium cut the footer note off below the fold with
                        // nothing hinting there was more to scroll to. ONE
                        // detent, not two: with a second option the sheet
                        // re-resolves its height whenever the content
                        // re-renders (i.e. on every toggle) and visibly
                        // nudges itself.
                        .presentationDetents([.fraction(0.88)])
                        .presentationDragIndicator(.visible)
                        // Nested sheets are separate presentations — the
                        // override on the inbox sheet itself doesn't reach
                        // this one (same rationale as ProfileSettingsSheet's
                        // prefs presentation).
                }
                .navigationDestination(for: ProfilePreviewDest.self) { dest in
                    switch dest {
                    case .profile(let id, let author):
                        PublicProfileView(accountId: id, preloaded: author, pushPath: $path)
                    case .followList(let id, let mode):
                        FollowListView(accountId: id, mode: mode, pushPath: $path)
                    case .publicStats(let id, let name):
                        StatsScreenView(
                            tripManager: mapVM.tripManager,
                            source: RemoteTripSource(accountId: id),
                            ownerName: name
                        )
                    case .publicMap(let id, let name):
                        PublicMapView(accountId: id, ownerName: name)
                    case .publicGarage(let id, let name):
                        PublicGarageView(accountId: id, ownerName: name)
                    case .publicVehicle(let id, let vid, let name):
                        PublicVehicleView(accountId: id, vehicleId: vid, ownerName: name)
                    case .trip, .socialTrip:
                        // Inbox doesn't push trip destinations directly —
                        // tap-on-reaction routes through the trip detail
                        // sheet outside this stack. Keeps the destination
                        // exhaustive without tying inbox to trip rendering.
                        EmptyView()
                    }
                }
        }
        .task { await store.refresh() }
        .onChange(of: store.items) { _, items in
            // Server knows the truth; merge rather than replace so a toggle
            // made in this session isn't undone by a refresh in flight.
            for item in items where item.isFollowing == true {
                if let id = item.actor?.id { followedBack.insert(id) }
            }
        }
        // Peek-and-close: report whatever was on screen before the debounce
        // had a chance to fire.
        .onDisappear { Task { await store.flushSeen() } }
        .toast(item: $toastItem)
    }

    // MARK: - Header (Figma 117:1841)

    private func header(c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        // Close sits on the RIGHT here like on every other sheet in the app
        // (Discover, settings): it used to be the only screen with the X on
        // the left, which read as a different kind of screen. Settings keeps
        // its slot immediately to its left. Canon 117:1853 draws this as a
        // pushed screen (back chevron + bell); as a sheet the same geometry
        // becomes title-left, controls-right.
        HStack(spacing: 8) {
            Text(AppStrings.activityTitle(lang.language))
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.22)
                .foregroundStyle(c.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Gear opens settings, full stop. It briefly hosted a popover
            // that also held «Отметить все прочитанными», but with rows
            // marking themselves read on sight (see `noteSeen`) that action
            // had nothing left to do, and a menu offering a single choice is
            // just a slower button.
            navCircleButton(icon: "gearshape") { showPreferences = true }
            navCircleButton(icon: "xmark") { dismiss() }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    /// Shared canon control (see `NavCircleIcon`) — this screen used to draw
    /// its own near-copy, which is why its buttons didn't quite match the
    /// ones on the other social screens.
    private func navCircleButton(
        icon: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            NavCircleIcon(systemImage: icon)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter chips

    private func chipsRow(c: AppTheme.Colors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(InboxChipFilter.allCases) { filter in
                    chip(filter, c: c)
                }
            }
            .padding(.horizontal, 14)
            // Breathing room inside the scroll clip so neither the ring nor
            // the card shadow gets shaved.
            .padding(.vertical, 3)
        }
        .padding(.bottom, 2)
    }

    private func chip(_ filter: InboxChipFilter, c: AppTheme.Colors) -> some View {
        let isOn = chipFilter == filter
        return Button {
            Haptics.selection()
            chipFilter = filter
        } label: {
            // Canon (Figma notifications screen): the active chip keeps the
            // same white pill as the others and is marked by an accent ring
            // + accent label. The peach fill we had made the selected chip
            // read as a warning badge next to the plain ones.
            Text(filter.title(lang.language))
                .font(.system(size: 12.5, weight: isOn ? .bold : .semibold))
                .foregroundStyle(isOn ? AppTheme.accent : c.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(c.card, in: Capsule())
                // `strokeBorder`, not `stroke`: a centred stroke puts half
                // its width outside the shape, and the enclosing horizontal
                // ScrollView clipped exactly that half off the top and
                // bottom of the ring.
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? AppTheme.accent : Color.clear, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
                .animation(.easeOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
        // Active chip is only signalled by fill/stroke — expose the state to
        // VoiceOver too, or every chip reads as an identical plain button.
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("notif_chip_\(filter.rawValue)")
    }

    /// Pagination trigger passthrough: the store's `loadMoreIfNeeded`
    /// guards on the FULL list's last item, so when a chip hides the tail
    /// the last VISIBLE row must hand over `store.items.last` — otherwise
    /// filtered lists silently stop paging.
    private func pagingTrigger(
        for item: NotificationItem, in visible: [NotificationItem]
    ) -> NotificationItem {
        item.id == visible.last?.id ? (store.items.last ?? item) : item
    }

    /// In-memory filter over loaded items. «Все» keeps unknown-kind
    /// fallback rows visible; typed chips match on `typedKind`.
    private var filteredItems: [NotificationItem] {
        switch chipFilter {
        case .all: return store.items
        case .reactions: return store.items.filter { $0.typedKind == .reaction }
        case .follows: return store.items.filter { $0.typedKind == .follow }
        case .comments: return store.items.filter { $0.typedKind == .comment }
        case .achievements: return store.items.filter { $0.typedKind == .achievement }
        case .companions:
            return store.items.filter {
                $0.typedKind == .companionInvite || $0.typedKind == .companionAccepted
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        if store.isLoading && store.items.isEmpty {
            // The skeleton is content-sized, so it has to be told to claim the
            // sheet the way the loaded list does — without this the sheet
            // shrinks to the height of six grey rows and floats mid-screen.
            VStack(spacing: 0) {
                SkeletonPlaceholder(shape: .row, count: 6)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.items.isEmpty {
            emptyState(c: c, lng: lng)
        } else {
            let items = filteredItems
            let today = items.filter { Calendar.current.isDateInToday($0.createdAt) }
            let earlier = items.filter { !Calendar.current.isDateInToday($0.createdAt) }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if items.isEmpty {
                        // Chip active, zero loaded matches — without this
                        // the area under the chips is just blank.
                        Text(AppStrings.noFilteredNotifications(lang.language))
                            .font(.system(size: 14))
                            .foregroundStyle(c.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                    if !today.isEmpty {
                        dateHeader(AppStrings.today(lang.language), c: c)
                    }
                    ForEach(today) { item in
                        row(item, c: c, lng: lng)
                            .onAppear {
                                store.noteSeen(item)
                                Task { await store.loadMoreIfNeeded(currentItem: pagingTrigger(for: item, in: items)) }
                            }
                    }
                    if !earlier.isEmpty {
                        dateHeader(AppStrings.earlier(lang.language), c: c)
                    }
                    ForEach(earlier) { item in
                        row(item, c: c, lng: lng)
                            .onAppear {
                                store.noteSeen(item)
                                Task { await store.loadMoreIfNeeded(currentItem: pagingTrigger(for: item, in: items)) }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await store.refresh() }
        }
    }

    /// Same endpoint/optimistic pattern as DiscoverView.toggleFollow, in
    /// the follow direction only. Reverts the local mark on failure so the
    /// button reappears.
    private func followToggle(for userId: UUID, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        let isFollowed = followedBack.contains(userId)
        return Button {
            Haptics.selection()
            if isFollowed { followedBack.remove(userId) } else { followedBack.insert(userId) }
            Task { await setFollow(userId, follow: !isFollowed) }
        } label: {
            Text(isFollowed
                 ? (AppStrings.notificationsInboxFollowing(lng))
                 : AppStrings.followBack(lang.language))
                // Pinned to the wider of the two labels: canon (117:1883)
                // hugs «В ответ» at 89pt, but «Подписан» is wider and the row
                // content jumped on every toggle (same fix as the Discover
                // row button).
                .socialActionButton(
                    isFollowed ? .done : .primary, colors: c, width: 110
                )
                .animation(.easeOut(duration: 0.2), value: isFollowed)
        }
        .buttonStyle(.plain)
    }

    /// Follow / unfollow, optimistic. Reverts the local mark on failure so
    /// the button can't lie about the server state.
    private func setFollow(_ userId: UUID, follow: Bool) async {
        do {
            let req = SocialFollowRequest(targetAccountId: userId)
            let _: SocialFollowResponse = try await APIClient.shared.post(
                follow ? APIEndpoint.socialFollow : APIEndpoint.socialUnfollow, body: req)
        } catch APIError.unknownServer(let code, _)
            where code == "ALREADY_FOLLOWING" || code == "NOT_FOLLOWING" {
            // The server and the button already agree — the request was a
            // no-op, not a failure. Reverting here is what made the row snap
            // back to «В ответ» and look like the tap did nothing.
        } catch {
            if follow { followedBack.remove(userId) } else { followedBack.insert(userId) }
        }
    }

    private func dateHeader(_ title: String, c: AppTheme.Colors) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.44)
            .textCase(.uppercase)
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .padding(.leading, 2)
    }

    /// `companion_invite` rows not yet answered this session render as a
    /// decision card (`decisionRow`) instead of the shared tap-to-open
    /// row — see `NotificationInviteRowModel.presentation`.
    @ViewBuilder
    private func row(_ item: NotificationItem, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        switch rowPresentation(for: item) {
        case .decision(let preview):
            decisionRow(item, preview: preview, c: c, lng: lng)
        case .info:
            infoRow(item, c: c, lng: lng)
        }
    }

    @ViewBuilder
    private func infoRow(_ item: NotificationItem, c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            handleTap(item)
        } label: {
            // Three fixed zones instead of one run-on sentence: marker rail,
            // identity (avatar + kind badge), then a stacked text block —
            // WHO on line one, WHAT on line two, WHEN on line three. The old
            // row concatenated all of it into a single wrapping paragraph, so
            // the verb landed in a different place on every card and the eye
            // had nothing to anchor on. Instagram / Strava / GitHub all use
            // this same name-then-action-then-time stack.
            HStack(alignment: .center, spacing: 11) {
                avatar(item, c: c)

                VStack(alignment: .leading, spacing: 2) {
                    Text(actorName(item, lng: lng))
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)

                    Text(actionLine(item, lng: lng))
                        .font(.inter(13))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(RelativeTripDate.string(from: item.createdAt, language: lang.language))
                        .font(.inter(11))
                        .foregroundStyle(c.textTertiary)
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Follow rows get a one-tap follow-back that then STAYS as
                // a «Подписан» toggle (canon). It used to just fade away,
                // which read as "did that even work?" and left no way back.
                if item.typedKind == .follow, let actor = item.actor {
                    followToggle(for: actor.id, c: c, lng: lng)
                }

                // Fix 11: an accepted invite's tap can page through up to
                // five `/companions/my-trips` requests before it resolves
                // (see `openAcceptedInviteTrip`) — this is the only visible
                // sign that's happening, replacing what used to be a tap
                // that silently did nothing for however long the sweep took.
                if item.typedKind == .companionInvite, let tripId = item.tripId,
                   resolvingAcceptedTripIds.contains(tripId) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityIdentifier("companion_invite_trip_loading")
                }
            }
            .padding(11)
            .background(
                // Unread rows sit on a whisper of accent so a glance down
                // the list separates new from seen.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(item.isRead ? Color.clear : AppTheme.accent.opacity(0.05))
            )
            .surfaceCard(cornerRadius: 16)
            // Unread stripe ON the card edge rather than a dot in its own
            // column: a dedicated marker rail left a dead gap in front of
            // every read row, which is most of them.
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(item.isRead ? Color.clear : AppTheme.accent)
                    .frame(width: 3.5)
                    .padding(.vertical, 14)
                    .animation(.easeOut(duration: 0.25), value: item.isRead)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Companion invite decision row

    /// A pending `companion_invite`: actor + trip shape (date/region/
    /// distance/duration) fetched via `invitePreview`, and Accept/Decline.
    /// NOT wrapped in a single tap-to-navigate `Button` like `infoRow` —
    /// there is nowhere to navigate to yet, the whole point of this state
    /// is that the invitee doesn't have trip access until they answer.
    @ViewBuilder
    private func decisionRow(
        _ item: NotificationItem, preview: NotificationInviteRowModel.PreviewState,
        c: AppTheme.Colors, lng: LanguageManager.Language
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 11) {
                avatar(item, c: c)
                VStack(alignment: .leading, spacing: 2) {
                    Text(actorName(item, lng: lng))
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(AppStrings.companionInviteAction(lang.language))
                        .font(.inter(13))
                        .foregroundStyle(c.textSecondary)
                }
                Spacer(minLength: 0)
            }

            decisionPreviewContent(item, preview: preview, c: c)

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    respond(item, accept: false)
                } label: {
                    Text(AppStrings.companionDecline(lang.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(c.cardAlt, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("companion_invite_decline")

                Button {
                    Haptics.tap()
                    respond(item, accept: true)
                } label: {
                    Text(AppStrings.companionAccept(lang.language))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("companion_invite_accept")
            }
        }
        .padding(11)
        .surfaceCard(cornerRadius: 16)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.isRead ? Color.clear : AppTheme.accent)
                .frame(width: 3.5)
                .padding(.vertical, 14)
        }
        .task(id: item.id) { await ensurePreviewIfNeeded(item) }
        .accessibilityIdentifier("companion_invite_row")
    }

    @ViewBuilder
    private func decisionPreviewContent(
        _ item: NotificationItem, preview: NotificationInviteRowModel.PreviewState, c: AppTheme.Colors
    ) -> some View {
        switch preview {
        case .loading:
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, 4)
        // Unreachable by construction — `NotificationInviteRowModel
        // .presentation` routes `.unavailable` straight to `.info` before
        // `decisionRow` (the only caller of this method) is ever drawn.
        // Handled anyway so this switch stays exhaustive; falls back to
        // the same retry banner `.failed` shows.
        case .failed, .unavailable:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.red)
                Text(AppStrings.companionInvitePreviewFailed(lang.language))
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textSecondary)
                Spacer(minLength: 4)
                Button {
                    Haptics.tap()
                    invitePreviews[item.id] = nil
                    Task { await ensurePreviewIfNeeded(item) }
                } label: {
                    Text(AppStrings.retry(lang.language))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        case .loaded(let loadedPreview):
            let line = NotificationInviteRowModel.decisionLine(
                item: item, preview: loadedPreview, lang: lang.language)
            Text(decisionLineText(line))
                .font(.system(size: 12.5))
                .foregroundStyle(c.textSecondary)
        }
    }

    /// Joins a `DecisionLine`'s present parts with the same "· " separator
    /// `SocialFeedCardView.dateRegionText` uses elsewhere in the app.
    private func decisionLineText(_ line: NotificationInviteRowModel.DecisionLine) -> String {
        var parts = [line.dateText]
        if let region = line.regionText { parts.append(region) }
        parts.append(line.distanceText)
        if let duration = line.durationText { parts.append(duration) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Companion invite state + networking

    /// Fix 1: notification-id-aware — see `CompanionsStore.respondedStatus
    /// (for:notificationId:)`'s doc comment for why the plain trip-keyed
    /// lookup isn't enough to make a re-invitation for the same trip
    /// answerable again.
    private func respondedStatus(for item: NotificationItem) -> CompanionStatus? {
        guard let tripId = item.tripId else { return nil }
        return companionsStore.respondedStatus(for: tripId, notificationId: item.id)
    }

    private func localResponse(for item: NotificationItem) -> NotificationInviteRowModel.LocalResponse? {
        switch respondedStatus(for: item) {
        case .accepted: return .accepted
        case .declined: return .declined
        case .pending, nil: return nil
        }
    }

    private func rowPresentation(for item: NotificationItem) -> NotificationInviteRowModel.Presentation {
        NotificationInviteRowModel.presentation(
            for: item, localResponse: localResponse(for: item),
            preview: invitePreviews[item.id] ?? .loading)
    }

    /// Fetches the invite preview for a still-pending decision row exactly
    /// once — guarded on both the local response (don't bother once
    /// answered) and the cache (don't bother if a fetch already
    /// resolved/is resolving for this row). Called from `decisionRow`'s
    /// `.task(id:)`, which SwiftUI may re-invoke if the row is recycled by
    /// the LazyVStack while scrolling; the guard is what actually prevents
    /// the repeat network call, not the `.task` lifecycle.
    private func ensurePreviewIfNeeded(_ item: NotificationItem) async {
        guard item.kind == NotificationKind.companionInvite.rawValue,
              localResponse(for: item) == nil,
              invitePreviews[item.id] == nil,
              let tripId = item.tripId else { return }
        invitePreviews[item.id] = .loading
        do {
            let preview = try await companionsStore.invitePreview(tripId: tripId)
            invitePreviews[item.id] = .loaded(preview)
        } catch {
            // Fix 8: a cancellation (the row scrolled off screen — SwiftUI
            // cancelled the backing `.task`) is not a failure and must not
            // be cached as one, or the card stays permanently broken (or
            // permanently spinning) when it scrolls back into view. Fix 2:
            // the server's specific "no longer a live pending invite"
            // signal (most commonly: answered on another device) routes to
            // `.unavailable` instead of a retryable `.failed` — see
            // `previewStateAfterFailure`'s doc comment.
            var isInviteGone = false
            if case APIError.unknownServer(let code, _) = error {
                isInviteGone = code == "COMPANION_INVITE_NOT_FOUND"
            }
            invitePreviews[item.id] = NotificationInviteRowModel.previewStateAfterFailure(
                wasCancelled: Task.isCancelled, isInviteGone: isInviteGone)
        }
    }

    /// Accept/decline, optimistic — `CompanionsStore.respond` already
    /// rolls its own state back and rethrows on failure; this just turns
    /// that failure into a visible toast (the row itself reverts on its
    /// own since `rowPresentation` re-derives from the now-rolled-back
    /// store state).
    private func respond(_ item: NotificationItem, accept: Bool) {
        guard let tripId = item.tripId else { return }
        Haptics.action()
        Task {
            do {
                // Fix 1: identifies THIS specific invitation, not just its
                // trip — see `CompanionsStore.respondedInvitationIds`.
                try await companionsStore.respond(tripId: tripId, notificationId: item.id, accept: accept)
            } catch {
                toastItem = ToastItem(
                    type: .error, message: AppStrings.companionRespondFailed(lang.language))
            }
        }
    }

    /// Opens the trip for a `companion_invite` already accepted (this
    /// session or a prior one — `CompanionsStore.respondedTripIds` is now
    /// persisted). There is currently no server endpoint to fetch an
    /// arbitrary non-owned trip by id — only listings (`/social/feed`,
    /// `/companions/my-trips`) — so this looks the trip up in
    /// `companionsStore.myTrips`, paging forward with the store's existing
    /// `loadMyTrips(reset: false)` continuation (capped at
    /// `Self.maxMyTripsPagesForTripLookup` pages total) if it isn't on the
    /// first page. `myTrips` orders by trip start date descending, so this
    /// only runs out before finding the trip when it's older than
    /// `maxMyTripsPagesForTripLookup * 20` other companion trips — the cap
    /// keeps the request count bounded on a single user-initiated tap while
    /// making that gap practically unreachable. A genuinely-exhausted
    /// search (or `hasMoreMyTrips` running out first) falls back to an
    /// error toast instead of a broken detail screen. A proper single-trip
    /// fetch endpoint would close this gap entirely but is a backend change
    /// out of this task's scope — recorded as a follow-up.
    private func openAcceptedInviteTrip(_ item: NotificationItem) {
        guard let tripId = item.tripId else { return }
        if let cached = acceptedInviteTrips[tripId] {
            navigateToTrip(tripId: tripId, social: cached)
            return
        }
        // Fix 11: a double-tap while a sweep is already running for this
        // trip must not fire a second, overlapping one.
        guard !resolvingAcceptedTripIds.contains(tripId) else { return }
        resolvingAcceptedTripIds.insert(tripId)
        Task {
            defer { resolvingAcceptedTripIds.remove(tripId) }
            if let found = companionsStore.myTrips.first(where: { $0.id == tripId }) {
                acceptedInviteTrips[tripId] = found
                navigateToTrip(tripId: tripId, social: found)
                return
            }
            await companionsStore.loadMyTrips(reset: true)
            var pagesLoaded = 1
            // Fix 11: `shouldContinuePagingForTrip` stops the sweep the
            // instant a page fails (`loadState == .failed`) instead of
            // re-requesting the exact same cursor `performLoadMyTrips`
            // leaves untouched on failure — see its doc comment.
            while NotificationInviteRowModel.shouldContinuePagingForTrip(
                found: companionsStore.myTrips.contains(where: { $0.id == tripId }),
                loadState: companionsStore.myTripsLoadState,
                hasMore: companionsStore.hasMoreMyTrips,
                pagesLoaded: pagesLoaded, maxPages: Self.maxMyTripsPagesForTripLookup
            ) {
                await companionsStore.loadMyTrips(reset: false)
                pagesLoaded += 1
            }
            if let found = companionsStore.myTrips.first(where: { $0.id == tripId }) {
                acceptedInviteTrips[tripId] = found
                navigateToTrip(tripId: tripId, social: found)
            } else {
                toastItem = ToastItem(
                    type: .error, message: AppStrings.companionTripUnavailable(lang.language))
            }
        }
    }

    /// Total `loadMyTrips` calls (the initial `reset: true` page plus any
    /// `reset: false` continuations) `openAcceptedInviteTrip` will make
    /// before giving up — see its doc comment.
    private static let maxMyTripsPagesForTripLookup = 5

    /// Same dismiss-then-post handoff `handleTap`'s reaction/comment
    /// branch already uses — `social` lets `FeedView`'s `.navigateToTrip`
    /// handler render a non-owned trip (see `TripDeepLink.social`'s doc
    /// comment). `nil` reproduces the pre-existing own-trip behavior
    /// exactly.
    private func navigateToTrip(tripId: UUID, social: SocialFeedTrip?) {
        dismiss()
        let link = TripDeepLink(tripId: tripId, focus: .top, social: social)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            NotificationCenter.default.post(name: .openTripDetail, object: link)
        }
    }

    private func avatar(_ item: NotificationItem, c: AppTheme.Colors) -> some View {
        // Actor rows: warm cardAlt disc. System rows (no actor): tinted
        // accent disc + the payload emoji. The kind rides as a badge on the
        // corner (Instagram/Strava pattern) so the row type is readable from
        // the left rail alone — that's what lets the sentence lose the inline
        // emoji that used to shove the text around.
        // An achievement is a system row even though it arrives WITH an
        // actor: the server fills `actor_account_id` with the recipient
        // (the column is NOT NULL), so `item.actor == nil` is never true for
        // it. Testing only that drew your OWN avatar under a name line
        // reading «TripTrack», and made `fallbackGlyph`'s achievement branch
        // dead code.
        let isSystemRow = item.actor == nil || item.typedKind == .achievement
        return Circle()
            .fill(isSystemRow ? AppTheme.accent.opacity(0.15) : c.cardAlt)
            .frame(width: 40, height: 40)
            .overlay {
                Text(isSystemRow
                     ? (item.emoji ?? fallbackGlyph(item))
                     : (item.actor?.avatarEmoji ?? item.emoji ?? fallbackGlyph(item)))
                    .font(.system(size: 20))
            }
            .overlay(alignment: .bottomTrailing) {
                kindBadge(item, c: c)
                    .offset(x: 3, y: 3)
            }
    }

    /// Glyph for an actor-less row whose payload carries no emoji either.
    /// A car is the right nothing-in-particular default, but on an
    /// achievement row it read as "someone drove", not "you earned this".
    private func fallbackGlyph(_ item: NotificationItem) -> String {
        item.typedKind == .achievement ? "🏅" : "🚗"
    }

    @ViewBuilder
    private func kindBadge(_ item: NotificationItem, c: AppTheme.Colors) -> some View {
        let size: CGFloat = 18
        switch item.typedKind {
        case .reaction:
            Circle()
                .fill(c.card)
                .frame(width: size, height: size)
                .overlay {
                    ReactionIconView(
                        emoji: ReactionEmoji.canonical(item.emoji ?? "🔥"),
                        size: 11,
                        filled: true,
                        tint: AppTheme.accent
                    )
                }
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        case .follow:
            badgeCircle("person.fill.badge.plus", tint: AppTheme.accent, c: c, size: size)
        case .comment:
            badgeCircle("bubble.right.fill", tint: AppTheme.accent, c: c, size: size)
        case .companionInvite, .companionAccepted:
            // Reached here only for the INFO state — an already-answered
            // invite or the owner's "someone joined" row. The pending
            // decision card (`decisionRow`) doesn't go through this badge.
            badgeCircle("person.2.fill", tint: AppTheme.accent, c: c, size: size)
        case .achievement:
            badgeCircle("rosette", tint: AppTheme.accent, c: c, size: size)
        case .none:
            EmptyView()
        }
    }

    private func badgeCircle(
        _ systemImage: String, tint: Color, c: AppTheme.Colors, size: CGFloat
    ) -> some View {
        Circle()
            .fill(c.card)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }

    private func actorName(_ item: NotificationItem, lng: LanguageManager.Language) -> String {
        // A badge unlock has no actor by nature — nobody did it to the
        // user — so the generic «Кто-то» fallback below would name a
        // person who doesn't exist. The row is signed by the app instead.
        if item.typedKind == .achievement { return AppStrings.activityAchievementActor }
        return item.actor?.displayName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? (AppStrings.notificationsInboxSomeone(lng))
    }

    /// Localized title of the unlocked badge. `badgeId` resolves against
    /// `Badge.all` so the name follows the in-app language switch; the
    /// server-rendered `tripTitle` is the fallback for an id this build
    /// doesn't know (a badge added server-side after this release) and
    /// because it is the one string field `NotificationsInboxStore.makeRead`
    /// already carries through.
    private func achievementName(_ item: NotificationItem) -> String? {
        if let id = item.badgeId?.trimmingCharacters(in: .whitespaces).nilIfEmpty,
           let badge = Badge.all.first(where: { $0.id == id }) {
            return badge.title(lang.language)
        }
        return item.tripTitle?.trimmingCharacters(in: .whitespaces).nilIfEmpty
    }

    /// Line two — the action, written as a plain phrase with the object in
    /// quotes so the eye can find it without parsing the whole row.
    private func actionLine(_ item: NotificationItem, lng: LanguageManager.Language) -> String {
        let trip = item.tripTitle?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? AppStrings.activityYourTrip(lang.language)
        switch item.typedKind {
        case .reaction:
            return AppStrings.activityReactedTo(lang.language, trip)
        case .follow:
            return AppStrings.activityFollowedYou(lang.language)
        case .comment:
            return AppStrings.activityCommented(lang.language, text: item.commentText, trip: trip)
        case .companionAccepted:
            return AppStrings.companionAcceptedAction(lang.language)
        case .achievement:
            guard let badge = achievementName(item) else {
                return AppStrings.activityAchievementUnlockedGeneric(lang.language)
            }
            return AppStrings.activityAchievementUnlocked(lang.language, badge: badge)
        case .companionInvite:
            // Reached only once answered locally, OR (Fix 2) once the
            // server confirms the invite is no longer live at all — the
            // decision card itself never calls this.
            if invitePreviews[item.id] == .unavailable {
                // Answered on ANOTHER device: this device has no local
                // record of which way it went, so — unlike the two cases
                // below — the phrasing stays deliberately neutral rather
                // than guessing "accepted".
                return AppStrings.companionInviteUnavailableNote(lang.language)
            }
            return respondedStatus(for: item) == .declined
                ? AppStrings.companionInviteDeclinedNote(lang.language)
                : AppStrings.companionInviteAcceptedNote(lang.language)
        case .none:
            return trip
        }
    }

    private func handleTap(_ item: NotificationItem) {
        Task { await store.markRead(item) }
        // Routing:
        //   reaction → close inbox + post `.openTripDetail` so the Mine
        //              tab pushes the user's own trip detail. Reactions
        //              by definition are on the user's own trips, so the
        //              receiver's interest is the trip ("who liked it"),
        //              not the actor's profile in isolation.
        //   follow   → push the follower's profile (so the user can
        //              decide whether to follow back).
        switch item.typedKind {
        case .reaction, .comment, .companionAccepted, .achievement:
            // All of these land on the user's OWN trip: a comment's payload
            // lives in the trip's comment thread, and `companion_accepted`
            // only ever notifies the trip's owner (someone accepted onto
            // a trip they own) — see `dispatchAcceptedSideEffects` on the
            // backend. An `achievement` row rides along because a badge is
            // earned ON a trip: when the server names that trip the tap
            // opens it, and when it doesn't (a cumulative badge answers to
            // no single drive) both branches below fall through and the tap
            // only marks the row read — which is the honest outcome, not a
            // dead end into some unrelated screen.
            if let tripId = item.tripId {
                dismiss()
                // A comment row lands on ITS comment (highlighted); a
                // reaction row lands at the top of the trip.
                let focus: TripFocus = {
                    guard item.typedKind == .comment else { return .top }
                    if let commentId = item.commentId { return .comment(commentId) }
                    return .comments
                }()
                let link = TripDeepLink(tripId: tripId, focus: focus)
                // Small async hop so the sheet finishes dismissing before
                // the receiving feed acts on the route — same pattern
                // `triptrack://trip/{uuid}` deep links use.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    NotificationCenter.default.post(name: .openTripDetail, object: link)
                }
            } else if item.typedKind != .achievement, let actor = item.actor {
                // Same trap as the avatar: an achievement's actor IS the
                // recipient, so without this an achievement row with no trip
                // attached would push you onto your own profile.
                path.cappedAppend(.profile(actor.id, actor))
            }
        case .companionInvite:
            // Reached only for the INFO state (the decision card has its
            // own Accept/Decline buttons, not this tap handler). An
            // accepted invite opens the trip — see `openAcceptedInviteTrip`
            // for why that needs a `myTrips` lookup rather than the plain
            // own-trip path above (this recipient doesn't own the trip). A
            // declined invite has nothing to open.
            if respondedStatus(for: item) == .accepted {
                openAcceptedInviteTrip(item)
            }
        case .follow, .none:
            guard let actor = item.actor else { return }
            path.cappedAppend(.profile(actor.id, actor))
        }
    }

    @ViewBuilder
    private func emptyState(c: AppTheme.Colors, lng: LanguageManager.Language) -> some View {
        VStack(spacing: 14) {
            EmptyStateIllustration(name: "empty_notifications")
            Text(AppStrings.notificationsInboxNothingYet(lng))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Text(AppStrings.notificationsInboxWhenSomeoneReacts(lng))
                .font(.system(size: 13))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Chip filter kinds (Figma 117:1841). Raw values feed the accessibility
/// identifiers (`notif_chip_*`).
private enum InboxChipFilter: String, CaseIterable, Identifiable {
    case all
    case reactions
    case follows
    case comments
    /// System-authored badge unlocks. Own chip for the same reason
    /// companions got one: it is its own kind of news, not a variant of
    /// what somebody else did to you.
    case achievements
    /// `companion_invite` + `companion_accepted`. A dedicated chip rather
    /// than folding them into an existing one — companions is its own
    /// growing feature (roster, picker, "Со мной" trips), not a variant of
    /// reactions/follows/comments, and it earns a chip the same way
    /// Comments did when it shipped. Every row still shows under «Все»
    /// regardless, so this chip is a discoverability win, not the only
    /// path to these rows.
    case companions

    var id: String { rawValue }

    func title(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .all: return AppStrings.all(lang)
        case .reactions: return AppStrings.chipReactions(lang)
        case .follows: return AppStrings.chipFollows(lang)
        case .comments: return AppStrings.chipComments(lang)
        case .achievements: return AppStrings.chipAchievements(lang)
        case .companions: return AppStrings.chipCompanions(lang)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
