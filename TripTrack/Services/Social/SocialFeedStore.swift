import Foundation
import Combine
import OSLog

private let socialLog = Logger(subsystem: "com.triptrack", category: "social")

@MainActor
final class SocialFeedStore: ObservableObject {
    /// Which server-side feed composition this instance mirrors.
    enum FeedType: String {
        case all
        case following
    }

    /// Global discovery feed («Все») — the instance every reaction/privacy/
    /// photo consumer references; its name must stay `shared`.
    static let shared = SocialFeedStore(type: .all)
    /// «Подписки» — followed users + own public trips. Separate instance so
    /// both segments keep independent pages/cursors; all notification-driven
    /// self-healing (privacy/delete/photo/comment observers) applies to both.
    static let following = SocialFeedStore(type: .following)

    private let feedType: FeedType

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
    /// Last-known `myReaction` per trip id, remembered for EVERY trip a feed
    /// page ever served (not just the trips currently cached). A detail screen
    /// can outlive its trip's presence in `trips` — refresh() replaces the
    /// array with a fresh 20-item page-1, evicting deep-scrolled trips — and
    /// reactions must still toggle correctly there instead of silently
    /// no-oping. Session-scoped, bounded by feed browsing; cleared on
    /// sign-out via `clear()`.
    private var knownReactions: [UUID: String?] = [:]

    private init(type: FeedType) {
        self.feedType = type
        // Network came back: reload if we're sitting on an offline error, so
        // the user doesn't have to notice and pull down themselves.
        CacheManager.shared.networkRestored
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.trips.isEmpty, self.lastError != nil else { return }
                Task { @MainActor in
                    self.coldStartRetries = 0
                    await self.refresh()
                }
            }
            .store(in: &cancellables)
        // Photo added/removed/uploaded somewhere in the app. The notification
        // arrives twice for the same change — once optimistically from
        // `TripRepository` with a `delta` (+1 add / -1 delete) so we can
        // bump the card's `photoCount` instantly, and again from
        // `APISyncTransport` after the upload lands (no delta) so we can
        // reconcile with the server's authoritative count.
        // Privacy flips can happen while FeedView (the only view-level
        // reconciler) is UNMOUNTED — from the record-tab completion summary
        // or a trip detail pushed on the Я tab. The store must self-heal:
        // hide → drop the card + invalidate freshness; publish → invalidate
        // so the next loadIfNeeded actually refetches instead of trusting
        // the 15-minute window. Idempotent with FeedView's own handler.
        NotificationCenter.default.publisher(for: .tripPrivacyChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, let payload = note.object as? PrivacyChangePayload else { return }
                if payload.isPrivate {
                    self.removeOptimistically(tripId: payload.tripId)
                } else {
                    self.lastLoadedAt = nil
                }
            }
            .store(in: &cancellables)

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

        // Trip deleted (detail-screen «…» menu — the only delete flow). Like
        // privacy flips, this can fire while FeedView is unmounted, so the
        // store must self-heal: drop the card immediately and invalidate
        // freshness so the next loadIfNeeded refetches authoritative state.
        // Without this, deleting an own PUBLIC trip left a ghost card in
        // «Все» for up to the 15-minute staleness window.
        NotificationCenter.default.publisher(for: .tripDeleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if let tripId = note.object as? UUID {
                    self.removeOptimistically(tripId: tripId)
                } else {
                    self.lastLoadedAt = nil
                }
            }
            .store(in: &cancellables)

