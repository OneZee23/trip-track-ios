import XCTest
import CoreData
@testable import TripTrack

/// Провод для электро и гибридов: четыре поля машины и режим поездки.
///
/// Почему это отдельный набор. Прецедент живой и стоил семи версий:
/// `fuelCurrency` клиент кодировал в каждом апсерте машины с 0.6.0, а сервер
/// молча выбрасывал лишний ключ — сборка зелёная, лог пустой, поле не
/// переживает переустановку. Здесь потеря стоит не символа валюты: обнулённый
/// запас хода это ДРУГАЯ раскладка у каждой поездки гибрида — литры вместо
/// киловатт-часов и другие деньги.
///
/// Полный путь через HTTP тут не нужен (его держит
/// `VehicleDashboardUnitsWireTests` для соседних полей того же пейлоада);
/// проверяются те два шва, где поля теряются молча: ручной кодировщик
/// `VehicleSyncPayload` и правила `applyRemote…`.
@MainActor
final class VehicleEnergyWireTests: XCTestCase {

    private var repo: CoreDataTripRepository!
    private var insertedVehicleIds: [UUID] = []
    private var insertedTripIds: [UUID] = []
    /// Своё хранилище ТОЛЬКО ради заготовки `TripEntity` под пейлоад: сам
    /// пейлоад читает из неё точки и снимки, а трогать общую базу ради этого
    /// незачем. Поле обнуляется в `tearDown` — невыпущенный in-memory стор
    /// роняет чужой класс через три буквы алфавита (CLAUDE.md, «Ловушки»).
    private var scratch: PersistenceController!

    override func setUp() async throws {
        try await super.setUp()
        repo = CoreDataTripRepository()
        scratch = PersistenceController(inMemory: true)
    }

    override func tearDown() async throws {
        let ctx = PersistenceController.shared.container.viewContext
        for id in insertedVehicleIds {
            let r: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
            r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for e in (try? ctx.fetch(r)) ?? [] { ctx.delete(e) }
        }
        for id in insertedTripIds {
            let r: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            for e in (try? ctx.fetch(r)) ?? [] { ctx.delete(e) }
        }
        try? ctx.save()
        insertedVehicleIds = []
        insertedTripIds = []
        scratch = nil
        repo = nil
        try await super.tearDown()
    }

    // MARK: - Кодирование машины

    private func hybridPayload(id: UUID = UUID()) -> VehicleSyncPayload {
        VehicleSyncPayload(
            id: id, name: "Astra", avatarEmoji: "🚗", odometerKm: 1000,
            manualOdometerKm: nil, level: 1, stickersJson: nil,
            cityConsumption: 10, highwayConsumption: 6, fuelPrice: 56,
            conflictVersion: 0, lastModifiedAt: Date(),
            powertrain: .pluginHybrid, electricConsumption: 18,
            electricityPrice: 8, electricRangeKm: 50)
    }

