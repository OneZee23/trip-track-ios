import XCTest
import CoreData
@testable import TripTrack

/// Отрезок живёт JSON-колонкой поездки, а не сущностью, поэтому всё, что у
/// отметки делает база (каскад, порядок, уникальность), здесь делает код — и
/// проверять это некому, кроме теста.
final class TripSegmentStoreTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var tripId: UUID!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        tripId = UUID()
        trip.id = tripId
        trip.startDate = Date()
        trip.endDate = Date()
        trip.isPrivate = false           // публичная — уходит на сервер и без облака
        trip.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
    }

    /// XCTest держит экземпляры тестов до конца прогона: поле, не обнулённое
    /// здесь, тянет свою `NSManagedObjectModel` в чужие классы (см. «Ловушки»
    /// в CLAUDE.md — «Multiple NSEntityDescriptions claim TripEntity»).
    override func tearDown() {
        repo = nil
        pc = nil
        tripId = nil
        super.tearDown()
    }

    @discardableResult
    private func addCheckpoint(elapsed: TimeInterval, distance: Double = 1_000) -> TripCheckpoint {
        let cp = TripCheckpoint(timestamp: Date().addingTimeInterval(elapsed), latitude: 45,
                                longitude: 38.9, distanceFromStart: distance, elapsedFromStart: elapsed)
        guard let saved = repo.addCheckpoint(cp, to: tripId) else {
            XCTFail("отметка не сохранилась"); return cp
        }
        return saved
    }

    private var status: Int16? { repo.fetchEntity(id: tripId)?.syncStatus }
    private func resetSyncStatus() { repo.fetchEntity(id: tripId)?.syncStatus = SyncStatus.synced.rawValue }
    private var storedSegments: [TripSegment] {
        CoreDataTripRepository.decodeSegments(repo.fetchEntity(id: tripId)?.segmentsJSON)
    }

    // MARK: - (a) порядок

    func testAddSegmentNormalisesOrderByElapsedTime() {
        let early = addCheckpoint(elapsed: 60)
        let late = addCheckpoint(elapsed: 3_600)

        // Человек выбрал «отрезок до…» и указал на БОЛЕЕ РАННЮЮ отметку.
        let segment = repo.addSegment(tripId: tripId, fromCheckpointId: late.id, toCheckpointId: early.id)

        XCTAssertEqual(segment?.fromCheckpointId, early.id)
        XCTAssertEqual(segment?.toCheckpointId, late.id)
    }

    func testAddSegmentKeepsOrderWhenAlreadyForward() {
        let early = addCheckpoint(elapsed: 60)
        let late = addCheckpoint(elapsed: 3_600)

        let segment = repo.addSegment(tripId: tripId, fromCheckpointId: early.id, toCheckpointId: late.id)

        XCTAssertEqual(segment?.fromCheckpointId, early.id)
        XCTAssertEqual(segment?.toCheckpointId, late.id)
    }

    // MARK: - (b) отрезок в самого себя

    func testSegmentToItselfIsRefused() {
        let cp = addCheckpoint(elapsed: 60)
        XCTAssertNil(repo.addSegment(tripId: tripId, fromCheckpointId: cp.id, toCheckpointId: cp.id))
        XCTAssertTrue(storedSegments.isEmpty)
    }

    func testSegmentWithUnknownCheckpointIsRefused() {
        let cp = addCheckpoint(elapsed: 60)
        XCTAssertNil(repo.addSegment(tripId: tripId, fromCheckpointId: cp.id, toCheckpointId: UUID()))
        XCTAssertNil(repo.addSegment(tripId: UUID(), fromCheckpointId: cp.id, toCheckpointId: cp.id))
        XCTAssertTrue(storedSegments.isEmpty)
    }

    // MARK: - (c) дубликат пары

    func testDuplicatePairInReverseOrderReturnsTheSameSegment() {
        let early = addCheckpoint(elapsed: 60)
        let late = addCheckpoint(elapsed: 3_600)

        let first = repo.addSegment(tripId: tripId, fromCheckpointId: early.id, toCheckpointId: late.id)
        let again = repo.addSegment(tripId: tripId, fromCheckpointId: late.id, toCheckpointId: early.id)

        XCTAssertNotNil(first)
        XCTAssertEqual(again?.id, first?.id)
        XCTAssertEqual(storedSegments.count, 1)
    }

    // MARK: - (d) очередь синка

    func testAddSegmentMarksTheTripForUpload() {
        let a = addCheckpoint(elapsed: 60), b = addCheckpoint(elapsed: 3_600)
        resetSyncStatus()
        XCTAssertNotNil(repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id))
        XCTAssertEqual(status, SyncStatus.pendingUpload.rawValue)
    }

    func testRenamingASegmentMarksTheTripForUpload() {
        let a = addCheckpoint(elapsed: 60), b = addCheckpoint(elapsed: 3_600)
        guard let segment = repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id) else {
            return XCTFail("отрезок не создался")
        }
        resetSyncStatus()

        XCTAssertEqual(repo.updateSegment(id: segment.id, name: "Серпантин"), tripId)
        XCTAssertEqual(status, SyncStatus.pendingUpload.rawValue)
        XCTAssertEqual(storedSegments.first?.name, "Серпантин")
    }

    func testDeletingASegmentMarksTheTripForUpload() {
        let a = addCheckpoint(elapsed: 60), b = addCheckpoint(elapsed: 3_600)
        guard let segment = repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id) else {
            return XCTFail("отрезок не создался")
        }
        resetSyncStatus()

        XCTAssertEqual(repo.deleteSegment(id: segment.id), tripId)
        XCTAssertEqual(status, SyncStatus.pendingUpload.rawValue)
        XCTAssertTrue(storedSegments.isEmpty)
    }

    /// Пустое имя — это `nil`, а не пустая строка: «A → B» при показе
    /// собирается именно по `nil`.
    func testBlankNameBecomesNil() {
        let a = addCheckpoint(elapsed: 60), b = addCheckpoint(elapsed: 3_600)
        guard let segment = repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id) else {
            return XCTFail("отрезок не создался")
        }
        repo.updateSegment(id: segment.id, name: "   ")
        XCTAssertNil(storedSegments.first?.name)
    }

    /// Отрезка, которого нет, — нет и поездки: очередь не должна получать мусор.
    func testUnknownSegmentReturnsNoTrip() {
        XCTAssertNil(repo.updateSegment(id: UUID(), name: "х"))
        XCTAssertNil(repo.deleteSegment(id: UUID()))
    }

    // MARK: - (e) каскад от отметки

    func testDeletingACheckpointRemovesItsSegments() {
        let a = addCheckpoint(elapsed: 60)
        let b = addCheckpoint(elapsed: 3_600)
        let c = addCheckpoint(elapsed: 7_200)
        repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id)
        repo.addSegment(tripId: tripId, fromCheckpointId: b.id, toCheckpointId: c.id)
        repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: c.id)
        XCTAssertEqual(storedSegments.count, 3)

        XCTAssertEqual(repo.deleteCheckpoint(id: b.id), tripId)

        // Осталась только пара, не касавшаяся удалённой отметки.
        XCTAssertEqual(storedSegments.count, 1)
        XCTAssertEqual(storedSegments.first?.fromCheckpointId, a.id)
        XCTAssertEqual(storedSegments.first?.toCheckpointId, c.id)
    }

    // MARK: - (f) висячий отрезок не читается

    func testSegmentWithMissingCheckpointIsDroppedOnRead() {
        let a = addCheckpoint(elapsed: 60)
        let b = addCheckpoint(elapsed: 3_600)
        let alive = repo.addSegment(tripId: tripId, fromCheckpointId: a.id, toCheckpointId: b.id)

        // Так выглядит база после пула, заменившего список отметок: отрезок
        // цел, а одной из его отметок больше нет.
        let dangling = TripSegment(fromCheckpointId: a.id, toCheckpointId: UUID())
        let entity = repo.fetchEntity(id: tripId)
        entity?.segmentsJSON = CoreDataTripRepository.encodeSegments(
            CoreDataTripRepository.decodeSegments(entity?.segmentsJSON) + [dangling])
        pc.save()

        let trip = repo.fetchTripDetail(id: tripId)
        XCTAssertEqual(trip?.segments.map(\.id), [alive?.id].compactMap { $0 })
    }
}
