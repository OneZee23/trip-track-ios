import Foundation
import OSLog

private let companionsLog = Logger(subsystem: "com.triptrack", category: "companions")

/// `list(tripId:)`'s request lifecycle for one trip, read by
/// `CompanionsCardModel.decide` so a card can tell "haven't asked yet",
/// "asking", "asked and got an answer" and "asked and it broke" apart.
/// `idle` and `loading` render identically today — nothing currently
/// depends on the difference — but collapsing them into one case would
/// re-introduce the exact bug this type exists to prevent: the whole
/// reason `loaded` and `failed` are distinct cases is that a card must
/// never mistake "the request failed" for "the request succeeded and came
/// back empty", and a type that only bothered to distinguish THOSE two
/// would be quietly asserting a confidence about "idle vs loading" it
/// hasn't earned either.
enum CompanionsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

/// Trip companions — who was in the car. Singleton (mirrors
/// `NotificationsInboxStore`) because the "companions on this trip" roster
/// and the "trips I'm a companion on" list are both consumed from more than
/// one screen (trip detail, invite picker, a future "my rides" tab) and
/// should share one cache instead of drifting.
///
/// Reads (`list`, `candidates`, `loadMyTrips`) follow `NotificationsInboxStore`'s
/// convention: swallow the error, log it, leave previously-cached state in
/// place. `list` and `invitePreview` are the exception — they return/throw
/// directly to the caller (no optimistic state to protect, and the calling
/// screen — companion roster section, invite-preview card — needs to tell
/// "still loading" apart from "failed"). `list` ALSO records that same
/// still-loading/failed/loaded distinction into `loadStateByTrip`, because a
/// caller that only reads `companionsByTrip` cannot tell a request that
/// failed apart from a trip that genuinely has no companions — both leave
/// that dictionary empty.
///
/// `invite`, `respond`, `remove` are optimistic mutations: they apply the
/// change to published state immediately, then roll back to the captured
/// previous value AND rethrow if the network call fails, so the caller can
/// show an error toast. Silent rollback (swallowing the error) would leave
/// the user thinking the action failed with no explanation — that's the
/// one thing this store must never do.
@MainActor
final class CompanionsStore: ObservableObject {
    static let shared = CompanionsStore()

    /// Roster per trip, keyed by tripId. Populated by `list(tripId:)`,
    /// mutated optimistically by `invite`/`remove`.
    @Published private(set) var companionsByTrip: [UUID: [CompanionItem]] = [:]
    /// `list(tripId:)`'s request lifecycle per trip — see `CompanionsLoadState`.
    /// Missing key (never queried) reads as `.idle` via `loadState(for:)`.
    @Published private(set) var loadStateByTrip: [UUID: CompanionsLoadState] = [:]
    /// Current candidate picker page for whichever trip was last queried.
    /// Not keyed by tripId — only one invite picker is ever on screen.
    @Published private(set) var candidates: [CompanionCandidate] = []
    /// `candidates(tripId:query:reset:)`'s own request lifecycle — same
    /// `CompanionsLoadState` `list(tripId:)` uses for `loadStateByTrip`, not
    /// keyed by trip for the same reason `candidates` itself isn't (one
    /// picker on screen at a time). Added so `CompanionsPickerSheet` can
    /// tell a failed page apart from a genuinely empty one instead of
    /// swallowing the error the way `candidates` used to (see
    /// `performCandidates`).
    @Published private(set) var candidatesLoadState: CompanionsLoadState = .idle
    /// "Со мной" — trips the signed-in user is an accepted companion on.
    @Published private(set) var myTrips: [SocialFeedTrip] = []
    /// True while a `myTrips` page (first load or "load more") is in flight.
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var hasMoreMyTrips: Bool = true
    /// `loadMyTrips(reset:)`'s own request lifecycle — same `CompanionsLoadState`
    /// `list(tripId:)`/`candidates` use. `performLoadMyTrips` used to swallow
    /// its own error (log + leave stale `myTrips` in place, same convention
    /// as `candidates` before `candidatesLoadState` existed) — added so
    /// `WithMeSection`'s pure `WithMeSectionModel.decide` can tell a failed
    /// page apart from a genuinely empty one, the same fix Task 2/3's
    /// reviews made `list`/`candidates` apply.
    @Published private(set) var myTripsLoadState: CompanionsLoadState = .idle
    /// Trip ids the SIGNED-IN user has answered an invite for, keyed to the
    /// status they chose. Set by `respond`, persisted to `UserDefaults` (see
    /// `persistRespondedTripIds`/`loadRespondedTripIds`) and restored in
    /// `init`. Exists so `NotificationsInboxView`'s `companion_invite` row
    /// doesn't revert to showing accept/decline controls — `NotificationItem
    /// .kind` never changes server-side once answered (it's a permanent log
    /// entry), and the server has no field distinguishing a pending invite
    /// from an already-answered one. In-memory-only state wasn't enough:
    /// that view's own `@State` is torn down when the sheet dismisses, AND
    /// (the bug this persistence closes) the whole store is torn down and
    /// rebuilt across an app relaunch, which iOS does routinely by evicting
    /// backgrounded apps — without persisting here, a re-launched app would
    /// show the decision card again for an invite the user already
    /// answered, and tapping either button would surface the server's
    /// `CompanionInviteNotFound` as a confusing error. Read via
    /// `respondedStatus(for:)`. Cleared (both here and in `UserDefaults`) by
    /// `clear()` so it can't leak an answer across accounts on a shared
    /// device.
    @Published private(set) var respondedTripIds: [UUID: CompanionStatus] = [:]
    /// `respondedTripIds`, mirrored to `UserDefaults` as `[String: Int]`
    /// (tripId's `uuidString` → `CompanionStatus.rawValue`) since neither
    /// `UUID` nor a `Dictionary` keyed by it round-trips through
    /// `UserDefaults`'s property-list storage directly.
    private static let respondedTripIdsDefaultsKey = "com.triptrack.companions.respondedTripIds"

