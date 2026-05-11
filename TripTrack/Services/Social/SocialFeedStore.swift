import Foundation
import Combine
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
    /// Monotonic counter incremented on each refresh. Used to detect
    /// "is the in-flight Task still the one I started?" without relying
    /// on Task identity (Task is a struct — `===` doesn't compile).
    /// Without this, a finished refresh from yesterday would leave
    /// `currentTask` non-nil and `loadIfNeeded()` would silently no-op
    /// forever.
    private var refreshGeneration: Int = 0
    /// Wall-clock timestamp of the last successful fetch. `loadIfNeeded`
    /// triggers a fresh fetch once this is older than `staleness`, even
    /// if `trips` is non-empty — otherwise app reopens days later still
    /// show yesterday's feed until the user pulls-to-refresh.
    private var lastLoadedAt: Date?
    private let staleness: TimeInterval = 5 * 60
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Photo added/removed/uploaded somewhere in the app. The notification
        // arrives twice for the same change — once optimistically from
        // `TripRepository` with a `delta` (+1 add / -1 delete) so we can
        // bump the card's `photoCount` instantly, and again from
        // `APISyncTransport` after the upload lands (no delta) so we can
        // reconcile with the server's authoritative count.
        NotificationCenter.default.publisher(for: .tripPhotosChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if let tripId = note.userInfo?["tripId"] as? UUID,
                   let delta = note.userInfo?["delta"] as? Int {
                    // Local-side optimistic event — bump and DON'T refresh.
                    // Refreshing now would round-trip the still-stale server
                    // count and overwrite our optimistic update before the
                    // upload/delete actually lands. The server-confirmed
                    // notification (no delta) below triggers the reconcile.
                    self.bumpPhotoCount(tripId: tripId, delta: delta)
                } else {
                    // Server-confirmed event — fetch authoritative state.
                    Task { @MainActor [weak self] in await self?.refresh() }
                }
            }
            .store(in: &cancellables)
    }

    /// Optimistic in-place bump of a feed card's `photoCount` so the user
    /// sees the indicator the instant they add/remove a photo, without
    /// waiting for upload + `/social/feed` round-trip.
    private func bumpPhotoCount(tripId: UUID, delta: Int) {
        guard let idx = trips.firstIndex(where: { $0.id == tripId }) else { return }
        var t = trips[idx]
        t.photoCount = max(0, t.photoCount + delta)
        // If we just dropped to 0, clear the cached thumbnail too — otherwise
        // the indicator flips off but the preview tile stays for the
        // half-second until the server-confirming refresh lands.
        if t.photoCount == 0 { t.firstPhotoThumbnail = nil }
        trips[idx] = t
    }

    // MARK: - Load

    /// Lifecycle-friendly load that no-ops when fresh data is already
    /// on screen or a refresh is in flight. Call sites that fire on
    /// view appear / tab switch / sign-in flip should use this —
    /// otherwise repeated cancel+restart of `refresh()` torpedoes
    /// in-flight requests on slow networks.
    ///
    /// "Fresh enough" = loaded within the last `staleness` interval.
    /// Past that window, even with cached `trips`, we kick a fresh
    /// fetch so the user doesn't reopen the app the next day to find
    /// yesterday's feed.
    ///
    /// Explicit user actions (pull-to-refresh, retry button) and
    /// invalidation events (publish/unpublish) keep using `refresh()`.
    func loadIfNeeded() async {
        if currentTask != nil { return }
        if !trips.isEmpty, let last = lastLoadedAt,
           Date().timeIntervalSince(last) < staleness {
            return
        }
        await refresh()
    }

    func refresh() async {
        // Cancel any in-flight refresh so pull-to-refresh always triggers a fresh
        // fetch. The previous URLSession task gets cancelled via Task cooperative
        // cancellation — its -999 error is swallowed by fetchPage()'s catch.
        currentTask?.cancel()
        refreshGeneration &+= 1
        let myGen = refreshGeneration

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
        // Clear only if a newer refresh hasn't already replaced us.
        // Without this, `loadIfNeeded()` would silently no-op forever
        // — `currentTask` would still hold our finished-but-non-nil Task.
        if refreshGeneration == myGen { currentTask = nil }
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
            // `requiresAuth: false` for guests so APIClient skips the token
            // header and the USER_NOT_AUTH retry. Server returns trending
            // when no viewer is identified.
            let res: SocialFeedResponse = try await APIClient.shared.post(
                APIEndpoint.socialFeed, body: req,
                requiresAuth: AuthService.shared.isSignedIn)
            try Task.checkCancellation()
            if replace {
                trips = res.trips
            } else {
                trips.append(contentsOf: res.trips)
            }
            nextCursor = res.nextCursor
            hasMore = res.nextCursor != nil
            lastError = nil
            lastLoadedAt = Date()
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
        lastLoadedAt = nil
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
            id: id, author: author, title: title, description: description,
            startDate: startDate, endDate: endDate,
            distance: distance, duration: duration,
            maxSpeed: maxSpeed, elevation: elevation, region: region,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            vehicle: vehicle,
            reactionCount: reactionCount, reactionBreakdown: updated,
            myReaction: myReaction, badgeIds: badgeIds
        )
    }
}
