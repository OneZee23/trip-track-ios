import XCTest
@testable import TripTrack

/// Тип двигателя: контракт строки, терпимость разбора и умолчание.
final class PowertrainTests: XCTestCase {

    // MARK: - Контракт строки

    /// `rawValue` — колонка в базе, поле провода и колонка сервера. Меняя их,
    /// меняешь показания у всех, кто уже выбрал тип, и на втором телефоне.
    /// Поэтому они записаны здесь буквально, а не выведены из `allCases`.
    func testRawValuesAreFrozen() {
        XCTAssertEqual(Powertrain.fuel.rawValue, "fuel")
        XCTAssertEqual(Powertrain.electric.rawValue, "electric")
        XCTAssertEqual(Powertrain.pluginHybrid.rawValue, "pluginHybrid")
        XCTAssertEqual(Powertrain.allCases.count, 3,
                       "появился четвёртый тип — проверь миграцию и сервер")
    }

    // MARK: - Разбор

    func testParseReadsKnownStrings() {
        XCTAssertEqual(Powertrain.parse("fuel"), .fuel)
        XCTAssertEqual(Powertrain.parse("electric"), .electric)
        XCTAssertEqual(Powertrain.parse("pluginHybrid"), .pluginHybrid)
    }

    /// Незнакомое слово и отсутствие ключа — одно и то же: «не сказано».
    /// Подставить сюда `.fuel` значило бы стереть человеку электромобиль
    /// входящим пулом с клиента, который знает четвёртый тип.
    func testParseAnswersNilToTheUnknown() {
        XCTAssertNil(Powertrain.parse(nil))
        XCTAssertNil(Powertrain.parse(""))
        XCTAssertNil(Powertrain.parse("hydrogen"))
        XCTAssertNil(Powertrain.parse("FUEL"))
    }

    // MARK: - Какие блоки показывать

    func testFuelVehicleHasFuelOnly() {
        XCTAssertTrue(Powertrain.fuel.usesFuel)
        XCTAssertFalse(Powertrain.fuel.usesElectricity)
        XCTAssertFalse(Powertrain.fuel.needsElectricRange)
    }

    func testElectricVehicleHasElectricityOnly() {
        XCTAssertFalse(Powertrain.electric.usesFuel)
        XCTAssertTrue(Powertrain.electric.usesElectricity)
        // Запас хода электромобилю для раскладки не нужен: всё расстояние
        // электрическое по определению.
        XCTAssertFalse(Powertrain.electric.needsElectricRange)
    }

    func testHybridHasBothAndTheRange() {
        XCTAssertTrue(Powertrain.pluginHybrid.usesFuel)
        XCTAssertTrue(Powertrain.pluginHybrid.usesElectricity)
        XCTAssertTrue(Powertrain.pluginHybrid.needsElectricRange)
    }

    // MARK: - Умолчание

    /// Ответ всех машин, заведённых до 0.8.3. Другое умолчание молча
    /// переписало бы показания половине гаражей.
    func testVehicleDefaultsToFuelAndEmptyNumbers() {
        let v = Vehicle()
        XCTAssertEqual(v.powertrain, .fuel)
        XCTAssertEqual(v.electricConsumption, 0)
        XCTAssertEqual(v.electricityPrice, 0)
        XCTAssertEqual(v.electricRangeKm, 0)
    }

    /// Машина, закодированная старой версией, не несёт этих ключей вовсе —
    /// и обязана раскодироваться, а не уронить весь гараж.
    func testDecodingAPayloadWithoutTheKeysKeepsTheVehicle() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Старая","avatarEmoji":"🚗",
         "type":"car","odometerKm":1000,"level":3,"stickers":[],
         "createdAt":0,"cityConsumption":9.5,"highwayConsumption":6.0,
         "fuelPrice":56,"plateVisible":false,"visibleToOthers":true,
         "about":"","make":"","model":"","year":0,"bodyType":""}
        """
        let v = try JSONDecoder().decode(Vehicle.self, from: Data(json.utf8))
        XCTAssertEqual(v.powertrain, .fuel)
        XCTAssertEqual(v.electricConsumption, 0)
        XCTAssertEqual(v.cityConsumption, 9.5, "старые поля пострадали от новых")
    }

    /// Незнакомый тип с будущего клиента не роняет разбор машины целиком —
    /// то же правило, что у `dashboardUnits` (там оно куплено падением).
    func testDecodingAnUnknownPowertrainDoesNotThrow() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Водородная","avatarEmoji":"🚗",
         "type":"car","odometerKm":0,"level":1,"stickers":[],
         "createdAt":0,"cityConsumption":9.5,"highwayConsumption":6.0,
         "fuelPrice":56,"plateVisible":false,"visibleToOthers":true,
         "powertrain":"hydrogen","electricConsumption":18,
         "about":"","make":"","model":"","year":0,"bodyType":""}
        """
        let v = try JSONDecoder().decode(Vehicle.self, from: Data(json.utf8))
        XCTAssertEqual(v.powertrain, .fuel, "незнакомое значение должно читаться как «топливо»")
        XCTAssertEqual(v.electricConsumption, 18, "соседнее поле потерялось вместе с типом")
    }

    // MARK: - Единица электричества у машины

    /// Функция ОТ единицы человека, а не чтение глобального выбора: сумме по
    /// нескольким машинам её нечем позвать.
    func testVehicleElectricUnitFollowsItsOwnDashboard() {
        var v = Vehicle()
        v.dashboardUnits = .metric
        XCTAssertEqual(v.electricUnit(app: .miles), .per100kWh)
        v.dashboardUnits = .imperial
        XCTAssertEqual(v.electricUnit(app: .km), .miPerKWh)
        v.dashboardUnits = .app
        XCTAssertEqual(v.electricUnit(app: .miles), .miPerKWh)
        XCTAssertEqual(v.electricUnit(app: .km), .per100kWh)
    }
}
