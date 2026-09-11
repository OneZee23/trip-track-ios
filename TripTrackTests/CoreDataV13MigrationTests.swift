import XCTest
import CoreData
@testable import TripTrack

/// Миграция схемы v12 → v13 на НАСТОЯЩЕМ v12-сторе.
///
/// v13 добавляет одну колонку — `VehicleEntity.dashboardUnits`. Проверяется не
/// то, что колонка появилась (это видно в файле схемы), а то, ради чего у неё
/// именно такое умолчание: **миграция физически не может никому сменить
/// показания**. У машины, заведённой до 0.6.7, ответа на вопрос «что у неё на
/// панели» не существует, и любое умолчание, кроме «как в приложении», молча
/// переставило бы цифры половине людей.
///
/// Тест открывает СТАРУЮ версию модели и мигрирует её: на чистом сторе
/// миграции не видно вовсе. Устройство — как у `CoreDataV12MigrationTests`.
final class CoreDataV13MigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v13-migration-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

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
                .first(where: { $0.lastPathComponent.hasPrefix(version + ".") }),
              let m = NSManagedObjectModel(contentsOf: url) else {
            XCTFail("версия «\(version)» не найдена в \(momd.lastPathComponent)")
            throw NSError(domain: "test", code: 2)
        }
        return m
    }

    private func open(_ model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "TripTrack", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return container
    }

    /// Машина, заведённая на v12 (0.6.6), переезжает целой — и получает
    /// «как в приложении», то есть ровно то, что с ней происходило вчера.
    func testAVehicleWrittenOnV12KeepsItsNumbersAndFollowsTheApp() throws {
        let vehicleId = UUID()
        do {
            let container = try open(try model(named: "TripTrack v12"))
            let ctx = container.viewContext
            let v = NSEntityDescription.insertNewObject(forEntityName: "VehicleEntity", into: ctx)
            v.setValue(vehicleId, forKey: "id")
            v.setValue("Тойота", forKey: "name")
            v.setValue(142_000.0, forKey: "odometerKm")
            v.setValue(NSNumber(value: 143_500.0), forKey: "manualOdometerKm")
            v.setValue(9.1, forKey: "cityConsumption")
            v.setValue(58.0, forKey: "fuelPrice")
            try ctx.save()
            for s in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(s)
            }
        }

        let current = try open(try model(named: "TripTrack v13"))
        let req = NSFetchRequest<NSManagedObject>(entityName: "VehicleEntity")
        req.predicate = NSPredicate(format: "id == %@", vehicleId as CVarArg)
        let row = try XCTUnwrap(try current.viewContext.fetch(req).first)

        // Числа — те же. Хранение метрическое, миграция ничего не пересчитывает
        // и не переименовывает: 142 000 километров остаются километрами.
        XCTAssertEqual(row.value(forKey: "odometerKm") as? Double, 142_000)
        XCTAssertEqual((row.value(forKey: "manualOdometerKm") as? NSNumber)?.doubleValue, 143_500)
        XCTAssertEqual(row.value(forKey: "cityConsumption") as? Double, 9.1)
        XCTAssertEqual(row.value(forKey: "fuelPrice") as? Double, 58)

        // А приборка — «как в приложении». Ни `metric`, ни `imperial`: любое
        // другое умолчание и есть та самая молчаливая смена показаний.
        let raw = row.value(forKey: "dashboardUnits") as? String
        XCTAssertEqual(DashboardUnits.parse(raw) ?? .app, .app,
                       "миграция сменила единицу приборки у существующей машины")
    }
}
