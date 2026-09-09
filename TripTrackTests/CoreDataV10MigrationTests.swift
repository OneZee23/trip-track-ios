import XCTest
import CoreData
@testable import TripTrack

/// Миграция схемы v9 → v10 на НАСТОЯЩЕМ v9-сторе.
///
/// v9 уже стоит на устройствах вместе с 0.6.4, и отозвать её нельзя. Один
/// non-optional атрибут без значения по умолчанию — и стор не откроется, а
/// поездки пропадут у всех разом, включая тех, кто ничего не обновлял осознанно.
///
/// v10 добавляет отметки на маршруте и два поля снимку: когда снят и где.
/// Тест обязан открывать именно старую версию модели и мигрировать её — на
/// чистом сторе миграции не видно вовсе: она просто не запускается, тест
/// зеленеет и не проверяет ничего.
final class CoreDataV10MigrationTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("v10-migration-\(UUID().uuidString).sqlite")
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

    /// Поездка, записанная прошлым релизом, обязана открыться после обновления.
    func testATripWrittenOnV9SurvivesTheUpgrade() throws {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_780_000_000)

        do {
            let container = try open(try model(named: "TripTrack v9"))
            let ctx = container.viewContext
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx)
            trip.setValue(id, forKey: "id")
            trip.setValue(start, forKey: "startDate")
            trip.setValue(start.addingTimeInterval(3_600), forKey: "endDate")
            trip.setValue(210_000.0, forKey: "distance")

            let photo = NSEntityDescription.insertNewObject(forEntityName: "TripPhotoEntity", into: ctx)
            photo.setValue(UUID(), forKey: "id")
            photo.setValue("sea.jpg", forKey: "filename")
            photo.setValue(start.addingTimeInterval(1_800), forKey: "timestamp")
            photo.setValue(trip, forKey: "trip")

            try ctx.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }

        let current = try open(try model(named: "TripTrack v10"))
        let req = NSFetchRequest<NSManagedObject>(entityName: "TripEntity")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let rows = try current.viewContext.fetch(req)

        XCTAssertEqual(rows.count, 1, "поездка не пережила миграцию")
        XCTAssertEqual(rows[0].value(forKey: "distance") as? Double, 210_000)
        XCTAssertEqual((rows[0].value(forKey: "photos") as? NSOrderedSet)?.count, 1,
                       "снимок отвязался от поездки при миграции")
    }

    /// Отметка, записанная на v10 (девелоперские сборки 0.6.5 до 8 сентября),
    /// переживает v11: новая колонка прикреплённых снимков пуста, обложка на месте.
    func testACheckpointWrittenOnV10SurvivesV11() throws {
        let tripId = UUID(), coverId = UUID()
        do {
            let container = try open(try model(named: "TripTrack v10"))
            let ctx = container.viewContext
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx)
            trip.setValue(tripId, forKey: "id")
            trip.setValue(Date(), forKey: "startDate")
            let cp = NSEntityDescription.insertNewObject(forEntityName: "TripCheckpointEntity", into: ctx)
            cp.setValue(UUID(), forKey: "id")
            cp.setValue(Date(), forKey: "timestamp")
            cp.setValue(coverId, forKey: "photoId")
            cp.setValue(trip, forKey: "trip")
            try ctx.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }
        let current = try open(try model(named: "TripTrack v11"))
        let req = NSFetchRequest<NSManagedObject>(entityName: "TripCheckpointEntity")
        let rows = try current.viewContext.fetch(req)
        XCTAssertEqual(rows.count, 1, "отметка не пережила миграцию v10 → v11")
        XCTAssertEqual(rows[0].value(forKey: "photoId") as? UUID, coverId)
        XCTAssertNil(rows[0].value(forKey: "photoIdsJSON"))
    }

    /// Снимок, добавленный до 0.6.5, приходит БЕЗ времени съёмки и координаты —
    /// и это правильный ответ, а не потеря.
    ///
    /// Восстановить их неоткуда: тогда сохранялось только время попадания в
    /// базу, которое может отличаться от съёмки на дни. Именно поэтому такие
    /// снимки на карту не встают — соврать местом хуже, чем промолчать.
    func testAPhotoFromBeforeTheUpgradeHasNoCaptureTime() throws {
        let photoId = UUID()
        let start = Date(timeIntervalSince1970: 1_780_000_000)

        do {
            let container = try open(try model(named: "TripTrack v9"))
            let ctx = container.viewContext
            let photo = NSEntityDescription.insertNewObject(forEntityName: "TripPhotoEntity", into: ctx)
            photo.setValue(photoId, forKey: "id")
            photo.setValue("old.jpg", forKey: "filename")
            photo.setValue(start, forKey: "timestamp")
            try ctx.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }

        let current = try open(try model(named: "TripTrack v10"))
        let req = NSFetchRequest<NSManagedObject>(entityName: "TripPhotoEntity")
        req.predicate = NSPredicate(format: "id == %@", photoId as CVarArg)
        let row = try XCTUnwrap(try current.viewContext.fetch(req).first)

        XCTAssertNil(row.value(forKey: "capturedAt"), "время съёмки взялось из ниоткуда")
        XCTAssertNil(row.value(forKey: "exifLatitude"))
        XCTAssertEqual(row.value(forKey: "timestamp") as? Date, start,
                       "время добавления обязано пережить миграцию")
    }

    /// Новая сущность заводится и связывается с поездкой.
    func testCheckpointsCanBeWrittenAfterTheUpgrade() throws {
        let tripId = UUID()
        let start = Date(timeIntervalSince1970: 1_780_000_000)

        do {
            let container = try open(try model(named: "TripTrack v9"))
            let ctx = container.viewContext
            let trip = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx)
            trip.setValue(tripId, forKey: "id")
            trip.setValue(start, forKey: "startDate")
            try ctx.save()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        }

        let current = try open(try model(named: "TripTrack v10"))
        let ctx = current.viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "TripEntity")
        req.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
        let trip = try XCTUnwrap(try ctx.fetch(req).first)

        let checkpoint = NSEntityDescription.insertNewObject(
            forEntityName: "TripCheckpointEntity", into: ctx)
        checkpoint.setValue(UUID(), forKey: "id")
        checkpoint.setValue(start.addingTimeInterval(8_040), forKey: "timestamp")
        checkpoint.setValue(44.56, forKey: "latitude")
        checkpoint.setValue(38.07, forKey: "longitude")
        checkpoint.setValue(143_000.0, forKey: "distanceFromStart")
        checkpoint.setValue(8_040.0, forKey: "elapsedFromStart")
        checkpoint.setValue("море", forKey: "name")
        checkpoint.setValue(trip, forKey: "trip")
        try ctx.save()

        XCTAssertEqual((trip.value(forKey: "checkpoints") as? NSOrderedSet)?.count, 1)
    }
}
