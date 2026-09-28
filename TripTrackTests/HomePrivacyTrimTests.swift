import CoreData
import CoreLocation
import XCTest
@testable import TripTrack

/// Приватная зона у дома на ГРАНИЦЕ ОТПРАВКИ (0.8.2).
///
/// `PrivacyZoneTests` держит саму арифметику обрезки; здесь — две вещи, до
/// которых чистой функции не дотянуться: что обрезка стоит ровно в сборке
/// `TripSyncPayload` (и не трогает ни чисел поездки, ни базы), и что смена
/// зоны переотправляет уже опубликованное.
///
/// Хранилище у половины про переотправку ОБЩЕЕ (`PersistenceController
/// .shared`), а не изолированное in-memory, — вынужденно, ровно как у
/// `JourneyPublishTests`: гейт синка (`SyncEnqueuer.fetchTripEntity`) читает
/// его напрямую, и подменить это нечем. Строки заводятся руками и руками
/// убираются в `tearDown`.
@MainActor
final class HomePrivacyTrimTests: XCTestCase {

    private let home = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    private var store: PersistenceController!
    /// Сырые байты ключа `home.settings`, а не разобранный `HomeSettings`:
    /// «ключа не было вовсе» и «лежит умолчание» — разные состояния, и
    /// `save()` умолчания в tearDown завёл бы дом там, где его не заводили.
    private var homeDefaultsBefore: Data??
    private var cloudSyncBefore = false
    private var insertedTripIds: [UUID] = []

    override func setUp() {
        super.setUp()
        store = PersistenceController(inMemory: true)
        homeDefaultsBefore = .some(UserDefaults.standard.data(forKey: "home.settings"))
        cloudSyncBefore = SettingsManager.shared.cloudSyncEnabled
        SettingsManager.shared.cloudSyncEnabled = false
        SyncQueue.shared.clearAll()
        // Реального входа в аккаунт в юнит-тесте не поставить без живого
        // POST'а, поэтому подменяется гейт АВТОРИЗАЦИИ; гейты приватности и
        // черновика — те самые, что здесь и проверяются, — остаются
        // настоящими (тот же приём, что у `JourneyPublishTests`).
        SyncEnqueuer.isAuthorizedToEnqueue = { true }
    }

    override func tearDown() {
        // `SyncEnqueuer.enqueue` заводит `Task { processQueue() }`, и тот
        // проснётся уже ПОСЛЕ удаления строк ниже: «Mutating a managed object
        // after it has been removed from its context» — ровно тот хвост, что
        // роняет ЧУЖОЙ класс через полалфавита (CLAUDE.md, «Ловушки»). Один
        // виток главного цикла отдаётся ему, пока строки ещё живы.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let ctx = PersistenceController.shared.container.viewContext
        for id in insertedTripIds {
            let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first { ctx.delete(entity) }
        }
        try? ctx.save()
        insertedTripIds = []
        SyncQueue.shared.clearAll()
        SyncEnqueuer.isAuthorizedToEnqueue = { AuthService.shared.isSignedIn }
        SettingsManager.shared.cloudSyncEnabled = cloudSyncBefore
        if case let .some(stored) = homeDefaultsBefore {
            if let stored {
                UserDefaults.standard.set(stored, forKey: "home.settings")
            } else {
                UserDefaults.standard.removeObject(forKey: "home.settings")
            }
        }
        homeDefaultsBefore = nil
        // Невыпущенный in-memory стор тянет за собой описание `TripEntity` и
        // роняет ЧУЖОЙ класс через полалфавита — CLAUDE.md, «Ловушки».
        store = nil
        super.tearDown()
    }

    // MARK: Мелочь

