import XCTest
import CoreData
@testable import TripTrack

/// v22 → v23: связь `trackPoints` перестала быть упорядоченной (Sentry
/// APPLE-IOS-P). Лёгкая миграция роняет скрытую колонку порядка, поэтому
/// проверяется главное: ни одна точка не теряется, а порядок по времени
/// восстанавливается даже у поездки, чей порядок в старой связи НЕ совпадал
/// со временем (пост-обработка, которая сортировала связь, могла не успеть).
final class CoreDataV23MigrationTests: XCTestCase {
    func testV22PointsSurviveAndComeBackInTimeOrder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("trip.sqlite")
        let tripID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // Ordered relationship stored in a scrambled order on purpose.
        let offsets: [TimeInterval] = [30, 0, 20, 10, 40, 10]
        var expectedIDs: [UUID] = []
        do {
            let container = try open(model: legacyModel(), url: url)
            defer { close(container) }
            let context = container.viewContext
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: context)
            trip.setValue(tripID, forKey: "id")
            trip.setValue(start, forKey: "startDate")
            trip.setValue(start.addingTimeInterval(60), forKey: "endDate")
            var points: [(TimeInterval, UUID, NSManagedObject)] = []
            for (i, offset) in offsets.enumerated() {
                let id = UUID()
                let point = NSEntityDescription.insertNewObject(forEntityName: "TrackPointEntity", into: context)
                point.setValue(id, forKey: "id")
                point.setValue(start.addingTimeInterval(offset), forKey: "timestamp")
                point.setValue(45.0 + Double(i) * 0.001, forKey: "latitude")
                point.setValue(39.0, forKey: "longitude")
                points.append((offset, id, point))
            }
            trip.setValue(NSOrderedSet(array: points.map(\.2)), forKey: "trackPoints")
            try context.save()
            expectedIDs = points
                .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.uuidString < $1.1.uuidString }
                .map(\.1)
        }

        let migrated = try open(model: PersistenceController.managedObjectModel, url: url)
        defer { close(migrated) }
        let trip = try XCTUnwrap(migrated.viewContext
            .fetch(NSFetchRequest<TripEntity>(entityName: "TripEntity")).first)
        XCTAssertEqual(trip.id, tripID)
        XCTAssertEqual(trip.trackPoints?.count, offsets.count, "no point may be lost")
        XCTAssertEqual(trip.orderedTrackPoints.map(\.id), expectedIDs,
                       "order comes from the timestamp, ties broken by id")
    }

    /// Миграция идёт на первом запуске после обновления. Если она долгая,
    /// система убивает приложение на старте — и человек остаётся без него.
    /// Библиотека здесь больше живой (самая большая на сервере — 3 млн точек
    /// на ~960 поездок у всех вместе): 200 поездок × 2 000 точек.
    func testMigratingALargeLibraryIsFast() throws {
        try measureMigration(trips: 200, perTrip: 2_000, budget: 10)
    }

    /// Самая большая библиотека на сервере на 10 окт 2026 — 1,27 млн точек у
    /// одного человека. Этот замер решает, можно ли мигрировать на старте.
    func testMigratingTheLargestKnownLibrary() throws {
        try measureMigration(trips: 640, perTrip: 2_000, budget: 120)
    }

    private func measureMigration(trips: Int, perTrip: Int, budget: TimeInterval) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("trip.sqlite")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        do {
            let container = try open(model: legacyModel(), url: url)
            defer { close(container) }
            let context = container.viewContext
            for t in 0..<trips {
                let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: context)
                trip.setValue(UUID(), forKey: "id")
                trip.setValue(start.addingTimeInterval(Double(t) * 86_400), forKey: "startDate")
                var points: [NSManagedObject] = []
                points.reserveCapacity(perTrip)
                for i in 0..<perTrip {
                    let p = NSEntityDescription.insertNewObject(forEntityName: "TrackPointEntity", into: context)
                    p.setValue(UUID(), forKey: "id")
                    p.setValue(start.addingTimeInterval(Double(t) * 86_400 + Double(i)), forKey: "timestamp")
                    p.setValue(45.0, forKey: "latitude")
                    p.setValue(39.0, forKey: "longitude")
                    points.append(p)
                }
                trip.setValue(NSOrderedSet(array: points), forKey: "trackPoints")
                if t % 20 == 19 { try context.save(); context.reset() }
            }
            try context.save()
        }
        let clock = Date()
        let migrated = try open(model: PersistenceController.managedObjectModel, url: url)
        let seconds = Date().timeIntervalSince(clock)
        defer { close(migrated) }
        let count = try migrated.viewContext.count(for: NSFetchRequest<TrackPointEntity>(entityName: "TrackPointEntity"))
        print("CoreDataV23Migration: \(trips * perTrip) points migrated in \(String(format: "%.2f", seconds)) s")
        XCTAssertEqual(count, trips * perTrip)
        XCTAssertLessThan(seconds, budget, "a slow first launch after the update gets killed by the system")
    }

    func testCurrentModelRelationshipIsUnorderedAndIndexed() throws {
        let model = PersistenceController.managedObjectModel
        let rel = try XCTUnwrap(model.entitiesByName["TripEntity"]?.relationshipsByName["trackPoints"])
        XCTAssertFalse(rel.isOrdered, "an ordered trackPoints makes every recording save quadratic")
        let indexes = model.entitiesByName["TrackPointEntity"]?.indexes.map(\.name) ?? []
        XCTAssertTrue(indexes.contains("byTripTimestamp"))
    }

    private func legacyModel() throws -> NSManagedObjectModel {
        let bundles = [Bundle.main, Bundle(for: Self.self)] + Bundle.allBundles
        let momd = try XCTUnwrap(bundles.compactMap {
            $0.url(forResource: "TripTrack", withExtension: "momd")
        }.first)
        let modelURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: momd, includingPropertiesForKeys: nil
        ).first { $0.lastPathComponent == "TripTrack v22.mom" })
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let originalHashes = model.entityVersionHashesByName
        // Generic managed objects: the fixture must not claim the app's classes
        // (see CoreDataV22MigrationTests for why one model per process matters).
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        XCTAssertEqual(model.entityVersionHashesByName, originalHashes)
        XCTAssertTrue(model.entitiesByName["TripEntity"]?.relationshipsByName["trackPoints"]?.isOrdered == true,
                      "the fixture must really be the ordered v22 schema")
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
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
}