    private var candidatesCursor: String?
    private var candidatesHasMore = true
    private var candidatesTask: Task<Void, Never>?
    /// Bumped on every `reset: true` candidates call so a slow, since-
    /// superseded search response can't land after a newer one already
    /// replaced `candidates` — `Task.cancel()` alone only requests
    /// cooperative cancellation, it doesn't stop an in-flight response
    /// from being applied.
    private var candidatesGeneration = 0

    private var myTripsCursor: String?
    private var myTripsTask: Task<Void, Never>?
    private var myTripsGeneration = 0

    private let client: APIClient
    /// Where `list(tripId:)` writes its Task 7 offline cache after a
    /// successful fetch. Defaults to a plain `CoreDataTripRepository()`
    /// (backed by `PersistenceController.shared`) rather than going through
    /// a `TripManager` — `TripManager` has no app-wide singleton (it's
    /// owned per-`MapViewModel`), and `CompanionsStore` is constructed
    /// before any view exists. Same shape as `APISyncTransport`'s own
    /// `repo: TripRepository` dependency.
    private let repository: TripRepository

    /// Not `private` — `CompanionsStorePersistenceTests` constructs a
    /// SECOND instance (independent of `.shared`) to prove
    /// `respondedTripIds` restores from `UserDefaults` in `init` itself,
    /// not merely "the same running instance remembers what it was told".
    /// `CompanionsCachePersistenceTests` uses the same non-private `init`
    /// to inject a mocked `APIClient` and an ISOLATED in-memory
    /// `TripRepository`, so those tests' network/CoreData side effects
    /// never touch the shared store or `.shared`. Production code has no
    /// reason to call this directly and should always go through `.shared`.
    init(client: APIClient = .shared, repository: TripRepository = CoreDataTripRepository()) {
        self.client = client
        self.repository = repository
        respondedTripIds = Self.loadRespondedTripIds()
    }

    /// Reads `respondedTripIdsDefaultsKey` back into `[UUID: CompanionStatus]`.
    /// Unparsable entries (a corrupt default, or a status value from a
    /// future app version this build doesn't recognize) are dropped rather
    /// than failing the whole restore — one bad entry shouldn't resurrect
    /// the decision card for every OTHER already-answered invite too.
    private static func loadRespondedTripIds() -> [UUID: CompanionStatus] {
        guard let raw = UserDefaults.standard.dictionary(forKey: respondedTripIdsDefaultsKey)
            as? [String: Int] else { return [:] }
        var result: [UUID: CompanionStatus] = [:]
        for (key, value) in raw {
            guard let tripId = UUID(uuidString: key), let status = CompanionStatus(rawValue: value) else {
                continue
            }
            result[tripId] = status
        }
        return result
    }

    private func persistRespondedTripIds() {
        let raw = Dictionary(uniqueKeysWithValues: respondedTripIds.map { ($0.key.uuidString, $0.value.rawValue) })
        UserDefaults.standard.set(raw, forKey: Self.respondedTripIdsDefaultsKey)
    }

