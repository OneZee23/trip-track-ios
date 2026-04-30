import SwiftUI

/// Strava/Twitter-style notifications inbox. Lists reactions and follows
/// triggered against the signed-in user, newest first. Tapping a row
/// marks it read and navigates to the trip / actor profile via the same
/// shared `pushPath` pattern the social feed uses.
struct NotificationsInboxView: View {
    @ObservedObject private var store = NotificationsInboxStore.shared
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// Capped path so deep navigation (Notifications → Trip → Profile →
    /// Trip) doesn't trigger SwiftUI's navigation-stack flash bug we hit
    /// on Discover before. Same pattern as DiscoverView / FeedView.
    @State private var path: [ProfilePreviewDest] = []
    @State private var showPreferences = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack(path: $path) {
            content(c: c, isRu: isRu)
                .background(c.bg)
                .navigationTitle(isRu ? "Уведомления" : "Notifications")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if store.unreadCount > 0 {
                            Button {
                                Haptics.tap()
                                Task { await store.markAllRead() }
                            } label: {
                                Text(isRu ? "Прочитать все" : "Read all")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 6) {
                            Button { showPreferences = true } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(c.textSecondary)
                            }
                            SheetCloseButton()
                        }
                    }
                }
                .sheet(isPresented: $showPreferences) {
                    NotificationPreferencesView()
                        .environmentObject(lang)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
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

    @ViewBuilder
    private func content(c: AppTheme.Colors, isRu: Bool) -> some View {
        if store.isLoading && store.items.isEmpty {
            VStack { Spacer(); PixelCarLoader(label: nil, height: 80); Spacer() }
        } else if store.items.isEmpty {
            emptyState(c: c, isRu: isRu)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.items) { item in
                        row(item, c: c, isRu: isRu)
                            .onAppear {
                                Task { await store.loadMoreIfNeeded(currentItem: item) }
                            }
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .refreshable { await store.refresh() }
        }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(item.isRead ? Color.clear : AppTheme.accentBg.opacity(0.4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ item: NotificationItem, c: AppTheme.Colors) -> some View {
        Circle()
            .fill(AppTheme.accentBg)
            .frame(width: 40, height: 40)
            .overlay {
                Text(item.actor?.avatarEmoji ?? "🚗").font(.system(size: 20))
            }
    }

    @ViewBuilder
    private func titleLine(_ item: NotificationItem, c: AppTheme.Colors, isRu: Bool) -> some View {
        let actorName = item.actor?.displayName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? (isRu ? "Кто-то" : "Someone")
        switch item.typedKind {
        case .reaction:
            // "Иван 🔥 на Krasnodar" — emoji rendered between actor + trip.
            // Title can be long, so cap to 2 lines.
            (
                Text(actorName).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text)
                + Text(" \(item.emoji ?? "🔥")")
                + Text(isRu ? "  на " : "  on ").font(.system(size: 14)).foregroundStyle(c.textSecondary)
                + Text(item.tripTitle ?? "—").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text)
            )
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        case .follow:
            (
                Text(actorName).font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.text)
        }
    }

    private func handleTap(_ item: NotificationItem) {
        Task { await store.markRead(item) }
        // Routing:
        //   reaction → push the actor's profile (the trip itself opens
        //              from there if the user wants); keeps inbox a
        //              "people who reacted" map rather than another
        //              trip viewer that races with the social feed.
        //   follow   → push the follower's profile.
        guard let actor = item.actor else { return }
        path.cappedAppend(.profile(actor.id, actor))
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
