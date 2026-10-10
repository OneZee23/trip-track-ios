import XCTest
import CoreData
@testable import TripTrack

final class CoreDataV22MigrationTests: XCTestCase {
    func testV21TripAndPointsSurviveWithNoInventedPauseBoundaries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("trip.sqlite")
        let id = UUID()
        let pointID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let container = try open(model: legacyModel(), url: url)
            defer { close(container) }
            let context = container.viewContext
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: context)
            trip.setValue(id, forKey: "id")
            trip.setValue(date, forKey: "startDate")
            trip.setValue(date.addingTimeInterval(60), forKey: "endDate")
            trip.setValue(1234.5, forKey: "distance")
            let point = NSEntityDescription.insertNewObject(forEntityName: "TrackPointEntity", into: context)
            point.setValue(pointID, forKey: "id")
            point.setValue(date, forKey: "timestamp")
            point.setValue(45.0, forKey: "latitude")
            point.setValue(39.0, forKey: "longitude")
            point.setValue(trip, forKey: "trip")
            try context.save()
        }
        // The current app model is shared process-wide. A second v22 model
        // would register competing TripEntity/TrackPointEntity descriptions
        // and break Entity(context:) in tests that run after this one.
        let migrated = try open(model: PersistenceController.managedObjectModel, url: url)
        defer { close(migrated) }
        let trips = try migrated.viewContext.fetch(NSFetchRequest<TripEntity>(entityName: "TripEntity"))
        let trip = try XCTUnwrap(trips.first)
        XCTAssertTrue(trip.entity === PersistenceController.managedObjectModel.entitiesByName["TripEntity"])
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trip.id, id)
        XCTAssertEqual(trip.distance, 1234.5)
        XCTAssertEqual(trip.trackPoints?.count, 1)
        XCTAssertEqual(trip.orderedTrackPoints.first?.id, pointID)
        XCTAssertNil(trip.recordingBreaksJSON)
        CoreDataTripRepository.setRecordingBreaks([date.addingTimeInterval(30)], on: trip)
        try migrated.viewContext.save()
        migrated.viewContext.reset()
        let reloaded = try XCTUnwrap(migrated.viewContext.fetch(NSFetchRequest<TripEntity>(entityName: "TripEntity")).first)
        XCTAssertEqual(CoreDataTripRepository.recordingBreaks(of: reloaded), [date.addingTimeInterval(30)])
    }

    private func legacyModel() throws -> NSManagedObjectModel {
        let bundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles
        let momd = try XCTUnwrap(bundles.compactMap {
            $0.url(forResource: "TripTrack", withExtension: "momd")
        }.first)
        let modelURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: momd, includingPropertiesForKeys: nil
        ).first { $0.lastPathComponent == "TripTrack v21.mom" })
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let originalHashes = model.entityVersionHashesByName
        // The legacy fixture uses KVC only. Give it generic managed objects
        // before attaching a coordinator so it cannot claim the app's classes.
        // Class mapping must leave the actual v21 store schema unchanged.
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        XCTAssertEqual(model.entityVersionHashesByName, originalHashes,
                       "Fixture class isolation must preserve the v21 migration source hashes")
        return model
    }

    private func open(model: NSManagedObjectModel, url: URL) throws -> NSPersistentContainer {
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
        container.viewContext.reset()
        for store in container.persistentStoreCoordinator.persistentStores {
            do {
                try container.persistentStoreCoordinator.remove(store)
            } catch {
                XCTFail("Could not close migration fixture: \(error)")
            }
        }
    }
}
