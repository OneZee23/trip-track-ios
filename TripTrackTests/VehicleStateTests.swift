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

    /// Пишет флаг прямо в запись машины, минуя `SettingsManager`, — так это
    /// делает приходящий синк, и именно поэтому выбор остаётся стоять.
    private func archiveBehindTheAppsBack(_ id: UUID) {
        mutateEntity(id) { $0.isArchived = true }
    }

    private func sellBehindTheAppsBack(_ id: UUID) {
        mutateEntity(id) { $0.soldAt = Date() }
    }

    /// Как `archiveBehindTheAppsBack`, но БЕЗ перечитывания списка — состояние,
    /// в котором CoreData уже знает про архив, а память ещё нет.
    private func archiveWithoutReload(_ id: UUID) {
        mutateEntity(id, reload: false) { $0.isArchived = true }
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

    func testArchivedVehicleIsNotRecordable() {
        let a = addCar("Активная")
        let b = addCar("Архивная")
        settings.setVehicleArchived(id: b, archived: true)

        let ids = settings.recordableVehicles.map(\.id)
        XCTAssertTrue(ids.contains(a))
        XCTAssertFalse(ids.contains(b), "архивная машина не может принимать новые поездки")
    }

    func testSoldVehicleIsNotRecordable() {
        let sold = addCar("Проданная")
        settings.setVehicleSold(id: sold, soldAt: Date())

        XCTAssertFalse(settings.recordableVehicles.contains { $0.id == sold })
    }

    /// `vehicles` обязан остаться полным: через него достают машину СТАРОЙ
    /// поездки. Фильтр там стёр бы историю — поездка показала бы «Транспорт
    /// удалён» у живой машины.
    func testTheFullListStillHoldsArchivedVehiclesForHistory() {
        let b = addCar("Архивная")
        settings.setVehicleArchived(id: b, archived: true)

        XCTAssertTrue(settings.vehicles.contains { $0.id == b })
        XCTAssertNotNil(settings.vehicle(for: b), "старая поездка обязана найти свою машину")
    }

    // MARK: - Активный слот не остаётся у того, кто выбыл

    func testArchivingTheActiveVehicleHandsTheSlotOverAndPersistsIt() {
        let a = addCar("Первая")
        let b = addCar("Вторая")
        settings.selectVehicle(id: a)

        settings.setVehicleArchived(id: a, archived: true)

        XCTAssertEqual(settings.selectedVehicleId, b)
        XCTAssertEqual(persistedSelection(), b,
                       "запись читает СОХРАНЁННЫЙ выбор — иначе поездка уйдёт на архивную")
    }

    func testSellingTheActiveVehiclePersistsTheNewSelection() {
        let a = addCar("Первая")
        let b = addCar("Вторая")
        settings.selectVehicle(id: a)

        settings.setVehicleSold(id: a, soldAt: Date())

        XCTAssertEqual(persistedSelection(), b,
                       "следующая после продажи поездка уезжала ровно на проданную машину")
    }

    /// Гараж из одной машины: убрали её — писать не на что, и это законный
    /// исход «Без транспорта», а не повод оставить активной архивную.
    func testArchivingTheOnlyVehicleLeavesNoSelection() {
        let only = addCar("Единственная")
        settings.selectVehicle(id: only)

        settings.setVehicleArchived(id: only, archived: true)

        XCTAssertNil(settings.selectedVehicleId)
        XCTAssertNil(persistedSelection())
    }

    func testDeletingTheActiveVehicleClearsThePersistedSelection() {
        let a = addCar("Первая")
        settings.selectVehicle(id: a)

        settings.deleteVehicle(id: a)

        XCTAssertNotEqual(persistedSelection(), a,
                          "выбранной осталась удалённая машина — поездка уйдёт в никуда")
    }

    func testUnarchivingBringsTheVehicleBack() {
        let b = addCar("Вернём")
        settings.setVehicleArchived(id: b, archived: true)
        settings.setVehicleArchived(id: b, archived: false)

        XCTAssertTrue(settings.recordableVehicles.contains { $0.id == b })
    }

    // MARK: - Синхронизация с другого устройства

    /// Архив и продажа с ДРУГОГО устройства приезжают синком прямо в запись
    /// машины и выбора не трогают. Когда список перечитывается, приложение
    /// обязано САМО передать активный слот — иначе человек остаётся без
    /// активной машины и без единого намёка, почему.
    func testASelectionThatSyncArchivedIsHandedOverOnReload() {
        let a = addCar("Первая")
        let b = addCar("Вторая")
        settings.selectVehicle(id: a)

        archiveBehindTheAppsBack(a)   // внутри перечитывает список, как это делает синк

        XCTAssertEqual(settings.selectedVehicleId, b, "слот обязан уйти живой машине")
        XCTAssertEqual(persistedSelection(), b, "и на диск тоже — запись читает именно его")
    }

    /// Единственная машина уехала в архив с другого устройства: активной стать
    /// некому, и это законное «Без транспорта», а не повод оставить архивную.
    func testTheLastVehicleArchivedBySyncLeavesNoSelection() {
        let a = addCar("Единственная")
        settings.selectVehicle(id: a)

        archiveBehindTheAppsBack(a)

        XCTAssertNil(settings.selectedVehicleId)
        XCTAssertNil(persistedSelection())
    }

    /// Последний рубеж: даже если список в памяти НИКТО не перечитал — а
    /// именно так и было, пока синк машин не дёргал перезагрузку, — проверка
    /// перед штампом обязана всё равно отказать. Она спрашивает хранилище.
    func testTheStampGuardRefusesEvenWithAStaleInMemoryList() {
        let a = addCar("Первая")
        settings.selectVehicle(id: a)

        archiveWithoutReload(a)

        XCTAssertTrue(settings.recordableVehicles.contains { $0.id == a },
                      "снимок в памяти намеренно оставлен несвежим — в этом суть проверки")
        XCTAssertNil(settings.recordableVehicleId(a),
                     "рубеж перед штампом обязан читать хранилище, а не снимок")
    }

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

    // MARK: - Обходные пути

    /// Магнитола архивной машины делала её активной молча, без единого тапа —
    /// правило обходилось само собой.
    func testStereoOfAnArchivedVehicleResolvesToNothing() {
        let b = addCar("Архивная")
        settings.addBluetoothDevice(
            SavedBluetoothDevice(uuid: "u-1", name: "Kia Stereo", vehicleId: b))

        XCTAssertEqual(settings.vehicleId(forDeviceName: "Kia Stereo"), b)

        settings.setVehicleArchived(id: b, archived: true)

        XCTAssertNil(settings.vehicleId(forDeviceName: "Kia Stereo"),
                     "иначе достаточно воткнуться в магнитолу, чтобы обойти архив")
    }

    func testDeletingAVehicleTakesItsStereoBindingWithIt() {
        let a = addCar("Первая")
        settings.addBluetoothDevice(
            SavedBluetoothDevice(uuid: "u-2", name: "Ford Stereo", vehicleId: a))

        settings.deleteVehicle(id: a)

        XCTAssertNil(settings.vehicleId(forDeviceName: "Ford Stereo"))
    }

    // MARK: - Ничего не архивируется само

    /// Дедовщина: у того, кто обновится, все машины остаются рабочими. Если
    /// этот тест когда-нибудь упадёт, значит появился автоматический архив —
    /// а он отнимает у человека машину без его ведома.
    func testNothingIsArchivedByItself() {
        addCar("Первая")
        addCar("Вторая")
        addCar("Третья")

        XCTAssertEqual(settings.recordableVehicles.count, 3)
        XCTAssertTrue(settings.vehicles.allSatisfy { !$0.isArchived })
    }
}

/// Продажа и её отмена по проводу.
///
/// «Вернуть из проданных» выглядела рабочей и не работала никогда: апсерт
/// выбрасывал `nil` как «нечего слать», сервер оставлял дату продажи, а
/// следующий пул возвращал машину в проданные.
final class VehicleSoldWireTests: XCTestCase {

    private func payload(soldAt: Date?) -> VehicleSyncPayload {
        VehicleSyncPayload(
            id: UUID(), name: "Polo", avatarEmoji: "🚗", odometerKm: 0, level: 1,
            stickersJson: nil, cityConsumption: 0, highwayConsumption: 0,
            fuelPrice: 0, conflictVersion: 0, lastModifiedAt: Date(), soldAt: soldAt)
    }

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
