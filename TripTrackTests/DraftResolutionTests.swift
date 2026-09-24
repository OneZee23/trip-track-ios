import XCTest
import CoreData
@testable import TripTrack

/// «Моя» переводит в мир ровно один раз; «Удалить» не оставляет ни строки.
@MainActor
final class DraftResolutionTests: XCTestCase {
    private var pc: PersistenceController!
    private var manager: TripManager!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
    }

    override func tearDown() {
        manager = nil
        pc = nil
        super.tearDown()
    }

    private func count<T: NSManagedObject>(_ request: NSFetchRequest<T>) throws -> Int {
        try pc.container.viewContext.count(for: request)
    }

    func testOnlyADraftFlipsToConfirmedAndOnlyOnce() throws {
        let draft = TrackTestKit.insertTrip(into: pc, points: [.init(east: 0, north: 0, seconds: 0)],
                                            processed: true, confirmation: .draft)
        let id = try XCTUnwrap(draft.id)
        XCTAssertTrue(manager.setConfirmation(.confirmed, tripId: id))
        XCTAssertEqual(draft.confirmation, "confirmed")
        XCTAssertFalse(manager.setConfirmation(.confirmed, tripId: id), "вход в мир дважды недопустим")
    }

    func testDiscardLeavesNoRowAndNoPoints() throws {
        let draft = TrackTestKit.insertTrip(into: pc, points: (0...10).map {
            .init(east: 0, north: Double($0) * 10, seconds: Double($0))
        }, processed: true, confirmation: .draft)
        XCTAssertTrue(manager.discardDraft(id: try XCTUnwrap(draft.id)))
        let trips: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        let points: NSFetchRequest<TrackPointEntity> = TrackPointEntity.fetchRequest()
        XCTAssertEqual(try count(trips), 0)
        XCTAssertEqual(try count(points), 0)
    }

    func testDiscardRefusesAConfirmedTrip() throws {
        let real = TrackTestKit.insertTrip(into: pc, points: [.init(east: 0, north: 0, seconds: 0)], processed: true)
        XCTAssertFalse(manager.discardDraft(id: try XCTUnwrap(real.id)))
        let trips: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        XCTAssertEqual(try count(trips), 1)
    }
}
