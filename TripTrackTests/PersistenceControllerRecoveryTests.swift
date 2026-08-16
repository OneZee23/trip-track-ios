import XCTest
import CoreData
@testable import TripTrack

/// The store loader used to quarantine on ANY load error — a transient I/O
/// failure, a store still encrypted because the device had not been unlocked
/// since boot, a migration that needed a moment. It renamed the database,
/// DELETED its -wal and -shm, and opened an empty store in their place, in
/// Release with no log line at all. That is what emptied a real user's library
/// of 107 trips while the server still held every one of them.
final class PersistenceControllerRecoveryTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        try super.tearDownWithError()
    }

    private var storeURL: URL { dir.appendingPathComponent("TripTrack.sqlite") }

    private func writeUnreadableStore() throws {
        try Data("not a database".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-shm"))
    }

    func testFailedLoadDoesNotTouchTheStoreFile() throws {
        let fm = FileManager.default
        try writeUnreadableStore()

        let pc = PersistenceController(storeURL: storeURL)

        XCTAssertTrue(fm.fileExists(atPath: storeURL.path), "the database must survive a failed load")
        XCTAssertTrue(fm.fileExists(atPath: storeURL.path + "-wal"), "the journal holds the newest transactions")
        XCTAssertTrue(fm.fileExists(atPath: storeURL.path + "-shm"))

        let siblings = try fm.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(siblings.contains { $0.hasPrefix("TripTrack_corrupted_") },
                       "nothing may be set aside without the user asking")
        XCTAssertFalse(pc.isStoreOpen)
        XCTAssertNil(pc.storeIdentity)
    }

    /// A coordinator with zero stores raises an Objective-C exception on save
    /// that Swift cannot catch, so the app would crash before the recovery
    /// screen could draw. The ephemeral fallback keeps the API honest while
    /// `isStoreOpen` stays false.
    func testAFailedLoadStillLeavesAUsableContext() throws {
        try writeUnreadableStore()
        let pc = PersistenceController(storeURL: storeURL)

        XCTAssertFalse(pc.isStoreOpen)
        XCTAssertFalse(pc.container.persistentStoreCoordinator.persistentStores.isEmpty,
                       "a storeless coordinator throws NSInternalInconsistencyException on save")
        let trip = TripEntity(context: pc.container.viewContext)
        trip.id = UUID()
        trip.startDate = Date()
        pc.save()  // must not crash
    }

    /// The assertion the whole design rests on: if the platform ever stops
    /// honouring it, it surfaces here rather than in a user's empty feed.
    func testStoreIdentityIsStableAcrossReopen() {
        let first = PersistenceController(storeURL: storeURL)
        XCTAssertTrue(first.isStoreOpen)
        let identity = first.storeIdentity
        XCTAssertNotNil(identity)

        let second = PersistenceController(storeURL: storeURL)
        XCTAssertTrue(second.isStoreOpen)
        XCTAssertEqual(second.storeIdentity, identity)
    }

    func testAFreshStoreReportsANewIdentity() {
        let a = PersistenceController(storeURL: storeURL)
        let b = PersistenceController(storeURL: dir.appendingPathComponent("Other.sqlite"))
        XCTAssertNotNil(a.storeIdentity)
        XCTAssertNotNil(b.storeIdentity)
        XCTAssertNotEqual(a.storeIdentity, b.storeIdentity)
    }

    /// Setting aside keeps the journal WITH the database. A .sqlite whose -wal
    /// was deleted is missing its most recent transactions, which made the old
    /// "backup for potential manual recovery" a comforting sentence rather
    /// than a fact.
    func testSetAsideKeepsTheWalNextToTheSqlite() throws {
        let fm = FileManager.default
        try writeUnreadableStore()

        let pc = PersistenceController(storeURL: storeURL)
        XCTAssertFalse(pc.isStoreOpen)

        pc.setAsideStoreAndStartFresh()

        let siblings = try fm.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("TripTrack_corrupted_") && $0.hasSuffix(".sqlite") },
                      "the unreadable store must be kept, not deleted")
        XCTAssertTrue(siblings.contains { $0.hasPrefix("TripTrack_corrupted_") && $0.hasSuffix(".sqlite-wal") },
                      "the journal travels with the database it belongs to")
        XCTAssertTrue(pc.isStoreOpen, "a fresh store opens only when the user asks for it")
    }

    /// The recovery screen retries the SAME container: `viewContext` is bound
    /// to the coordinator, not to the store, so a store that attaches on a
    /// later try revives every context that already exists.
    func testRetrySucceedsOnceTheStoreBecomesReadable() throws {
        try writeUnreadableStore()
        let pc = PersistenceController(storeURL: storeURL)
        XCTAssertFalse(pc.isStoreOpen)
        XCTAssertFalse(pc.retryLoadingStore(), "still unreadable")

        try FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))

        XCTAssertTrue(pc.retryLoadingStore())
        XCTAssertTrue(pc.isStoreOpen)
        XCTAssertNotNil(pc.storeIdentity)
    }
}
