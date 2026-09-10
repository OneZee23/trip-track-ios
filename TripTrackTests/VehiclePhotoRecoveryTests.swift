import XCTest
import CoreData
@testable import TripTrack

/// Снимок машины не имеет права остаться на телефоне навсегда — и не имеет
/// права пережить саму машину.
///
/// Две дыры об одном и том же. Наверх: `.vehiclePhoto` попадает в очередь ровно
/// из двух мест, очередь живёт в памяти, а сканирование на запуске снимков
/// машины не знало вовсе — значит кадр, снятый в самолёте или при выключенном
/// облаке, не уезжал никогда, а каталог `VehiclePhotos/` исключён из резервной
/// копии, и смена телефона стирала его насовсем. Вниз: надгробие машины
/// удаляло `VehicleEntity` и на этом останавливалось, хотя связи с машиной у
/// строки снимка нет и каскад её не заберёт.
///
/// Хранилище здесь СВОЁ, in-memory: обе проверяемые функции принимают контекст
/// параметром. Общими остаются только привязка магнитолы (она в
/// `SettingsManager.shared`) и каталог со снимками на диске — оба
/// восстанавливаются в `tearDown`.
@MainActor
final class VehiclePhotoRecoveryTests: XCTestCase {
    private var pc: PersistenceController!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var savedDevices: [SavedBluetoothDevice] = []
    private var writtenFiles: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        pc = PersistenceController(inMemory: true)
        suiteName = "vehicle.photo.recovery.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedDevices = SettingsManager.shared.savedBluetoothDevices
    }

    /// Отпускать обязательно: XCTest держит экземпляры до конца прогона, и
    /// хвост, оставленный здесь, роняет ЧУЖОЙ класс — общий `SettingsManager`,
    /// общий каталог `VehiclePhotos/` и отдельный домен `UserDefaults`.
    override func tearDown() async throws {
        for url in writtenFiles { try? FileManager.default.removeItem(at: url) }
        writtenFiles = []
        SettingsManager.shared.savedBluetoothDevices = savedDevices
        savedDevices = []
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        pc = nil
        try await super.tearDown()
    }

    // MARK: Мир

    @discardableResult
    private func vehicle(_ id: UUID = UUID()) -> UUID {
        let ctx = pc.container.viewContext
        // Через имя сущности, а не через класс: в прогоне живут ДВА стора
        // (общий и этот), и `+[VehicleEntity entity]` не может выбрать между
        // двумя описаниями одной модели — CoreData ругается в лог.
        let e = NSEntityDescription.insertNewObject(forEntityName: "VehicleEntity", into: ctx)
        e.setValue(id, forKey: "id")
        e.setValue("Патриот", forKey: "name")
        try? ctx.save()
        return id
    }

    @discardableResult
    private func photo(of vehicleId: UUID,
                       remoteURL: String? = nil,
                       thumbnailURL: String? = nil,
                       filename: String = UUID().uuidString + ".jpg") -> UUID {
        let ctx = pc.container.viewContext
        let e = NSEntityDescription.insertNewObject(forEntityName: "VehiclePhotoEntity", into: ctx)
        let id = UUID()
        e.setValue(id, forKey: "id")
        e.setValue(vehicleId, forKey: "vehicleId")
        e.setValue(filename, forKey: "filename")
        e.setValue(Date(), forKey: "timestamp")
        e.setValue(remoteURL, forKey: "remoteURL")
        e.setValue(thumbnailURL, forKey: "thumbnailURL")
        try? ctx.save()
        return id
    }

    private func recovered() -> [SyncOperation] {
        SyncCoordinator.pendingVehiclePhotoOperations(in: pc.container.viewContext)
    }

    // MARK: Наверх

    func testPhotoWithoutServerCopyComesBackAsUpload() {
        let car = vehicle()
        let id = photo(of: car)
        let ops = recovered()
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.entityType, .vehiclePhoto)
        XCTAssertEqual(ops.first?.entityId, id)
        XCTAssertEqual(ops.first?.action, .upload)
    }

    /// Уехавший целиком в очереди не нужен: иначе каждый запуск приложения
    /// перебирал бы весь гараж заново.
    func testFullyUploadedPhotoGoesNowhere() {
        let car = vehicle()
        photo(of: car, remoteURL: "r2/original.jpg", thumbnailURL: "r2/thumb.jpg")
        XCTAssertTrue(recovered().isEmpty)
    }

    /// Оборвалось между размерами — на сервере лежит не весь снимок, и это
    /// такой же незаконченный случай, как полное отсутствие.
    func testHalfUploadedPhotoStillComesBack() {
        let car = vehicle()
        let id = photo(of: car, remoteURL: nil, thumbnailURL: "r2/thumb.jpg")
        XCTAssertEqual(recovered().map(\.entityId), [id])
    }

    /// Главное здесь. Машины уже нет — сервер ответит отказом в доступе, и
    /// операция сядет в `failedQueue` навсегда: лечение стало бы новой болезнью.
    func testPhotoOfADeadVehicleIsNotEnqueued() {
        photo(of: UUID())
        XCTAssertTrue(recovered().isEmpty)
    }

    /// Живая и мёртвая машины рядом: отсеивается ровно одна строка.
    func testDeadVehicleDoesNotTakeTheLiveOneWithIt() {
        let car = vehicle()
        let alive = photo(of: car)
        photo(of: UUID())
        XCTAssertEqual(recovered().map(\.entityId), [alive])
    }

    /// По операции на строку, без дублей — очередь дедуплицирует по тройке
    /// (тип, id, действие), но приходить сюда дважды одна строка не должна.
    func testEachPendingRowYieldsExactlyOneOperation() {
        let car = vehicle()
        let a = photo(of: car)
        let b = photo(of: car)
        photo(of: car, remoteURL: "r2/o.jpg", thumbnailURL: "r2/t.jpg")
        XCTAssertEqual(Set(recovered().map(\.entityId)), [a, b])
        XCTAssertEqual(recovered().count, 2)
    }

    // MARK: Вниз — надгробие машины

    func testTombstoneTakesPhotoRowsAndFilesWithIt() throws {
        let car = vehicle()
        let filename = UUID().uuidString + ".jpg"
        let file = VehiclePhotoStore.directory.appendingPathComponent(filename)
        try? FileManager.default.createDirectory(
            at: VehiclePhotoStore.directory, withIntermediateDirectories: true)
        try Data([0xFF, 0xD8, 0xFF]).write(to: file)
        writtenFiles.append(file)
        photo(of: car, filename: filename)

        PullApplier.purgeLocalRemains(
            ofVehicle: car, context: pc.container.viewContext,
            settings: SettingsManager.shared, defaults: defaults)

        let req = NSFetchRequest<NSManagedObject>(entityName: "VehiclePhotoEntity")
        req.predicate = NSPredicate(format: "vehicleId == %@", car as CVarArg)
        XCTAssertEqual(try pc.container.viewContext.count(for: req), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// Привязка магнитолы к удалённой машине пережила бы её и продолжила
    /// указывать в мёртвый id — а `AutoTripService` сохранил бы выбранной
    /// несуществующую машину, и поездка молча записалась бы «Без транспорта».
    func testTombstoneUnbindsTheStereo() {
        let car = vehicle()
        let other = vehicle()
        SettingsManager.shared.savedBluetoothDevices = [
            SavedBluetoothDevice(uuid: "AA", name: "Магнитола", vehicleId: car),
            SavedBluetoothDevice(uuid: "BB", name: "Колонка", vehicleId: other)
        ]

        PullApplier.purgeLocalRemains(
            ofVehicle: car, context: pc.container.viewContext,
            settings: SettingsManager.shared, defaults: defaults)

        XCTAssertEqual(SettingsManager.shared.savedBluetoothDevices.map(\.uuid), ["BB"])
    }

    /// Вопрос «показывать снимки этой машины другим» забывается вместе с
    /// машиной: иначе машина с тем же id, вернувшаяся синком, не спросит ничего.
    func testTombstoneForgetsTheVisibilityQuestion() {
        let car = vehicle()
        VehiclePhotoVisibilityAsk.markAsked(car, defaults)
        XCTAssertTrue(VehiclePhotoVisibilityAsk.wasAsked(car, defaults))

        PullApplier.purgeLocalRemains(
            ofVehicle: car, context: pc.container.viewContext,
            settings: SettingsManager.shared, defaults: defaults)

        XCTAssertFalse(VehiclePhotoVisibilityAsk.wasAsked(car, defaults))
    }

    /// Чужие снимки уборка не трогает — иначе одно надгробие уносило бы гараж.
    func testTombstoneLeavesOtherVehiclesPhotosAlone() throws {
        let car = vehicle()
        let other = vehicle()
        photo(of: car)
        let kept = photo(of: other)

        PullApplier.purgeLocalRemains(
            ofVehicle: car, context: pc.container.viewContext,
            settings: SettingsManager.shared, defaults: defaults)

        let req = NSFetchRequest<NSManagedObject>(entityName: "VehiclePhotoEntity")
        let rows = try pc.container.viewContext.fetch(req)
        XCTAssertEqual(rows.compactMap { $0.value(forKey: "id") as? UUID }, [kept])
    }

    /// Потолок за один проход, и он не про осторожность вообще, а про
    /// замеренное: `SyncQueue.enqueue` ищет дубль линейно и заново публикует
    /// снимок очереди, поэтому 500 операций стоят 32 мс главного потока, а
    /// 2000 — уже 462 мс, прямо на запуске приложения. Двести стоят 6 мс.
    /// Отрезанное не теряется: это опрос, и остаток подберёт следующий проход.
    func testOnePassIsCapped() {
        let car = vehicle()
        for _ in 0..<250 { photo(of: car) }
        XCTAssertEqual(recovered().count, 200)
    }
}
