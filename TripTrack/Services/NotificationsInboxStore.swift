import Foundation
import Combine
import UIKit
import OSLog

private let inboxLog = Logger(subsystem: "com.triptrack", category: "notifications.inbox")

/// In-app notification inbox. Pull-based: refreshes on app foreground,
/// after sign-in, and after a push lands (PushNotificationManager could
/// post a notification once we wire that up). Local state is the single
/// source of truth for the UI; server stays authoritative for `isRead`.
///
/// Singleton because the unread badge is consumed by both the Profile
/// entry row and the bottom tab bar — keeping a shared `@Published`
/// avoids two stores drifting.
@MainActor
final class NotificationsInboxStore: ObservableObject {
    static let shared = NotificationsInboxStore()

    @Published private(set) var items: [NotificationItem] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var hasMore: Bool = true

    private var nextCursor: String?
    private var cancellables = Set<AnyCancellable>()
    /// In-flight refresh task. Concurrent callers wait on this instead of
    /// kicking off a duplicate request.
    private var activeRefresh: Task<Void, Never>?

    private init() {
        // Foreground bring-up — refresh both the list and unread count so
        // the badge stays accurate even when the user re-opens the app
        // hours later. Sign-in/out also trigger refresh.
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshUnreadOnly() }
            }
            .store(in: &cancellables)
    }

    /// Loads page 1 of the inbox + refreshes the unread count. Called by
    /// the inbox view's `.task` modifier on first appear, and by pull-to-
    /// refresh, and by foreground push delivery. Concurrent calls coalesce
    /// onto the in-flight task so a foreground transition that races
    /// `view.task` doesn't interleave the two responses (causing the
    /// second-finished-overwrites-first-finished stale-data bug).
    func refresh() async {
        if let inflight = activeRefresh {
            await inflight.value
            return
        }
        guard AuthService.shared.isSignedIn else {
            items = []
            unreadCount = 0
            return
        }
        let task = Task<Void, Never> { [weak self] in
            await self?.performRefresh()
        }
        activeRefresh = task
        await task.value
        activeRefresh = nil
    }

    private func performRefresh() async {
        isLoading = true
        defer { isLoading = false }
        nextCursor = nil
        hasMore = true
        do {
            async let feedFut = APIClient.shared.post(
                APIEndpoint.notificationsFeed,
                body: NotificationsFeedRequest(limit: 30)
            ) as NotificationsFeedResponse
            async let countFut = APIClient.shared.post(
                APIEndpoint.notificationsUnreadCount,
                body: EmptyRequest()
            ) as NotificationsUnreadCountResponse
            let (feed, count) = try await (feedFut, countFut)
            items = feed.items
            nextCursor = feed.nextCursor
            hasMore = feed.nextCursor != nil
            unreadCount = count.count
        } catch {
            inboxLog.error("refresh failed: \(error.localizedDescription)")
        }
    }

    /// Lightweight unread-only ping. Cheaper than a full feed fetch — used
    /// on app foreground when we want the badge accurate but the user
    /// isn't necessarily looking at the inbox screen.
    func refreshUnreadOnly() async {
        guard AuthService.shared.isSignedIn else { return }
        do {
            let res: NotificationsUnreadCountResponse = try await APIClient.shared.post(
                APIEndpoint.notificationsUnreadCount, body: EmptyRequest())
            unreadCount = res.count
        } catch {
            inboxLog.error("unread-count refresh failed: \(error.localizedDescription)")
        }
    }

    /// Pagination — fires when the inbox view scrolls near the end of the
    /// loaded page. Idempotent if already at the end. After the append,
    /// trim the head if the buffered list grows above `Self.maxBufferedItems`
    /// — keeps memory bounded across long sessions even if the user
    /// pages way back. The user can always pull-to-refresh to start over.
    func loadMoreIfNeeded(currentItem: NotificationItem) async {
        guard hasMore, let cursor = nextCursor else { return }
        guard let last = items.last, last.id == currentItem.id else { return }
        do {
            let res: NotificationsFeedResponse = try await APIClient.shared.post(
                APIEndpoint.notificationsFeed,
                body: NotificationsFeedRequest(limit: 30, cursor: cursor))
            items.append(contentsOf: res.items)
            if items.count > Self.maxBufferedItems {
                items.removeFirst(items.count - Self.maxBufferedItems)
            }
            nextCursor = res.nextCursor
            hasMore = res.nextCursor != nil
        } catch {
            inboxLog.error("load-more failed: \(error.localizedDescription)")
        }
    }

    private static let maxBufferedItems = 200

    /// Marks a single notification read locally + on the server. Optimistic:
    /// flips `isRead` immediately and decrements `unreadCount`, then sends
    /// the network request. If the network call fails we revert the local
    /// state so the unread badge / row underline stay accurate — without
    /// the revert the user would see "0 unread" while the server still
    /// has the row pending, which `refreshUnreadOnly` then corrects by
    /// jumping the badge back up unprompted.
    func markRead(_ item: NotificationItem) async {
        guard !item.isRead, let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let original = items[idx]
        items[idx] = makeRead(original)
        unreadCount = max(0, unreadCount - 1)
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.notificationsMarkRead,
                body: NotificationsMarkReadRequest(ids: [item.id]))
        } catch {
            inboxLog.error("mark-read failed: \(error.localizedDescription)")
            // Revert — only if the row hasn't been replaced by a refresh
            // mid-flight (defensive: refresh would have set `isRead`
            // authoritatively from the server).
            if let stillIdx = items.firstIndex(where: { $0.id == original.id }),
               items[stillIdx].isRead {
                items[stillIdx] = original
                unreadCount += 1
            }
        }
    }

    /// Ids seen on screen but not yet reported to the server.
    private var pendingSeen: Set<UUID> = []
    private var seenFlushTask: Task<Void, Never>?

    /// Read-on-sight: a row that has actually been displayed counts as read,
    /// which is what users expect from an activity feed (and what Instagram
    /// / Telegram do). Batched — rows stream in as you scroll, and one
    /// request per row would be a storm. Because it keys off display, not
    /// off the loaded page, rows that only become visible under a chip
    /// filter are covered too.
    func noteSeen(_ item: NotificationItem) {
        guard !item.isRead else { return }
        pendingSeen.insert(item.id)
        seenFlushTask?.cancel()
        seenFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushSeen()
        }
    }

    /// Flush whatever has accumulated. Called on the debounce and when the
    /// inbox goes away, so a quick peek-and-close still reports.
    func flushSeen() async {
        let ids = pendingSeen
        pendingSeen = []
        guard !ids.isEmpty else { return }
        var flipped = 0
        items = items.map { item in
            guard ids.contains(item.id), !item.isRead else { return item }
            flipped += 1
            return makeRead(item)
        }
        guard flipped > 0 else { return }
        unreadCount = max(0, unreadCount - flipped)
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.notificationsMarkRead,
                body: NotificationsMarkReadRequest(ids: Array(ids)))
        } catch {
            // Left optimistic on purpose: the next `refreshUnreadOnly` pulls
            // the authoritative count, and re-showing rows the user already
            // read is worse than a badge that self-corrects a moment later.
            inboxLog.error("mark-seen failed: \(error.localizedDescription)")
        }
    }

    /// Marks every unread row in the loaded page read locally + on the
    /// server (server-side it marks ALL unread for the account, not just
    /// the loaded page — that's intentional so the badge clears even if
    /// there are unread rows past the cursor).
    func markAllRead() async {
        guard unreadCount > 0 else { return }
        items = items.map(makeRead)
        unreadCount = 0
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.notificationsMarkRead,
                body: NotificationsMarkReadRequest(ids: nil))
        } catch {
            inboxLog.error("mark-all-read failed: \(error.localizedDescription)")
        }
    }

    /// Reset on sign-out so a re-sign-in starts clean.
    func clear() {
        items = []
        unreadCount = 0
        nextCursor = nil
        hasMore = true
    }

    private func makeRead(_ item: NotificationItem) -> NotificationItem {
        guard !item.isRead else { return item }
        return NotificationItem(
            id: item.id, kind: item.kind, tripId: item.tripId,
            tripTitle: item.tripTitle, emoji: item.emoji,
            commentId: item.commentId, commentText: item.commentText,
            isFollowing: item.isFollowing,
            isRead: true, createdAt: item.createdAt, actor: item.actor,
            // Rebuilding the item field by field means every field added
            // later has to be added HERE too, and `badgeId` defaults to nil,
            // so the compiler said nothing when it wasn't: marking an
            // achievement row read wiped the badge and the row rewrote
            // itself in place ~800ms after you looked at it, falling back to
            // the TRIP title as the achievement's name.
            badgeId: item.badgeId,
        )
    }
}
