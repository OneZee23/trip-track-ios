#if DEBUG && targetEnvironment(simulator)
    import CoreData
    import UIKit

    /// Isolated review fixture: only runs on an explicit simulator launch argument.
    enum DebugGarageSeed {
        static let launchArgument = "-seed-garage-demo"
        static let vehicleID = UUID(uuidString: "D37A9000-0000-4000-8000-000000000091")!
        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
        /// Puts the car back the way the seed made it. Shot tests change it
        /// (tags, DRIVE2 unlinked, finish), and without this a second run of
        /// the same class on a used simulator started from that changed car.
        /// Relaunches inside one test leave it out: they check persistence.
        static let resetArgument = "-seed-garage-reset"
        /// Gives the car a main photo, so the «Я» hero shows the photo filling
        /// the road band. Without the argument the seeded photo is removed:
        /// every other shot reviews the drawn car on its platform.
        static let photoArgument = "-seed-garage-photo"
        /// Marks the seeded photo, so only it is ever removed.
        static let photoMarker = UUID(uuidString: "D37A9000-0000-4000-8000-0000000000F0")!

        @MainActor static func run() {
            let persistence = PersistenceController.shared
            DebugMapSeed.run(territory: TerritoryManager())
            let context = persistence.container.viewContext
            let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", vehicleID as CVarArg)
            if ProcessInfo.processInfo.arguments.contains(resetArgument),
               let stale = try? context.fetch(request).first {
                context.delete(stale)
                persistence.save()
            }
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
            seedPhoto(ProcessInfo.processInfo.arguments.contains(photoArgument))
            let settings = SettingsManager.shared
            settings.reloadVehiclesForTesting()
            settings.selectVehicle(id: vehicleID)
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(AppTab.profile.rawValue, forKey: AppTab.storageKey)
        }

        /// A flat sky over flat asphalt with a pale car: the top of the band
        /// is one known colour, which is what the shot test reads.
        @MainActor private static func seedPhoto(_ wanted: Bool) {
            let seeded = VehiclePhotoStore.photos(of: vehicleID).filter { $0.sourceTripId == photoMarker }
            if !wanted {
                for photo in seeded { VehiclePhotoStore.delete(photo.id, of: vehicleID) }
                return
            }
            guard seeded.isEmpty else { return }
            let size = CGSize(width: 1200, height: 800)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(red: 0x8F / 255, green: 0xB3 / 255, blue: 0xCF / 255, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                UIColor(red: 0x4F / 255, green: 0x55 / 255, blue: 0x5C / 255, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 440, width: 1200, height: 360))
                UIColor(white: 0.92, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 330, y: 380, width: 540, height: 190), cornerRadius: 60).fill()
                UIBezierPath(roundedRect: CGRect(x: 440, y: 300, width: 320, height: 120), cornerRadius: 50).fill()
                UIColor(white: 0.12, alpha: 1).setFill()
                for x in [400.0, 700.0] { UIBezierPath(ovalIn: CGRect(x: x, y: 520, width: 100, height: 100)).fill() }
            }
            VehiclePhotoStore.add(image, to: vehicleID, sourceTripId: photoMarker)
        }
    }
#endif
