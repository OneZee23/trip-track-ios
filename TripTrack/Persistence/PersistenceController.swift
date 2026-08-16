import CoreData
import OSLog

private let persistenceLog = Logger(subsystem: "com.triptrack", category: "persistence")

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    /// Where the store was asked to live. Kept so `setAsideStoreAndStartFresh`
    /// can find the files after the coordinator has let go of them.
    private let requestedStoreURL: URL?

    /// True when the real SQLite store is attached.
    ///
    /// Derived, never stored: a flag would be one more thing that can disagree
    /// with reality, and this type is a struct behind a `static let`, so it
    /// could not be flipped after `init` anyway. `false` means the app is
    /// running on the ephemeral fallback and must not pretend otherwise.
    var isStoreOpen: Bool {
        container.persistentStoreCoordinator.persistentStores
            .contains { $0.type == NSSQLiteStoreType }
    }

    /// The identity of the attached store, as Core Data minted it when it
    /// created the file.
    ///
    /// We never write this — that is the entire point. A recreated store always
    /// reports a different one, so nothing outside the file can forge it, and
    /// the sync cursor can refuse to answer for a database it does not
    /// describe (see `LastSyncedAtStore`).
    ///
    /// Known caveat: `NSStoreUUIDKey` is not guaranteed stable across a
    /// lightweight migration, and this repo bumps the model most releases. A
    /// changed identity costs one extra full pull, which `applyRemoteSettings`
    /// makes harmless — that is the trade, taken deliberately. The alternative,
    /// writing our own key via `setMetadata(_:for:)`, only lands on the next
    /// save, so a store that opens and never saves would carry no stamp at all.
    var storeIdentity: String? {
        let coordinator = container.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first(where: { $0.type == NSSQLiteStoreType })
        else { return nil }
        return coordinator.metadata(for: store)[NSStoreUUIDKey] as? String
    }

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

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        requestedStoreURL = storeURL
        container = NSPersistentContainer(name: "TripTrack")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            container.persistentStoreDescriptions.first?.url = storeURL
        }

        // Enable lightweight migration for schema changes
        if let description = container.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            // Encrypt the SQLite store at rest. Default class on iOS apps
            // without entitlements is `Default` which translates to
            // `CompleteUntilFirstUserAuthentication` — meaning the store is
            // readable from the moment the user enters their passcode after
            // boot. With trips containing GPS tracks + region history this
            // would let a stolen-unlocked-device attacker read everything
            // via filesystem extraction. `complete` keeps the store
            // encrypted whenever the device is locked.
            // Note: CoreData internally re-opens the store on background
            // tasks; `completeUntilFirstUserAuthentication` is the strictest
            // class that doesn't break those access patterns. `complete`
            // would suspend background CoreData on lock, breaking auto-trip
            // and Live Activity recording. CUFUA is the right balance.
            #if os(iOS) && !targetEnvironment(simulator)
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
            #endif
        }

        loadStore()
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Loads the store. On failure it changes NOTHING on disk.
    ///
    /// The version this replaced quarantined on ANY error: it renamed the
    /// database, deleted its `-wal`/`-shm`, and opened an empty store in their
    /// place — silently, because the only log line was behind `#if DEBUG`. A
    /// device that had simply not been unlocked since boot (the store is
    /// `completeUntilFirstUserAuthentication`, see below) was therefore
    /// indistinguishable from a corrupt one, and a recoverable failure became
    /// permanent loss. That is how a real user's 107 trips disappeared from a
    /// phone while every one of them sat intact on the server.
    @discardableResult
    private func loadStore() -> Bool {
        var loaded = false
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                persistenceLog.fault("""
                    store load FAILED url=\(description.url?.lastPathComponent ?? "—", privacy: .public) \
                    domain=\(error.domain, privacy: .public) code=\(error.code) — files left untouched
                    """)
            } else {
                loaded = true
            }
        }
        if !loaded { attachEphemeralFallback() }
        return loaded
    }

    /// A coordinator with zero stores does not fail softly. `context.save()`
    /// raises the Objective-C `NSInternalInconsistencyException` ("This
    /// NSPersistentStoreCoordinator has no persistent stores"), which Swift's
    /// `try?` and `do`/`catch` cannot catch — the app would crash inside
    /// `TripTrackApp.init`, before the recovery screen could draw a pixel.
    ///
    /// An in-memory store keeps every existing call site honest. Nothing
    /// written to it is persisted, and `isStoreOpen` stays false, so the gate
    /// in `TripTrackApp` keeps the user out of it.
    private func attachEphemeralFallback() {
        let coordinator = container.persistentStoreCoordinator
        guard coordinator.persistentStores.isEmpty else { return }
        do {
            try coordinator.addPersistentStore(
                ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
            persistenceLog.notice("attached ephemeral in-memory store — nothing will be persisted")
        } catch {
            persistenceLog.fault("ephemeral fallback failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Retries the SAME container rather than building a new one.
    /// `viewContext` is bound to the coordinator, not to the store, so a store
    /// that attaches on the third try revives every context that already
    /// exists — no singleton has to be torn down and no object graph rebuilt.
    @discardableResult
    func retryLoadingStore() -> Bool {
        guard !isStoreOpen else { return true }
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores where store.type == NSInMemoryStoreType {
            try? coordinator.remove(store)
        }
        return loadStore()
    }

    /// The user's explicit choice to walk away from data the app could not
    /// read. Moves the database AND its journal aside under one shared
    /// timestamp — a `.sqlite` whose `-wal` was deleted is missing its most
    /// recent transactions, which is what made the old "backup for manual
    /// recovery" a comforting sentence rather than a fact — then opens a fresh
    /// store.
    func setAsideStoreAndStartFresh() {
        let url = requestedStoreURL ?? container.persistentStoreDescriptions.first?.url
        guard let url, url.path != "/dev/null" else { return }

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }

        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        let setAside = url.deletingLastPathComponent()
            .appendingPathComponent("TripTrack_corrupted_\(stamp).sqlite")
        try? fm.moveItem(at: url, to: setAside)
        // SQLite journal files use -wal/-shm suffixes, not .wal/.shm.
        for suffix in ["-wal", "-shm"] {
            let from = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.moveItem(at: from, to: URL(fileURLWithPath: setAside.path + suffix))
        }
        persistenceLog.fault("""
            store set aside as \(setAside.lastPathComponent, privacy: .public) at the user's request; \
            starting fresh
            """)
        loadStore()
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Was a `#if DEBUG print`. A Release build that says nothing about
            // a failed write is exactly why the incident was undiagnosable
            // from the user's exported log.
            persistenceLog.error("save failed: \(error.localizedDescription, privacy: .public)")
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
                persistenceLog.error("async save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - One-time Migrations

    /// Stamp `userId` on all existing Trip and Vehicle entities that don't have one yet.
    /// Called once from SettingsManager after localUserId is resolved.
    func migrateUserIdIfNeeded(userId: UUID) {
        let context = container.viewContext
        let key = "didMigrateUserId"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let tripRequest: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        tripRequest.predicate = NSPredicate(format: "userId == nil")
        if let trips = try? context.fetch(tripRequest) {
            for trip in trips { trip.userId = userId }
        }

        let vehicleRequest: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        vehicleRequest.predicate = NSPredicate(format: "userId == nil")
        if let vehicles = try? context.fetch(vehicleRequest) {
            for vehicle in vehicles { vehicle.userId = userId }
        }

        save()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Background Context (for future sync operations)

    /// Create an isolated background context for sync/import operations.
    /// Changes merge into viewContext automatically via `automaticallyMergesChangesFromParent`.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    /// Execute a block on a background context. Saves automatically if changes exist.
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            block(context)
            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                #if DEBUG
                print("⚠️ CoreData background save failed: \(error)")
                #endif
            }
        }
    }
}
