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
    /// if `trips` is non-empty — otherwise app reopens an hour later
    /// still show old feed until the user pulls-to-refresh. Trip
    /// activity is low-frequency (driving sessions) so 15 minutes is a
    /// reasonable middle ground vs. battery + bandwidth.
    private var lastLoadedAt: Date?
    private let staleness: TimeInterval = 15 * 60
    private var cancellables = Set<AnyCancellable>()
    /// Debounce hub for server-confirmed photo refreshes. When Cloud Sync
    /// drains, each uploaded photo posts a no-delta `.tripPhotosChanged`;
    /// calling `refresh()` (a `/social/feed` round-trip) per photo hammered the
    /// network and republished the whole feed repeatedly. Routing those events
    /// through this subject collapses a burst into a single trailing refresh.
    private let serverPhotoRefresh = PassthroughSubject<Void, Never>()
    /// Bounded cold-start auto-retry counter. The FIRST feed load after launch
    /// can fail on a not-yet-warm connection (cold LAN/localhost dev backend,
    /// momentary no-route on app start, or a flaky RU mobile network exhausting
    /// APIClient's in-place attempts). Without this the feed dead-ends on the
    /// empty/error state until a MANUAL pull-to-refresh. Reset on any success.
    private var coldStartRetries = 0
    private let maxColdStartRetries = 2

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
                    // Server-confirmed event — fetch authoritative state, but
                    // debounced (below) so a drain of N photos = one refresh.
                    self.serverPhotoRefresh.send(())
                }
            }
            .store(in: &cancellables)

        // THROTTLE (not debounce): one /social/feed refresh per window at most,
        // but a long continuous photo drain still refreshes periodically rather
        // than withholding every update until the stream finally quiesces.
        serverPhotoRefresh
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refresh() }
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
    /// Also invalidates `lastLoadedAt` so a subsequent `loadIfNeeded` re-fetches
    /// the authoritative server state instead of treating the locally-mutated
    /// cache as fresh (which would let the freshness window mask a missed sync).
    func removeOptimistically(tripId: UUID) {
        trips.removeAll { $0.id == tripId }
        lastLoadedAt = nil
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
            coldStartRetries = 0
        } catch is CancellationError {
            // Superseded by a newer refresh, OR our in-flight fetch was cancelled
            // by the cold-start token-refresh race — the reported "feed empty on
            // cold launch until pull-to-refresh". If we're still empty and nothing
            // newer is running, self-heal with a bounded retry (the guard inside
            // prevents stomping a refresh the user/system already started).
            scheduleColdStartRetry(replace: replace)
        } catch let e as APIError {
            // URLSession cancellations surface as APIError.network(-999) — same
            // cold-start race; recover the same way instead of sitting empty.
            if case .network(let urlErr) = e, urlErr.code == .cancelled {
                scheduleColdStartRetry(replace: replace)
                return
            }
            lastError = e
            socialLog.error("feed fetch failed: \(String(describing: e))")

            // Cold-start self-heal for transient errors (network, 5xx, server
            // hiccup, 429) — otherwise the feed sits empty until a manual pull.
            let isTransient: Bool
            switch e {
            case .network: isTransient = true            // non-cancelled (handled above)
            case .invalidHTTPStatus(let code): isTransient = code >= 500
            case .unknownServer, .tooManyRequests: isTransient = true
            default: isTransient = false
            }
            if isTransient { scheduleColdStartRetry(replace: replace) }
        } catch {
            socialLog.error("feed fetch error: \(error.localizedDescription)")
        }
    }

    /// Schedule ONE bounded, delayed retry when the FIRST page load left the feed
    /// EMPTY — covers transient errors AND cancellations. The cold-start
    /// token-refresh race cancels the in-flight feed fetch (-999), which used to
    /// leave the feed empty until the user manually pulled. The `currentTask == nil`
    /// + `trips.isEmpty` re-check at fire time prevents looping or stomping a
    /// refresh the user/system already started — so a normal pull-to-refresh on a
    /// populated feed (which also cancels the prior task) never triggers a spurious
    /// retry, and a freshly-started refresh wins.
    private func scheduleColdStartRetry(replace: Bool) {
        guard replace, trips.isEmpty, coldStartRetries < maxColdStartRetries else { return }
        coldStartRetries += 1
        let attempt = coldStartRetries
        let maxAttempts = maxColdStartRetries
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            guard self.currentTask == nil, self.trips.isEmpty else { return }
            socialLog.notice("feed cold-start auto-retry \(attempt)/\(maxAttempts)")
            await self.refresh()
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
            maxSpeed: maxSpeed, elevation: elevation,
            maxAltitude: maxAltitude, drivingTime: drivingTime, stoppedTime: stoppedTime,
            region: region,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            vehicle: vehicle,
            reactionCount: reactionCount, reactionBreakdown: updated,
            myReaction: myReaction, badgeIds: badgeIds,
            commentCountRaw: commentCountRaw
        )
    }
}
