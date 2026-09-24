import XCTest
import CoreData
@testable import TripTrack

/// Схема v20 (спека §3.5): у поездки появились статус подтверждения и
/// состояние достройки. Все существующие поездки остаются подтверждёнными —
/// черновиком бывает только то, что приложение начало само.
@MainActor
final class TripConfirmationSchemaTests: XCTestCase {
    private var pc: PersistenceController!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        pc = nil
        super.tearDown()
    }

    func testNewTripEntityDefaultsToConfirmedAndUnchecked() {
        let entity = TripEntity(context: pc.container.viewContext)
        XCTAssertEqual(entity.confirmation, "confirmed")
        XCTAssertEqual(entity.roadFillState, "unchecked")
    }

    func testStartTripCanCreateADraft() throws {
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: nil, confirmation: .draft)
        XCTAssertEqual(manager.activeTrip?.isDraft, true)
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        XCTAssertEqual(try pc.container.viewContext.fetch(request).first?.confirmation, "draft")
    }

    func testStartTripIsConfirmedByDefault() {
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: nil)
        XCTAssertEqual(manager.activeTrip?.confirmation, .confirmed)
    }

    /// `handleNewLocation` пересобирает `activeTrip` на каждой записанной
    /// точке — и дважды уже теряла так поля поездки (см. комментарий там).
    /// Черновик, забытый пересборкой, завершался бы по правилам человека, а не
    /// приложения, и дописывался бы до вечера.
    func testDraftSurvivesTheRebuildOnEveryFix() {
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: nil, confirmation: .draft)
        manager.handleNewLocation(TrackTestKit.fix(east: 0, north: 0, speed: 10, after: 0))
        manager.handleNewLocation(TrackTestKit.fix(east: 0, north: 10, speed: 10, after: 1))
        XCTAssertEqual(manager.activeTrip?.isDraft, true)
    }

    /// Процесс убили посреди черновика — после запуска он остаётся черновиком.
    func testRecoveredOrphanKeepsItsDraftFlag() throws {
        let ctx = pc.container.viewContext
        let entity = TripEntity(context: ctx)
        entity.id = UUID()
        entity.startDate = Date().addingTimeInterval(-600)
        entity.distance = 3000
        entity.maxSpeed = 15
        entity.confirmation = TripConfirmation.draft.rawValue
        for i in 0..<5 {
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            p.latitude = 45 + Double(i) * 0.001
            p.longitude = 39
            p.timestamp = Date().addingTimeInterval(-300 + Double(i) * 30)
            p.trip = entity
        }
        try ctx.save()

        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        XCTAssertEqual(manager.recoverableOrphan?.isDraft, true)
    }

    func testRepositoryMapsUnknownStringsToSafeDefaults() throws {
        let ctx = pc.container.viewContext
        let entity = TripEntity(context: ctx)
        let id = UUID()
        entity.id = id
        entity.startDate = Date()
        entity.endDate = Date()
        entity.confirmation = "somethingFromTheFuture"
        entity.roadFillState = "later"
        try ctx.save()

        let trip = CoreDataTripRepository(persistenceController: pc).fetchTripDetail(id: id)
        XCTAssertEqual(trip?.confirmation, .confirmed)
        XCTAssertEqual(trip?.roadFillState, .unchecked)
    }
}
