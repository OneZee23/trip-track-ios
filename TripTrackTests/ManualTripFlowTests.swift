import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Создание вписанной рукой поездки от начала до конца: строка в базе, её
/// колонка `source`, очередь синка и уведомление, по которому перечитываются
/// лента и «Мои».
///
/// Две меры против чужого хвоста, и обе обязательны.
///
/// Первая: хранилище и `TripManager` — ОДНИ на класс. Вторая: геокодер
/// заглушен (`namesFromGeocoder: false`). `createManualTrip` в приложении
/// спрашивает у `CLGeocoder` имя и регион, а тот отвечает ПОЗЖЕ и держит при
/// себе `TripEntity` — то есть после конца теста пишет в контекст хранилища,
/// которого уже нет. Куча портится молча, а падает от этого ЧУЖОЙ класс: у
/// нас это были `MapRegionsBundleTests` и `PostTripTrackProcessorTests` через
/// полалфавита — ровно тот хвост, что разобран в CLAUDE.md. Строки тесты друг
/// другу не мешают: каждый смотрит на СВОЙ id.
@MainActor
final class ManualTripFlowTests: XCTestCase {
    private static let pc = PersistenceController(inMemory: true)
    private static let repo = CoreDataTripRepository(persistenceController: pc)
    private static let locationManager = LocationManager()
    private static let manager = TripManager(
        locationManager: locationManager, persistenceController: pc, repository: repo)

    private var pc: PersistenceController { Self.pc }
    private var repo: CoreDataTripRepository { Self.repo }
    private var manager: TripManager { Self.manager }

    private func built(title: String? = nil, vehicleId: UUID? = nil) -> Trip {
        let coords = (0..<120).map { i -> CLLocationCoordinate2D in
            CLLocationCoordinate2D(latitude: 45.0 + Double(i) * 0.0006, longitude: 39.0)
        }
        let draft = ManualTripBuilder.Draft(
            coordinates: coords,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 3600,
            vehicleId: vehicleId,
            title: title
        )
        return ManualTripBuilder.build(draft)!
    }

    private func entity(_ id: UUID) throws -> TripEntity {
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try XCTUnwrap(try pc.container.viewContext.fetch(request).first)
    }

    // MARK: - Строка в базе

    func testCreatedTripLandsWithManualSourceAndPendingUpload() throws {
        let trip = built(title: "До моря")
        let saved = try XCTUnwrap(manager.createManualTrip(trip, namesFromGeocoder: false))

        let e = try entity(saved.id)
        XCTAssertEqual(e.source, "manual")
        XCTAssertEqual(e.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "без этого поездка жила бы до первого пула и пропала бы на нём")
        XCTAssertNotNil(e.endDate)
        XCTAssertTrue(e.isPrivate)
        XCTAssertNotNil(e.previewPolyline,
                        "превью — то, из чего «Атлас» берёт открытое; без него поездка не откроет ничего")
    }

    func testTheSavedDistanceIsTheBuiltOne() throws {
        let trip = built()
        let saved = try XCTUnwrap(manager.createManualTrip(trip, namesFromGeocoder: false))
        XCTAssertEqual(saved.distance, trip.distance, accuracy: 0.5)
        XCTAssertEqual(saved.source, .manual)
        XCTAssertEqual(saved.trackPoints.count, trip.trackPoints.count)
    }

    /// Имя человека геокодер не трогает — то же правило, что у
    /// `Place.rename`/`adoptName`.
    func testATypedNameSurvivesCreation() throws {
        let saved = try XCTUnwrap(manager.createManualTrip(built(title: "До моря"), namesFromGeocoder: false))
        let e = try entity(saved.id)
        XCTAssertEqual(e.title, "До моря")
        XCTAssertTrue(e.titleIsCustom)
    }

    // MARK: - Уведомление

    /// Лента и «Мои» перечитываются по СВОЕМУ уведомлению, а не по
    /// `.tripRecordingEnded`: у того на хвосте дела финиша (переключение
    /// вкладки на карточку итогов), которых здесь быть не должно.
    func testCreationPostsItsOwnNotificationAndNotTheRecordingOne() throws {
        // Считаем синхронно, без `wait`: `createManualTrip` постит на месте, а
        // окно ожидания в две секунды ловило бы и чужие уведомления — в полном
        // прогоне соседние наборы досчитывают свои задачи в том же процессе.
        var created: [UUID] = []
        var recording = 0
        let a = NotificationCenter.default.addObserver(
            forName: .manualTripCreated, object: nil, queue: nil
        ) { note in if let id = note.object as? UUID { created.append(id) } }
        let b = NotificationCenter.default.addObserver(
            forName: .tripRecordingEnded, object: nil, queue: nil
        ) { _ in recording += 1 }
        defer {
            NotificationCenter.default.removeObserver(a)
            NotificationCenter.default.removeObserver(b)
        }

        let saved = try XCTUnwrap(manager.createManualTrip(built(), namesFromGeocoder: false))
        XCTAssertEqual(created, [saved.id])
        XCTAssertEqual(recording, 0,
                       "у `.tripRecordingEnded` на хвосте дела финиша, которых здесь быть не должно")
    }

    // MARK: - Награды не начисляются

    /// Опыт у профиля не двигается: `createManualTrip` в наградную цепочку не
    /// заходит вовсе, а если однажды зайдёт — гейт в `calculateXP` вернёт ноль.
    func testCreatingAManualTripLeavesXPWhereItWas() throws {
        let gamification = GamificationManager(
            persistenceController: pc,
            defaults: UserDefaults(suiteName: "manual-flow-\(UUID().uuidString)")!
        )
        let saved = try XCTUnwrap(manager.createManualTrip(built(), namesFromGeocoder: false))
        let trip = try XCTUnwrap(repo.fetchTripDetail(id: saved.id))

        XCTAssertEqual(gamification.calculateXP(for: trip, allTrips: [trip]).total, 0)
        XCTAssertEqual(try entity(saved.id).xpEarned, 0)
    }
}
