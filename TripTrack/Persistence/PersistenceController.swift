import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext

        let trip = TripEntity(context: viewContext)
        trip.id = UUID()
        trip.startDate = Date().addingTimeInterval(-3600)
        trip.endDate = Date()
        trip.distance = 45200
        trip.maxSpeed = 33.3
        trip.averageSpeed = 12.6

        for i in 0..<10 {
            let point = TrackPointEntity(context: viewContext)
            point.id = UUID()
            point.latitude = 55.7558 + Double(i) * 0.001
            point.longitude = 37.6173 + Double(i) * 0.001
            point.altitude = 150 + Double(i) * 2
            point.speed = Double.random(in: 5...30)
            point.course = Double(i * 36)
            point.horizontalAccuracy = 5.0
            point.timestamp = Date().addingTimeInterval(-3600 + Double(i) * 360)
            point.trip = trip
        }

        try? viewContext.save()
        return controller
    }()

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "TripTrack")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable lightweight migration for schema changes
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        container.loadPersistentStores { [container] description, error in
            guard let error = error as NSError? else { return }
            #if DEBUG
            print("⚠️ CoreData store load failed: \(error), \(error.userInfo)")
            #endif

            // Quarantine corrupted store (backup for potential manual recovery)
            // then create a fresh store so the app remains functional
            if let storeURL = description.url, storeURL.path != "/dev/null" {
                let fm = FileManager.default
                let backupURL = storeURL.deletingLastPathComponent()
                    .appendingPathComponent("TripTrack_corrupted_\(Int(Date().timeIntervalSince1970)).sqlite")
                try? fm.moveItem(at: storeURL, to: backupURL)

                // SQLite journal files use -wal/-shm suffix (not .wal/.shm)
                let basePath = storeURL.path
                for suffix in ["-wal", "-shm"] {
                    let journalURL = URL(fileURLWithPath: basePath + suffix)
                    if fm.fileExists(atPath: journalURL.path) {
                        try? fm.removeItem(at: journalURL)
                    }
                }

                container.loadPersistentStores { _, retryError in
                    if let retryError {
                        #if DEBUG
                        print("⚠️ CoreData recovery failed: \(retryError)")
                        #endif
                    }
                }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("⚠️ CoreData save failed: \(error)")
            #endif
        }
    }

    /// Schedule an asynchronous save on the view context's queue.
    /// This avoids blocking the current call site (e.g., GPS location callback)
    /// by deferring the save to the next run loop iteration.
    func saveAsync() {
        let context = container.viewContext
        context.perform {
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                #if DEBUG
                print("⚠️ CoreData async save failed: \(error)")
                #endif
            }
        }
    }
}
