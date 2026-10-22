#if DEBUG && targetEnvironment(simulator)
    import CoreData
    import UIKit

    /// Isolated review fixture: only runs on an explicit simulator launch argument.
    enum DebugGarageSeed {
        static let launchArgument = "-seed-garage-demo"
        static let vehicleID = UUID(uuidString: "D37A9000-0000-4000-8000-000000000091")!
        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

        @MainActor static func run() {
            let persistence = PersistenceController.shared
            DebugMapSeed.run(territory: TerritoryManager())
            let context = persistence.container.viewContext
            let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", vehicleID as CVarArg)
            if (try? context.fetch(request).first) == nil {
                let car = VehicleEntity(context: context)
                car.id = vehicleID
                car.name = "Полторашка"
                car.avatarEmoji = "pixel_car_blue"
                car.avatarStyle = "car"
                car.vehicleType = "car"
                car.make = "Volkswagen"
                car.model = "Polo"
                car.bodyType = "car"
                car.year = 2018
                car.createdAt = Date(timeIntervalSince1970: 1_740_787_200)
                car.manualOdometerKm = NSNumber(value: 96400)
                car.paintFinish = "gloss"
                car.cardStyle = ""
                car.drive2URL = "https://www.drive2.ru/r/volkswagen/polo/123456789/"
                car.catalogModelId = "volkswagen-polo"
                car.catalogGenerationId = "volkswagen-polo-sedan-2015"
                car.catalogVariantId = "volkswagen-polo-sedan-2015-16-110-at6"
                car.modTagsJSON = VehicleModTags.encodeJSON(["Шумка", "CarPlay", "Зимняя резина"])
                car.visibleToOthers = true
                car.mapVisible = true
                car.photosVisible = true
                let trips = (try? context.fetch(TripEntity.fetchRequest())) ?? []
                for trip in trips { trip.vehicleId = vehicleID }
                car.odometerKm = trips.reduce(0) { $0 + $1.distance / 1000 }
                car.vehicleLevel = 17
                car.lastModifiedAt = Date()
                car.syncStatus = SyncStatus.synced.rawValue
                // Trip photos are seeded by DebugMapSeed; no main car photo so the platform can be reviewed.
                let photoIDs: [UUID] = []
                car.modsJSON = VehicleMod.encodeJSON([
                    VehicleMod(
                        title: "Шумоизоляция дверей", date: "2026-03-12", odometerKm: 95100,
                        photoIds: Array(photoIDs.prefix(3))),
                    VehicleMod(title: "Зимние шины Nokian Hakkapeliitta R5", date: "2025-11-03", odometerKm: 93400),
                    VehicleMod(
                        title: "Магнитола с CarPlay", date: "2025-08-18", odometerKm: 91200,
                        photoIds: Array(photoIDs.prefix(1))),
                ])
                persistence.save()
                VehiclePhotoStore.invalidateMainCache()
            }
            let settings = SettingsManager.shared
            settings.reloadVehiclesForTesting()
            settings.selectVehicle(id: vehicleID)
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(AppTab.profile.rawValue, forKey: AppTab.storageKey)
        }
    }
#endif
