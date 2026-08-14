import Foundation
import CoreData
import Combine

/// How a trip's average speed is reported.
/// - `overall`: distance / total elapsed time (includes stops & pauses).
/// - `moving`: distance / driving time only (the "чистого хода" speed).
enum AvgSpeedMode: String, CaseIterable {
    case overall
    case moving
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var avatarEmoji: String = "😎"
    @Published var themeMode: String = "dark"
    @Published var language: String = "ru"
    @Published var fuelConsumption: Double = 7.8
    @Published var fuelPrice: Double = 56.0
    @Published var selectedVehicleId: UUID?
    @Published var vehicles: [Vehicle] = []

    // User identity (local UUID, persisted in UserSettingsEntity.id)
    @Published private(set) var localUserId: UUID = UUID()

    // Cloud sync toggle. UserDefaults persisted. Default `false` — TripTrack
    // is privacy-first; nothing leaves the device until the user opts in.
    // For existing installs that had it on, `migrateCloudSyncToOptIn()` flips
    // them to false on the upgrade so previously-cached `true` doesn't bypass
    // the new default.
    @Published var cloudSyncEnabled: Bool = UserDefaults.standard.object(forKey: "com.triptrack.settings.cloudSyncEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(cloudSyncEnabled, forKey: "com.triptrack.settings.cloudSyncEnabled") }
    }

    // Profile background identifier (one of ProfileBackground rawValues, "" = default).
    @Published var profileBackground: String = UserDefaults.standard.string(forKey: "com.triptrack.settings.profileBackground") ?? "" {
        didSet { UserDefaults.standard.set(profileBackground, forKey: "com.triptrack.settings.profileBackground") }
    }

    // Badge id pinned to the profile ("" = none) — shown prominently on the «Я» screen.
    @Published var pinnedBadgeId: String = UserDefaults.standard.string(forKey: "com.triptrack.settings.pinnedBadgeId") ?? "" {
        didSet { UserDefaults.standard.set(pinnedBadgeId, forKey: "com.triptrack.settings.pinnedBadgeId") }
    }

    // MARK: - Profile identity («Мой профиль» hub, 0.6.0)
    //
    // All three are LOCAL ONLY. `ProfileUpdateRequest` carries none of them, so
    // nothing here leaves the device — and the public profile other people see
    // is exactly where canon draws the handle, the flag pill and the bio
    // (Figma 962:405). What the backend still owes, in order:
    //   · `username` on the account + an availability endpoint. Until that
    //     exists `UsernameEditorSheet` is handed a check that always answers
    //     "не удалось проверить", and two accounts can claim the same handle.
    //   · `bio` accepted on /auth/profile-update. It is already RETURNED on
    //     `SocialProfile` (read-only), so only the write half is missing.
    //   · `country` on the account, echoed back on `SocialProfile`.
    // Deliberately UserDefaults and not CoreData: the model already gained a
    // version this release, and a second migration in the same commit buys
    // nothing for three short strings.

    // Handle, stored WITHOUT the leading «@» and already lowercased by the
    // editor. "" = not set.
    @Published var profileUsername: String = UserDefaults.standard.string(forKey: "com.triptrack.settings.profileUsername") ?? "" {
        didSet { UserDefaults.standard.set(profileUsername, forKey: "com.triptrack.settings.profileUsername") }
    }

    // «О себе» — free text, ≤140 chars (capped by the editor). "" = not set.
    @Published var profileBio: String = UserDefaults.standard.string(forKey: "com.triptrack.settings.profileBio") ?? "" {
        didSet { UserDefaults.standard.set(profileBio, forKey: "com.triptrack.settings.profileBio") }
    }

