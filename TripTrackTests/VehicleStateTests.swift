import XCTest
import CoreData
@testable import TripTrack

/// Состояние машины и то, на что можно писать.
///
/// До 0.6.4 приложение спорило само с собой: гараж рисовал раздел «Архив» и
/// обещал, что новые поездки идут на активную машину, а флаг `isArchived` при
/// этом не использовался НИГДЕ — шторка на экране записи предлагала все машины
/// подряд, включая проданные. Здесь заперто ровно одно правило, из которого
/// растут все экраны: **можно писать только на неархивную и непроданную**.
///
/// Отдельно заперта старая ошибка с сохранением: выбор машины читается при
/// старте записи из СОХРАНЁННОЙ `UserSettingsEntity`, поэтому присваивание
/// `selectedVehicleId` без записи на диск ничего не меняет для поездки —
/// именно так следующая после продажи поездка уезжала на проданную машину.
final class VehicleStateTests: XCTestCase {

    private var pc: PersistenceController!
    private var settings: SettingsManager!
    /// Привязки магнитол лежат не в CoreData, а в глобальном `UserDefaults`, и
    /// поэтому переживают и подмену хранилища, и весь прогон целиком. Первая
    /// версия этих тестов на этом и споткнулась: во второй запуск `add` тихо
    /// ничего не делал, потому что uuid уже лежал с прошлого раза. Сохраняем и
    /// возвращаем — иначе тест мусорит в состоянии соседей.
    private var savedDevicesBackup: Data?
    private static let devicesKey = "savedBluetoothDevices"

    override func setUp() {
        super.setUp()
        savedDevicesBackup = UserDefaults.standard.data(forKey: Self.devicesKey)
        UserDefaults.standard.removeObject(forKey: Self.devicesKey)
        pc = PersistenceController(inMemory: true)
        settings = SettingsManager(persistenceController: pc)
    }

    override func tearDown() {
        settings = nil
        pc = nil
        if let savedDevicesBackup {
            UserDefaults.standard.set(savedDevicesBackup, forKey: Self.devicesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.devicesKey)
        }
        savedDevicesBackup = nil
        super.tearDown()
    }

    /// То, что реально прочитает старт записи, — а не то, что лежит в памяти.
    private func persistedSelection() -> UUID? {
        let request: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        request.fetchLimit = 1
        return (try? pc.container.viewContext.fetch(request).first)??.selectedVehicleId
    }

    /// Пишет продажу прямо в запись машины, минуя `SettingsManager`, — так это
    /// делает приходящий синк, и именно поэтому выбор остаётся стоять.
    private func sellBehindTheAppsBack(_ id: UUID) {
        mutateEntity(id) { $0.soldAt = Date() }
    }

    /// То же, но БЕЗ перечитывания списка: хранилище уже знает о продаже, а
    /// снимок в памяти — ещё нет.
    private func sellWithoutReload(_ id: UUID) {
        mutateEntity(id, reload: false) { $0.soldAt = Date() }
    }

    private func mutateEntity(_ id: UUID, reload: Bool = true,
                              _ change: (VehicleEntity) -> Void) {
        let context = pc.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let entity = try? context.fetch(request).first else {
            return XCTFail("машина не найдена в хранилище")
        }
        change(entity)
        try? context.save()
        if reload { settings.reloadVehiclesForTesting() }
    }

    @discardableResult
    private func addCar(_ name: String) -> UUID {
        settings.addVehicle(name: name, emoji: "🚗")
    }

    // MARK: - Что вообще доступно для записи

    /// Архив убран в 0.6.4: он был подготовкой к монетизации, а не пользой.
    /// Единственное состояние, которое запрещает запись, — продажа.
    func testOnlySaleStopsAVehicleFromRecording() {
        let a = addCar("Первая")
        let b = addCar("Вторая")

        XCTAssertEqual(settings.recordableVehicles.count, 2,
                       "обе машины рабочие — разбирать гараж руками человек не обязан")

        settings.setVehicleSold(id: b, soldAt: Date())

        let ids = settings.recordableVehicles.map(\.id)
        XCTAssertTrue(ids.contains(a))
        XCTAssertFalse(ids.contains(b))
    }

    func testSoldVehicleIsNotRecordable() {
        let sold = addCar("Проданная")
        settings.setVehicleSold(id: sold, soldAt: Date())

        XCTAssertFalse(settings.recordableVehicles.contains { $0.id == sold })
    }

    // MARK: - Активный слот не остаётся у того, кто выбыл

    func testSellingTheActiveVehiclePersistsTheNewSelection() {
        let a = addCar("Первая")
        let b = addCar("Вторая")
        settings.selectVehicle(id: a)

        settings.setVehicleSold(id: a, soldAt: Date())

        XCTAssertEqual(persistedSelection(), b,
                       "следующая после продажи поездка уезжала ровно на проданную машину")
    }