    /// Смещение строго на север — широта без долготной поправки, число точное.
    private func north(_ metres: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: home.latitude + metres / 111_320.0,
                               longitude: home.longitude)
    }

    private func zoneOn(radius: HomeSettings.Radius = .block) {
        var settings = HomeSettings()
        settings.latitude = home.latitude
        settings.longitude = home.longitude
        settings.radius = radius
        settings.trimsPublicTracks = true
        settings.save()
    }

    private func zoneOff() {
        var settings = HomeSettings()
        settings.latitude = home.latitude
        settings.longitude = home.longitude
        settings.trimsPublicTracks = false
        settings.save()
    }

    /// Точка на `metres` к северу от дома, со своей высотой и временем: по ним
    /// потом видно, считались числа поездки по полному треку или по обрезку.
    private func point(_ metres: Double, at second: Double, altitude: Double) -> TrackPoint {
        let c = north(metres)
        return TrackPoint(latitude: c.latitude, longitude: c.longitude,
                          altitude: altitude, speed: 20,
                          timestamp: t0.addingTimeInterval(second))
    }

    /// Выезд со двора, круг и возвращение домой в середине: 50 м и 120 м
    /// лежат внутри квартала (500 м), остальное снаружи.
    private func driveThroughHome() -> [TrackPoint] {
        [
            point(50, at: 0, altitude: 900),
            point(1500, at: 30, altitude: 10),
            point(3000, at: 60, altitude: 20),
            point(120, at: 90, altitude: 950),
            point(2000, at: 120, altitude: 30),
        ]
    }

    private func payload(for trip: Trip) -> TripSyncPayload {
        let entity = TripEntity(context: store.container.viewContext)
        return TripSyncPayload(trip: trip, entity: entity)
    }

    // MARK: A. Обрезка на границе отправки

    /// Внутри круга — не уехало, снаружи — уехало, и превью режется тем же
    /// правилом: два носителя геометрии, один ответ.
    func testWithTheZoneOnOnlyThePointsOutsideItLeaveThePhone() {
        zoneOn()
        let points = driveThroughHome()
        let trip = Trip(id: UUID(), startDate: t0, trackPoints: points,
                        previewPolyline: Trip.encodePolyline(points.map(\.coordinate)))

        let p = payload(for: trip)

        let sent = try! XCTUnwrap(p.trackPoints)
        XCTAssertEqual(sent.count, 3, "три точки снаружи квартала обязаны уехать")
        for wire in sent {
            let c = CLLocationCoordinate2D(latitude: wire.latitude, longitude: wire.longitude)
            XCTAssertFalse(PrivacyZone.hides(c, centre: home, radius: 500),
                           "точка внутри зоны уехала с телефона")
        }

        let preview = Trip.decodePolyline(
            Data(base64Encoded: try! XCTUnwrap(p.previewPolyline))!)
        XCTAssertEqual(preview.count, 3, "превью обязано резаться тем же правилом")
        for c in preview {
            XCTAssertFalse(PrivacyZone.hides(c, centre: home, radius: 500),
                           "двор виден в превью — карточка в чужой ленте рисует именно его")
        }
    }

    /// Зоны нет — пейлоад обязан быть ПРЕЖНИМ, байт в байт.
    func testWithoutTheZoneTheWireIsExactlyWhatItWasBefore() throws {
        zoneOff()
        let points = driveThroughHome()
        let coords = points.map(\.coordinate)
        let trip = Trip(id: UUID(), startDate: t0, trackPoints: points,
                        previewPolyline: Trip.encodePolyline(coords))

        let p = payload(for: trip)

        XCTAssertEqual(try XCTUnwrap(p.trackPoints).count, points.count)
        XCTAssertEqual(p.previewPolyline, Trip.encodePolyline(coords).base64EncodedString(),
                       "превью без зоны уезжает ровно тем же base64, что лежит в базе")
    }

    /// Поездка ЦЕЛИКОМ внутри зоны уезжает без трека и без превью — а числа
    /// поездки при этом не меняются: они про саму поездку, а не про то, что
    /// видно чужим.
    func testATripEntirelyInsideTheZoneKeepsItsNumbersAndLosesItsTrack() throws {
        let inside = [
            point(10, at: 0, altitude: 800),
            point(60, at: 30, altitude: 810),
            point(120, at: 60, altitude: 815),
        ]
        let trip = Trip(id: UUID(), startDate: t0, endDate: t0.addingTimeInterval(60),
                        distance: 430, maxSpeed: 12, averageSpeed: 7,
                        trackPoints: inside, fuelUsed: 0.4, elevation: 15,
                        previewPolyline: Trip.encodePolyline(inside.map(\.coordinate)))

        zoneOff()
        let whole = payload(for: trip)
        zoneOn()
        let trimmed = payload(for: trip)

        XCTAssertEqual(try XCTUnwrap(trimmed.trackPoints).count, 0,
                       "пустой СПИСОК, а не `nil`: `nil` в проводе — «не трогать», "
                       + "и уже уехавший целиком трек остался бы на сервере навсегда")
        XCTAssertNotNil(trimmed.trackPoints, "ключ обязан приехать — он стирает серверный трек")
        XCTAssertNil(trimmed.previewPolyline)

        XCTAssertEqual(trimmed.distance, whole.distance)
        XCTAssertEqual(trimmed.maxSpeed, whole.maxSpeed)
        XCTAssertEqual(trimmed.averageSpeed, whole.averageSpeed)
        XCTAssertEqual(trimmed.elevation, whole.elevation)
        XCTAssertEqual(trimmed.maxAltitude, whole.maxAltitude,
                       "высоты считаются по ПОЛНОМУ треку, до обрезки")
        XCTAssertEqual(trimmed.drivingTime, whole.drivingTime)
        XCTAssertEqual(trimmed.stoppedTime, whole.stoppedTime)
    }

    /// Обрезка НЕ спрашивает `isPrivate`. Правило версии — «режется то, что
    /// уходит с телефона», а приватная поездка уходит на тот же сервер; и
    /// `unpublishAllPublicTrips` ставит `isPrivate = true` ПЕРЕД сборкой
    /// пейлоада, то есть на выходе из аккаунта обрезанный серверный трек
    /// заменился бы полным ровно тогда, когда человек просил спрятать.
    func testHidingATripDoesNotSendTheYardBackUp() throws {
        zoneOn()
        var trip = Trip(id: UUID(), startDate: t0, trackPoints: driveThroughHome())
        trip.isPrivate = true

        let p = payload(for: trip)

        XCTAssertEqual(try XCTUnwrap(p.trackPoints).count, 3)
    }

    // MARK: B. Переотправка уже опубликованного

    /// Заводит строку в ОБЩЕМ хранилище — иначе гейт синка её не увидит.
    @discardableResult
    private func insertTrip(isPrivate: Bool, onServer: Bool,
                            confirmation: TripConfirmation = .confirmed,
                            pointCount: Int = 4) -> UUID {
        let ctx = PersistenceController.shared.container.viewContext
        let entity = TripEntity(context: ctx)
        let id = UUID()
        entity.id = id
        entity.startDate = t0
        entity.endDate = t0.addingTimeInterval(600)
        entity.isPrivate = isPrivate
        entity.serverCreatedAt = onServer ? t0 : nil
        entity.confirmation = confirmation.rawValue
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.lastModifiedAt = t0
        for i in 0..<pointCount {
            let p = TrackPointEntity(context: ctx)
            p.id = UUID()
            p.latitude = home.latitude + Double(i) / 111_320.0 * 40
            p.longitude = home.longitude
            p.timestamp = t0.addingTimeInterval(Double(i) * 10)
            p.trip = entity
        }
        try? ctx.save()
        insertedTripIds.append(id)
        return id
    }

    private func queuedTripIds() -> [UUID] {
        SyncQueue.shared.pending
            .filter { $0.entityType == .trip && $0.action == .update }
            .map(\.entityId)
    }

    /// По операции на каждую ПУБЛИЧНУЮ поездку, лежащую на сервере. Ни одной
    /// на приватную, ни одной на черновик, ни одной на ту, которой на сервере
    /// ещё не было.
    func testResendQueuesOneUpdatePerPublishedTripAndNothingElse() {
        zoneOn()
        let publicA = insertTrip(isPrivate: false, onServer: true)
        let publicB = insertTrip(isPrivate: false, onServer: true)
        let privateOne = insertTrip(isPrivate: true, onServer: true)
        let draft = insertTrip(isPrivate: false, onServer: true, confirmation: .draft)
        let neverSent = insertTrip(isPrivate: false, onServer: false)

        let count = HomePrivacyResync.shared.resendPublishedTrips()

        let queued = queuedTripIds()
        XCTAssertEqual(count, 2, "в очередь идут ровно две публичные поездки")
        XCTAssertEqual(Set(queued), [publicA, publicB])
        XCTAssertEqual(queued.count, 2, "по ОДНОЙ операции на поездку, без дублей")
        XCTAssertFalse(queued.contains(privateOne), "приватную чужие глаза не видят")
        XCTAssertFalse(queued.contains(draft), "черновик не уходит на сервер ни при каком облаке")
        XCTAssertFalse(queued.contains(neverSent), "её первый апсерт уедет обрезанным сам")
    }

    /// Переотправка трогает ОТПРАВКУ, а не базу: локальный трек цел до точки.
    func testResendLosesNotASinglePointLocally() throws {
        zoneOn()
        let id = insertTrip(isPrivate: false, onServer: true, pointCount: 6)

        HomePrivacyResync.shared.resendPublishedTrips()

        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let entity = try XCTUnwrap(try ctx.fetch(req).first)
        XCTAssertEqual(entity.trackPoints?.count, 6,
                       "своя поездка на своём телефоне остаётся целой всегда")
        XCTAssertEqual(entity.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "без флага очередь синка её не увидит")
    }

    /// Уведомление — единственная связь листа настройки с очередью, и оно
    /// обязано доезжать.
    func testTheNotificationIsWhatStartsTheResend() {
        zoneOn()
        let id = insertTrip(isPrivate: false, onServer: true)
        let center = NotificationCenter()
        let resync = HomePrivacyResync(center: center)

        center.post(name: .homePrivacyZoneChanged, object: nil)
        // Подписка кладёт работу на главную очередь (`.receive(on:)`), поэтому
        // ждём один её виток: наша задача встанет в очередь ПОСЛЕ обработчика.
        let turned = expectation(description: "главная очередь провернулась")
        DispatchQueue.main.async { turned.fulfill() }
        wait(for: [turned], timeout: 2)

        XCTAssertTrue(SyncQueue.shared.pending.contains { $0.entityId == id },
                      "уведомление — единственная связь листа настройки с очередью")
        withExtendedLifetime(resync) {}
    }

    /// Координата КАДРА внутри зоны уезжать не должна: снимок во дворе несёт
    /// точку дома точнее любого трека, и по ней ставится булавка прямо на
    /// публичной карте поездки.
    func testPhotoExifInsideTheZoneNeverLeaves() {
        let home = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
        let zone: TripSyncPayload.Zone = (centre: home, radius: 500)
        let inside = TripSyncPayload.wireExif(45.036, 38.975, zone: zone)
        XCTAssertNil(inside, "кадр из двора уехал с координатой")

        let outside = TripSyncPayload.wireExif(45.2, 38.975, zone: zone)
        XCTAssertEqual(outside?.latitude, 45.2)
        XCTAssertEqual(outside?.longitude, 38.975)

        // Без зоны — как было, байт в байт.
        XCTAssertEqual(TripSyncPayload.wireExif(45.036, 38.975, zone: nil)?.latitude, 45.036)
        // Половина пары — это сломанная пара, а не «меньше данных».
        XCTAssertNil(TripSyncPayload.wireExif(45.036, nil, zone: zone))
        XCTAssertNil(TripSyncPayload.wireExif(nil, 38.975, zone: nil))
    }
}