    /// Четыре ключа обязаны оказаться в теле. Ручной кодировщик — ровно то
    /// место, где поле теряется без единой ошибки.
    func testEncodedVehicleCarriesAllFourKeys() throws {
        let data = try JSONEncoder().encode(hybridPayload())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["powertrain"] as? String, "pluginHybrid")
        XCTAssertEqual(json["electricConsumption"] as? Double, 18)
        XCTAssertEqual(json["electricityPrice"] as? Double, 8)
        XCTAssertEqual(json["electricRangeKm"] as? Double, 50)
    }

    /// Машина на топливе не шлёт того, чего у неё нет: ключи опциональны, и
    /// `nil` означает «не трогай локальное» на той стороне.
    func testFuelVehicleOmitsTheEnergyKeys() throws {
        let p = VehicleSyncPayload(
            id: UUID(), name: "Corolla", avatarEmoji: "🚗", odometerKm: 0,
            manualOdometerKm: nil, level: 1, stickersJson: nil,
            cityConsumption: 10, highwayConsumption: 6, fuelPrice: 56,
            conflictVersion: 0, lastModifiedAt: Date())
        let data = try JSONEncoder().encode(p)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["powertrain"])
        XCTAssertNil(json["electricRangeKm"])
    }

    // MARK: - Разбор машины

    /// Старый сервер колонок не знает и ключей не шлёт. Это «не сказано», а не
    /// «сбросить в ноль».
    func testDecodingWithoutTheKeysMeansNoOpinion() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Старая","avatarEmoji":"🚗",
         "odometerKm":0,"level":1,"cityConsumption":10,"highwayConsumption":6,
         "fuelPrice":56,"conflictVersion":0,"lastModifiedAt":"2026-09-29T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let p = try decoder.decode(VehicleSyncPayload.self, from: Data(json.utf8))

        XCTAssertNil(p.powertrain)
        XCTAssertNil(p.electricConsumption)
        XCTAssertNil(p.electricityPrice)
        XCTAssertNil(p.electricRangeKm)
    }

    /// Незнакомый тип с будущего клиента не роняет машину целиком — он
    /// читается как «мнения нет». То же правило, что у `dashboardUnits`.
    func testUnknownPowertrainDoesNotBreakTheVehicle() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Водородная","avatarEmoji":"🚗",
         "odometerKm":0,"level":1,"cityConsumption":10,"highwayConsumption":6,
         "fuelPrice":56,"conflictVersion":0,"lastModifiedAt":"2026-09-29T10:00:00Z",
         "powertrain":"hydrogen","electricRangeKm":50}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let p = try decoder.decode(VehicleSyncPayload.self, from: Data(json.utf8))

        XCTAssertNil(p.powertrain, "незнакомый тип должен читаться как «не сказано»")
        XCTAssertEqual(p.electricRangeKm, 50, "соседнее поле потерялось вместе с типом")
    }

    // MARK: - Пул поверх машины

    private func insertVehicle(id: UUID, pendingUpload: Bool) {
        let ctx = PersistenceController.shared.container.viewContext
        let e = VehicleEntity(context: ctx)
        e.id = id
        e.name = "Стенд"
        e.powertrain = Powertrain.pluginHybrid.rawValue
        e.electricConsumption = 18
        e.electricityPrice = 8
        e.electricRangeKm = 50
        e.cityConsumption = 9.1
        e.highwayConsumption = 5.4
        e.fuelPrice = 61
        e.syncStatus = (pendingUpload ? SyncStatus.pendingUpload : SyncStatus.synced).rawValue
        try? ctx.save()
        insertedVehicleIds.append(id)
    }

    private func vehicleEntity(_ id: UUID) -> VehicleEntity? {
        let ctx = PersistenceController.shared.container.viewContext
        let r: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? ctx.fetch(r).first
    }

    /// Молчащий сервер локальное не трогает.
    func testPullWithoutKeysKeepsLocalEnergy() {
        let id = UUID()
        insertVehicle(id: id, pendingUpload: false)
        let p = VehicleSyncPayload(
            id: id, name: "Стенд", avatarEmoji: "🚗", odometerKm: 0,
            manualOdometerKm: nil, level: 1, stickersJson: nil,
            cityConsumption: 10, highwayConsumption: 6, fuelPrice: 56,
            conflictVersion: 0, lastModifiedAt: Date())
        repo.applyRemoteVehicle(p)

        let e = vehicleEntity(id)
        XCTAssertEqual(e?.powertrain, "pluginHybrid")
        XCTAssertEqual(e?.electricRangeKm, 50)
    }

    /// Не уехавшая локальная правка сильнее входящего пула — то же правило,
    /// что у единицы приборки, и по той же причине: вернувшийся запас хода
    /// это НЕВЕРНОЕ ЧИСЛО в раскладке, а не досада.
    func testLocalEditBeatsThePull() {
        let id = UUID()
        insertVehicle(id: id, pendingUpload: true)
        let p = VehicleSyncPayload(
            id: id, name: "Стенд", avatarEmoji: "🚗", odometerKm: 0,
            manualOdometerKm: nil, level: 1, stickersJson: nil,
            cityConsumption: 10, highwayConsumption: 6, fuelPrice: 56,
            conflictVersion: 0, lastModifiedAt: Date(),
            powertrain: .fuel, electricConsumption: 0,
            electricityPrice: 0, electricRangeKm: 0)
        repo.applyRemoteVehicle(p)

        let e = vehicleEntity(id)
        XCTAssertEqual(e?.powertrain, "pluginHybrid", "пул отменил локальную правку типа")
        XCTAssertEqual(e?.electricRangeKm, 50, "пул обнулил локальный запас хода")
    }

    /// А синхронизированную машину сервер вправе поправить.
    func testPullUpdatesASyncedVehicle() {
        let id = UUID()
        insertVehicle(id: id, pendingUpload: false)
        let p = VehicleSyncPayload(
            id: id, name: "Стенд", avatarEmoji: "🚗", odometerKm: 0,
            manualOdometerKm: nil, level: 1, stickersJson: nil,
            cityConsumption: 10, highwayConsumption: 6, fuelPrice: 56,
            conflictVersion: 0, lastModifiedAt: Date(),
            powertrain: .electric, electricConsumption: 20,
            electricityPrice: 9, electricRangeKm: 0)
        repo.applyRemoteVehicle(p)

        let e = vehicleEntity(id)
        XCTAssertEqual(e?.powertrain, "electric")
        XCTAssertEqual(e?.electricConsumption, 20)
    }

    /// Расход и цена ТОПЛИВА — под тем же гейтом, что электрические числа.
    ///
    /// До 0.8.3 гейта здесь не было вовсе, а писатель (`updateVehicleFuel`) не
    /// взводил `pendingUpload` — то есть набранный расход мог вернуться к
    /// серверному до того, как уедет. Полный пул 0.6.1 заказывается на каждом
    /// устройстве с несовпавшим штампом хранилища, так что окно не редкое.
    func testLocalFuelEditBeatsThePull() {
        let id = UUID()
        insertVehicle(id: id, pendingUpload: true)
        let p = VehicleSyncPayload(
            id: id, name: "Стенд", avatarEmoji: "🚗", odometerKm: 0,
            manualOdometerKm: nil, level: 1, stickersJson: nil,
            cityConsumption: 10, highwayConsumption: 6, fuelPrice: 56,
            conflictVersion: 0, lastModifiedAt: Date())
        repo.applyRemoteVehicle(p)

        let e = vehicleEntity(id)
        XCTAssertEqual(e?.cityConsumption, 9.1, "пул вернул серверный расход поверх набранного")
        XCTAssertEqual(e?.fuelPrice, 61, "пул вернул серверную цену поверх набранной")
    }

    /// А синхронизированной машине сервер по-прежнему хозяин.
    func testPullUpdatesFuelOfASyncedVehicle() {
        let id = UUID()
        insertVehicle(id: id, pendingUpload: false)
        let p = VehicleSyncPayload(
            id: id, name: "Стенд", avatarEmoji: "🚗", odometerKm: 0,
            manualOdometerKm: nil, level: 1, stickersJson: nil,
            cityConsumption: 10, highwayConsumption: 6, fuelPrice: 56,
            conflictVersion: 0, lastModifiedAt: Date())
        repo.applyRemoteVehicle(p)

        let e = vehicleEntity(id)
        XCTAssertEqual(e?.cityConsumption, 10)
        XCTAssertEqual(e?.fuelPrice, 56)
    }

    // MARK: - Режим поездки

    /// «Авто» уезжает СТРОКОЙ, а не отсутствием ключа. Иначе возврат с
    /// «Электро» обратно на «Авто» не доедет до второго телефона никогда:
    /// молчание там читается как «не трогай».
    private func scratchEntity() -> TripEntity {
        TripEntity(context: scratch.container.viewContext)
    }

    func testAutoTravelsAsAnExplicitString() throws {
        var trip = Trip(distance: 1000, energyMode: .auto)
        let auto = TripSyncPayload(trip: trip, entity: scratchEntity(), zone: nil)
        XCTAssertEqual(auto.energyMode, "auto")

        trip = Trip(distance: 1000, energyMode: .electric)
        let electric = TripSyncPayload(trip: trip, entity: scratchEntity(), zone: nil)
        XCTAssertEqual(electric.energyMode, "electric")
    }

    func testEncodedTripCarriesTheMode() throws {
        let payload = TripSyncPayload(trip: Trip(distance: 1000, energyMode: .fuel),
                                      entity: scratchEntity(), zone: nil)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try encoder.encode(payload)) as? [String: Any])
        XCTAssertEqual(json["energyMode"] as? String, "fuel")
    }

    /// Незнакомый режим — «мнения нет»: локальный выбор остаётся. Прочитай мы
    /// его как «Авто», будущий клиент молча затирал бы человеку раскладку.
    func testUnknownModeLeavesTheLocalChoiceAlone() {
        let id = UUID()
        let ctx = PersistenceController.shared.container.viewContext
        let e = TripEntity(context: ctx)
        e.id = id
        e.startDate = Date()
        e.endDate = Date()
        e.energyMode = TripEnergyMode.electric.rawValue
        e.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
        insertedTripIds.append(id)

        var p = TripSyncPayload(trip: Trip(id: id, distance: 1000), entity: scratchEntity(), zone: nil)
        p.energyMode = "regenerative"
        repo.applyRemoteTrip(p)

        let r: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        XCTAssertEqual((try? ctx.fetch(r).first)?.energyMode, "electric",
                       "незнакомый режим затёр локальный выбор")
    }

    /// А знакомое «Авто» с другого телефона обязано стереть выбор здесь.
    func testAutoFromTheServerClearsTheChoice() {
        let id = UUID()
        let ctx = PersistenceController.shared.container.viewContext
        let e = TripEntity(context: ctx)
        e.id = id
        e.startDate = Date()
        e.endDate = Date()
        e.energyMode = TripEnergyMode.electric.rawValue
        e.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
        insertedTripIds.append(id)

        var p = TripSyncPayload(trip: Trip(id: id, distance: 1000), entity: scratchEntity(), zone: nil)
        p.energyMode = "auto"
        repo.applyRemoteTrip(p)

        let r: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        XCTAssertNil((try? ctx.fetch(r).first)?.energyMode,
                     "«Авто» со второго телефона не доехало")
    }

    /// «Авто» в колонке лежит как `nil` — у поездки, где выбора не делали,
    /// хранить нечего.
    func testAutoIsStoredAsNil() {
        XCTAssertNil(TripEnergyMode.auto.stored)
        XCTAssertEqual(TripEnergyMode.electric.stored, "electric")
        XCTAssertEqual(TripEnergyMode.fuel.stored, "fuel")
        XCTAssertEqual(TripEnergyMode.parse(nil), .auto)
        XCTAssertEqual(TripEnergyMode.parse("whatever"), .auto)
    }
}
