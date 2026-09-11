import XCTest
import CoreData
@testable import TripTrack

/// Тест, который нельзя не написать.
///
/// Расстояние входит в НАГРАДЫ — опыт, значки, уровень машины, — а опыт и
/// уровень лежат В БАЗЕ. Конвертированное число, попавшее в наградное место,
/// сдвинет их у всех задним числом: американец, переключивший единицы, получил
/// бы «марафон» на сорока двух милях, а его машина потеряла бы треть уровня.
/// Это единственная поломка версии 0.6.7, которую НЕ чинит следующий релиз —
/// откатывать нечего, цифры уже переписаны в хранилище.
///
/// Поэтому здесь проверяется ровно одно свойство и в самой грубой форме,
/// какая возможна: выбрать мили, посчитать награды, выбрать километры,
/// посчитать снова — числа обязаны совпасть побитово.
///
/// Ключ единицы правится в общем `UserDefaults.standard`, потому что именно
/// оттуда его читает `DistanceUnit.current`, и подменить хранилище у наградного
/// кода нечем. Прежнее значение снимается в `setUp` и возвращается в
/// `tearDown` — иначе тест уносит с собой настройку соседа по прогону.
final class ScoringStaysMetricTests: XCTestCase {

    private var savedUnit: String?
    private var pc: PersistenceController!
    private var defaults: UserDefaults!
    private let suiteName = "ScoringStaysMetricTests"