    // ISO-3166 alpha-2 ("RU"), or one of `CountryChoice`'s sentinels
    // ("WORLD" / "NEUTRAL"). "" = «Не указывать», which is a real answer and
    // not missing data — see `CountryChoice`.
    @Published var profileCountry: String = UserDefaults.standard.string(forKey: "com.triptrack.settings.profileCountry") ?? "" {
        didSet { UserDefaults.standard.set(profileCountry, forKey: "com.triptrack.settings.profileCountry") }
    }

    // How average speed is reported. Default `.overall` = no change for existing
    // users; `.moving` reports distance / driving time (excludes stops & pauses).
    @Published var avgSpeedMode: AvgSpeedMode =
        AvgSpeedMode(rawValue: UserDefaults.standard.string(forKey: "com.triptrack.settings.avgSpeedMode") ?? "") ?? .overall {
        didSet { UserDefaults.standard.set(avgSpeedMode.rawValue, forKey: "com.triptrack.settings.avgSpeedMode") }
    }

    // Opt-IN to showing the user's PUBLIC trips on the website's public globe
    // (account-level; synced to the server via syncProfileToServer, not the
    // settings entity). Default FALSE — privacy-first, nobody is on the globe
    // until they enable it. Local mirror of the server `account.show_on_public_map`;
    // seeded from the login response and reset on sign-out.
    @Published var showOnPublicMap: Bool =
        UserDefaults.standard.object(forKey: "com.triptrack.settings.showOnPublicMap") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showOnPublicMap, forKey: "com.triptrack.settings.showOnPublicMap") }
    }

    // Gamification
    @Published var profileXP: Int = 0
    @Published var profileLevel: Int = 1
    @Published var currentStreak: Int = 0
    @Published var bestStreak: Int = 0

    // Auto-record
    @Published var autoRecordMode: AutoRecordMode = .off {
        didSet {
            guard !isLoadingAutoRecord else { return }
            UserDefaults.standard.set(autoRecordMode.rawValue, forKey: "autoRecordMode")
        }
    }
    @Published var autoStopTimeout: Int = 3 {
        didSet {
            guard !isLoadingAutoRecord else { return }
            UserDefaults.standard.set(autoStopTimeout, forKey: "autoStopTimeout")
        }
    }
    @Published var savedBluetoothDevices: [SavedBluetoothDevice] = [] {
        didSet {
            guard !isLoadingAutoRecord else { return }
            if let data = try? JSONEncoder().encode(savedBluetoothDevices) {
                UserDefaults.standard.set(data, forKey: "savedBluetoothDevices")
            }
        }
    }

    private var isLoadingAutoRecord = false
    private let persistenceController: PersistenceController
    private var settingsEntity: UserSettingsEntity?
    private var settingsEnqueueDebouncer: Timer?

    func scheduleSettingsSync() {
        settingsEnqueueDebouncer?.invalidate()
        settingsEnqueueDebouncer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                SyncEnqueuer.enqueue(SyncOperation(
                    entityType: .settings, entityId: self.localUserId, action: .upload))
            }
        }
    }

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        migrateCloudSyncToOptIn()
        migrateTripsToPrivateByDefault()
        loadAutoRecordSettings()
        loadSettings()
        persistenceController.migrateUserIdIfNeeded(userId: localUserId)
        loadVehicles()
        // No default vehicle is created. A fresh garage is empty on purpose:
        // the app invented a car nobody had ever driven, gave it a random
        // colour, and left the person to discover it. Trips record fine with
        // no vehicle at all, so there is nothing to stand in for.
        migrateDefaultVehicleName()
    }

    /// Privacy-by-default: trips created before this version were public by
    /// default. Flip every local trip private. Stripping the server copies
    /// (`.unpublish`) requires the user to be signed in — at SettingsManager
    /// init time `AuthService` may not have hydrated yet, so we persist the
    /// IDs and let `AuthService.drainPendingPrivateMigrationUnpublish()`
    /// flush them after sign-in instead of firing a doomed enqueue here.
    private func migrateTripsToPrivateByDefault() {
        let key = "com.triptrack.settings.privateByDefaultMigrationV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let repo: TripRepository = CoreDataTripRepository(persistenceController: persistenceController)
        let serverSideIds = repo.migrateAllTripsToPrivate()
        if !serverSideIds.isEmpty {
            let strings = serverSideIds.map { $0.uuidString }
            UserDefaults.standard.set(strings, forKey: Self.pendingPrivateMigrationUnpublishKey)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Key for the UUIDs (as strings) of trips whose server copies still
    /// need unpublishing as part of the privacy-by-default migration. Drained
    /// by `AuthService` after a successful sign-in.
    static let pendingPrivateMigrationUnpublishKey =
        "com.triptrack.settings.pendingPrivateMigrationUnpublish"

    /// One-shot privacy-default migration. Existing installs may have
    /// `cloudSyncEnabled = true` cached in UserDefaults from before TripTrack
    /// switched to opt-in sync. On first launch after the update we force it
    /// to false so no data leaves the device until the user explicitly turns
    /// sync on. The pending sync queue is preserved — re-enabling sync later
    /// resumes from where we stopped. Server-side data (already-uploaded
    /// trips/photos) is untouched; only new pushes are paused.
    private func migrateCloudSyncToOptIn() {
        let key = "com.triptrack.settings.cloudSyncOptInMigrationV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        cloudSyncEnabled = false
        // Re-show the GDPR-style consent next time the user toggles sync on
        // — the contract changed (now strictly opt-in), so prior consent
        // shouldn't carry over silently.
        UserDefaults.standard.set(false, forKey: "com.triptrack.sync.firstToggleShown")
        // Drain any sync ops queued before the migration so we don't fire
        // them off the moment the user re-enables sync from a stale state.
        // SyncQueue is @MainActor; settings init is also called on the main
        // thread during app launch, so the hop is just for actor isolation.
        Task { @MainActor in SyncQueue.shared.clearAll() }
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Auto-record Settings

    private func loadAutoRecordSettings() {
        isLoadingAutoRecord = true
        defer { isLoadingAutoRecord = false }
        if let raw = UserDefaults.standard.string(forKey: "autoRecordMode"),
           let mode = AutoRecordMode(rawValue: raw) {
            autoRecordMode = mode
        }
        let timeout = UserDefaults.standard.integer(forKey: "autoStopTimeout")
        autoStopTimeout = timeout > 0 ? timeout : 3
        if let data = UserDefaults.standard.data(forKey: "savedBluetoothDevices"),
           let devices = try? JSONDecoder().decode([SavedBluetoothDevice].self, from: data) {
            savedBluetoothDevices = devices
        }
    }

    func isSavedBluetoothDevice(name: String) -> Bool {
        savedBluetoothDevices.contains { $0.name == name }
    }

    func bluetoothDevice(forVehicle vehicleId: UUID) -> SavedBluetoothDevice? {
        savedBluetoothDevices.first { $0.vehicleId == vehicleId }
    }

    func vehicleId(forDeviceName name: String) -> UUID? {
        savedBluetoothDevices.first { $0.name == name }?.vehicleId
    }

    func addBluetoothDevice(_ device: SavedBluetoothDevice) {
        guard !savedBluetoothDevices.contains(where: { $0.uuid == device.uuid }) else { return }
        savedBluetoothDevices.append(device)
    }

    func removeBluetoothDevice(uuid: String) {
        savedBluetoothDevices.removeAll { $0.uuid == uuid }
    }

    func removeBluetoothDevice(forVehicle vehicleId: UUID) {
        savedBluetoothDevices.removeAll { $0.vehicleId == vehicleId }
    }

    // MARK: - Settings

    private func loadSettings() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        request.fetchLimit = 1

        if let entity = try? context.fetch(request).first {
            settingsEntity = entity
            syncFromEntity(entity)
        } else {
            let entity = UserSettingsEntity(context: context)
            entity.id = UUID()
            persistenceController.save()
            settingsEntity = entity
            syncFromEntity(entity)
        }
    }

    private static let vehicleEmojis: Set<String> = ["🏎️", "🚗", "🏍️", "🚙", "🛻", "🚐", "🏁", "⛽"]

    private func syncFromEntity(_ entity: UserSettingsEntity) {
        if let id = entity.id {
            localUserId = id
        }
        let stored = entity.avatarEmoji ?? "😎"
        // Migrate: old vehicle emoji as profile avatar → reset to person emoji
        avatarEmoji = Self.vehicleEmojis.contains(stored) ? "😎" : stored
        themeMode = entity.themeMode ?? "dark"
        language = entity.language ?? "ru"
        fuelConsumption = entity.fuelConsumption
        fuelPrice = entity.fuelPrice
        selectedVehicleId = entity.selectedVehicleId
        // Gamification
        profileXP = Int(entity.profileXP)
        profileLevel = Int(entity.profileLevel)
        currentStreak = Int(entity.currentStreak)
        bestStreak = Int(entity.bestStreak)
    }

    func saveSettings() {
        guard let entity = settingsEntity else { return }
        entity.avatarEmoji = avatarEmoji
        entity.themeMode = themeMode
        entity.language = language
        entity.fuelConsumption = fuelConsumption
        entity.fuelPrice = fuelPrice
        entity.selectedVehicleId = selectedVehicleId
        persistenceController.save()
        scheduleSettingsSync()
    }

    /// Persisting vehicle selection — single source of truth for "which car".
    /// Always use this instead of assigning `selectedVehicleId` directly: a bare
    /// assignment mutates only the in-memory @Published value, but the recording
    /// start path re-reads the vehicle from the *persisted* UserSettingsEntity
    /// (MapViewModel.selectedVehicleId → fetchSettingsEntity). A missing save
    /// there is exactly why Shortcuts/automations and the idle quick-picker
    /// always started with the stale (first) car. Setting + saving here keeps
    /// the two stores in lockstep.
    func selectVehicle(id: UUID?) {
        selectedVehicleId = id
        saveSettings()
    }

    /// Resolve a vehicle by id. Nil in, nil out.
    ///
    /// This used to fall back to `vehicles.first` for any id it could not
    /// match, which made two different facts look identical: "no vehicle was
    /// chosen" and "the chosen one is gone". Recording without transport is a
    /// first-class state now — falling back would put a car the person did not
    /// pick on their Lock Screen.
    func vehicle(for id: UUID?) -> Vehicle? {
        guard let id else { return nil }
        return vehicles.first { $0.id == id }
    }

    // MARK: - Vehicles

    private func loadVehicles() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \VehicleEntity.name, ascending: true)]

        vehicles = (try? context.fetch(request))?.compactMap { vehicleFromEntity($0) } ?? []
    }

    private func migrateDefaultVehicleName() {
        let legacyNames: Set<String> = ["Телега", "Telega"]
        guard let first = vehicles.first, legacyNames.contains(first.name) else { return }

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", first.id as CVarArg)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return }
        let savedLang = UserDefaults.standard.string(forKey: "appLanguage")
        entity.name = savedLang == "ru" ? "Ваша машина" : "Your car"
        persistenceController.save()
        loadVehicles()
    }

    /// Returns the new vehicle's id so the caller can select it or follow it
    /// with the fuel figures from the same form submission.
    @discardableResult
    func addVehicle(
        name: String,
        emoji: String,
        type: VehicleType = .car,
        plate: String = "",
        plateVisible: Bool = false,
        visibleToOthers: Bool = true
    ) -> UUID {
        let context = persistenceController.container.viewContext
        let entity = VehicleEntity(context: context)
        let vehicleId = UUID()
        entity.id = vehicleId
        entity.name = name
        entity.avatarEmoji = emoji
        entity.vehicleType = type.rawValue
        entity.plate = plate
        entity.plateVisible = plateVisible
        entity.visibleToOthers = visibleToOthers
        entity.odometerKm = 0
        entity.vehicleLevel = 1
        entity.createdAt = Date()
        persistenceController.save()
        loadVehicles()
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: vehicleId, action: .upload))
        }
        return vehicleId
    }

    func deleteVehicle(id: UUID) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        if let entity = try? context.fetch(request).first {
            context.delete(entity)
            persistenceController.save()
            loadVehicles()
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .delete))
            }
        }
    }

    private func vehicleFromEntity(_ entity: VehicleEntity) -> Vehicle? {
        guard let id = entity.id else { return nil }

        // Decode stickers from JSON
        var stickers: [VehicleSticker] = []
        if let json = entity.stickersJSON, !json.isEmpty,
           let data = json.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            stickers = ids.compactMap { VehicleSticker(rawValue: $0) }
        }

        return Vehicle(
            id: id,
            name: entity.name ?? "",
            avatarEmoji: entity.avatarEmoji ?? "🏎️",
            type: VehicleType(storage: entity.vehicleType),
            plate: entity.plate ?? "",
            plateVisible: entity.plateVisible,
            visibleToOthers: entity.visibleToOthers,
            odometerKm: entity.odometerKm,
            // Derived, not read. The stored column was written by the old
            // ten-rung curve, so every vehicle that existed before this change
            // carries a number that no longer means anything — and the level
            // is a function of the odometer, so there is nothing to store.
            // The column stays for the sync payload's sake.
            level: VehicleLevelSystem.level(for: entity.odometerKm),
            stickers: stickers,
            createdAt: entity.createdAt ?? Date(),
            cityConsumption: entity.cityConsumption,
            highwayConsumption: entity.highwayConsumption,
            fuelPrice: entity.fuelPrice,
            fuelCurrency: entity.fuelCurrency ?? FuelCurrency.current
        )
    }

    /// The identity half of the form: everything the person typed or picked
    /// that is not a fuel figure. One write, one sync operation.
    func updateVehicleIdentity(
        id: UUID,
        name: String,
        emoji: String,
        type: VehicleType,
        plate: String,
        plateVisible: Bool,
        visibleToOthers: Bool
    ) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.name = name
        entity.avatarEmoji = emoji
        entity.vehicleType = type.rawValue
        // A type that cannot carry a plate keeps none: switching a car to a
        // bicycle must not leave a hidden plate behind in the database.
        entity.plate = type.hasPlate ? plate : ""
        entity.plateVisible = type.hasPlate ? plateVisible : false
        entity.visibleToOthers = visibleToOthers
        persistenceController.save()
        loadVehicles()
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .update))
        }
    }

    func updateVehicleCurrency(id: UUID, symbol: String) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.fuelCurrency = symbol
        persistenceController.save()
        loadVehicles()
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .update))
        }
    }

    func renameVehicle(id: UUID, name: String) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.name = name
            persistenceController.save()
            loadVehicles()
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .update))
            }
        }
    }

    func updateVehicleAvatar(id: UUID, emoji: String) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.avatarEmoji = emoji
            persistenceController.save()
            loadVehicles()
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .update))
            }
        }
    }

    func updateVehicleFuel(id: UUID, city: Double, highway: Double, price: Double) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.cityConsumption = city
            entity.highwayConsumption = highway
            entity.fuelPrice = price
            persistenceController.save()
            loadVehicles()
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .update))
            }
        }
    }

    func reloadFromCoreData() {
        loadSettings()
        loadVehicles()
    }

    func reloadGamificationState() {
        if let entity = settingsEntity {
            profileXP = Int(entity.profileXP)
            profileLevel = Int(entity.profileLevel)
            currentStreak = Int(entity.currentStreak)
            bestStreak = Int(entity.bestStreak)
        }
        loadVehicles()
    }
}
