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
    private let fetch: (UUID) async throws -> TripSyncPayload
    private let afterLoad: (UUID) async -> Void

    init(repository: CoreDataTripRepository = CoreDataTripRepository(),
         accountId: @escaping () -> UUID? = { TokenStore.shared.accountId },
         fetch: @escaping (UUID) async throws -> TripSyncPayload = { id in
             try await APIClient.shared.post(APIEndpoint.tripDetail,
                 body: TripDetailRequest(id: id, includeTrackPoints: true))
         },
         afterLoad: @escaping (UUID) async -> Void = { id in
             await ManualTripAftermath.settle(tripId: id)
         }) {
        self.repository = repository
        self.accountId = accountId
        self.fetch = fetch
        self.afterLoad = afterLoad
    }

    func loadIfNeeded(id: UUID) async -> Trip? {
        guard !Task.isCancelled, let owner = accountId(),
              let snapshot = repository.missingManualTrack(id: id) else { return nil }
        do {
            let payload = try await fetch(id)
            let points = await Task.detached(priority: .utility) {
                Self.validatedPoints(payload, expected: snapshot)
            }.value
            // No suspension between identity/local-edit checks and persistence:
            // another account or a newer local row must never adopt this reply.
            guard !Task.isCancelled, accountId() == owner, let points,
                  repository.applyMissingManualTrack(points, expected: snapshot) else { return nil }
            await afterLoad(id)
            guard !Task.isCancelled, accountId() == owner else { return nil }
            return repository.fetchTripDetail(id: id)
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
}
