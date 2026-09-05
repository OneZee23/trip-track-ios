import Foundation
import CoreData
import OSLog

private let wipeLog = Logger(subsystem: "com.triptrack", category: "data.wipe")

/// Erases everything this device holds ABOUT the user.
///
/// It exists for one row: «Удалить аккаунт — безвозвратно, везде». Apple's
/// 5.1.1(v) only asks that the account and its server-side data go, but the
/// row says «везде», and a promise on a destructive button has to be literally
/// true — the drives, their points and photos, the cars and the territory all
/// live on this phone too.
///
/// Deliberately NOT touched: the app's own preferences (theme, language,
/// units) and the onboarding flag. Those are settings, not the user's data,
/// and resetting them would drop the person back into a first-launch app that
/// looks broken rather than emptied.
enum LocalDataWipe {
    @MainActor
    static func run() {
        let context = PersistenceController.shared.container.viewContext

        // Order matters only for readability — every relationship here is
        // cascade-deleted from `TripEntity`, and the batch deletes below name
        // the children anyway so nothing survives a partial cascade.
        let entities = [
            "TripPhotoEntity", "TrackPointEntity", "TripEntity",
            // `VehiclePhotoEntity` названа ЯВНО: связи с машиной у неё нет,
            // `vehicleId` — обычный атрибут, поэтому каскад её не заберёт, и
            // после «удалить безвозвратно, везде» снимки машин оставались и
            // строками, и файлами.
            "VehiclePhotoEntity", "VehicleEntity", "VisitedGeohashEntity", "RoadEntity",
            "GeocodeCacheEntity",
        ]
        for name in entities {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            let delete = NSBatchDeleteRequest(fetchRequest: request)
            // Batch deletes bypass the context, so the in-memory objects would
            // stay live and views would keep drawing deleted rows until a
            // relaunch. Asking for the ids back lets us merge the deletion in.
            delete.resultType = .resultTypeObjectIDs
            do {
                let result = try context.execute(delete) as? NSBatchDeleteResult
                if let ids = result?.result as? [NSManagedObjectID], !ids.isEmpty {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                        into: [context]
                    )
                }
            } catch {
                wipeLog.error("batch delete \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            try context.save()
        } catch {
            wipeLog.error("save after wipe failed: \(error.localizedDescription, privacy: .public)")
        }

        // Photo blobs live on disk, not in CoreData — deleting the rows alone
        // would leave every JPEG the user ever attached sitting in Documents.
        let photos = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TripPhotos", isDirectory: true)
        try? FileManager.default.removeItem(at: photos)
        try? FileManager.default.removeItem(at: VehiclePhotoStore.directory)

        wipeLog.notice("[data.wipe] local user data erased")
    }
}
