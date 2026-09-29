import XCTest
@testable import TripTrack

/// Раскладка поездки: километры, киловатт-часы, литры, деньги.
///
/// Табличный набор по §6 спеки. Главное, что он сторожит, — первый тест:
/// **машина на топливе не меняется ни на копейку.** Всё остальное в 0.8.3
/// добавлено, а эти числа существовали до неё и обязаны остаться теми же.
final class EnergyEstimateTests: XCTestCase {

    // MARK: - Машины стенда

    /// Обычная бензиновая: 10 л/100 в городе, 6 на трассе, 56 за литр.
    private func petrol() -> Vehicle {
        var v = Vehicle()
        v.powertrain = .fuel
        v.cityConsumption = 10
        v.highwayConsumption = 6
        v.fuelPrice = 56
        return v
    }

    /// Электромобиль: 18 кВт·ч/100 км, 8 за киловатт-час.
    private func electric() -> Vehicle {
        var v = Vehicle()
        v.powertrain = .electric
        v.electricConsumption = 18
        v.electricityPrice = 8
        // Топливные числа у электромобиля остаются в базе (их не стирает
        // смена типа), и раскладка обязана их игнорировать.
        v.cityConsumption = 10
        v.highwayConsumption = 6
        v.fuelPrice = 56
        return v
    }

    /// Плагин-гибрид: запас 50 км, 18 кВт·ч/100 км, плюс бензиновая половина.
    private func hybrid(rangeKm: Double = 50) -> Vehicle {
        var v = Vehicle()
        v.powertrain = .pluginHybrid
        v.electricConsumption = 18
        v.electricityPrice = 8
        v.electricRangeKm = rangeKm
        v.cityConsumption = 10
        v.highwayConsumption = 6
        v.fuelPrice = 56
        return v
    }

    /// Средняя скорость 30 км/ч — ровно городской конец смеси, доля трассы 0.
    private let cityMS: Double = 30 / 3.6

    // MARK: - Машина на топливе не меняется ни на копейку

    func testFuelVehicleReproducesTheOldNumbersExactly() {
        let v = petrol()
        let metres: Double = 42_000
        let old = v.fuelCost(metres: metres, avgSpeedMS: cityMS)
        let new = EnergyEstimate.resolve(vehicle: v, metres: metres,
                                         avgSpeedMS: cityMS, mode: .auto)

        XCTAssertEqual(new.litres, old.liters, accuracy: 1e-12, "литры разошлись со старым счётом")
        XCTAssertEqual(new.fuelCost ?? -1, old.cost, accuracy: 1e-12, "деньги разошлись со старым счётом")
        XCTAssertEqual(new.fuelMetres, metres)
        XCTAssertEqual(new.electricMetres, 0)
        XCTAssertEqual(new.kWh, 0)
        XCTAssertNil(new.electricCost, "у бензиновой машины появилась цена электричества")
    }

    /// Смесь город/трасса осталась прежней: на 80 км/ч и выше это полностью
    /// трассовый расход.
    func testFuelVehicleKeepsTheHighwayMix() {
        let v = petrol()
        let highwayMS: Double = 80 / 3.6
        let e = EnergyEstimate.resolve(vehicle: v, metres: 100_000,
                                       avgSpeedMS: highwayMS, mode: .auto)
        XCTAssertEqual(e.litres, 6, accuracy: 1e-9)
    }

    /// Режим поездки у машины на топливе не читается вовсе — он про гибрид.
    func testFuelVehicleIgnoresTheTripMode() {
        let v = petrol()
        for mode in TripEnergyMode.allCases {
            let e = EnergyEstimate.resolve(vehicle: v, metres: 10_000,
                                           avgSpeedMS: cityMS, mode: mode)
            XCTAssertEqual(e.electricMetres, 0, "режим \(mode) увёл бензин на батарею")
            XCTAssertEqual(e.fuelMetres, 10_000)
        }
    }