    func testDeletingTheActiveVehicleClearsThePersistedSelection() {
        let a = addCar("Первая")
        settings.selectVehicle(id: a)

        settings.deleteVehicle(id: a)

        XCTAssertNotEqual(persistedSelection(), a,
                          "выбранной осталась удалённая машина — поездка уйдёт в никуда")
    }

    // MARK: - Синхронизация с другого устройства

    /// Пустой выбор — это «Без транспорта», решение человека. Подменять его
    /// первой попавшейся машиной нельзя: иначе нажатие отменяется само.
    func testAnEmptySelectionIsNotQuietlyReplacedBySomeCar() {
        addCar("Первая")
        settings.selectVehicle(id: nil)

        XCTAssertNil(settings.activeRecordableVehicleId)
    }

    /// Проданная машина, до которой не доехал флаг архива, не попадала НИ В
    /// ОДИН раздел гаража и пропадала из приложения вместе с дверью, за
    /// которой её можно вернуть.
    func testASoldVehicleWithoutTheArchiveFlagIsStillReachable() {
        let a = addCar("Первая")
        let sold = addCar("Проданная")
        settings.selectVehicle(id: a)
        sellBehindTheAppsBack(sold)

        XCTAssertFalse(settings.recordableVehicles.contains { $0.id == sold })
        // Тот же разбор на разделы, что делает гараж.
        let recordable = Set(settings.recordableVehicles.map(\.id))
        let archive = settings.vehicles.filter { !recordable.contains($0.id) }
        XCTAssertTrue(archive.contains { $0.id == sold },
                      "машина исчезла бы из гаража насовсем")
    }

    /// Полный список обязан остаться полным: через него четыре экрана
    /// достают машину СТАРОЙ поездки.
    func testTheFullListStillHoldsSoldVehiclesForHistory() {
        let b = addCar("Проданная")
        settings.setVehicleSold(id: b, soldAt: Date())

        XCTAssertTrue(settings.vehicles.contains { $0.id == b })
        XCTAssertNotNil(settings.vehicle(for: b), "старая поездка обязана найти свою машину")
    }

    /// Машина, убранная в архив ДО отмены механики, обязана вернуться в строй.
    /// Иначе она тихо исчезает из выбора: механики нет, а флаг остался.
    func testAVehicleArchivedBeforeTheChangeComesBack() throws {
        let key = "com.triptrack.settings.archiveRemovedV1"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let context = pc.container.viewContext
        let stuck = VehicleEntity(context: context)
        stuck.id = UUID()
        stuck.name = "Из архива"
        stuck.isArchived = true
        try context.save()

        let fresh = SettingsManager(persistenceController: pc)

        XCTAssertTrue(fresh.recordableVehicles.contains { $0.id == stuck.id },
                      "машина осталась бы вне выбора навсегда")
    }

    // MARK: - Обходные пути

    func testDeletingAVehicleTakesItsStereoBindingWithIt() {
        let a = addCar("Первая")
        settings.addBluetoothDevice(
            SavedBluetoothDevice(uuid: "u-2", name: "Ford Stereo", vehicleId: a))

        settings.deleteVehicle(id: a)

        XCTAssertNil(settings.vehicleId(forDeviceName: "Ford Stereo"))
    }

    // MARK: - Ничего не архивируется само

    /// Те же стратегии дат, что у боевого клиента: иначе тест проверял бы
    /// сериализацию, которой в приложении не существует.
    private func encode(_ p: VehicleSyncPayload) throws -> [String: Any] {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .custom { date, e in
            var c = e.singleValueContainer()
            try c.encode(ISODate.format(date))
        }
        return try JSONSerialization.jsonObject(with: enc.encode(p)) as! [String: Any]
    }

    private func payload(soldAt: Date?) -> VehicleSyncPayload {
        VehicleSyncPayload(
            id: UUID(), name: "Polo", avatarEmoji: "🚗", odometerKm: 0, level: 1,
            stickersJson: nil, cityConsumption: 0, highwayConsumption: 0,
            fuelPrice: 0, conflictVersion: 0, lastModifiedAt: Date(), soldAt: soldAt)
    }

