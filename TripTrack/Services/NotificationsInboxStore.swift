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
    /// refresh.
    func refresh() async {
        guard AuthService.shared.isSignedIn else {
            items = []
            unreadCount = 0
            return
        }
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
    /// loaded page. Idempotent if already at the end.
    func loadMoreIfNeeded(currentItem: NotificationItem) async {
        guard hasMore, let cursor = nextCursor else { return }
        guard let last = items.last, last.id == currentItem.id else { return }
        do {
            let res: NotificationsFeedResponse = try await APIClient.shared.post(
                APIEndpoint.notificationsFeed,
                body: NotificationsFeedRequest(limit: 30, cursor: cursor))
            items.append(contentsOf: res.items)
            nextCursor = res.nextCursor
            hasMore = res.nextCursor != nil
        } catch {
            inboxLog.error("load-more failed: \(error.localizedDescription)")
        }
    }

    /// Marks a single notification read locally + on the server. Optimistic:
    /// flips `isRead` immediately and decrements `unreadCount`, then sends
    /// the network request; on failure we don't revert because the next
    /// refresh will reconcile.
    func markRead(_ item: NotificationItem) async {
        guard !item.isRead, let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = makeRead(items[idx])
        unreadCount = max(0, unreadCount - 1)
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.notificationsMarkRead,
                body: NotificationsMarkReadRequest(ids: [item.id]))
        } catch {
            inboxLog.error("mark-read failed: \(error.localizedDescription)")
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
            isRead: true, createdAt: item.createdAt, actor: item.actor,
        )
    }
}
