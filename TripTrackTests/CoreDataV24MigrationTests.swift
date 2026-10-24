import CoreData
import XCTest

@testable import TripTrack

final class CoreDataV24MigrationTests: XCTestCase {
    func testV23VehicleAndTripsSurviveWithEmptyGarageFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("trip.sqlite")
        let bundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles
        let directory = try XCTUnwrap(
            bundles.compactMap { $0.url(forResource: "TripTrack", withExtension: "momd") }.first)
        let legacy = try XCTUnwrap(
            NSManagedObjectModel(contentsOf: directory.appendingPathComponent("TripTrack v23.mom")))
        for entity in legacy.entities { entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }
        let id = UUID()
        let tripID = UUID()
        do {
            let old = try open(legacy, url)
            defer { close(old) }
            let car = NSEntityDescription.insertNewObject(forEntityName: "VehicleEntity", into: old.viewContext)
            car.setValue(id, forKey: "id")
            car.setValue("Polo", forKey: "name")
            car.setValue("pixel_car_blue", forKey: "avatarEmoji")
            car.setValue(96400.0, forKey: "manualOdometerKm")
            car.setValue("card_gold", forKey: "cardStyle")
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: old.viewContext)
            trip.setValue(Date(timeIntervalSince1970: 1_740_787_200), forKey: "startDate")
            trip.setValue(tripID, forKey: "id")
            trip.setValue(id, forKey: "vehicleId")
            trip.setValue(6240000.0, forKey: "distance")
            try old.viewContext.save()
        }
        let migrated = try open(PersistenceController.managedObjectModel, url)
        defer { close(migrated) }
        let car = try XCTUnwrap(migrated.viewContext.fetch(VehicleEntity.fetchRequest()).first)
        XCTAssertEqual(car.id, id)
        XCTAssertEqual(car.name, "Polo")
        XCTAssertEqual(car.manualOdometerKm?.doubleValue, 96400)
        XCTAssertEqual(car.cardStyle, "card_gold")
        for key in [
            "drive2URL", "modTagsJSON", "paintFinish", "modsJSON", "catalogModelId", "catalogGenerationId",
            "catalogVariantId",
        ] {
            XCTAssertNil(car.value(forKey: key), key)
            XCTAssertEqual(car.entity.attributesByName[key]?.isOptional, true)
        }
        let trip = try XCTUnwrap(migrated.viewContext.fetch(TripEntity.fetchRequest()).first)
        XCTAssertEqual(trip.id, tripID)
        XCTAssertEqual(trip.vehicleId, id)
        XCTAssertEqual(trip.distance, 6_240_000)
    }
    private func open(_ model: NSManagedObjectModel, _ url: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "TripTrack", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        return container
    }
    private func close(_ container: NSPersistentContainer) {
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
}