    override func setUp() {
        super.setUp()
        savedUnit = UserDefaults.standard.string(forKey: DistanceUnit.storageKey)
        pc = PersistenceController(inMemory: true)
        UserDefaults.standard.removeObject(forKey: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: DistanceUnit.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: DistanceUnit.storageKey)
        }
        savedUnit = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        pc = nil
        super.tearDown()
    }

    private func select(_ unit: DistanceUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: DistanceUnit.storageKey)
        XCTAssertEqual(DistanceUnit.current, unit, "выбор единицы не доехал до чтения")
    }

    /// Двести километров — не круглое число «побольше», а сам порог бонуса
    /// ×2. В милях это 124.3, то есть ниже порога: если бы награда считалась
    /// по показанному числу, двойной опыт исчез бы именно здесь.
    private func longTrip() -> Trip {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return Trip(
            startDate: start,
            endDate: start.addingTimeInterval(3 * 3600),
            distance: 200_000,
            maxSpeed: 33,
            averageSpeed: 18.5,
            region: "Krasnodar Krai"
        )
    }

    // MARK: - Опыт

    func testTripXPIsTheSameInBothUnits() {
        let trip = longTrip()

        select(.km)
        let inKm = GamificationManager(persistenceController: pc, defaults: defaults)
            .calculateXP(for: trip, allTrips: [trip])

        select(.miles)
        let inMiles = GamificationManager(persistenceController: pc, defaults: defaults)
            .calculateXP(for: trip, allTrips: [trip])

        XCTAssertEqual(inKm.total, inMiles.total,
                       "опыт за одну и ту же поездку разошёлся: \(inKm.total) против \(inMiles.total)")
        XCTAssertEqual(inKm.base, 200, "база — километр за километр, при любой настройке")
        XCTAssertEqual(inMiles.base, 200)
        XCTAssertEqual(inMiles.longTripBonus, 200,
                       "бонус за 200 км обязан сработать и у того, кто смотрит в милях")
    }

    // MARK: - Значки

    func testMarathonUnlocksAtTheSameDistanceInBothUnits() {
        // 42.2 км: марафон взят. В милях это 26.2 — если бы порог сравнивался с
        // показанным числом, значок бы не выдался.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(
            startDate: start,
            endDate: start.addingTimeInterval(2600),
            distance: 42_200,
            maxSpeed: 30,
            averageSpeed: 16
        )

        select(.km)
        let kmIds = Set(BadgeManager.unlockedBadges(
            for: BadgeManager.computeStats(from: [trip])).map(\.id))

        select(.miles)
        let mileIds = Set(BadgeManager.unlockedBadges(
            for: BadgeManager.computeStats(from: [trip])).map(\.id))

        XCTAssertTrue(kmIds.contains("marathon_42"), "марафон не выдан в километрах")
        XCTAssertEqual(kmIds, mileIds,
                       "набор значков зависит от настройки показа: \(kmIds.symmetricDifference(mileIds))")
    }

    func testBadgeStatsAreIdenticalInBothUnits() {
        let trips = [longTrip()]

        select(.km)
        let a = BadgeManager.computeStats(from: trips)
        select(.miles)
        let b = BadgeManager.computeStats(from: trips)

        XCTAssertEqual(a.totalDistanceKm, b.totalDistanceKm, accuracy: 0.000_1)
        XCTAssertEqual(a.longestTripKm, b.longestTripKm, accuracy: 0.000_1)
        XCTAssertEqual(a.maxSpeedKmh, b.maxSpeedKmh, accuracy: 0.000_1)
        XCTAssertEqual(a.totalDistanceKm, 200, accuracy: 0.000_1,
                       "порог значков считается в километрах, а не в том, что выбрано")
    }

    // MARK: - Уровень машины

    func testVehicleLevelIsTheSameInBothUnits() {
        let vehicleId = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trips = (0..<6).map { i in
            Trip(
                id: UUID(),
                startDate: start.addingTimeInterval(Double(i) * 86_400),
                endDate: start.addingTimeInterval(Double(i) * 86_400 + 3600),
                distance: 100_000,
                vehicleId: vehicleId
            )
        }

        select(.km)
        let kmOdometer = VehicleOdometer.tracked(from: trips, vehicleId: vehicleId)
        let kmLevel = VehicleLevelSystem.level(for: kmOdometer)

        select(.miles)
        let mileOdometer = VehicleOdometer.tracked(from: trips, vehicleId: vehicleId)
        let mileLevel = VehicleLevelSystem.level(for: mileOdometer)

        XCTAssertEqual(kmOdometer, mileOdometer, accuracy: 0.000_1,
                       "одометр машины поехал вслед за настройкой показа")
        XCTAssertEqual(kmOdometer, 600, accuracy: 0.000_1)
        XCTAssertEqual(kmLevel, mileLevel, "уровень машины зависит от выбранной единицы")
        // 600 км — четвёртый уровень (50·L·(L−1): 0 / 100 / 300 / 600).
        XCTAssertEqual(kmLevel, 4)
    }

    /// Наградное начисление ЦЕЛИКОМ, а не по кускам.
    ///
    /// Предыдущие тесты спрашивают составные части — опыт, одометр, уровень —
    /// у тех функций, которые их считают. Но в базу они попадают не оттуда, а
    /// из `processCompletedTrip`: это он складывает опыт с прежним, пишет
    /// `profileXP`, прибавляет километры к `VehicleEntity.odometerKm` и ставит
    /// новый уровень машины. Ровно эти четыре числа лежат в базе, и ровно их
    /// нельзя починить следующим релизом.
    ///
    /// Поэтому здесь дверь, а не её створки: если однажды кто-то добавит в
    /// этот метод пятое наградное число и посчитает его показанным, ни один
    /// тест выше не покраснеет.
    func testTripCompletionWritesTheSameRewardsInBothUnits() {
        let trip = longTrip()

        func complete(_ unit: DistanceUnit) -> (TripCompletionData, Double, Int) {
            select(unit)
            let ctx = pc.container.viewContext
            let settings = UserSettingsEntity(context: ctx)
            settings.profileXP = 1_000
            settings.profileLevel = 3
            let vehicle = VehicleEntity(context: ctx)
            vehicle.id = UUID()
            vehicle.name = "Car"
            vehicle.odometerKm = 500
            vehicle.vehicleLevel = 3
            let gm = GamificationManager(persistenceController: pc, defaults: defaults)
            let data = gm.processCompletedTrip(
                trip: trip, allTrips: [trip],
                settingsEntity: settings, vehicleEntity: vehicle)
            let odometer = vehicle.odometerKm
            let level = Int(vehicle.vehicleLevel)
            ctx.delete(settings)
            ctx.delete(vehicle)
            return (data, odometer, level)
        }

        let (km, kmOdometer, kmVehicleLevel) = complete(.km)
        let (mi, miOdometer, miVehicleLevel) = complete(.miles)

        XCTAssertEqual(km.xpEarned, mi.xpEarned, "опыт за поездку поехал вслед за настройкой")
        XCTAssertEqual(km.newXP, mi.newXP, "записанный в базу опыт зависит от единицы")
        XCTAssertEqual(km.newLevel, mi.newLevel, "уровень водителя зависит от единицы")
        XCTAssertEqual(kmOdometer, miOdometer, accuracy: 0.000_1,
                       "одометр машины в базе поехал вслед за настройкой")
        XCTAssertEqual(kmVehicleLevel, miVehicleLevel, "уровень машины зависит от единицы")

        // Абсолютные числа, чтобы тест падал ДВАЖДЫ на подмене: 200 км дают
        // 200 базовых + 200 бонусом за длинную + 20 за первую в дне + 50 за
        // новый регион + 100 за регион к базе. В милях это 124.3 — и база, и
        // бонус, и уровень машины стали бы другими.
        XCTAssertEqual(km.xpEarned, 570)
        XCTAssertEqual(kmOdometer, 700, accuracy: 0.000_1)
        // 700 км — пятый уровень (50·L·(L−1): 0 / 100 / 300 / 600 / 1000 —
        // то есть 700 всё ещё четвёртый).
        XCTAssertEqual(kmVehicleLevel, 4)
    }

    /// Пересчёт одометра в репозитории — второе место, где живёт то же число.
    /// Разойтись им нельзя: оба пишут в `VehicleEntity.odometerKm`, под которым
    /// лежит уровень.
    func testRepositoryOdometerRecomputeIsMetric() {
        let ctx = pc.container.viewContext
        let vehicleId = UUID()
        let vehicle = VehicleEntity(context: ctx)
        vehicle.id = vehicleId
        vehicle.name = "Car"
        vehicle.odometerKm = 0
        vehicle.vehicleLevel = 1

        for i in 0..<6 {
            let t = TripEntity(context: ctx)
            t.id = UUID()
            t.startDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400)
            t.endDate = t.startDate?.addingTimeInterval(3600)
            t.distance = 100_000
            t.vehicleId = vehicleId
            t.isTransfer = false
        }
        try? ctx.save()

        let repo = CoreDataTripRepository(persistenceController: pc)

        select(.miles)
        repo.recomputeOdometers(forVehicles: [vehicleId])
        let inMiles = (vehicle.odometerKm, vehicle.vehicleLevel)

        select(.km)
        repo.recomputeOdometers(forVehicles: [vehicleId])
        let inKm = (vehicle.odometerKm, vehicle.vehicleLevel)

        XCTAssertEqual(inMiles.0, inKm.0, accuracy: 0.000_1)
        XCTAssertEqual(inMiles.1, inKm.1)
        XCTAssertEqual(inKm.0, 600, accuracy: 0.000_1,
                       "одометр обязан остаться километровым при любой настройке")
    }

    // MARK: - Граница показа

    /// Обратная половина того же свойства: показ ОБЯЗАН отличаться. Иначе
    /// «награды метрические» было бы легко получить, просто не переведя ничего.
    func testDisplayDoesChangeWhileScoringDoesNot() {
        let trip = longTrip()
        let km = Measure.distance(metres: trip.distance, unit: .km, lang: .en, style: .grouped)
        let miles = Measure.distance(metres: trip.distance, unit: .miles, lang: .en, style: .grouped)
        XCTAssertEqual(km, "200 km")
        XCTAssertEqual(miles, "124 mi")
        XCTAssertEqual(trip.scoringKm, 200, accuracy: 0.000_1,
                       "scoringKm — метры делить на тысячу, и ничего больше")
    }
}
