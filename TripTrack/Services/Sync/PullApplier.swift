import Foundation

@MainActor
final class PullApplier {
    private let repo: TripRepository = CoreDataTripRepository()

    func apply(_ response: SyncPullResponse) {
        for p in response.trips.upserted { repo.applyRemoteTrip(p) }
        for id in response.trips.deleted { repo.deleteTripHard(id: id) }
        for p in response.vehicles.upserted { repo.applyRemoteVehicle(p) }
        for id in response.vehicles.deleted { repo.deleteVehicleHard(id: id) }
        for p in response.photos.upserted { repo.applyRemotePhoto(p) }
        for id in response.photos.deleted { repo.deletePhotoHard(id: id) }
        if let s = response.settings {
            repo.applyRemoteSettings(s)
            SettingsManager.shared.reloadFromCoreData()
        }
    }
}
