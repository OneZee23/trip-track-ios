import XCTest
import CoreData
@testable import TripTrack

/// Финиш кладёт прямую достройку сразу, дорогу потом спросит `RoadGapFiller`
/// (спека §2.3). Достройка лежит в треке по времени, в километры не входит и
/// попадает в превью.
@MainActor
final class PostTripFillTests: XCTestCase {
    private var pc: PersistenceController!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        pc = nil
        super.tearDown()
    }

    /// Прямая на 10 м/с с дырой с 20-й по 80-ю секунду.
    private func tunnelTrip() -> TripEntity {
        var specs = (0...20).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
        specs += (80...100).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
        return TrackTestKit.insertTrip(into: pc, points: specs)
    }

    private func points(_ entity: TripEntity) -> [TrackPointEntity] {
        entity.trackPoints?.array as? [TrackPointEntity] ?? []
    }

    func testGapGetsAStraightFillInTimeOrder() async throws {
        let entity = tunnelTrip()
        // Новая строка и так `pendingUpload` (0) — без этого проверка ниже
        // ничего бы не проверяла.
        entity.syncStatus = SyncStatus.synced.rawValue
        try pc.container.viewContext.save()
        // Флаг синка теперь зависит от приватности и облака (правило E,
        // ревью раунд 1) — без инъекции тест зависел бы от живого
        // `SettingsManager.shared`, той же ловушки, что у
        // `SyncEnqueuer.isAuthorizedToEnqueue`.
        await PostTripTrackProcessor(persistenceController: pc, cloudSyncEnabled: { true })
            .processTrip(try XCTUnwrap(entity.id))

        let all = points(entity)
        let fills = all.filter(\.isInterpolated)
        XCTAssertEqual(fills.count, 29)
        XCTAssertEqual(all.map { $0.timestamp ?? .distantPast }, all.map { $0.timestamp ?? .distantPast }.sorted(),
                       "трек лежит по времени — карта и реплей читают его без сортировки")
        XCTAssertTrue(fills.allSatisfy { $0.speed == -1 && $0.horizontalAccuracy == -1 })
        XCTAssertEqual(entity.roadFillState, RoadFillState.pending.rawValue)
        // Допуск 2, не 1: `TrackTestKit.coordinate` кладёт широту по плоской
        // константе 111 320 м/градус, а `CLLocation.distance` считает по
        // эллипсоиду — на 45° широты расхождение ~0.17 %, и на тысяче метров
        // пути это уже 1.7 м. На коротких дистанциях (`DistanceDoorTests`) тот
        // же допуск 1 проходит случайно; здесь путь достаточно длинный, чтобы
        // систематика стала видна.
        XCTAssertEqual(entity.distance, 1000, accuracy: 2, "достройка в километры не входит; мост прямой — как раньше")
        XCTAssertEqual(entity.syncStatus, SyncStatus.pendingUpload.rawValue)
        // `tunnelTrip()` — точная меридианная прямая (east: 0 везде), а прямая
        // достройка по определению лежит на хорде между краями дыры: третьей
        // геометрии внутри достройки взяться неоткуда. RDP честно схлопывает
        // ЛЮБУЮ точно коллинеарную ломаную до двух конечных точек — это не
        // баг, а верное минимальное представление прямой. `>=`, а не `>`:
        // проверка, что превью пересобралось и не осталось пустым/битым после
        // достройки, а не что RDP обязана сохранить лишние точки на прямой.
        XCTAssertGreaterThanOrEqual(Trip.decodePolyline(try XCTUnwrap(entity.previewPolyline)).count, 2)
    }

    /// Правило E (ревью раунд 1): приватная поездка без облака получает
    /// достройку как обычно — дорога синка это не касается, — но флаг синка
    /// остаётся прежним: апдейт всё равно не смог бы доехать (гейт
    /// `SyncEnqueuer`), и вечный `pendingUpload` без единого шанса на синк
    /// был бы враньём в «Статусе».
    func testGapFillDoesNotFlipPrivateTripWithCloudOff() async throws {
        let entity = tunnelTrip()
        entity.syncStatus = SyncStatus.synced.rawValue
        // isPrivate по умолчанию true — helper ничего не выставляет явно.
        try pc.container.viewContext.save()
        await PostTripTrackProcessor(persistenceController: pc, cloudSyncEnabled: { false })
            .processTrip(try XCTUnwrap(entity.id))

        XCTAssertEqual(entity.roadFillState, RoadFillState.pending.rawValue)
        XCTAssertFalse(points(entity).filter(\.isInterpolated).isEmpty, "достройка всё равно случилась")
        XCTAssertEqual(entity.syncStatus, SyncStatus.synced.rawValue, "синк недостижим — трогать нечего")
    }

    func testTripWithoutGapsIsDone() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: (0...50).map {
            .init(east: 0, north: Double($0) * 10, seconds: Double($0))
        })
        await PostTripTrackProcessor(persistenceController: pc).processTrip(try XCTUnwrap(entity.id))
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue)
        XCTAssertFalse(points(entity).contains(where: \.isInterpolated))
    }

    /// Review Focus 1: 5 км за 11 с — прыжок GPS, а не дыра.
    func testTeleportGapStaysUnfilled() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: [
            .init(east: 0, north: 0, seconds: 0),
            .init(east: 0, north: 10, seconds: 1),
            .init(east: 0, north: 5010, seconds: 12),
            .init(east: 0, north: 5020, seconds: 13),
        ])
        await PostTripTrackProcessor(persistenceController: pc).processTrip(try XCTUnwrap(entity.id))
        XCTAssertFalse(points(entity).contains(where: \.isInterpolated))
    }

    /// Выброс, удалённый фильтром, не возвращается в трек при пересборке
    /// порядка после достройки: дыра стоит сразу за ним, и `sortTrackPoints`
    /// идёт по связи, из которой удалённое обязано уже уйти.
    func testRemovedSpikeDoesNotComeBackWithTheFill() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: [
            .init(east: 0, north: 0, seconds: 0),
            .init(east: 0, north: 10, seconds: 1),
            .init(east: 900, north: 15, seconds: 2),   // выброс
            .init(east: 0, north: 20, seconds: 3),
            .init(east: 0, north: 500, seconds: 60),   // дыра 57 с и 480 м
            .init(east: 0, north: 510, seconds: 61),
        ])
        await PostTripTrackProcessor(persistenceController: pc).processTrip(try XCTUnwrap(entity.id))
        let all = points(entity)
        XCTAssertFalse(all.contains(where: \.isDeleted))
        XCTAssertEqual(all.filter { !$0.isInterpolated }.count, 5)
        XCTAssertFalse(all.filter(\.isInterpolated).isEmpty)
    }
}
