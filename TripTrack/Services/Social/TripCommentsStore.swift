import Foundation
import OSLog

private let commentsLog = Logger(subsystem: "com.triptrack", category: "comments")

/// Per-trip comment list + composer state for the «Комментарии · N» card
/// (Figma 549:129 / 531:119). NOT a singleton — each detail screen owns one
/// via `@StateObject` so two stacked detail pushes don't share pages.
///
/// Optimistic paths:
///   * `post` inserts a temp row (temp UUID, `isMine: true`) at the top
///     immediately, then swaps in the server id/createdAt on success or
///     removes the row and returns an error message on failure.
///   * `delete` removes the row immediately and restores it at its original
///     index if the server call fails.
@MainActor
final class TripCommentsStore: ObservableObject {
    @Published private(set) var comments: [TripComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isPosting = false
    @Published private(set) var nextCursor: String?
    /// First page has completed (success or failure) — gates the section
    /// out of its skeleton-less "nothing yet" flash.
    @Published private(set) var hasLoadedOnce = false
    /// First page threw (offline / server error) — the section keeps
    /// trusting the feed-DTO count instead of asserting «· 0».
    @Published private(set) var loadFailed = false
    /// The server answered 404 for the comments route — backend without the
    /// comments module. The section hides entirely (visible-but-dead
    /// composer is worse than none); flips back on the next app launch
    /// against a deployed backend.
    @Published private(set) var unavailable = false
    /// The thread on screen is the device's own copy of a conversation the
    /// server no longer holds. Read-only by nature: there is nothing left to
    /// reply to.
    @Published private(set) var isArchived = false

    private var tripId: UUID?
    private let pageSize = 30

    /// Loads the first page. Safe to call repeatedly (`.task(id:)` re-fires
    /// on structural identity changes) — a same-trip reload just refreshes.
    func load(tripId: UUID) async {
        self.tripId = tripId
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false; hasLoadedOnce = true }
        do {
            let res: TripCommentsResponse = try await APIClient.shared.post(
                APIEndpoint.socialComments,
                body: TripCommentsRequest(tripId: tripId, limit: pageSize, cursor: nil),
                requiresAuth: AuthService.shared.isSignedIn)
            comments = res.comments
            nextCursor = res.nextCursor
            loadFailed = false
            unavailable = false
            isArchived = false
        } catch {
            // Non-fatal — the card keeps the feed-known count. A route-level
            // 404 means the backend doesn't ship comments yet → hide the UI.
            loadFailed = true
            if case APIError.invalidHTTPStatus(404) = error { unavailable = true }
            commentsLog.error("comments load failed: \(error.localizedDescription)")

            // The server cannot answer for a trip it no longer has — which is
            // precisely what happens when the owner takes one private, since
            // that erases it there. The thread was copied to the device before
            // the erasure; this is where that copy is read. Only ever as a
            // fallback, so a live thread is always the live one.
            let archived = DiscussionArchive.load(for: tripId)
            if !archived.isEmpty {
                comments = archived
                nextCursor = nil
                loadFailed = false
                unavailable = false
                isArchived = true
            }
        }
    }

