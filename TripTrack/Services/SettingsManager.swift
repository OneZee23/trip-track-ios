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

    /// Магнитола → машина, НО только та, на которую сейчас можно писать.
    ///
    /// Без этой проверки правило «в архив — значит не пишем» обходилось само,
    /// без единого тапа человека: воткнулся в магнитолу архивной машины — и
    /// она молча снова стала активной, потому что оба вызывающих отсюда пишут
    /// результат прямо в сохранённый выбор. Поездка при этом остаётся на той
    /// машине, что активна сейчас, и переназначить её задним числом можно
    /// бесплатно.
    func vehicleId(forDeviceName name: String) -> UUID? {
        guard let id = savedBluetoothDevices.first(where: { $0.name == name })?.vehicleId,
              recordableVehicles.contains(where: { $0.id == id }) else { return nil }
        return id
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

    /// На что можно писать ПРЯМО СЕЙЧАС — и единственное место, где это
    /// решается.
    ///
    /// `vehicles` намеренно остаётся неотфильтрованным: через него четыре
    /// экрана достают машину СТАРОЙ поездки (`VehicleDetailView`,
    /// `TripDetailView` дважды, сам гараж), и фильтр там стёр бы историю —
    /// поездка двухлетней давности показала бы «Транспорт удалён».
    /// Фильтровать можно только в точке ПРИМЕНЕНИЯ, то есть здесь.
    ///
    /// Сюда же придёт лимит бесплатного тарифа, когда будет что покупать:
    /// одной строкой в этом фильтре, а не проверкой на десяти экранах.
    var recordableVehicles: [Vehicle] {
        vehicles.filter { !$0.isArchived && !$0.isSold }
    }

    /// Машина, на которую уйдёт СЛЕДУЮЩАЯ поездка, — и единственный ответ на
    /// этот вопрос для всех экранов сразу.
    ///
    /// `nil` тут значит «без транспорта», и это законный выбор человека, а не
    /// сбой: подменять пустой выбор первой попавшейся машиной нельзя, иначе
    /// нажатие «Без транспорта» молча отменяется.
    ///
    /// Отдельно ловится случай, которого не бывает по своей воле: выбранная
    /// машина перестала быть доступной НЕ через этот экран. Синхронизация с
    /// другого устройства пишет `isArchived` прямо в запись машины и выбора не
    /// трогает — без этой проверки поездка уехала бы на архивную машину,
    /// причём гараж в этот момент показывал бы её как активную.
    var activeRecordableVehicleId: UUID? {
        guard let id = selectedVehicleId else { return nil }
        return recordableVehicles.contains { $0.id == id } ? id : nil
    }

    /// Пропускает id, только если на эту машину сейчас можно писать.
    ///
    /// Через это горлышко проходит и «Команды»: ярлык, сохранённый месяц назад,
    /// помнит машину, которую с тех пор убрали в архив, и iOS показывает его
    /// до следующего опроса. Такая поездка запишется без транспорта — назначить
    /// машину задним числом можно бесплатно и в любой момент.
    func recordableVehicleId(_ id: UUID?) -> UUID? {
        guard let id else { return nil }
        // Читаем ЗАПИСЬ, а не список в памяти. Список — снимок, он обновляется
        // только когда его кто-то перечитает, и однажды кто-то этого не
        // сделает: ровно так синк уже проносил архивную машину мимо проверки.
        // Это последний рубеж, он обязан спрашивать у хранилища, а не у копии.
        // Цена — один запрос на старт поездки, раз в несколько часов.
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try? context.fetch(request).first,
              !entity.isArchived, entity.soldAt == nil else { return nil }
        return id
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

    /// Перечитать список машин — то же, что делает приходящий синк, дописав
    /// запись машины напрямую. Нужен тестам, которым надо воспроизвести именно
    /// этот путь, а не пройти через методы экрана.
    func reloadVehiclesForTesting() { loadVehicles() }

    private func loadVehicles() {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \VehicleEntity.name, ascending: true)]

        vehicles = (try? context.fetch(request))?.compactMap { vehicleFromEntity($0) } ?? []
        healStuckSelection()
    }

    /// Выбор указывает на машину, которая больше не может принимать поездки, —
    /// чиним молча и отдаём слот другой.
    ///
    /// Пустой выбор не трогаем НИКОГДА: `nil` значит «Без транспорта», это
    /// решение человека, а не поломка.
    ///
    /// Случай не выдуманный: продажа машины раньше меняла выбор только в
    /// памяти и не сохраняла его, поэтому на диске он так и остался стоять на
    /// проданной. Пока запись брала выбор на веру, поездки уезжали на неё;
    /// после того как проверка появилась, человек остался вообще без активной
    /// машины — и без единого намёка, почему. Такие данные уже лежат на
    /// устройствах, и вычистить их можно только здесь.
    private func healStuckSelection() {
        guard let id = selectedVehicleId,
              !recordableVehicles.contains(where: { $0.id == id }) else { return }
        selectVehicle(id: recordableVehicles.first?.id)
    }

    private func migrateDefaultVehicleName() {
        let legacyNames: Set<String> = ["Телега", "Telega"]
        guard let first = vehicles.first, legacyNames.contains(first.name) else { return }

        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", first.id as CVarArg)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else { return }
        let lang = LanguageManager.currentLanguage
        entity.name = AppStrings.defaultVehicleName(lang)
        persistenceController.save()
        loadVehicles()
    }

    /// Returns the new vehicle's id so the caller can select it or follow it
    /// with the fuel figures from the same form submission.
    @discardableResult
    func addVehicle(
        name: String,
        emoji: String,
        avatarStyle: String = VehicleAvatar.defaultStyle,
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
        entity.avatarStyle = avatarStyle
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
            // Привязка магнитолы к удалённой машине пережила бы саму машину и
            // осталась бы указывать в никуда: `vehicleId(forDeviceName:)` по
            // ней ничего не найдёт, а список привязок будет копить мусор.
            removeBluetoothDevice(forVehicle: id)
            // Снимки машины лежат файлами на диске, а строка про них — без
            // связи с машиной, поэтому каскад их не заберёт: без этой строки
            // фотографии удалённой машины оставались в Documents навсегда, и
            // добраться до них было уже нечем.
            VehiclePhotoStore.deleteAll(of: id)
            VehiclePhotoVisibilityAsk.forget(id)
            persistenceController.save()
            loadVehicles()
            // Удалённая не может остаться выбранной — иначе следующая поездка
            // уйдёт на несуществующий id и покажется «Транспорт удалён».
            if selectedVehicleId == id {
                selectVehicle(id: recordableVehicles.first?.id)
            }
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

        var v = Vehicle(
            id: id,
            name: entity.name ?? "",
            avatarEmoji: entity.avatarEmoji ?? "🏎️",
            avatarStyle: entity.avatarStyle ?? VehicleAvatar.defaultStyle,
            type: VehicleType(storage: entity.vehicleType),
            plate: entity.plate ?? "",
            plateVisible: entity.plateVisible,
            visibleToOthers: entity.visibleToOthers,
            odometerKm: entity.odometerKm,
            // NSNumber, а не Double: колонка опциональна, и «не заполнено»
            // должно отличаться от «ноль» (ноль — законный пробег новой машины).
            manualOdometerKm: entity.manualOdometerKm?.doubleValue,
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
        // Поля паспорта присваиваются ОТДЕЛЬНО, а не аргументами инициализатора:
        // с ними одно выражение перестало проверяться по типам за разумное
        // время («unable to type-check this expression in reasonable time»).
        // Разбиение — не стилевая прихоть, а условие сборки.
        v.about = entity.about ?? ""
        v.make = entity.make ?? ""
        v.model = entity.model ?? ""
        v.year = Int(entity.year)
        v.bodyType = entity.bodyType ?? ""
        v.photosVisible = entity.photosVisible
        v.mapVisible = entity.mapVisible
        v.isArchived = entity.isArchived
        v.soldAt = entity.soldAt
        return v
    }

    /// Записать пробег с приборной панели. `nil` стирает значение и возвращает
    /// карточку к треканному числу.
    ///
    /// Уровень машины НЕ пересчитывается: он считается от треканного пробега,
    /// иначе уровни раздавались бы за цифру, набранную на клавиатуре.
    func setManualOdometer(vehicleId: UUID, km: Double?) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", vehicleId as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.manualOdometerKm = km.map { NSNumber(value: max(0, $0)) }
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        persistenceController.save()
        // Как у остальных мутаторов машины: без этого значение уезжало бы
        // только на следующем запуске, через восстановление зависших сущностей.
        Task { @MainActor in
            SyncEnqueuer.enqueue(
                SyncOperation(entityType: .vehicle, entityId: vehicleId, action: .update))
        }
        loadVehicles()
    }

    /// The identity half of the form: everything the person typed or picked
    /// that is not a fuel figure. One write, one sync operation.
    /// Марка, модель, год и кузов — поля паспорта (0.6.4).
    ///
    /// Отдельной функцией, а не аргументами `updateVehicleIdentity`: та уже
    /// принимает семь параметров и отвечает за то, КАК машина выглядит и кому
    /// видна, а это — что она такое. Плюс её вызывают из мест, которым про
    /// каталог знать незачем.
    func updateVehiclePassport(
        id: UUID, make: String, model: String, year: Int, bodyType: String,
        about: String = ""
    ) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.make = make
        entity.model = model
        // 0 — «не указан»: год не бывает нулевым, и опционал протёк бы в каждую
        // подпись. Заведомо неправдоподобные значения не сохраняем — пустое
        // поле честнее, чем «1» в паспорте.
        entity.year = (year >= 1900 && year <= 2100) ? Int32(year) : 0
        entity.bodyType = bodyType
        entity.about = about
        entity.lastModifiedAt = Date()
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        persistenceController.save()
        loadVehicles()
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .upload))
        }
    }

    /// Архив и продажа — РАЗНЫЕ состояния, и намеренно двумя функциями.
    ///
    /// «Не активна» значит «машина твоя, просто новые поездки идут не на неё».
    /// «Продана» значит «владелец сменился, биография заморожена»: записать на
    /// такую машину поездку — приписать чужую дорогу своему паспорту. Поэтому
    /// активной проданную сделать нельзя, пока продажу не отменили.
    func setVehicleSold(id: UUID, soldAt: Date?) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.soldAt = soldAt
        // Проданная всегда в архиве; возврат из проданных архива не снимает —
        // это второй, отдельный шаг, чтобы случайный тап не переписал историю.
        if soldAt != nil { entity.isArchived = true }
        entity.lastModifiedAt = Date()
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        // Активной проданная быть не может: следующая запись ушла бы на чужую
        // машину. Снимаем выбор молча — альтернатива это диалог посреди
        // подтверждения продажи.
        persistenceController.save()
        loadVehicles()
        // ПОСЛЕ loadVehicles и через selectVehicle, а не голым присваиванием:
        // запись читает выбор из СОХРАНЁННОЙ UserSettingsEntity, а голое
        // присваивание меняло только @Published. Из-за этого следующая после
        // продажи поездка уходила ровно на проданную машину — то самое, ради
        // чего эти три строки и были написаны.
        if soldAt != nil, selectedVehicleId == id {
            selectVehicle(id: recordableVehicles.first?.id)
        }
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .upload))
        }
    }

    func setVehicleArchived(id: UUID, archived: Bool) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.isArchived = archived
        entity.lastModifiedAt = Date()
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        persistenceController.save()
        loadVehicles()
        // Убранная в архив не может остаться активной — иначе гараж обещает
        // одно («пишем на активную»), а запись делает другое. Слот уходит
        // другой машине, а в гараже из одной машины — никому: «Без
        // транспорта» это законный исход, а не ошибка.
        if archived, selectedVehicleId == id {
            selectVehicle(id: recordableVehicles.first?.id)
        }
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .upload))
        }
    }

    /// Четыре оси видимости машины (экран 13). Отдельно от
    /// `updateVehicleIdentity`: та про то, как машина ВЫГЛЯДИТ, а это про то,
    /// кому она видна, и меняется с другого экрана и по другому поводу.
    func updateVehicleVisibility(
        id: UUID, visibleToOthers: Bool, plateVisible: Bool,
        mapVisible: Bool, photosVisible: Bool
    ) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.visibleToOthers = visibleToOthers
        entity.plateVisible = plateVisible
        entity.mapVisible = mapVisible
        entity.photosVisible = photosVisible
        entity.lastModifiedAt = Date()
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        persistenceController.save()
        loadVehicles()
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .upload))
        }
    }

    func updateVehicleIdentity(
        id: UUID,
        name: String,
        emoji: String,
        type: VehicleType,
        plate: String,
        plateVisible: Bool,
        visibleToOthers: Bool,
        // No default. A caller that says nothing about the silhouette is not
        // asking for a saloon, but the assignment below cannot tell the
        // difference — and a defaulted argument makes that a silent data loss
        // the compiler is happy with. Required, so forgetting it is an error
        // rather than a vehicle quietly turning back into a car.
        avatarStyle: String
    ) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else { return }
        entity.name = name
        entity.avatarEmoji = emoji
        entity.avatarStyle = avatarStyle
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
