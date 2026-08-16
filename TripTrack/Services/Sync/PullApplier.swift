import Foundation

@MainActor
final class PullApplier {
    private let repo: TripRepository = CoreDataTripRepository()

    func apply(_ response: SyncPullResponse) {
        for p in response.trips.upserted { repo.applyRemoteTrip(p) }

        // A tombstone for a trip this device never mirrored is not about our
        // copy — see `deleteTripHardIfMirrored`. Remember the ones we kept:
        // their photos need the same protection.
        var keptTripIds = Set<UUID>()
        for id in response.trips.deleted where !repo.deleteTripHardIfMirrored(id: id) {
            keptTripIds.insert(id)
        }

        for p in response.vehicles.upserted { repo.applyRemoteVehicle(p) }
        for id in response.vehicles.deleted { repo.deleteVehicleHard(id: id) }
        for p in response.photos.upserted { repo.applyRemotePhoto(p) }

        // `/trips/delete` cascades `isDeleted` onto every photo row of the
        // trip, so the SAME pull that carries a trip id in `trips.deleted`
        // carries its photo ids here. Deleting them unguarded hands the user
        // back a trip with an empty gallery — and since `deletePhotoHard`
        // removes only the row, the JPEGs stay in Documents with nothing
        // pointing at them.
        for id in response.photos.deleted {
            if let tripId = repo.tripId(forPhoto: id), keptTripIds.contains(tripId) { continue }
            repo.deletePhotoHard(id: id)
        }
        if let s = response.settings {
            repo.applyRemoteSettings(s)
        }
        // One save for the whole batch instead of N saves (one per row).
        // CoreData performance scales linearly with save count, so a
        // pull of 50 trips drops from 50× saveContext() to 1×.
        repo.flushPendingApplies()
        if response.settings != nil {
            SettingsManager.shared.reloadFromCoreData()
        }
    }
}
