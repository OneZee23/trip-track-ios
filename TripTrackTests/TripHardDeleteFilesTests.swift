import XCTest
import CoreData
@testable import TripTrack

/// Твёрдое удаление поездки обязано уносить и КАДРЫ.
///
/// Каскад CoreData забирает строки снимков, отметок и точек, но про
/// `Documents/TripPhotos/<id>/` он не знает ничего, а каталог исключён из
/// резервной копии. Убирать файлы умел один `purgeSoftDeletedTrips`, а мимо
/// него идут три пути: своё удаление поездки, ещё не доехавшей до сервера,
/// подтверждение удаления сервером и надгробие с другого телефона. Во всех
/// трёх кадры оставались на диске навсегда, и добраться до них было уже нечем.
///
/// Отдельно проверяется отказ: надгробие, которое поездку НЕ удалило (она
/// местная или снята с публикации), не имеет права тронуть её снимки — иначе
/// защита от чужого удаления теряла бы ровно то, что берегла.
final class TripHardDeleteFilesTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var madeDirs: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    /// Каталог общий и переживает весь прогон — убираем за собой руками.
    override func tearDown() async throws {
        for dir in madeDirs { try? FileManager.default.removeItem(at: dir) }
        madeDirs = []
        repo = nil
        pc = nil
        try await super.tearDown()
    }

    @discardableResult
    private func trip(serverCreatedAt: Date?) -> UUID {
        let ctx = pc.container.viewContext
        let e = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx)
        let id = UUID()
        e.setValue(id, forKey: "id")
        e.setValue(Date(timeIntervalSince1970: 1_760_000_000), forKey: "startDate")
        e.setValue(Date(timeIntervalSince1970: 1_760_003_600), forKey: "endDate")
        e.setValue(serverCreatedAt, forKey: "serverCreatedAt")
        try? ctx.save()
        return id
    }

    /// Кадр на диске — настоящий: проверяется именно файл, а не строка.
    private func photoFile(of tripId: UUID) throws -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TripPhotos", isDirectory: true)
            .appendingPathComponent(tripId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        madeDirs.append(dir)
        let file = dir.appendingPathComponent("kadr.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: file)
        return file
    }

    func testHardDeleteTakesThePhotoFilesWithIt() throws {
        let id = trip(serverCreatedAt: nil)
        let file = try photoFile(of: id)

        repo.deleteTripHard(id: id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTombstoneTakesThePhotoFilesWithIt() throws {
        let id = trip(serverCreatedAt: Date(timeIntervalSince1970: 1_760_000_000))
        let file = try photoFile(of: id)

        XCTAssertTrue(repo.deleteTripHardIfMirrored(id: id))

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// Надгробие про поездку, которой на сервере не было, отклоняется — и
    /// кадры остаются на месте вместе с ней.
    func testRefusedTombstoneKeepsThePhotoFiles() throws {
        let id = trip(serverCreatedAt: nil)
        let file = try photoFile(of: id)

        XCTAssertFalse(repo.deleteTripHardIfMirrored(id: id))

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
