import XCTest
import CoreData
@testable import TripTrack

/// Миграция схемы v8 → v9 на НАСТОЯЩЕМ v8-сторе.
///
/// Единственная вещь в 0.6.4, которую нельзя переделать задним числом: v8 уже
/// стоит на устройствах, и отозвать её нельзя. Один non-optional атрибут без
/// значения по умолчанию — и стор не откроется, а гараж окажется пустым у
/// всех разом, включая тех, кто ничего не обновлял осознанно.
///
/// Тест обязан открывать именно старую версию модели и мигрировать её.
/// На чистом сторе миграции не видно вовсе: она просто не запускается, тест
/// зеленеет и не проверяет ничего.
final class CoreDataV9MigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v9-migration-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    // MARK: - Модели

    /// Скомпилированная модель лежит в бандле ПРИЛОЖЕНИЯ, а не тестов: юнит-тесты
    /// хостятся приложением, поэтому искать надо в обоих, начиная с `main`.
    ///
    /// Здесь намеренно `XCTFail`, а не `XCTSkip`. Первая версия этого файла
    /// скипалась, когда не находила momd, — и все четыре теста миграции ушли в
    /// «пропущено», а прогон остался зелёным. Тест, который умеет тихо не
    /// проверять ничего, хуже отсутствующего: он создаёт уверенность.
    private func model(named version: String) throws -> NSManagedObjectModel {
        let candidates = [Bundle.main, Bundle(for: type(of: self))] + Bundle.allBundles
        guard let momd = candidates.compactMap({
            $0.url(forResource: "TripTrack", withExtension: "momd")
        }).first else {
            XCTFail("TripTrack.momd не найден ни в одном бандле — миграцию проверить нечем")
            throw NSError(domain: "test", code: 1)
        }
        guard let url = try? FileManager.default
                .contentsOfDirectory(at: momd, includingPropertiesForKeys: nil)
                .first(where: { $0.lastPathComponent.hasPrefix(version) }),
              let m = NSManagedObjectModel(contentsOf: url) else {
            XCTFail("версия «\(version)» не найдена в \(momd.lastPathComponent)")
            throw NSError(domain: "test", code: 2)
        }
        return m
    }

    private func open(_ model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "TripTrack", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: storeURL)
        // Ровно те же два флага, что у боевого контейнера: тест, который
        // мигрирует иначе, чем приложение, проверяет чужую миграцию.
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    // MARK: - Сама миграция

    func testAVehicleWrittenOnV8SurvivesTheUpgrade() throws {
        let v8 = try model(named: "TripTrack v8")
        let id = UUID()

        // ── старая версия: заводим машину так, как её видел прошлый релиз
        do {
            let container = try open(v8)
            let ctx = container.viewContext
            let e = NSEntityDescription.insertNewObject(forEntityName: "VehicleEntity", into: ctx)
            e.setValue(id, forKey: "id")
            e.setValue("Полторашка", forKey: "name")
            e.setValue(143_500.0, forKey: "odometerKm")
            e.setValue("car", forKey: "vehicleType")
            e.setValue(true, forKey: "visibleToOthers")
            try ctx.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }

        // ── текущая версия: тот же файл, миграция на лету
        let current = try open(try model(named: "TripTrack v9"))
        let req = NSFetchRequest<NSManagedObject>(entityName: "VehicleEntity")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let rows = try current.viewContext.fetch(req)

        XCTAssertEqual(rows.count, 1, "машина не пережила миграцию — гараж пуст")
        let v = rows[0]
        XCTAssertEqual(v.value(forKey: "name") as? String, "Полторашка")
        XCTAssertEqual(v.value(forKey: "odometerKm") as? Double, 143_500)
        XCTAssertEqual(v.value(forKey: "visibleToOthers") as? Bool, true,
                       "видимость, выставленная до обновления, обязана пережить его")
    }

    /// Новые колонки на старой строке обязаны прийти со своими умолчаниями, а
    /// не с nil: их читает `Vehicle`, и nil там означал бы «поле пропало».
    func testNewColumnsArriveWithTheirDefaults() throws {
        let id = UUID()
        do {
            let container = try open(try model(named: "TripTrack v8"))
            let ctx = container.viewContext
            let e = NSEntityDescription.insertNewObject(forEntityName: "VehicleEntity", into: ctx)
            e.setValue(id, forKey: "id")
            e.setValue("Пчела", forKey: "name")
            try ctx.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }

        let current = try open(try model(named: "TripTrack v9"))
        let req = NSFetchRequest<NSManagedObject>(entityName: "VehicleEntity")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let v = try XCTUnwrap(try current.viewContext.fetch(req).first)

        // Умолчания разные и оба осознанные: фотографии закрыты, пока их не
        // откроют (во дворе виден и номер, и дом), карта открыта — без неё
        // паспорт наполовину пуст.
        XCTAssertEqual(v.value(forKey: "photosVisible") as? Bool, false,
                       "фотографии не могут открыться сами при обновлении")
        XCTAssertEqual(v.value(forKey: "mapVisible") as? Bool, true)
        XCTAssertEqual(v.value(forKey: "isArchived") as? Bool, false,
                       "существующая машина не должна уехать в архив при обновлении")
        XCTAssertNil(v.value(forKey: "soldAt"), "и тем более не должна оказаться проданной")
        XCTAssertEqual(v.value(forKey: "year") as? Int, 0, "0 — это «год не указан»")
    }

    /// Сущность фотографий машины появляется пустой и работоспособной.
    func testVehiclePhotoEntityExistsAfterMigration() throws {
        do {
            let container = try open(try model(named: "TripTrack v8"))
            try container.viewContext.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }
        let current = try open(try model(named: "TripTrack v9"))
        let names = current.managedObjectModel.entities.compactMap(\.name)
        XCTAssertTrue(names.contains("VehiclePhotoEntity"),
                      "сущность фотографий машины не доехала: \(names.sorted())")

        let ctx = current.viewContext
        let p = NSEntityDescription.insertNewObject(forEntityName: "VehiclePhotoEntity", into: ctx)
        p.setValue(UUID(), forKey: "id")
        p.setValue("photo.jpg", forKey: "filename")
        p.setValue(Date(), forKey: "timestamp")
        XCTAssertNoThrow(try ctx.save(), "новая сущность не пишется")
    }

    /// Каждый атрибут VehicleEntity обязан быть либо опциональным, либо с
    /// умолчанием. Это и есть то правило, нарушение которого не открывает стор.
    func testEveryVehicleAttributeIsSafeForALightweightMigration() throws {
        let v9 = try model(named: "TripTrack v9")
        let vehicle = try XCTUnwrap(v9.entities.first { $0.name == "VehicleEntity" })
        for (name, attr) in vehicle.attributesByName {
            if name == "id" { continue }   // ключ — единственное обязательное поле
            XCTAssertTrue(attr.isOptional || attr.defaultValue != nil,
                          "\(name): не опциональный и без умолчания — стор не откроется")
        }
    }
}