    /// «Показать ещё» — appends the next page (id-deduped, the optimistic
    /// insert can overlap a freshly-posted comment the server now pages).
    func loadMore() async {
        guard let tripId, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let res: TripCommentsResponse = try await APIClient.shared.post(
                APIEndpoint.socialComments,
                body: TripCommentsRequest(tripId: tripId, limit: pageSize, cursor: cursor),
                requiresAuth: AuthService.shared.isSignedIn)
            let known = Set(comments.map(\.id))
            comments.append(contentsOf: res.comments.filter { !known.contains($0.id) })
            nextCursor = res.nextCursor
        } catch {
            commentsLog.error("comments loadMore failed: \(error.localizedDescription)")
        }
    }

    /// Client-side gate + optimistic create. Returns nil on success or a
    /// localized error message (validation or network) for the caller's
    /// toast. Empty-after-trim text is a silent no-op (button should be
    /// disabled anyway).
    func post(
        text: String,
        replyTo parent: TripComment? = nil,
        language: LanguageManager.Language
    ) async -> String? {
        guard let tripId, !isPosting else { return nil }
        // Same as the notes path: VALIDATE via ContentFilter (which
        // sanitizes internally for its checks) but STORE the edge-trimmed
        // original — sanitize() collapses internal newlines, and the
        // composer is multi-line.
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if let err = ContentFilter.validate(cleaned, field: .comment, language: language) {
            return err
        }

        // Optimistic temp row — newest-first list, so it goes on top.
        let tempId = UUID()
        let me = SocialAuthor(
            id: TokenStore.shared.accountId ?? UUID(),
            displayName: AuthService.shared.userName,
            avatarEmoji: SettingsManager.shared.avatarEmoji,
            profileLevel: SettingsManager.shared.profileLevel
        )
        // Replies attach to the thread ROOT, matching what the server will
        // do, so the optimistic row lands in the same place the reload puts
        // it. Newest-first list, so it goes on top either way.
        let rootId = parent.map { $0.parentId ?? $0.id }
        let temp = TripComment(
            id: tempId, user: me, text: cleaned, createdAt: Date(), isMine: true,
            parentId: rootId, replyToName: parent?.user.displayName)
        comments.insert(temp, at: 0)
        isPosting = true
        defer { isPosting = false }

        do {
            // singleAttempt: comment create is NOT idempotent (no client id,
            // duplicates allowed server-side) — a transport retry after a
            // late -1001/-1005 would post the comment twice. On failure the
            // user retries manually from the visible error toast.
            let res: SocialCommentCreateResponse = try await APIClient.shared.post(
                APIEndpoint.socialComment,
                body: SocialCommentCreateRequest(
                    tripId: tripId, text: cleaned, parentId: rootId),
                singleAttempt: true)
            // Swap temp id/date for the server's authoritative values.
            if let idx = comments.firstIndex(where: { $0.id == tempId }) {
                comments[idx] = TripComment(
                    id: res.id, user: me, text: cleaned,
                    createdAt: res.createdAt, isMine: true,
                    parentId: rootId, replyToName: parent?.user.displayName)
            }
            // Feed cards render the store-side «💬 N» — bump it in place.
            NotificationCenter.default.post(
                name: .tripCommentCountChanged, object: nil,
                userInfo: ["tripId": tripId, "delta": 1])
            return nil
        } catch {
            comments.removeAll { $0.id == tempId }
            commentsLog.error("comment post failed: \(error.localizedDescription)")
            if case APIError.tooManyRequests = error {
                return AppStrings.commentRateLimited(language)
            }
            return AppStrings.commentPostFailed(language)
        }
    }

    /// Optimistic delete (author or trip owner). Returns nil on success or
    /// a localized error message after restoring the row.
    func delete(commentId: UUID, language: LanguageManager.Language) async -> String? {
        guard let idx = comments.firstIndex(where: { $0.id == commentId }) else { return nil }
        let removed = comments.remove(at: idx)
        do {
            let _: SocialCommentDeleteResponse = try await APIClient.shared.post(
                APIEndpoint.socialCommentDelete,
                body: SocialCommentDeleteRequest(commentId: commentId))
            if let tripId {
                NotificationCenter.default.post(
                    name: .tripCommentCountChanged, object: nil,
                    userInfo: ["tripId": tripId, "delta": -1])
            }
            return nil
        } catch {
            // Already gone server-side (moderated away / deleted from
            // another device) — that IS the outcome the user asked for.
            if case APIError.unknownServer(let code, _) = error, code == "COMMENT_NOT_FOUND" {
                return nil
            }
            // Restore at the original slot (clamped — list may have moved).
            comments.insert(removed, at: min(idx, comments.count))
            commentsLog.error("comment delete failed: \(error.localizedDescription)")
            return AppStrings.commentDeleteFailed(language)
        }
    }
}
