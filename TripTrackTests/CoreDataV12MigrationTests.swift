import XCTest
import CoreData
@testable import TripTrack

/// Миграция схемы v11 → v12 на НАСТОЯЩЕМ v11-сторе.
///
/// v12 добавляет `JourneyEntity` — путешествие живёт в своей таблице, ничего
/// в `TripEntity` не меняется. Тест открывает СТАРУЮ версию модели и
/// мигрирует её: на чистом сторе миграции не видно вовсе.
final class CoreDataV12MigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v12-migration-\(UUID().uuidString).sqlite")
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

    /// Отметка с прикреплёнными снимками, записанная на v11 (0.6.5), переживает v12.
    func testACheckpointWrittenOnV11SurvivesV12() throws {
        let tripId = UUID()
        do {
            let container = try open(try model(named: "TripTrack v11"))
            let ctx = container.viewContext
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx)
            trip.setValue(tripId, forKey: "id"); trip.setValue(Date(), forKey: "startDate")
            let cp = NSEntityDescription.insertNewObject(forEntityName: "TripCheckpointEntity", into: ctx)
            cp.setValue(UUID(), forKey: "id"); cp.setValue(Date(), forKey: "timestamp")
            cp.setValue("[\"\(UUID().uuidString)\"]", forKey: "photoIdsJSON"); cp.setValue(trip, forKey: "trip")
            try ctx.save()
            for s in container.persistentStoreCoordinator.persistentStores { try container.persistentStoreCoordinator.remove(s) }
        }
        let current = try open(try model(named: "TripTrack v12"))
        XCTAssertEqual(try current.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "TripCheckpointEntity")), 1)
        XCTAssertEqual(try current.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: "JourneyEntity")), 0)
    }
}
