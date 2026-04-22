import Foundation
import OSLog

private let socialLog = Logger(subsystem: "com.triptrack", category: "social")

@MainActor
final class SocialFeedStore: ObservableObject {
    static let shared = SocialFeedStore()

    @Published private(set) var trips: [SocialFeedTrip] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var lastError: APIError?

    private var nextCursor: String?
    private var hasMore = true
    private var currentTask: Task<Void, Never>?

    private init() {}

    // MARK: - Load

    func refresh() async {
        // Cancel any in-flight refresh so pull-to-refresh always triggers a fresh
        // fetch. The previous URLSession task gets cancelled via Task cooperative
        // cancellation — its -999 error is swallowed by fetchPage()'s catch.
        currentTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.isLoading = true }
            defer { Task { @MainActor in self.isLoading = false } }

            await MainActor.run {
                self.nextCursor = nil
                self.hasMore = true
            }
            await self.fetchPage(replace: true)
        }
        currentTask = task
        await task.value
    }

    /// Optimistic removal used when the user flips one of their own trips back to
    /// private from the detail screen — removes the card immediately so the feed
    /// reflects the new privacy state without waiting for the server round-trip.
    func removeOptimistically(tripId: UUID) {
        trips.removeAll { $0.id == tripId }
    }

    func loadMoreIfNeeded(currentItem: SocialFeedTrip) async {
        guard hasMore, !isLoadingMore,
              let last = trips.last,
              currentItem.id == last.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        await fetchPage(replace: false)
    }

    private func fetchPage(replace: Bool) async {
        let req = SocialFeedRequest(limit: 20, cursor: nextCursor)
        do {
            let res: SocialFeedResponse = try await APIClient.shared.post(
                APIEndpoint.socialFeed, body: req)
            try Task.checkCancellation()
            if replace {
                trips = res.trips
            } else {
                trips.append(contentsOf: res.trips)
            }
            nextCursor = res.nextCursor
            hasMore = res.nextCursor != nil
            lastError = nil
        } catch is CancellationError {
            // Superseded by a newer refresh — ignore silently.
        } catch let e as APIError {
            // URLSession cancellations surface as APIError.network(-999); ignore those too.
            if case .network(let urlErr) = e, urlErr.code == .cancelled {
                return
            }
            lastError = e
            socialLog.error("feed fetch failed: \(String(describing: e))")
        } catch {
            socialLog.error("feed fetch error: \(error.localizedDescription)")
        }
    }

    // MARK: - Reactions (optimistic)

    func toggleReaction(for tripId: UUID, emoji: String) async {
        guard let idx = trips.firstIndex(where: { $0.id == tripId }) else { return }
        let trip = trips[idx]
        let wasMine = trip.myReaction != nil
        let wasSameEmoji = trip.myReaction == emoji

        // Optimistic update
        let newCount: Int
        let newMine: String?
        if wasSameEmoji {
            newCount = max(0, trip.reactionCount - 1)
            newMine = nil
        } else if wasMine {
            newCount = trip.reactionCount
            newMine = emoji
        } else {
            newCount = trip.reactionCount + 1
            newMine = emoji
        }
        trips[idx] = trip.with(reactionCount: newCount, myReaction: newMine)

        do {
            if wasSameEmoji {
                let _: SocialReactResponse = try await APIClient.shared.post(
                    APIEndpoint.socialUnreact, body: SocialUnreactRequest(tripId: tripId))
            } else {
                let _: SocialReactResponse = try await APIClient.shared.post(
                    APIEndpoint.socialReact, body: SocialReactRequest(tripId: tripId, emoji: emoji))
            }
        } catch {
            // Revert optimistic change on failure
            trips[idx] = trip
            socialLog.error("react toggle failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Clear (on sign out)

    func clear() {
        trips = []
        nextCursor = nil
        hasMore = true
        lastError = nil
    }
}

private extension SocialFeedTrip {
    func with(reactionCount: Int, myReaction: String?) -> SocialFeedTrip {
        // Rebuild breakdown locally to reflect optimistic toggle:
        // decrement previous myReaction bucket, increment new one.
        var breakdown = reactionBreakdown.reduce(into: [String: Int]()) { $0[$1.emoji] = $1.count }
        if let old = self.myReaction {
            breakdown[old, default: 1] -= 1
            if (breakdown[old] ?? 0) <= 0 { breakdown.removeValue(forKey: old) }
        }
        if let new = myReaction {
            breakdown[new, default: 0] += 1
        }
        let updated = breakdown
            .map { ReactionTally(emoji: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        return SocialFeedTrip(
            id: id, author: author, title: title,
            startDate: startDate, endDate: endDate,
            distance: distance, duration: duration, region: region,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            reactionCount: reactionCount, reactionBreakdown: updated,
            myReaction: myReaction, badgeIds: badgeIds
        )
    }
}
