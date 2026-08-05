import SwiftUI

/// Strava/Twitter-style notifications inbox. Lists reactions and follows
/// triggered against the signed-in user, newest first. Tapping a row
/// marks it read and navigates to the trip / actor profile via the same
/// shared `pushPath` pattern the social feed uses.
struct NotificationsInboxView: View {
    @ObservedObject private var store = NotificationsInboxStore.shared
    @EnvironmentObject private var lang: LanguageManager
    /// Injected by both presenters (FeedView, ProfileSettingsSheet) — needed
    /// to re-apply the in-app theme override on the nested prefs sheet.
    @EnvironmentObject private var themeManager: ThemeManager
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
    /// Actors followed back from this screen this session (optimistic).
    @State private var followedBack: Set<UUID> = []

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header(c: c, isRu: isRu)
                if !store.items.isEmpty {
                    chipsRow(c: c)
                }
                content(c: c, isRu: isRu)
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
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        // Nested sheets are separate presentations — the
                        // override on the inbox sheet itself doesn't reach
                        // this one (same rationale as ProfileSettingsSheet's
                        // prefs presentation).
                        .preferredColorScheme(themeManager.preferredColorScheme)
                }
                .navigationDestination(for: ProfilePreviewDest.self) { dest in
                    switch dest {
                    case .profile(let id, let author):
                        PublicProfileView(accountId: id, preloaded: author, pushPath: $path)
                    case .followList(let id, let mode):
                        FollowListView(accountId: id, mode: mode, pushPath: $path)
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
    }

    // MARK: - Header (Figma 117:1841)

    private func header(c: AppTheme.Colors, isRu: Bool) -> some View {
        HStack(spacing: 6) {
            navCircleButton(icon: "xmark", c: c) { dismiss() }

            Text(AppStrings.activityTitle(lang.language))
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.22)
                .foregroundStyle(c.text)
                .lineLimit(1)
                .padding(.leading, 4)

            Spacer()

            if store.unreadCount > 0 {
                Button {
                    Haptics.tap()
                    Task { await store.markAllRead() }
                } label: {
                    Text(isRu ? "Прочитать все" : "Read all")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }

            navCircleButton(icon: "gearshape", c: c) { showPreferences = true }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func navCircleButton(
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

    // MARK: - Filter chips

    private func chipsRow(c: AppTheme.Colors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(InboxChipFilter.allCases) { filter in
                    chip(filter, c: c)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 4)
    }

    private func chip(_ filter: InboxChipFilter, c: AppTheme.Colors) -> some View {
        let isOn = chipFilter == filter
        return Button {
            Haptics.selection()
            chipFilter = filter
        } label: {
            Text(filter.title(lang.language))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isOn ? AppTheme.accent : c.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? AppTheme.orangeDim : c.card, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(isOn ? AppTheme.accent : Color.clear, lineWidth: 1)
                )
                .shadow(color: isOn ? .clear : .black.opacity(0.03), radius: 2, y: 1)
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
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(c: AppTheme.Colors, isRu: Bool) -> some View {
        if store.isLoading && store.items.isEmpty {
            VStack { Spacer(); PixelCarLoader(label: nil, height: 80); Spacer() }
        } else if store.items.isEmpty {
            emptyState(c: c, isRu: isRu)
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
                        row(item, c: c, isRu: isRu)
                            .onAppear {
                                Task { await store.loadMoreIfNeeded(currentItem: pagingTrigger(for: item, in: items)) }
                            }
                    }
                    if !earlier.isEmpty {
                        dateHeader(AppStrings.earlier(lang.language), c: c)
                    }
                    ForEach(earlier) { item in
                        row(item, c: c, isRu: isRu)
                            .onAppear {
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
    private func followBack(_ userId: UUID) async {
        do {
            let req = SocialFollowRequest(targetAccountId: userId)
            let _: SocialFollowResponse = try await APIClient.shared.post(
                APIEndpoint.socialFollow, body: req)
        } catch {
            followedBack.remove(userId)
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

    @ViewBuilder
    private func row(_ item: NotificationItem, c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            handleTap(item)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                avatar(item, c: c)

                VStack(alignment: .leading, spacing: 4) {
                    titleLine(item, c: c, isRu: isRu)
                    Text(RelativeTripDate.string(from: item.createdAt, language: lang.language))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Follow rows get a one-tap follow-back (Figma 117:1841).
                // SocialAuthor carries no isFollowing flag, so the button
                // shows until tapped this session; already-following users
                // just get idempotent server success.
                if item.typedKind == .follow, let actor = item.actor,
                   !followedBack.contains(actor.id) {
                    Button {
                        Haptics.tap()
                        followedBack.insert(actor.id)
                        Task { await followBack(actor.id) }
                    } label: {
                        Text(AppStrings.followBack(lang.language))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if !item.isRead {
                    // Strava-style unread dot — a tiny accent disc on the
                    // right edge so the user can tell at a glance which
                    // rows are new without reading every line.
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(11)
            .surfaceCard(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ item: NotificationItem, c: AppTheme.Colors) -> some View {
        // Actor rows: warm cardAlt disc. System rows (no actor): tinted
        // accent disc + the payload emoji.
        Circle()
            .fill(item.actor == nil ? AppTheme.accent.opacity(0.15) : c.cardAlt)
            .frame(width: 36, height: 36)
            .overlay {
                Text(item.actor?.avatarEmoji ?? item.emoji ?? "🚗")
                    .font(.system(size: 19))
            }
    }

    @ViewBuilder
    private func titleLine(_ item: NotificationItem, c: AppTheme.Colors, isRu: Bool) -> some View {
        let actorName = item.actor?.displayName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? (isRu ? "Кто-то" : "Someone")
        switch item.typedKind {
        case .reaction:
            // "Иван отреагировал 🔥 на Krasnodar" — verb per Figma 117:1875
            // (the verb-less "Иван 🔥 на …" read as a fragment next to the
            // follow/comment rows, which keep theirs). Title can be long, so
            // cap to 2 lines. Mixed weights per Figma: actor bold, verb
            // regular, object semibold.
            (
                Text(actorName).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                + Text(isRu ? " отреагировал" : " reacted").font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                + Text(" \(item.emoji ?? "🔥")")
                + Text(isRu ? " на " : " to ").font(.system(size: 14)).foregroundStyle(c.textSecondary)
                + Text(item.tripTitle ?? "—").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text)
            )
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        case .comment:
            // "Иван прокомментировал(а) Krasnodar" — same anatomy as the
            // reaction row: actor + verb + trip title.
            (
                Text(actorName).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                + Text(isRu ? " прокомментировал(а) " : " commented on ")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                + Text(item.tripTitle ?? "—").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text)
            )
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        case .follow:
            (
                Text(actorName).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                + Text(isRu ? " подписался на Вас" : " is now following you")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
            )
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        case .none:
            // Forward-compat — server rolls out a new kind we don't
            // recognise, render a neutral fallback so the row still has
            // SOME meaning.
            Text(actorName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(c.text)
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
        case .reaction, .comment:
            // Both land on the user's own trip — a comment's payload lives
            // in the trip's comment thread, not on the actor's profile.
            if let tripId = item.tripId {
                dismiss()
                // Small async hop so the sheet finishes dismissing before
                // the receiving feed acts on the route — same pattern
                // `triptrack://trip/{uuid}` deep links use.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openTripDetail, object: tripId)
                }
            } else if let actor = item.actor {
                path.cappedAppend(.profile(actor.id, actor))
            }
        case .follow, .none:
            guard let actor = item.actor else { return }
            path.cappedAppend(.profile(actor.id, actor))
        }
    }

    @ViewBuilder
    private func emptyState(c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "bell")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(c.textTertiary)
            Text(isRu ? "Здесь пока пусто" : "Nothing yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Text(isRu
                 ? "Когда кто-то отреагирует на Вашу поездку или подпишется — увидите здесь."
                 : "When someone reacts to your trip or follows you, it'll show up here.")
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

    var id: String { rawValue }

    func title(_ lang: LanguageManager.Language) -> String {
        switch self {
        case .all: return AppStrings.all(lang)
        case .reactions: return AppStrings.chipReactions(lang)
        case .follows: return AppStrings.chipFollows(lang)
        case .comments: return AppStrings.chipComments(lang)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
