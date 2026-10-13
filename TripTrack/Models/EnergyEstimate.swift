import Foundation

/// Раскладка поездки: сколько на электричестве, сколько на топливе и во что это
/// обошлось.
///
/// **Чистая функция, и это главное решение 0.8.3.** Хранится только РЕЖИМ
/// поездки (`TripEnergyMode`); километры, киловатт-часы, литры и деньги
/// считаются при показе. Поэтому правка запаса хода или расхода мгновенно
/// пересчитывает всю историю — без миграции и без устаревших чисел в базе.
/// Ровно то же решение, что у сегодняшней оценки топлива
/// (`Vehicle.fuelCost`), и по той же причине: второй счёт однажды разошёлся бы
/// с первым, как расходились километры до `TripDistanceGate`.
///
/// **Вход в СИ.** Метры и метры в секунду — по той же защите, что у
/// `Vehicle.fuelCost`: километры и километры в час с 0.6.7 бывают милями и
/// милями в час, и подставленные сюда мили дали бы плюс шестьдесят процентов
/// энергии и денег без единой ошибки компилятора.
///
/// **До наград это не доходит никогда.** Опыт, уровень человека, уровень
/// машины и значки считают `Trip.rewardKm`; энергия к ним отношения не имеет и
/// в наградных файлах не упоминается — держит
/// `VehicleUnitsStayOutOfRewardsTests`.
struct EnergyEstimate: Equatable {
    /// Сколько метров поездки прошло на батарее.
    let electricMetres: Double
    /// Сколько метров прошло на топливе.
    let fuelMetres: Double
    /// Киловатт-часы. Ноль, если расход электричества у машины не задан.
    let kWh: Double
    /// Литры. Ноль, если расход топлива у машины не задан.
    let litres: Double
    /// Деньги за электричество. `nil` — цена киловатт-часа не задана, и это
    /// НЕ ноль: ноль значил бы «бесплатно», а мы просто не знаем.
    let electricCost: Double?
    /// Деньги за топливо. `nil` — цена литра не задана.
    let fuelCost: Double?

    /// Пустая раскладка: машина не назначена, расстояния нет, показывать нечего.
    static let none = EnergyEstimate(electricMetres: 0, fuelMetres: 0,
                                     kWh: 0, litres: 0,
                                     electricCost: nil, fuelCost: nil)

    /// Сумма того, у чего есть цена. `nil` — цены нет ни у одной ненулевой
    /// части, и плитки стоимости на экране не будет вовсе.
    var totalCost: Double? {
        switch (electricCost, fuelCost) {
        case let (e?, f?): return e + f
        case let (e?, nil): return e
        case let (nil, f?): return f
        case (nil, nil):   return nil
        }
    }

    // MARK: - Одна поездка

    /// Раскладка одной поездки.
    ///
    /// - Parameters:
    ///   - electricMetresUsedToday: сколько метров запаса хода эта машина уже
    ///     потратила в тот же календарный день ДО этой поездки. Считает
    ///     `day(vehicle:trips:)`; у машины на топливе и у электромобиля не
    ///     читается вовсе.
    static func resolve(vehicle: Vehicle,
                        metres: Double,
                        avgSpeedMS: Double,
                        mode: TripEnergyMode,
                        electricMetresUsedToday: Double = 0) -> EnergyEstimate {
        guard metres > 0 else { return .none }

        let electricMetres: Double
        switch vehicle.powertrain {
        case .fuel:
            electricMetres = 0
        case .electric:
            electricMetres = metres
        case .pluginHybrid:
            switch mode {
            case .electric:
                electricMetres = metres
            case .fuel:
                electricMetres = 0
            case .auto:
                // Заряд за ночь восстанавливает полный запас, значит первая
                // поездка утра начинает с полного. Запас 0 — «не задан» или
                // «не заряжаю»: вся поездка на топливе, и это честный ответ
                // гибриду, которого не заряжают.
                let rangeMetres = vehicle.electricRangeKm * 1000
                let left = max(0, rangeMetres - electricMetresUsedToday)
                electricMetres = min(left, metres)
            }
        }
        let fuelMetres = max(0, metres - electricMetres)

        // Киловатт-часы: расход хранится на сотню КИЛОМЕТРОВ, поэтому метры
        // делятся на тысячу и на сотню. Ноль расхода — ноль энергии, и плитки
        // на экране не будет: «не задано» не печатается как «0 кВт·ч».
        let kWh = electricMetres / 1000 / 100 * vehicle.electricConsumption

        // Топливная половина считает ПРЕЖНЯЯ функция и на своём куске
        // расстояния. Смесь город/трасса берётся от средней скорости ВСЕЙ
        // поездки: у нас нет способа узнать, на каком её участке работал
        // двигатель, а средняя скорость — то единственное, что описывает
        // характер поездки целиком.
        let fuel = vehicle.fuelCost(metres: fuelMetres, avgSpeedMS: avgSpeedMS)

        return EnergyEstimate(
            electricMetres: electricMetres,
            fuelMetres: fuelMetres,
            kWh: kWh,
            litres: fuel.liters,
            // Ноль цены — «не задана». Умножать на него и печатать ноль
            // значило бы обещать бесплатную зарядку.
            electricCost: vehicle.electricityPrice > 0 && kWh > 0
                ? kWh * vehicle.electricityPrice : nil,
            fuelCost: vehicle.fuelPrice > 0 && fuel.liters > 0 ? fuel.cost : nil)
    }

    // MARK: - День

    /// Раскладка всех поездок ОДНОЙ машины за ОДИН календарный день.
    ///
    /// Запас хода тратится по порядку старта, и каждая поездка тратит его
    /// СВОИМ режимом: «Электро» может выбрать его до нуля для соседей,
    /// «Топливо» не трогает вовсе. Поэтому раскладка дня сходится сама с
    /// собой, а не считается дважды с разных концов.
    ///
    /// Поездка через полночь целиком относится ко дню СТАРТА — день здесь
    /// вообще не вычисляется, его выбирает тот, кто набрал список.
    ///
    /// - Parameter trips: поездки одной машины одного дня, в любом порядке.
    static func day(vehicle: Vehicle, trips: [Trip]) -> [UUID: EnergyEstimate] {
        var used: Double = 0
        var result: [UUID: EnergyEstimate] = [:]
        for trip in trips.sorted(by: { $0.startDate < $1.startDate }) {
            let estimate = resolve(vehicle: vehicle,
                                   metres: trip.distance,
                                   avgSpeedMS: trip.averageSpeed,
                                   mode: trip.energyMode,
                                   electricMetresUsedToday: used)
            result[trip.id] = estimate
            used += estimate.electricMetres
        }
        return result
    }
}