    // MARK: - Электромобиль

    func testElectricVehicleSpendsEverythingOnTheBattery() {
        let v = electric()
        let e = EnergyEstimate.resolve(vehicle: v, metres: 100_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertEqual(e.electricMetres, 100_000)
        XCTAssertEqual(e.fuelMetres, 0)
        XCTAssertEqual(e.kWh, 18, accuracy: 1e-9)
        XCTAssertEqual(e.electricCost ?? -1, 144, accuracy: 1e-9)
        XCTAssertEqual(e.litres, 0, "у электромобиля посчитались литры")
        XCTAssertNil(e.fuelCost, "у электромобиля появилась цена топлива")
    }

    func testElectricVehicleIgnoresTheTripMode() {
        let v = electric()
        for mode in TripEnergyMode.allCases {
            let e = EnergyEstimate.resolve(vehicle: v, metres: 10_000,
                                           avgSpeedMS: cityMS, mode: mode)
            XCTAssertEqual(e.electricMetres, 10_000, "режим \(mode) увёл электромобиль на топливо")
        }
    }

    // MARK: - Гибрид, режим «Авто»

    /// Первая поездка дня начинает с полного запаса: 30 км из 50 — вся на
    /// батарее.
    func testHybridFirstTripOfTheDayFitsInTheRange() {
        let e = EnergyEstimate.resolve(vehicle: hybrid(), metres: 30_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertEqual(e.electricMetres, 30_000)
        XCTAssertEqual(e.fuelMetres, 0)
        XCTAssertEqual(e.kWh, 5.4, accuracy: 1e-9)
        XCTAssertEqual(e.litres, 0)
        XCTAssertNil(e.fuelCost, "нулевой расход топлива не должен давать плитку стоимости")
    }

    /// Вторая поездка дня берёт ОСТАТОК: 20 км из 50 уже потрачено.
    func testHybridSecondTripTakesWhatIsLeft() {
        let e = EnergyEstimate.resolve(vehicle: hybrid(), metres: 45_000,
                                       avgSpeedMS: cityMS, mode: .auto,
                                       electricMetresUsedToday: 20_000)
        XCTAssertEqual(e.electricMetres, 30_000)
        XCTAssertEqual(e.fuelMetres, 15_000)
    }

    /// Поездка длиннее запаса: 300 км — 50 на батарее, 250 на топливе.
    /// Это приёмка «на устройстве» из §6 спеки, записанная числом.
    func testHybridTripLongerThanTheRangeSplitsAtTheRange() {
        let v = hybrid()
        let e = EnergyEstimate.resolve(vehicle: v, metres: 300_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertEqual(e.electricMetres, 50_000)
        XCTAssertEqual(e.fuelMetres, 250_000)
        XCTAssertEqual(e.kWh, 9, accuracy: 1e-9)
        // Топливо считается по СВОЕМУ куску, а не по всей поездке.
        XCTAssertEqual(e.litres, v.fuelCost(metres: 250_000, avgSpeedMS: cityMS).liters,
                       accuracy: 1e-12)
    }

    /// Запас выбран полностью — вся поездка на топливе, без отрицательных км.
    func testHybridWithTheRangeSpentRunsOnFuel() {
        let e = EnergyEstimate.resolve(vehicle: hybrid(), metres: 40_000,
                                       avgSpeedMS: cityMS, mode: .auto,
                                       electricMetresUsedToday: 90_000)
        XCTAssertEqual(e.electricMetres, 0)
        XCTAssertEqual(e.fuelMetres, 40_000)
    }

    /// Запас 0 — «не задан» или «не заряжаю». Честный ответ: всё на топливе.
    func testHybridWithoutARangeRunsOnFuel() {
        let e = EnergyEstimate.resolve(vehicle: hybrid(rangeKm: 0), metres: 40_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertEqual(e.electricMetres, 0)
        XCTAssertEqual(e.fuelMetres, 40_000)
        XCTAssertEqual(e.kWh, 0)
    }

    // MARK: - Гибрид, ручные режимы

    /// «Электро» побеждает запас: человек знает лучше, а настоящий запас
    /// гуляет с погодой и сезоном.
    func testHybridElectricModeIgnoresTheRange() {
        let e = EnergyEstimate.resolve(vehicle: hybrid(), metres: 300_000,
                                       avgSpeedMS: cityMS, mode: .electric,
                                       electricMetresUsedToday: 40_000)
        XCTAssertEqual(e.electricMetres, 300_000)
        XCTAssertEqual(e.fuelMetres, 0)
        XCTAssertEqual(e.litres, 0)
    }

    func testHybridFuelModeIgnoresTheRange() {
        let e = EnergyEstimate.resolve(vehicle: hybrid(), metres: 20_000,
                                       avgSpeedMS: cityMS, mode: .fuel)
        XCTAssertEqual(e.electricMetres, 0)
        XCTAssertEqual(e.fuelMetres, 20_000)
        XCTAssertEqual(e.kWh, 0)
    }

    // MARK: - День

    private func trip(_ minutesFromMidnight: Int, km: Double,
                      mode: TripEnergyMode = .auto) -> Trip {
        let midnight = Date(timeIntervalSince1970: 1_780_000_000)
        return Trip(startDate: midnight.addingTimeInterval(Double(minutesFromMidnight) * 60),
                    distance: km * 1000,
                    averageSpeed: cityMS,
                    energyMode: mode)
    }

    /// Запас тратится по порядку СТАРТА, а не по порядку в массиве.
    func testDaySpendsTheRangeInStartOrder() {
        let v = hybrid()
        let late = trip(600, km: 30)
        let early = trip(60, km: 30)
        let result = EnergyEstimate.day(vehicle: v, trips: [late, early])

        XCTAssertEqual(result[early.id]?.electricMetres, 30_000, "ранняя поездка не взяла запас первой")
        XCTAssertEqual(result[late.id]?.electricMetres, 20_000, "поздней достался не остаток")
        XCTAssertEqual(result[late.id]?.fuelMetres, 10_000)
    }

    /// Сумма электрических километров дня не больше запаса — пока никто не
    /// выбрал режим «Электро» руками.
    func testDayNeverSpendsMoreThanTheRangeOnAuto() {
        let v = hybrid()
        let trips = [trip(60, km: 20), trip(200, km: 20), trip(400, km: 20), trip(600, km: 20)]
        let result = EnergyEstimate.day(vehicle: v, trips: trips)
        let total = trips.compactMap { result[$0.id]?.electricMetres }.reduce(0, +)
        XCTAssertEqual(total, 50_000, accuracy: 1e-9)
    }

    /// Ранняя поездка «Электро» ВЫБИРАЕТ запас у соседей — в этом и состоит
    /// «раскладка дня сходится сама с собой».
    func testEarlyElectricTripEatsTheRangeForTheRest() {
        let v = hybrid()
        let first = trip(60, km: 80, mode: .electric)
        let second = trip(600, km: 30)
        let result = EnergyEstimate.day(vehicle: v, trips: [first, second])

        XCTAssertEqual(result[first.id]?.electricMetres, 80_000)
        XCTAssertEqual(result[second.id]?.electricMetres, 0, "запас не был выбран ранней поездкой")
        XCTAssertEqual(result[second.id]?.fuelMetres, 30_000)
    }

    /// Ранняя поездка «Топливо» запаса НЕ трогает.
    func testEarlyFuelTripLeavesTheRangeAlone() {
        let v = hybrid()
        let first = trip(60, km: 40, mode: .fuel)
        let second = trip(600, km: 30)
        let result = EnergyEstimate.day(vehicle: v, trips: [first, second])

        XCTAssertEqual(result[first.id]?.electricMetres, 0)
        XCTAssertEqual(result[second.id]?.electricMetres, 30_000, "запас куда-то делся")
    }

    /// Поездка через полночь целиком относится ко дню СТАРТА: день выбирает
    /// тот, кто набрал список, и функция его не пересчитывает.
    func testDayIsDecidedByTheCaller() {
        let v = hybrid()
        // Поездка стартовала в 23:30 и кончилась после полуночи — в списке
        // дня старта она одна, и запас у неё полный.
        let overnight = trip(23 * 60 + 30, km: 45)
        let result = EnergyEstimate.day(vehicle: v, trips: [overnight])
        XCTAssertEqual(result[overnight.id]?.electricMetres, 45_000)
    }

    // MARK: - Цена, которой нет

    /// Ноль цены — «не задана», а не «бесплатно». Плитки стоимости не будет.
    func testMissingElectricityPriceGivesNoCost() {
        var v = hybrid()
        v.electricityPrice = 0
        let e = EnergyEstimate.resolve(vehicle: v, metres: 30_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertEqual(e.kWh, 5.4, accuracy: 1e-9, "киловатт-часы пропали вместе с ценой")
        XCTAssertNil(e.electricCost)
        XCTAssertNil(e.totalCost, "поездка целиком на батарее без цены дала стоимость")
    }

    /// Цена есть только у одной части — в сумму идёт только она.
    func testOnlyThePricedPartCounts() {
        var v = hybrid()
        v.electricityPrice = 0
        let e = EnergyEstimate.resolve(vehicle: v, metres: 300_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertNil(e.electricCost)
        XCTAssertNotNil(e.fuelCost)
        XCTAssertEqual(e.totalCost, e.fuelCost)
    }

    func testBothPricesGiveTheSum() {
        let e = EnergyEstimate.resolve(vehicle: hybrid(), metres: 300_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertEqual(e.totalCost ?? -1,
                       (e.electricCost ?? 0) + (e.fuelCost ?? 0), accuracy: 1e-9)
    }

    /// Расход не задан — киловатт-часов ноль, и плитки не будет. «Не задано»
    /// не печатается как «0 кВт·ч».
    func testMissingConsumptionGivesNoEnergy() {
        var v = hybrid()
        v.electricConsumption = 0
        let e = EnergyEstimate.resolve(vehicle: v, metres: 30_000,
                                       avgSpeedMS: cityMS, mode: .auto)
        XCTAssertEqual(e.electricMetres, 30_000, "километры на батарее считаются и без расхода")
        XCTAssertEqual(e.kWh, 0)
        XCTAssertNil(e.electricCost)
    }

    // MARK: - Границы

    func testZeroDistanceGivesNothing() {
        XCTAssertEqual(EnergyEstimate.resolve(vehicle: hybrid(), metres: 0,
                                              avgSpeedMS: cityMS, mode: .auto),
                       .none)
    }

    /// Сумма частей всегда равна расстоянию поездки — иначе на экране
    /// появятся километры, которых человек не проезжал.
    func testPartsAlwaysAddUpToTheDistance() {
        let cases: [(Vehicle, TripEnergyMode, Double)] = [
            (petrol(), .auto, 12_345), (electric(), .auto, 12_345),
            (hybrid(), .auto, 12_345), (hybrid(), .auto, 120_000),
            (hybrid(), .electric, 120_000), (hybrid(), .fuel, 120_000),
            (hybrid(rangeKm: 0), .auto, 12_345),
        ]
        for (v, mode, metres) in cases {
            let e = EnergyEstimate.resolve(vehicle: v, metres: metres,
                                           avgSpeedMS: cityMS, mode: mode)
            XCTAssertEqual(e.electricMetres + e.fuelMetres, metres, accuracy: 1e-9,
                           "\(v.powertrain)/\(mode): части не сошлись с расстоянием")
        }
    }
}
