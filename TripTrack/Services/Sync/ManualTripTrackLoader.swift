import Foundation

/// Full geometry for an own web-created manual trip, downloaded on opening it.
/// Summary pulls stay small. A failed request leaves the existing preview and
/// is retried on the next opening; no saved data is cleared to force a download.
@MainActor
final class ManualTripTrackLoader {
    static let shared = ManualTripTrackLoader()

    struct Snapshot: Equatable {
        let id: UUID
        let conflictVersion: Int
        let lastModifiedAt: Date?
    }

    /// Same ceiling as the web manual-create contract. Never truncate a route.
    static let maximumPoints = 10_000

    private let repository: CoreDataTripRepository
    private let accountId: () -> UUID?
    private let cloudSyncEnabled: () -> Bool
    private let fetch: (UUID) async throws -> TripSyncPayload
    private let afterLoad: (UUID) async -> Void

    init(repository: CoreDataTripRepository = CoreDataTripRepository(),
         accountId: @escaping () -> UUID? = { TokenStore.shared.accountId },
         cloudSyncEnabled: @escaping () -> Bool = { SettingsManager.shared.cloudSyncEnabled },
         fetch: @escaping (UUID) async throws -> TripSyncPayload = { id in
             try await APIClient.shared.post(APIEndpoint.tripDetail,
                 body: TripDetailRequest(id: id, includeTrackPoints: true))
         },
         afterLoad: @escaping (UUID) async -> Void = { id in
             await ManualTripAftermath.settle(tripId: id)
         }) {
        self.repository = repository
        self.accountId = accountId
        self.cloudSyncEnabled = cloudSyncEnabled
        self.fetch = fetch
        self.afterLoad = afterLoad
    }

    /// Cloud Sync is checked twice: before asking the server, and again just
    /// before writing. Turning it off while the request is in flight means
    /// "stop mirroring the server into this phone" — the late reply is dropped.
    func loadIfNeeded(id: UUID) async -> Trip? {
        guard !Task.isCancelled, cloudSyncEnabled(), let owner = accountId(),
              let snapshot = repository.missingManualTrack(id: id) else { return nil }
        do {
            let payload = try await fetch(id)
            let points = await Task.detached(priority: .utility) {
                Self.validatedPoints(payload, expected: snapshot)
            }.value
            // Identity, Cloud Sync and the row's unsaved state are checked on the
            // main actor; the write re-checks the saved row in its own context.
            // The view context first: unsaved edits by the person live there, and
            // a background context reads only what has been saved.
            guard !Task.isCancelled, cloudSyncEnabled(), accountId() == owner,
                  let points, repository.missingManualTrack(id: id) == snapshot else { return nil }
            // The write runs off the main actor and re-checks the row in its own
            // context (local edits, deletion, a newer pull) just before saving.
            guard await repository.applyMissingManualTrackAsync(points, expected: snapshot),
                  !Task.isCancelled, accountId() == owner else { return nil }
            await afterLoad(id)
            guard !Task.isCancelled, accountId() == owner else { return nil }
            // Off the main actor too: materializing ten thousand points to
            // hand back to the screen cost ~110 ms there.
            let hydrated = await repository.fetchTripDetailAsync(id: id)
            guard !Task.isCancelled, accountId() == owner else { return nil }
            return hydrated
        } catch {
            // The screen still has the synced preview. Do not log a private URL,
            // coordinates, token or the payload merely to describe a retry.
            return nil
        }
    }

    nonisolated private static func validatedPoints(_ payload: TripSyncPayload,
                                                    expected: Snapshot) -> [TrackPointPayload]? {
        guard payload.id == expected.id, payload.source == .manual,
              payload.conflictVersion == expected.conflictVersion,
              payload.lastModifiedAt == expected.lastModifiedAt,
              let end = payload.endDate, end >= payload.startDate,
              let points = payload.trackPoints,
              (2...maximumPoints).contains(points.count) else { return nil }
        var ids = Set<UUID>()
        var previous = payload.startDate
        for point in points {
            guard point.latitude.isFinite, abs(point.latitude) <= 90,
                  point.longitude.isFinite, abs(point.longitude) <= 180,
                  point.altitude.isFinite, point.speed.isFinite,
                  point.course.isFinite, point.horizontalAccuracy.isFinite,
                  point.timestamp >= previous, point.timestamp <= end,
                  ids.insert(point.id).inserted else { return nil }
            // -1 means unmeasured accuracy, as in ManualTripBuilder; it does
            // not make a constructed manual coordinate invalid.
            previous = point.timestamp
        }
        return points
    }

    /// Can this trip go to the server with `trackPoints = nil` ("leave the
    /// server's route alone")?
    ///
    /// Not when it is public and a home privacy zone is on. The server copy
    /// of a web-created route is the FULL route — the phone never had it, so
    /// it never trimmed it — and `nil` would publish exactly that, home
    /// included. Such an upload first downloads the route, so the ordinary
    /// `wireTrack` trims it like any other trip; until that succeeds the
    /// upload waits in the queue. A private trip is not shown to anyone, and
    /// its first real upload after loading is trimmed as usual.
    nonisolated static func mustLoadBeforeUpload(source: TripOrigin, isPrivate: Bool,
                                                 hasLocalPoints: Bool, isOnServer: Bool,
                                                 zoneActive: Bool) -> Bool {
        source == .manual && isOnServer && !hasLocalPoints && !isPrivate && zoneActive
    }

    enum UploadDeferred: LocalizedError {
        /// The route must be downloaded and trimmed before this public trip
        /// can be uploaded under the home privacy zone.
        case routeNotLoaded

        var errorDescription: String? { "Route not downloaded yet" }
    }

    /// Ensure the upload of `id` will not publish an untrimmed server route.
    /// Throws `UploadDeferred` when the route is needed and could not be
    /// loaded, so `SyncQueue` keeps the operation and retries it later.
    func prepareUpload(id: UUID, zoneActive: Bool = HomeSettings.load().activeZone != nil) async throws {
        guard let entity = repository.fetchEntity(id: id) else { return }
        let source = TripOrigin(rawValue: entity.source ?? "") ?? .recorded
        guard Self.mustLoadBeforeUpload(
            source: source, isPrivate: entity.isPrivate,
            hasLocalPoints: (entity.trackPoints?.count ?? 0) > 0,
            isOnServer: entity.serverCreatedAt != nil, zoneActive: zoneActive) else { return }
        guard await loadIfNeeded(id: id) != nil,
              (repository.fetchEntity(id: id)?.trackPoints?.count ?? 0) > 0 else {
            throw UploadDeferred.routeNotLoaded
        }
    }
}

