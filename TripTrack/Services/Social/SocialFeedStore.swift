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

    private init() {}

    // MARK: - Load

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        nextCursor = nil
        hasMore = true
        await fetchPage(replace: true)
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
            if replace {
                trips = res.trips
            } else {
                trips.append(contentsOf: res.trips)
            }
            nextCursor = res.nextCursor
            hasMore = res.nextCursor != nil
            lastError = nil
        } catch let e as APIError {
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
        SocialFeedTrip(
            id: id, author: author, title: title,
            startDate: startDate, endDate: endDate,
            distance: distance, duration: duration, region: region,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            reactionCount: reactionCount, myReaction: myReaction,
            badgeIds: badgeIds
        )
    }
}