        // Comment posted/deleted by the signed-in user in a detail screen —
        // bump the card's «💬 N» counter in place. Same optimistic pattern as
        // `bumpPhotoCount`; without it the card contradicts what the user
        // just did until a manual pull-to-refresh or the staleness window.
        // userInfo: ["tripId": UUID, "delta": Int].
        NotificationCenter.default.publisher(for: .tripCommentCountChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self,
                      let tripId = note.userInfo?["tripId"] as? UUID,
                      let delta = note.userInfo?["delta"] as? Int else { return }
                self.bumpCommentCount(tripId: tripId, delta: delta)
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

    /// Optimistic in-place bump of a feed card's comment counter so the «💬 N»
    /// bubble reflects a just-posted/deleted comment without waiting for a
    /// `/social/feed` round-trip.
    private func bumpCommentCount(tripId: UUID, delta: Int) {
        guard let idx = trips.firstIndex(where: { $0.id == tripId }) else { return }
        let t = trips[idx]
        trips[idx] = t.with(commentCount: max(0, t.commentCount + delta))
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
        // Offline: fail immediately instead of handing the request to
        // URLSession and then sitting on its timeout ladder plus our own
        // cold-start retries. In airplane mode that combination showed
        // «Загружаем ленту…» for minutes and never reached the error state.
        if CacheManager.shared.isOffline {
            currentTask?.cancel()
            currentTask = nil
            isLoading = false
            if trips.isEmpty { lastError = .network(URLError(.notConnectedToInternet)) }
            return
        }
        // Cancel any in-flight refresh so pull-to-refresh always triggers a fresh
        // fetch. The previous URLSession task gets cancelled via Task cooperative
        // cancellation — its -999 error is swallowed by fetchPage()'s catch.
        currentTask?.cancel()
        refreshGeneration &+= 1
        let myGen = refreshGeneration
        // Set synchronously (we're @MainActor) so there is no frame where
        // isLoading is false while trips is empty — FeedView renders the
        // "feed is empty" state on `trips.isEmpty && !isLoading`.
        isLoading = true

        let task = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.nextCursor = nil
                self.hasMore = true
            }
            await self.fetchPage(replace: true)
        }
        currentTask = task
        await task.value
        // Only the LATEST refresh clears shared state. A superseded refresh
        // (cancelled by a newer one — e.g. the Cloud-Sync photo-drain reconcile
        // torpedoing the initial cold-start load) must NOT flip isLoading=false
        // while its successor is still fetching, or the "feed is empty" message
        // flashes for the ~second the refire takes on slow links (VPN / cold RU
        // mobile). Guarding by generation keeps the spinner up instead. Also
        // clears currentTask so loadIfNeeded() doesn't silently no-op forever.
        if refreshGeneration == myGen {
            currentTask = nil
            isLoading = false
        }
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
        // `type` is sent only for the following feed — old servers ignore
        // the unknown field, and "all" is their default anyway.
        let req = SocialFeedRequest(
            limit: 20, cursor: nextCursor,
            type: feedType == .following ? FeedType.following.rawValue : nil)
        // Capture the generation BEFORE the request goes out. refresh() only
        // cancels `currentTask` — a loadMore in flight when a refresh fires
        // (pull-to-refresh, the photo-drain reconcile) survives, and landing
        // its stale page after the refresh replaced `trips` would append
        // duplicates AND rewind `nextCursor` onto the old cursor chain.
        let myGen = refreshGeneration
        do {
            // `requiresAuth: false` for guests so APIClient skips the token
            // header and the USER_NOT_AUTH retry. Server returns trending
            // when no viewer is identified.
            let res: SocialFeedResponse = try await APIClient.shared.post(
                APIEndpoint.socialFeed, body: req,
                requiresAuth: AuthService.shared.isSignedIn)
            try Task.checkCancellation()
            guard refreshGeneration == myGen else { return }
            if replace {
                trips = res.trips
            } else {
                // Id-dedup on append: the trending feed orders by reaction
                // count but pages by a startDate cursor, so page 2 can
                // re-serve high-reaction trips already on page 1. Duplicate
                // ids double the card AND break ForEach identity in FeedView.
                let known = Set(trips.map(\.id))
                trips.append(contentsOf: res.trips.filter { !known.contains($0.id) })
            }
            for t in res.trips { knownReactions[t.id] = t.myReaction }
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
        // Retrying into a dead radio just re-runs the timeout ladder; the
        // network-restored subscription below is what recovers us.
        guard !CacheManager.shared.isOffline else { return }
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
        // The trip may have been EVICTED from the cached page-1 while a detail
        // screen stayed open (every refresh replaces `trips` with a fresh
        // 20-item first page). The POST must still go out in that case — the
        // pre-6.1 bug where store-absent trips silently no-oped is exactly
        // what this fallback fixes. `knownReactions` supplies the last-known
        // `myReaction` so toggle semantics survive eviction.
        let idx = trips.firstIndex(where: { $0.id == tripId })
        let snapshot = idx.map { trips[$0] }
        // Store copy wins (including its nil); the remembered value only
        // kicks in for evicted trips. A flattening `??` chain here would
        // wrongly resurrect a stale remembered reaction when the cached
        // trip's myReaction is legitimately nil.
        let current: String?
        if let snapshot {
            current = snapshot.myReaction
        } else {
            current = knownReactions[tripId] ?? nil
        }
        let wasMine = current != nil
        let wasSameEmoji = current == emoji
        let newMine: String? = wasSameEmoji ? nil : emoji

        // Optimistic update (only possible while the trip is still cached)
        if let idx, let trip = snapshot {
            let newCount: Int
            if wasSameEmoji {
                newCount = max(0, trip.reactionCount - 1)
            } else if wasMine {
                newCount = trip.reactionCount
            } else {
                newCount = trip.reactionCount + 1
            }
            trips[idx] = trip.with(reactionCount: newCount, myReaction: newMine)
        }
        knownReactions[tripId] = newMine

        do {
            if wasSameEmoji {
                let _: SocialReactResponse = try await APIClient.shared.post(
                    APIEndpoint.socialUnreact, body: SocialUnreactRequest(tripId: tripId))
            } else {
                let _: SocialReactResponse = try await APIClient.shared.post(
                    APIEndpoint.socialReact, body: SocialReactRequest(tripId: tripId, emoji: emoji))
            }
        } catch {
            // Revert the optimistic change on failure. Re-find by id — the
            // captured index can be STALE after the await (`trips` may have
            // been replaced by a refresh, shrunk by removeOptimistically, or
            // cleared on sign-out), so `trips[idx]` could trap out-of-range
            // or stamp the old value over a DIFFERENT trip's slot.
            if let snapshot,
               let curIdx = trips.firstIndex(where: { $0.id == tripId }) {
                trips[curIdx] = snapshot
            }
            knownReactions[tripId] = current
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
        knownReactions = [:]
    }
}

extension Notification.Name {
    /// Posted (userInfo: ["tripId": UUID, "delta": Int]) when the signed-in
    /// user posts (+1) or deletes (−1) a comment, so cached feed cards bump
    /// their «💬 N» counter without a `/social/feed` round-trip. Poster:
    /// `TripCommentsStore.post` / `.delete` on server-confirmed success.
    static let tripCommentCountChanged = Notification.Name("tripCommentCountChanged")
}

private extension SocialFeedTrip {
    /// Rebuild with a new comment count — `commentCountRaw` is a `let` on the
    /// DTO, so optimistic bumps go through the memberwise init like the
    /// reaction path below.
    func with(commentCount: Int) -> SocialFeedTrip {
        SocialFeedTrip(
            id: id, author: author, title: title, description: description,
            startDate: startDate, endDate: endDate,
            distance: distance, duration: duration,
            maxSpeed: maxSpeed, elevation: elevation,
            maxAltitude: maxAltitude, drivingTime: drivingTime, stoppedTime: stoppedTime,
            region: region, isPrivate: isPrivate,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            vehicle: vehicle,
            reactionCount: reactionCount, reactionBreakdown: reactionBreakdown,
            myReaction: myReaction, badgeIds: badgeIds,
            commentCountRaw: commentCount
        )
    }

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
            region: region, isPrivate: isPrivate,
            previewPolyline: previewPolyline,
            photoCount: photoCount, firstPhotoThumbnail: firstPhotoThumbnail,
            vehicle: vehicle,
            reactionCount: reactionCount, reactionBreakdown: updated,
            myReaction: myReaction, badgeIds: badgeIds,
            commentCountRaw: commentCountRaw
        )
    }
}
