import XCTest
import CoreData
@testable import TripTrack

/// Миграция схемы v13 → v14 на НАСТОЯЩЕМ v13-сторе.
///
/// v14 добавляет `PlaceEntity`/`PlacePassEntity` (обе без связей — место
/// выводится из отметок и треков, а не хранит связь с ними) и колонку
/// `TripEntity.placesMatchedAt`. Проверяется не то, что колонки появились (это
/// видно в файле схемы), а то, что миграция САМА ничего не досчитывает:
/// старая отметка с `placeId` переезжает как есть, новые сущности остаются
/// пустыми, а `placesMatchedAt` у поездки — `nil`, то есть «ещё не сверялась».
/// Сверку сделает матчер при следующем запуске (следующая задача волны), не
/// эта миграция.
///
/// Тест открывает СТАРУЮ версию модели и мигрирует её: на чистом сторе
/// миграции не видно вовсе. Устройство — как у `CoreDataV13MigrationTests`.
final class CoreDataV14MigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v14-migration-\(UUID().uuidString).sqlite")
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

    /// Отметка с `placeId`, записанная на v13, переезжает целой; новые
    /// сущности пусты; у поездки появляется пустой `placesMatchedAt` — то есть
    /// «ещё не сверялась», и сверка при запуске возьмёт её сама.
    func testACheckpointWrittenOnV13SurvivesV14AndTripsAwaitMatching() throws {
        let placeId = UUID()
        do {
            let container = try open(try model(named: "TripTrack v13"))
            let ctx = container.viewContext
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx)
            trip.setValue(UUID(), forKey: "id"); trip.setValue(Date(), forKey: "startDate")
            trip.setValue(Date(), forKey: "endDate")
            let cp = NSEntityDescription.insertNewObject(forEntityName: "TripCheckpointEntity", into: ctx)
            cp.setValue(UUID(), forKey: "id"); cp.setValue(Date(), forKey: "timestamp")
            cp.setValue(placeId, forKey: "placeId"); cp.setValue(trip, forKey: "trip")
            try ctx.save()
            for s in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(s)
            }
        }
        let current = try open(try model(named: "TripTrack v14"))
        let ctx = current.viewContext
        let cps = try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: "TripCheckpointEntity"))
        XCTAssertEqual(cps.count, 1)
        XCTAssertEqual(cps.first?.value(forKey: "placeId") as? UUID, placeId)
        let trips = try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: "TripEntity"))
        XCTAssertNil(trips.first?.value(forKey: "placesMatchedAt"))
        XCTAssertEqual(try ctx.count(for: NSFetchRequest<NSManagedObject>(entityName: "PlaceEntity")), 0)
        XCTAssertEqual(try ctx.count(for: NSFetchRequest<NSManagedObject>(entityName: "PlacePassEntity")), 0)
    }
}