    /// `.idle` for a trip `list(tripId:)` has never been called for yet —
    /// distinct from every other state, none of which the dictionary can
    /// represent with a missing key.
    func loadState(for tripId: UUID) -> CompanionsLoadState {
        loadStateByTrip[tripId] ?? .idle
    }

    /// This session's recorded answer to an invite on `tripId`, if any —
    /// see `respondedTripIds`. `nil` means "not answered this session",
    /// NOT "still pending" (a trip accepted/declined in a PRIOR session
    /// reads as `nil` here too; there is currently no cheap way to tell
    /// those apart client-side without re-hitting `invitePreview`).
    func respondedStatus(for tripId: UUID) -> CompanionStatus? {
        respondedTripIds[tripId]
    }

    // MARK: - Roster (list)

    /// Loads (and caches, in memory) the companion roster for one trip.
    /// Throws on failure — unlike `candidates`/`loadMyTrips`, callers here
    /// (the trip detail companion section) need to distinguish "still
    /// loading" from "failed to load" rather than silently keep
    /// stale/empty state. Also records the same distinction into
    /// `loadStateByTrip` BEFORE the throw/return, so a caller reading only
    /// the published state (not catching this call itself) still sees it.
    ///
    /// Task 7: a successful response is ALSO written to the on-device cache
    /// (`Trip.companions` / `companionsJSON`) via `cacheRoster`, so the next
    /// time this same call can't reach the network, the card has something
    /// to fall back to — see `CompanionsCardModel.decide`'s `cached`
    /// parameter.
    ///
    /// - Parameter treatTripNotFoundAsEmpty: Fix 2. `TripCompanionsSection`
    ///   only calls `list` at all once it believes the trip is on the
    ///   server (`TripDetailView`'s `canQueryCompanions` gate) — but that
    ///   belief is a LOCAL flag (`Trip.isOnServer`), and a record→upload
    ///   race (the sync push hasn't landed server-side yet, even though the
    ///   local row already thinks it has) can still make the request come
    ///   back `TRIP_NOT_FOUND` for a trip that IS, genuinely, this device's
    ///   own. Passing `true` (only ever done for an own trip — see the call
    ///   site) folds exactly that error into a normal empty, loaded roster
    ///   instead of `.failed`, so the race can't flash the red retry
    ///   banner. A non-owner's `TRIP_NOT_FOUND` is never remapped — for
    ///   them it means what it says.
    @discardableResult
    func list(tripId: UUID, treatTripNotFoundAsEmpty: Bool = false) async throws -> CompanionsListResponse {
        loadStateByTrip[tripId] = .loading
        do {
            let res: CompanionsListResponse = try await client.post(
                APIEndpoint.companionsList, body: CompanionsTripRequest(tripId: tripId))
            companionsByTrip[tripId] = res.items
            loadStateByTrip[tripId] = .loaded
            cacheRoster(res.items, for: tripId)
            return res
        } catch APIError.tripNotFound where treatTripNotFoundAsEmpty {
            let empty = CompanionsListResponse(items: [], isOwnerView: true)
            companionsByTrip[tripId] = empty.items
            loadStateByTrip[tripId] = .loaded
            cacheRoster(empty.items, for: tripId)
            return empty
        } catch {
            loadStateByTrip[tripId] = .failed
            companionsLog.error("list failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Writes a just-fetched roster into the local offline cache. Called
    /// unconditionally after every successful `list(tripId:)` — own trip or
    /// not. That's deliberate, not an oversight: `TripRepository
    /// .updateCompanions` itself no-ops when `tripId` has no local
    /// `TripEntity` (`guard let entity = fetchEntity(id: tripId) else {
    /// return }`), and a trip that isn't ours never has one. That guard —
    /// not a check performed here — is what keeps a foreign trip's roster
    /// from ever creating a local row. See `CompanionsCachePersistenceTests`
    /// for the count-based proof this holds.
    private func cacheRoster(_ items: [CompanionItem], for tripId: UUID) {
        repository.updateCompanions(for: tripId, companions: items.map(TripCompanion.init(item:)))
    }

    // MARK: - Candidates (invite picker, cursor-paged)

    /// `reset: true` starts a fresh page — new search text, or the picker
    /// just opened for a (possibly different) trip: cancels any in-flight
    /// request and replaces `candidates`. `reset: false` pages forward from
    /// the stored cursor, id-deduping appended rows (a candidate near a page
    /// boundary could otherwise repeat if the caller re-triggers); a no-op
    /// once the previous page reported no `nextCursor`. Concurrent
    /// "load more" calls coalesce onto the same in-flight Task instead of
    /// firing a duplicate request.
    func candidates(tripId: UUID, query: String? = nil, reset: Bool) async {
        if reset {
            candidatesTask?.cancel()
            candidatesTask = nil
            candidatesGeneration &+= 1
            candidatesCursor = nil
            candidatesHasMore = true
        } else {
            guard candidatesHasMore else { return }
            if let inflight = candidatesTask {
                await inflight.value
                return
            }
        }
        let cursor = reset ? nil : candidatesCursor
        let generation = candidatesGeneration
        let task = Task<Void, Never> { [weak self] in
            await self?.performCandidates(
                tripId: tripId, query: query, cursor: cursor, replace: reset, generation: generation)
        }
        candidatesTask = task
        await task.value
        if candidatesTask == task { candidatesTask = nil }
    }

    private func performCandidates(
        tripId: UUID, query: String?, cursor: String?, replace: Bool, generation: Int
    ) async {
        // A newer `reset: true` call may have already superseded this one
        // before its Task even started running (`Task.cancel()` is only
        // cooperative) — don't announce "loading" for a request nothing
        // downstream still cares about.
        guard generation == candidatesGeneration else { return }
        candidatesLoadState = .loading
        do {
            let res: CompanionsCandidatesResponse = try await client.post(
                APIEndpoint.companionsCandidates,
                body: CompanionsCandidatesRequest(tripId: tripId, query: query, cursor: cursor))
            // A newer `reset: true` call superseded this one while it was
            // in flight — drop the stale page instead of clobbering the
            // list a fresher search already replaced.
            guard generation == candidatesGeneration else { return }
            if replace {
                candidates = res.items
            } else {
                let known = Set(candidates.map(\.accountId))
                candidates.append(contentsOf: res.items.filter { !known.contains($0.accountId) })
            }
            candidatesCursor = res.nextCursor
            candidatesHasMore = res.nextCursor != nil
            candidatesLoadState = .loaded
        } catch {
            guard generation == candidatesGeneration else { return }
            candidatesLoadState = .failed
            companionsLog.error("candidates failed: \(error.localizedDescription)")
        }
    }

    // MARK: - My trips (cursor-paged)

    /// `reset: true` = first page / pull-to-refresh; `reset: false` = "load
    /// more" from the stored cursor. Same coalescing + generation-guard +
    /// id-dedup shape as `candidates`.
    func loadMyTrips(reset: Bool) async {
        if reset {
            myTripsTask?.cancel()
            myTripsTask = nil
            myTripsGeneration &+= 1
            myTripsCursor = nil
            hasMoreMyTrips = true
        } else {
            guard hasMoreMyTrips else { return }
            if let inflight = myTripsTask {
                await inflight.value
                return
            }
        }
        let cursor = reset ? nil : myTripsCursor
        let generation = myTripsGeneration
        let task = Task<Void, Never> { [weak self] in
            await self?.performLoadMyTrips(cursor: cursor, replace: reset, generation: generation)
        }
        myTripsTask = task
        await task.value
        if myTripsTask == task { myTripsTask = nil }
    }

    private func performLoadMyTrips(cursor: String?, replace: Bool, generation: Int) async {
        isLoading = true
        defer { if generation == myTripsGeneration { isLoading = false } }
        // A newer `reset: true` call may have already superseded this one
        // before its Task even started running — don't announce "loading"
        // for a request nothing downstream still cares about (same guard
        // `performCandidates` uses).
        guard generation == myTripsGeneration else { return }
        myTripsLoadState = .loading
        do {
            let res: CompanionsMyTripsResponse = try await client.post(
                APIEndpoint.companionsMyTrips, body: CompanionsMyTripsRequest(cursor: cursor))
            guard generation == myTripsGeneration else { return }
            if replace {
                myTrips = res.items
            } else {
                let known = Set(myTrips.map(\.id))
                myTrips.append(contentsOf: res.items.filter { !known.contains($0.id) })
            }
            myTripsCursor = res.nextCursor
            hasMoreMyTrips = res.nextCursor != nil
            myTripsLoadState = .loaded
        } catch {
            guard generation == myTripsGeneration else { return }
            myTripsLoadState = .failed
            companionsLog.error("loadMyTrips failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Invite preview

    /// The single driver card a still-pending invitee sees before accepting.
    /// Throws directly — no cached state, the caller needs the error to
    /// render its own failure state.
    func invitePreview(tripId: UUID) async throws -> CompanionInvitePreview {
        try await client.post(
            APIEndpoint.companionsInvitePreview, body: CompanionsTripRequest(tripId: tripId))
    }

    // MARK: - Optimistic mutations

    /// Invites `accountId` onto `tripId`. Optimistically drops the account
    /// from the candidate picker (it's no longer invitable) and, ONLY if
    /// this trip's roster is already cached (a prior `list(tripId:)` call),
    /// appends a pending row to it — reusing the candidate's display
    /// name/avatar so the row isn't blank while the request is in flight.
    /// If nothing is cached yet, the roster is left untouched rather than
    /// seeded with a one-row `[pending]` array: that would locally "hide"
    /// every already-accepted companion until the next `list()` call
    /// overwrote it. Rolls back both on failure and rethrows so the caller
    /// can show a toast.
    func invite(tripId: UUID, accountId: UUID) async throws {
        let previousCandidates = candidates
        let previousRoster = companionsByTrip[tripId]

        let invited = candidates.first { $0.accountId == accountId }
        candidates.removeAll { $0.accountId == accountId }
        if var roster = companionsByTrip[tripId] {
            roster.append(CompanionItem(
                accountId: accountId, displayName: invited?.displayName,
                avatarEmoji: invited?.avatarEmoji, status: .pending))
            companionsByTrip[tripId] = roster
        }

        do {
            let _: CompanionsInviteResponse = try await client.post(
                APIEndpoint.companionsInvite, body: CompanionsInviteRequest(tripId: tripId, accountId: accountId))
        } catch {
            candidates = previousCandidates
            companionsByTrip[tripId] = previousRoster
            companionsLog.error("invite failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Accepts or declines an invite for the SIGNED-IN user on `tripId`. If
    /// that user's own row happens to be cached in `companionsByTrip[tripId]`
    /// (they've viewed the roster before, or after an earlier accept), flips
    /// its status optimistically; harmless no-op otherwise. Rolls back the
    /// cache entry and rethrows on failure.
    func respond(tripId: UUID, accept: Bool) async throws {
        let previousRoster = companionsByTrip[tripId]
        let previousResponded = respondedTripIds[tripId]
        if let myId = TokenStore.shared.accountId,
           var roster = companionsByTrip[tripId],
           let idx = roster.firstIndex(where: { $0.accountId == myId }) {
            roster[idx] = CompanionItem(
                accountId: myId, displayName: roster[idx].displayName,
                avatarEmoji: roster[idx].avatarEmoji, status: accept ? .accepted : .declined)
            companionsByTrip[tripId] = roster
        }
        respondedTripIds[tripId] = accept ? .accepted : .declined
        persistRespondedTripIds()

        do {
            let _: CompanionsRespondResponse = try await client.post(
                APIEndpoint.companionsRespond, body: CompanionsRespondRequest(tripId: tripId, accept: accept))
        } catch {
            companionsByTrip[tripId] = previousRoster
            respondedTripIds[tripId] = previousResponded
            persistRespondedTripIds()
            companionsLog.error("respond failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Removes `accountId` from `tripId`'s roster (owner removing anyone, or
    /// a companion removing themselves). Optimistically drops the row;
    /// restores it and rethrows on failure.
    func remove(tripId: UUID, accountId: UUID) async throws {
        let previousRoster = companionsByTrip[tripId]
        companionsByTrip[tripId]?.removeAll { $0.accountId == accountId }

        do {
            let _: CompanionsRemoveResponse = try await client.post(
                APIEndpoint.companionsRemove, body: CompanionsRemoveRequest(tripId: tripId, accountId: accountId))
        } catch {
            companionsByTrip[tripId] = previousRoster
            companionsLog.error("remove failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Clear (on sign out)

    func clear() {
        companionsByTrip = [:]
        loadStateByTrip = [:]
        candidates = []
        candidatesLoadState = .idle
        myTrips = []
        isLoading = false
        hasMoreMyTrips = true
        myTripsLoadState = .idle
        respondedTripIds = [:]
        UserDefaults.standard.removeObject(forKey: Self.respondedTripIdsDefaultsKey)
        candidatesCursor = nil
        candidatesHasMore = true
        candidatesTask = nil
        myTripsCursor = nil
        myTripsTask = nil
    }
}
