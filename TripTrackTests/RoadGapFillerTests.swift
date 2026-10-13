import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import TripTrack

/// Дорога вместо прямой (спека §2.3) и проход по старым поездкам (§2.5).
/// Раунд 1 ревью добавил сюда: три фазы `fill` не текут на главный актёр
/// (§A), дренаж переживает поездку, финишировавшую посреди себя (§C), и
/// таблицу кодов `MKError` (§D). Раунд 2 добавил: остановка без единого
/// маршрута не пишет ничего (пункт 1), и двустороннюю проверку дыры —
/// пустую дыру односторонняя проверка пропускала бы молча (пункт 3).
@MainActor
final class RoadGapFillerTests: XCTestCase {
    private var pc: PersistenceController!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        pc = nil
        super.tearDown()
    }

    /// `east` и `secondsOffset` разводят поездки друг с другом в тестах, где
    /// их несколько: разный `east` даёт разные координаты дыры (чтобы
    /// маршрутизатор мог отличить одну поездку от другой), разный
    /// `secondsOffset` — разный `startDate` (чтобы был смысл в «новее»).
    private func tunnelSpecs(east: Double = 0, secondsOffset: Double = 0) -> [TrackTestKit.PointSpec] {
        (0...20).map { TrackTestKit.PointSpec(east: east, north: Double($0) * 10, seconds: Double($0) + secondsOffset) }
            + (80...100).map { TrackTestKit.PointSpec(east: east, north: Double($0) * 10, seconds: Double($0) + secondsOffset) }
    }

    /// Тот же трек плюс третий настоящий отрезок — вторая дыра с 100-й по
    /// 160-ю секунду, той же формы, что первая (Review Focus A, раунд 1).
    private func twoGapSpecs() -> [TrackTestKit.PointSpec] {
        tunnelSpecs() + (160...180).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
    }

    /// Дыра с 20-й по 80-ю секунду между (0, 200) и (0, 800), уже с прямой.
    /// `cloudSyncEnabled` инъецируется детерминированно (правило E, раунд 1):
    /// живой `SettingsManager.shared` в тесте — та же ловушка, что у
    /// `SyncEnqueuer.isAuthorizedToEnqueue`.
    private func processedTunnelTrip(east: Double = 0, secondsOffset: Double = 0,
                                      confirmation: TripConfirmation = .confirmed,
                                      cloudSyncEnabled: Bool = true) async throws -> TripEntity {
        let entity = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs(east: east, secondsOffset: secondsOffset),
                                             confirmation: confirmation)
        await PostTripTrackProcessor(persistenceController: pc, cloudSyncEnabled: { cloudSyncEnabled })
            .processTrip(try XCTUnwrap(entity.id))
        return entity
    }

    private func processedTwoGapTrip() async throws -> TripEntity {
        let entity = TrackTestKit.insertTrip(into: pc, points: twoGapSpecs())
        await PostTripTrackProcessor(persistenceController: pc, cloudSyncEnabled: { true })
            .processTrip(try XCTUnwrap(entity.id))
        return entity
    }

    /// Крюк на 150 м вбок: 700 м пути, 90 с езды — правдоподобно.
    private static let detour: [CLLocationCoordinate2D] = [
        TrackTestKit.coordinate(east: 0, north: 200), TrackTestKit.coordinate(east: 150, north: 400),
        TrackTestKit.coordinate(east: 150, north: 600), TrackTestKit.coordinate(east: 0, north: 800),
    ]

    private func road(distance: Double = 800) -> RoadRoute {
        RoadRoute(coordinates: Self.detour, distance: distance, expectedTravelTime: 90)
    }

    /// `cloudSyncEnabled`/`pause`/`enqueue`/`reveal` — со детерминированными
    /// умолчаниями (раунд 1): ни один существующий тест не читает
    /// `syncStatus`, поэтому смена умолчания с живого `SettingsManager` на
    /// фиксированный `true` ничего не ломает и убирает недетерминизм разом.
    private func filler(_ router: RoadRouter, online: Bool = true, cloudSyncEnabled: Bool = true,
                        pause: @escaping (Duration) async -> Void = { _ in },
                        enqueue: @escaping @MainActor (UUID) -> Void = { _ in },
                        reveal: @escaping (UUID) async -> Void = { _ in }) -> RoadGapFiller {
        RoadGapFiller(router: router, persistence: pc, isAllowedToRun: { online },
                      pause: pause, reveal: reveal, enqueue: enqueue,
                      cloudSyncEnabled: { cloudSyncEnabled })
    }

    private func fills(_ entity: TripEntity) -> [TrackPointEntity] {
        entity.orderedTrackPoints.filter(\.isInterpolated)
    }

    func testPlausibleRoadReplacesTheStraightFill() async throws {
        let entity = try await processedTunnelTrip()
        let distanceBefore = entity.distance
        let router = StubRoadRouter { _, _ in self.road() }
        let outcome = await filler(router).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue)
        XCTAssertTrue(fills(entity).contains { $0.longitude > TrackTestKit.origin.longitude + 0.001 },
                      "достройка ушла на дорогу")
        XCTAssertEqual(entity.distance, distanceBefore, "километры достройку не видят")
    }

    func testPausedSectionNeverRequestsARoad() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs())
        CoreDataTripRepository.setRecordingBreaks([TrackTestKit.epoch.addingTimeInterval(80)], on: entity)
        try pc.container.viewContext.save()
        let router = StubRoadRouter { _, _ in self.road() }
        let result = await filler(router).fill(tripId: try XCTUnwrap(entity.id))
        pc.container.viewContext.refreshAllObjects()

        XCTAssertEqual(result, .done)
        XCTAssertEqual(router.calls, 0)
        XCTAssertTrue(fills(entity).isEmpty)
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue)
    }

    func testLibraryScanDoesNotFillAnExplicitPause() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs(), processed: true)
        CoreDataTripRepository.setRecordingBreaks([TrackTestKit.epoch.addingTimeInterval(80)], on: entity)
        entity.distance = 400
        try pc.container.viewContext.save()

        let router = StubRoadRouter { _, _ in self.road() }
        let count = await filler(router).scanLibrary()
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(router.calls, 0)
        XCTAssertTrue(fills(entity).isEmpty)
        XCTAssertEqual(entity.distance, 400)
    }

    func testPauseMetadataArrivingDuringDirectionsPreventsApplyingTheRoad() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs())
        let id = try XCTUnwrap(entity.id)
        let pcRef = pc!
        let router = StubRoadRouter { _, _ in
            let context = pcRef.newBackgroundContext()
            context.performAndWait {
                let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                if let current = try? context.fetch(request).first {
                    CoreDataTripRepository.setRecordingBreaks([TrackTestKit.epoch.addingTimeInterval(80)],
                                                              on: current)
                    try? context.save()
                }
            }
            return self.road()
        }
        var enqueued: [UUID] = []
        _ = await filler(router, enqueue: { enqueued.append($0) }).fill(tripId: id)
        pc.container.viewContext.refreshAllObjects()

        XCTAssertEqual(router.calls, 1)
        XCTAssertTrue(fills(entity).isEmpty)
        XCTAssertTrue(enqueued.isEmpty)
        XCTAssertEqual(CoreDataTripRepository.recordingBreaks(of: entity),
                       [TrackTestKit.epoch.addingTimeInterval(80)])
    }

    func testImplausibleRoadKeepsTheStraightLine() async throws {
        let entity = try await processedTunnelTrip()
        let router = StubRoadRouter { _, _ in self.road(distance: 5000) }
        _ = await filler(router).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue)
        XCTAssertTrue(fills(entity).allSatisfy { abs($0.longitude - TrackTestKit.origin.longitude) < 0.0001 })
    }

    /// Review Focus 4: лимит или сеть — поездка ждёт, прямая цела, повтор не
    /// плодит второй достройки и дорогу второй раз не спрашивает.
    func testThrottledKeepsPendingAndTheRetryDoesNotDuplicate() async throws {
        let entity = try await processedTunnelTrip()
        let id = try XCTUnwrap(entity.id)
        let straightCount = fills(entity).count

        let router = StubRoadRouter { _, _ in throw RoadRouteError.throttled }
        let first = await filler(router).fill(tripId: id)
        XCTAssertEqual(first, .stillPending)
        XCTAssertEqual(entity.roadFillState, RoadFillState.pending.rawValue)
        XCTAssertEqual(fills(entity).count, straightCount)

        router.answer = { _, _ in self.road() }
        let second = await filler(router).fill(tripId: id)
        XCTAssertEqual(second, .done)
        let expected = GapFill.resample(Self.detour, from: TrackTestKit.epoch.addingTimeInterval(20),
                                        to: TrackTestKit.epoch.addingTimeInterval(80),
                                        altitudeFrom: 30, altitudeTo: 30).count
        XCTAssertEqual(fills(entity).count, expected)

        let third = await filler(router).fill(tripId: id)
        XCTAssertEqual(third, .done)
        XCTAssertEqual(router.calls, 2, "дорогу второй раз не спрашивают")
    }

    /// Ревью раунд 2, пункт 1: остановка без единого маршрута обязана не
    /// писать НИЧЕГО. Поездка искусственно стоит `done`, хотя дыра всё ещё
    /// прямая (могло случиться до фикса, или руками) — без охранника
    /// «Применить» пересохранила бы её и откатила `done` обратно в
    /// `pending`, хотя писать было нечего.
    func testEarlyStopWithNothingCollectedLeavesADoneTripAlone() async throws {
        let entity = try await processedTunnelTrip()
        entity.roadFillState = RoadFillState.done.rawValue
        try pc.container.viewContext.save()

        let router = StubRoadRouter { _, _ in throw RoadRouteError.throttled }
        let outcome = await filler(router).fill(tripId: try XCTUnwrap(entity.id))

        XCTAssertEqual(outcome, .stillPending)
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue, "писать было нечего — «Применить» не звали")
    }

    func testNotAllowedToRunLeavesEverythingAsIs() async throws {
        let entity = try await processedTunnelTrip()
        let router = StubRoadRouter { _, _ in self.road() }
        let outcome = await filler(router, online: false).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(outcome, .stillPending)
        XCTAssertEqual(router.calls, 0)
    }

    func testLibraryScanFillsOldTripsWithoutMovingTheirKilometres() async throws {
        let old = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs(), processed: true)
        old.distance = 1234.5   // что бы там ни лежало — не трогаем
        try pc.container.viewContext.save()

        let router = StubRoadRouter { _, _ in throw RoadRouteError.offline }
        let pending = await filler(router).scanLibrary()
        XCTAssertEqual(pending, 1)
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(old.roadFillState, RoadFillState.pending.rawValue)
        XCTAssertFalse(fills(old).isEmpty)
        XCTAssertEqual(old.distance, 1234.5)
    }

    /// Review Focus 5: поездка пула уже с достройкой.
    func testLibraryScanLeavesAlreadyFilledTripsAlone() async throws {
        var specs = (0...20).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
        specs.append(.init(east: 0, north: 500, seconds: 50, accuracy: -1, speed: -1, interpolated: true))
        specs += (80...100).map { TrackTestKit.PointSpec(east: 0, north: Double($0) * 10, seconds: Double($0)) }
        let pulled = TrackTestKit.insertTrip(into: pc, points: specs, processed: true)

        let router = StubRoadRouter { _, _ in throw RoadRouteError.offline }
        let pending = await filler(router).scanLibrary()
        XCTAssertEqual(pending, 0)
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(fills(pulled).count, 1)
        XCTAssertEqual(pulled.roadFillState, RoadFillState.done.rawValue)
    }

    /// Правило B (раунд 1): список id мог устареть между выборкой и
    /// обработкой — поездку, помеченную на удаление, `scanLibrary` не трогает
    /// (здесь предикат самой выборки уже её отсекает, а `existingObject` +
    /// проверка статуса — вторая, защитная дверь для более узкой гонки).
    func testScanSkipsTripsMarkedForDeletion() async throws {
        let entity = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs(), processed: true)
        entity.syncStatus = SyncStatus.pendingDelete.rawValue
        try pc.container.viewContext.save()

        let router = StubRoadRouter { _, _ in throw RoadRouteError.offline }
        let pending = await filler(router).scanLibrary()
        XCTAssertEqual(pending, 0)
        XCTAssertTrue(fills(entity).isEmpty, "поездку под удаление достройка не трогает")
    }

    // MARK: Review Focus A — вторая дыра не топит первую

    /// Две дыры: первая получает дорогу, вторая упирается в лимит. Собранное
    /// на первой обязано примениться, а не пропасть вместе с ранним выходом.
    func testSecondGapThrottledLeavesFirstGapAppliedAndTripPending() async throws {
        let entity = try await processedTwoGapTrip()
        let id = try XCTUnwrap(entity.id)
        let gap1Range = TrackTestKit.epoch.addingTimeInterval(20)...TrackTestKit.epoch.addingTimeInterval(80)
        let gap2Range = TrackTestKit.epoch.addingTimeInterval(100)...TrackTestKit.epoch.addingTimeInterval(160)

        var askedCount = 0
        let router = StubRoadRouter { _, _ in
            askedCount += 1
            if askedCount == 1 { return self.road() }
            throw RoadRouteError.throttled
        }
        var enqueued: [UUID] = []
        let outcome = await filler(router, enqueue: { enqueued.append($0) }).fill(tripId: id)

        XCTAssertEqual(outcome, .stillPending)
        XCTAssertEqual(entity.roadFillState, RoadFillState.pending.rawValue)
        XCTAssertEqual(enqueued, [id], "применённая дорога уже стоит поездке в очередь")
        XCTAssertTrue(fills(entity).filter { gap1Range.contains($0.timestamp ?? .distantPast) }
            .contains { $0.longitude > TrackTestKit.origin.longitude + 0.001 }, "первая дыра ушла на дорогу")
        XCTAssertTrue(fills(entity).filter { gap2Range.contains($0.timestamp ?? .distantPast) }
            .allSatisfy { abs($0.longitude - TrackTestKit.origin.longitude) < 0.0001 }, "вторая дыра осталась прямой")
        let timestamps = entity.orderedTrackPoints.map { $0.timestamp ?? .distantPast }
        XCTAssertEqual(timestamps, timestamps.sorted(), "трек лежит по времени")
        XCTAssertNotNil(entity.previewPolyline)

        // Повтор: вторую дыру теперь пускают.
        router.answer = { _, _ in self.road() }
        let callsBeforeRetry = router.calls
        let second = await filler(router, enqueue: { enqueued.append($0) }).fill(tripId: id)

        XCTAssertEqual(second, .done)
        XCTAssertEqual(entity.roadFillState, RoadFillState.done.rawValue)
        XCTAssertEqual(router.calls - callsBeforeRetry, 1, "дорогу спросили только про вторую дыру")
        let gap2After = fills(entity).filter { gap2Range.contains($0.timestamp ?? .distantPast) }
        XCTAssertTrue(gap2After.contains { $0.longitude > TrackTestKit.origin.longitude + 0.001 })
        let expectedGap2Count = GapFill.resample(Self.detour, from: gap2Range.lowerBound, to: gap2Range.upperBound,
                                                 altitudeFrom: 30, altitudeTo: 30).count
        XCTAssertEqual(gap2After.count, expectedGap2Count, "старые прямые точки удалены — дублей нет")
    }

    // MARK: Правило B — удалённые поездки не воскресают

    func testPendingDeleteTripReturnsNotFound() async throws {
        let entity = try await processedTunnelTrip()
        let straightBefore = fills(entity).count
        entity.syncStatus = SyncStatus.pendingDelete.rawValue
        try pc.container.viewContext.save()

        var enqueued: [UUID] = []
        var revealed: [UUID] = []
        let router = StubRoadRouter { _, _ in self.road() }
        let outcome = await filler(router, enqueue: { enqueued.append($0) }, reveal: { revealed.append($0) })
            .fill(tripId: try XCTUnwrap(entity.id))

        XCTAssertEqual(outcome, .notFound)
        XCTAssertEqual(entity.syncStatus, SyncStatus.pendingDelete.rawValue)
        XCTAssertEqual(fills(entity).count, straightBefore)
        XCTAssertTrue(enqueued.isEmpty)
        XCTAssertTrue(revealed.isEmpty)
        XCTAssertEqual(router.calls, 0, "предикат «Анализа» уже исключает pendingDelete")
    }

    /// Поездку помечают на удаление НА ДРУГОМ контексте, пока «Спросить»
    /// ждёт ответ сети, — «Применить» переоткрывает трек тем же предикатом,
    /// что «Анализ», и находит надгробие, а не поездку.
    func testTripSoftDeletedDuringRouterCallWritesNothing() async throws {
        let entity = try await processedTunnelTrip()
        let id = try XCTUnwrap(entity.id)
        let straightBefore = fills(entity).count
        let pcRef = pc!

        var enqueued: [UUID] = []
        let router = StubRoadRouter { _, _ in
            let bg = pcRef.newBackgroundContext()
            bg.performAndWait {
                let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                if let trip = try? bg.fetch(request).first {
                    trip.syncStatus = SyncStatus.pendingDelete.rawValue
                    try? bg.save()
                }
            }
            return self.road()
        }
        let outcome = await filler(router, enqueue: { enqueued.append($0) }).fill(tripId: id)

        XCTAssertEqual(outcome, .notFound)
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(entity.syncStatus, SyncStatus.pendingDelete.rawValue)
        XCTAssertEqual(fills(entity).count, straightBefore, "прямая осталась нетронутой")
        XCTAssertTrue(enqueued.isEmpty)
    }

    // MARK: Двусторонняя проверка — раунд 2

    /// Ревью раунд 2, пункт 3: у ПУСТОЙ дыры нет своих id, которые могли бы
    /// разойтись — односторонняя проверка (только «мои старые id ещё живы»)
    /// пропустила бы её молча. Пока «Спросить» ждёт ответ, пул успевает
    /// принести в то же окно СВОЮ прямую достройку — двусторонняя проверка
    /// обязана заметить НОВУЮ точку и не положить дорогу поверх нею.
    func testPulledStraightFillIntoAnEmptyGapDuringTheRouterCallIsNotOverwritten() async throws {
        // Без PostTripTrackProcessor — дыра совсем пустая, ни одной точки.
        let entity = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs())
        let id = try XCTUnwrap(entity.id)
        let pcRef = pc!

        let router = StubRoadRouter { _, _ in
            let bg = pcRef.newBackgroundContext()
            bg.performAndWait {
                let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                if let trip = try? bg.fetch(request).first {
                    let pulled = TrackPointEntity(context: bg)
                    pulled.id = UUID()
                    let c = TrackTestKit.coordinate(east: 0, north: 500)
                    pulled.latitude = c.latitude
                    pulled.longitude = c.longitude
                    pulled.altitude = 30
                    pulled.speed = -1
                    pulled.horizontalAccuracy = -1
                    pulled.timestamp = TrackTestKit.epoch.addingTimeInterval(50)
                    pulled.isInterpolated = true
                    pulled.trip = trip
                    try? bg.save()
                }
            }
            return self.road()
        }
        var enqueued: [UUID] = []
        let outcome = await filler(router, enqueue: { enqueued.append($0) }).fill(tripId: id)

        // Проход окончен (роутер ответил, лимит не мешал) — но состояние
        // самой поездки осталось `pending`: см. доккомментарий `Outcome.done`.
        XCTAssertEqual(outcome, .done)
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(entity.roadFillState, RoadFillState.pending.rawValue)
        XCTAssertTrue(enqueued.isEmpty, "дыру пропустили — синку нечего доставлять")
        let insideGap = fills(entity).filter {
            guard let ts = $0.timestamp else { return false }
            return ts > TrackTestKit.epoch.addingTimeInterval(20) && ts < TrackTestKit.epoch.addingTimeInterval(80)
        }
        XCTAssertEqual(insideGap.count, 1, "только притянутая пулом точка — без дублей и без дороги рядом")
        XCTAssertTrue(insideGap.allSatisfy { abs($0.longitude - TrackTestKit.origin.longitude) < 0.0001 },
                      "дорога не легла поверх — дыра осталась прямой (чужой)")
    }

    // MARK: Review Focus B — пауза сама уводит в фон

    /// Вторая дыра: пауза перед её запросом сама переключает
    /// `isAllowedToRun` на `false` (симуляция ухода в фон посреди паузы,
    /// спека §2.5) — запрос про эту дыру не идёт вовсе.
    func testAllowedToRunFlippingDuringPauseStopsBeforeTheSecondGap() async throws {
        let entity = try await processedTwoGapTrip()
        let id = try XCTUnwrap(entity.id)

        var allowed = true
        var pauseCalls = 0
        let router = StubRoadRouter { _, _ in self.road() }
        let f = RoadGapFiller(router: router, persistence: pc, isAllowedToRun: { allowed },
                              pause: { _ in pauseCalls += 1; allowed = false },
                              reveal: { _ in }, enqueue: { _ in }, cloudSyncEnabled: { true })
        let outcome = await f.fill(tripId: id)

        XCTAssertEqual(outcome, .stillPending)
        XCTAssertEqual(pauseCalls, 1)
        XCTAssertEqual(router.calls, 1, "вторую дыру уже не спросили")
    }

    // MARK: Review Focus C — дренаж

    func testDrainStopsOnStillPendingLeavingSecondTripUntouched() async throws {
        _ = try await processedTunnelTrip(east: 0, secondsOffset: 0)
        _ = try await processedTunnelTrip(east: 3000, secondsOffset: 1000)
        let router = StubRoadRouter { _, _ in throw RoadRouteError.throttled }
        await filler(router).drainIfPossible()
        XCTAssertEqual(router.calls, 1, "дренаж встал после первой же поездки")
    }

    func testDrainSkipsPendingDeleteTrips() async throws {
        let entity = try await processedTunnelTrip()
        entity.syncStatus = SyncStatus.pendingDelete.rawValue
        try pc.container.viewContext.save()
        let router = StubRoadRouter { _, _ in self.road() }
        await filler(router).drainIfPossible()
        XCTAssertEqual(router.calls, 0)
    }

    /// Две поездки — пауза стоит МЕЖДУ ними, а не перед первым запросом
    /// вообще: шаг в две секунды общий на очередь, а не свой у каждой
    /// поездки.
    func testDrainAsksTwoPendingTripsWithOnePauseBetweenThem() async throws {
        _ = try await processedTunnelTrip(east: 0, secondsOffset: 0)
        _ = try await processedTunnelTrip(east: 3000, secondsOffset: 1000)
        var pauseCalls = 0
        let router = StubRoadRouter { _, _ in self.road() }
        await filler(router, pause: { _ in pauseCalls += 1 }).drainIfPossible()
        XCTAssertEqual(router.calls, 2)
        XCTAssertEqual(pauseCalls, 1, "пауза между поездками, а не перед первой")
    }

    /// Пока дренаж разбирает поездку A, «финиширует» поездка C (тем же
    /// приёмом, что и `testTripSoftDeletedDuringRouterCallWritesNothing`:
    /// мутация на другом контексте внутри ответа маршрутизатора) — C обязана
    /// попасть в ТОТ ЖЕ дренаж, а не ждать следующего `didBecomeActive`.
    func testDrainServesATripThatBecomesPendingDuringTheDrain() async throws {
        let a = try await processedTunnelTrip(east: 0, secondsOffset: 0)
        let c = TrackTestKit.insertTrip(into: pc, points: tunnelSpecs(east: 3000, secondsOffset: 1000))
        _ = try XCTUnwrap(a.id)
        let cId = try XCTUnwrap(c.id)
        let pcRef = pc!

        let router = StubRoadRouter { _, _ in
            let bg = pcRef.newBackgroundContext()
            bg.performAndWait {
                let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", cId as CVarArg)
                if let trip = try? bg.fetch(request).first {
                    trip.roadFillState = RoadFillState.pending.rawValue
                    try? bg.save()
                }
            }
            return self.road()
        }
        await filler(router).drainIfPossible()

        XCTAssertEqual(router.calls, 2, "новую поездку дожали в ТОМ ЖЕ дренаже")
        pc.container.viewContext.refreshAllObjects()
        XCTAssertEqual(c.roadFillState, RoadFillState.done.rawValue)
    }

    /// Поездка, упёршаяся в лимит в ПЕРВОМ дренаже, идёт ПОСЛЕДНЕЙ во ВТОРОМ
    /// — несмотря на то, что она новее и по датам шла бы первой.
    func testStalledTripGoesLastInNextDrain() async throws {
        let older = try await processedTunnelTrip(east: 0, secondsOffset: 0)
        let newer = try await processedTunnelTrip(east: 20_000, secondsOffset: 5_000)
        _ = try XCTUnwrap(older.id)
        _ = try XCTUnwrap(newer.id)

        var order: [String] = []
        let router = StubRoadRouter { from, _ in
            let label = from.longitude > TrackTestKit.origin.longitude + 0.1 ? "newer" : "older"
            order.append(label)
            if label == "newer" { throw RoadRouteError.throttled }
            return self.road()
        }
        let f = filler(router)
        await f.drainIfPossible()
        XCTAssertEqual(order, ["newer"], "первый дренаж спрашивает новее — по startDate")

        order.removeAll()
        router.answer = { from, _ in
            let label = from.longitude > TrackTestKit.origin.longitude + 0.1 ? "newer" : "older"
            order.append(label)
            return self.road()
        }
        await f.drainIfPossible()
        XCTAssertEqual(order, ["older", "newer"], "застрявшая поездка — теперь в хвосте")
    }

    // MARK: Реплей тумана

    /// Черновик не открывает туман, подтверждённая поездка — открывает, и
    /// ровно один раз, со своим id.
    func testRevealSkipsDraftButFiresForConfirmed() async throws {
        let confirmed = try await processedTunnelTrip(east: 0, secondsOffset: 0)
        var revealedConfirmed: [UUID] = []
        let routerA = StubRoadRouter { _, _ in self.road() }
        _ = await filler(routerA, reveal: { revealedConfirmed.append($0) })
            .fill(tripId: try XCTUnwrap(confirmed.id))
        XCTAssertEqual(revealedConfirmed, [try XCTUnwrap(confirmed.id)])

        let draft = try await processedTunnelTrip(east: 3000, secondsOffset: 1000, confirmation: .draft)
        var revealedDraft: [UUID] = []
        let routerB = StubRoadRouter { _, _ in self.road() }
        _ = await filler(routerB, reveal: { revealedDraft.append($0) })
            .fill(tripId: try XCTUnwrap(draft.id))
        XCTAssertTrue(revealedDraft.isEmpty, "черновик не открывает туман (спека §3.2)")
        // «Нет реплея» не должно быть враньём от «ничего не применилось»:
        // дорога у черновика всё равно легла, реплея нет только у тумана.
        XCTAssertTrue(fills(draft).contains { $0.longitude > TrackTestKit.origin.longitude + 0.001 },
                      "дорога у черновика тоже легла — не реплеится только туман")
    }

    // MARK: Правило E — флаг синка

    func testFillFlipsPendingUploadWhenCloudSyncOn() async throws {
        let entity = try await processedTunnelTrip()
        entity.syncStatus = SyncStatus.synced.rawValue
        try pc.container.viewContext.save()
        let router = StubRoadRouter { _, _ in self.road() }
        _ = await filler(router, cloudSyncEnabled: true).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(entity.syncStatus, SyncStatus.pendingUpload.rawValue)
    }

    /// Приватная поездка без облака — апдейт всё равно не смог бы уйти
    /// (гейт `SyncEnqueuer`), поэтому статус остаётся как был.
    func testFillDoesNotFlipPrivateTripWithCloudOff() async throws {
        let entity = try await processedTunnelTrip()
        entity.syncStatus = SyncStatus.synced.rawValue
        // isPrivate по умолчанию true — TrackTestKit ничего не выставляет.
        try pc.container.viewContext.save()
        let router = StubRoadRouter { _, _ in self.road() }
        _ = await filler(router, cloudSyncEnabled: false).fill(tripId: try XCTUnwrap(entity.id))
        XCTAssertEqual(entity.syncStatus, SyncStatus.synced.rawValue, "синк недостижим — трогать нечего")
    }

    // MARK: Правило D — таблица кодов

    /// Чистая функция, без единого сетевого запроса.
    func testErrorMappingTable() {
        let table: [(MKError.Code, RoadRouteError)] = [
            (.loadingThrottled, .throttled),
            (.directionsNotFound, .noRoute),
            (.placemarkNotFound, .noRoute),
            (.decodingFailed, .noRoute),
            (.unknown, .offline),
            (.serverFailure, .offline),
        ]
        for (code, expected) in table {
            XCTAssertEqual(RoadRouteError.from(MKError(code)), expected, "\(code)")
        }
        XCTAssertEqual(RoadRouteError.from(URLError(.notConnectedToInternet)), .offline, "не-MKError — тоже офлайн")
    }
}