    private func decode(_ json: String) throws -> VehicleSyncPayload {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = ISODate.parse(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: s))
            }
            return date
        }
        return try dec.decode(VehicleSyncPayload.self, from: Data(json.utf8))
    }

    func testUnsellingSendsAnExplicitNullNotSilence() throws {
        let json = try encode(payload(soldAt: nil))
        XCTAssertTrue(json.keys.contains("soldAt"),
                      "ключа нет — сервер оставит старую дату продажи")
        XCTAssertTrue(json["soldAt"] is NSNull, "должен приехать явный null")
    }

    func testSellingStillSendsTheDate() throws {
        let json = try encode(payload(soldAt: Date()))
        XCTAssertFalse(json["soldAt"] is NSNull)
    }

    /// Молчание сервера ≠ «продажа отменена».
    func testAServerThatOmitsTheKeyDoesNotUnsellLocally() throws {
        let p = try decode(#"{"id":"\#(UUID().uuidString)","name":"Polo","avatarEmoji":"🚗","odometerKm":0,"level":1,"cityConsumption":0,"highwayConsumption":0,"fuelPrice":0,"conflictVersion":0,"lastModifiedAt":"2026-09-04T10:00:00.000Z"}"#)
        XCTAssertFalse(p.soldAtKnown, "ключа не было — трогать локальную продажу нельзя")
    }

    func testAnExplicitNullFromTheServerIsKnownAndClears() throws {
        let p = try decode(#"{"id":"\#(UUID().uuidString)","name":"Polo","avatarEmoji":"🚗","odometerKm":0,"level":1,"cityConsumption":0,"highwayConsumption":0,"fuelPrice":0,"conflictVersion":0,"lastModifiedAt":"2026-09-04T10:00:00.000Z","soldAt":null}"#)
        XCTAssertTrue(p.soldAtKnown)
        XCTAssertNil(p.soldAt)
    }
}

/// Разовый вопрос о видимости фотографий.
final class VehiclePhotoVisibilityAskTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "photo-ask-\(UUID().uuidString)")
    }

    func testAVehicleIsAskedOnlyOnce() {
        let id = UUID()
        XCTAssertFalse(VehiclePhotoVisibilityAsk.wasAsked(id, defaults))
        VehiclePhotoVisibilityAsk.markAsked(id, defaults)
        XCTAssertTrue(VehiclePhotoVisibilityAsk.wasAsked(id, defaults))
    }

    /// Решение принимается ПРО МАШИНУ: у одной снимки безобидные, у другой во
    /// дворе номер и подъезд.
    func testEachVehicleIsAskedSeparately() {
        let a = UUID(), b = UUID()
        VehiclePhotoVisibilityAsk.markAsked(a, defaults)
        XCTAssertTrue(VehiclePhotoVisibilityAsk.wasAsked(a, defaults))
        XCTAssertFalse(VehiclePhotoVisibilityAsk.wasAsked(b, defaults))
    }

    /// Машину удалили — вопрос забывается, иначе машина с тем же
    /// идентификатором (восстановление, синк) не спросит ничего.
    func testDeletingAVehicleForgetsTheQuestion() {
        let id = UUID()
        VehiclePhotoVisibilityAsk.markAsked(id, defaults)
        VehiclePhotoVisibilityAsk.forget(id, defaults)
        XCTAssertFalse(VehiclePhotoVisibilityAsk.wasAsked(id, defaults))
    }
}

/// Разовое выключение карты у машин, заведённых до 0.6.4.
///
/// Обещание дано в журнале изменений, во всех двенадцати текстах магазина и в
/// заметках ревьюеру. Выполнял его только бэкенд, и то вхолостую: сырой UPDATE
/// не трогает `updated_at`, инкрементный пул это вниз не отдаёт, а следующий
/// апсерт возвращает локальное `true` обратно.
final class VehicleMapOptInMigrationTests: XCTestCase {

    private let key = "com.triptrack.settings.vehicleMapOptInV1"

    func testExistingVehiclesLoseTheirRouteMapOnce() throws {
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let pc = PersistenceController(inMemory: true)
        // Машина, заведённая ДО обновления: карта включена, как её оставила схема.
        let context = pc.container.viewContext
        let before = VehicleEntity(context: context)
        before.id = UUID()
        before.name = "Старая"
        before.mapVisible = true
        before.syncStatus = SyncStatus.synced.rawValue
        try context.save()

        // Первый запуск после обновления.
        _ = SettingsManager(persistenceController: pc)

        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        let after = try context.fetch(request).first
        XCTAssertEqual(after?.mapVisible, false,
                       "маршруты старой машины опубликовались бы без ведома владельца")
        XCTAssertEqual(after?.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "выключение обязано уехать на сервер, иначе на втором телефоне карта останется")
    }

    /// Второй запуск ничего не трогает: иначе человек, включивший карту
    /// осознанно, терял бы её при каждом старте.
    func testTheMigrationDoesNotRunTwice() throws {
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let pc = PersistenceController(inMemory: true)
        let context = pc.container.viewContext
        let v = VehicleEntity(context: context)
        v.id = UUID()
        v.name = "Машина"
        v.mapVisible = true
        try context.save()

        _ = SettingsManager(persistenceController: pc)
        // Человек включил карту обратно, руками.
        v.mapVisible = true
        try context.save()
        _ = SettingsManager(persistenceController: pc)

        XCTAssertTrue(v.mapVisible, "миграция отработала один раз и больше не вмешивается")
    }
}
