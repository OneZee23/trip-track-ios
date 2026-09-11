import XCTest
@testable import TripTrack

/// Расход — самое опасное место 0.6.7, потому что он завязан на ДВЕ единицы
/// сразу и расстояние входит в него множителем: 8 литров на сотню километров
/// и 8 литров на сотню миль — разные машины, разница в 1.609.
///
/// Этот тип уже однажды «расхвалил прожорливость»: прошлая версия экрана
/// подписала хранимые километровые числа словом «mpg», не переведя их, —
/// шкала у mpg идёт в другую сторону, и экономичная машина стала выглядеть
/// грузовиком. С тех пор он под тестами, и 0.6.7 переписывала его тестами
/// вперёд кода.
///
/// **Что изменила 0.6.7.** Диалект расхода перестал быть отдельной настройкой
/// и стал СЛЕДСТВИЕМ приборки: метрическая панель → литры на сотню
/// километров, мильная → мили на галлон. Отдельной галочкой он давал
/// комбинацию «литры на сотню МИЛЬ» — единицу, в которой не ездит никто, зато
/// число в ней молча другое. Теперь эта комбинация не выражается: `per100`
/// означает сотню километров и ничего больше.
final class VehicleConsumptionUnitTests: XCTestCase {

    // MARK: - Диалект выводится, а не выбирается

    func testTheDialectFollowsTheDashboardAndNothingElse() {
        XCTAssertEqual(ConsumptionUnit.forDashboard(.km), .per100)
        XCTAssertEqual(ConsumptionUnit.forDashboard(.miles), .mpg)
    }

    /// Оба сценария владельца, дословно: «у меня целиком по приложению я
    /// американец — у меня мили. При этом у меня тойота с литрами и
    /// километрами на приборке. И наоборот: в РФ американка с милями и
    /// галлонами».
    func testAnAmericanWithAMetricToyotaReadsLitresPerHundredKilometres() {
        let toyota = Vehicle(name: "Тойота", cityConsumption: 8, fuelPrice: 65,
                             dashboardUnits: .metric)
        let unit = toyota.consumptionUnit(app: .miles)

        XCTAssertEqual(unit, .per100)
        // Восемь остаются восемью: панель метрическая, и сотня в подписи —
        // сотня километров.
        XCTAssertEqual(unit.display(fromPer100: toyota.cityConsumption), 8)
        XCTAssertEqual(unit.volumeUnit, .liters)
        XCTAssertEqual(unit.displayPrice(fromPerLitre: toyota.fuelPrice), 65)
    }

    func testARussianWithAnAmericanCarReadsMilesPerGallon() {
        let mustang = Vehicle(name: "Мустанг", cityConsumption: 9.4, fuelPrice: 65,
                              dashboardUnits: .imperial)
        let unit = mustang.consumptionUnit(app: .km)

        XCTAssertEqual(unit, .mpg)
        XCTAssertEqual(unit.display(fromPer100: mustang.cityConsumption), 25.02, accuracy: 0.05)
        // Галлоны едут вместе с милями: «мили на галлон» и «рубли за литр» —
        // не набор единиц, которым кто-то пользуется.
        XCTAssertEqual(unit.volumeUnit, .gallons)
        XCTAssertEqual(unit.displayPrice(fromPerLitre: 65), 246.05, accuracy: 0.01)
    }

    /// Машина без выбора идёт за человеком — то же умолчание, что у всех
    /// заведённых до 0.6.7.
    func testAVehicleWithNoChoiceFollowsThePerson() {
        let plain = Vehicle(name: "Без выбора")

        XCTAssertEqual(plain.consumptionUnit(app: .km), .per100)
        XCTAssertEqual(plain.consumptionUnit(app: .miles), .mpg)
    }

    /// Две машины в одном гараже у одного человека печатаются РАЗНЫМИ
    /// единицами и хранят ОДНО И ТО ЖЕ. Ради этого вся версия.
    func testTwoCarsInOneGarageDisagreeOnScreenAndAgreeInStorage() {
        let toyota = Vehicle(name: "Тойота", cityConsumption: 9.4, dashboardUnits: .metric)
        let mustang = Vehicle(name: "Мустанг", cityConsumption: 9.4, dashboardUnits: .imperial)

        XCTAssertEqual(toyota.cityConsumption, mustang.cityConsumption)
        XCTAssertNotEqual(toyota.consumptionUnit(app: .km), mustang.consumptionUnit(app: .km))
        XCTAssertNotEqual(
            toyota.consumptionUnit(app: .km).display(fromPer100: 9.4),
            mustang.consumptionUnit(app: .km).display(fromPer100: 9.4))
    }

    // MARK: - Хранение не двигается

    /// Литры и деньги за поездку считаются от ХРАНИМЫХ чисел и про приборку
    /// не спрашивают: одна и та же дорога на двух одинаковых машинах с разными
    /// панелями стоит одинаково.
    func testTripFuelDoesNotMoveWithTheDashboard() {
        let metric = Vehicle(name: "A", cityConsumption: 9.4, highwayConsumption: 6.2,
                             fuelPrice: 65, dashboardUnits: .metric)
        let imperial = Vehicle(name: "B", cityConsumption: 9.4, highwayConsumption: 6.2,
                               fuelPrice: 65, dashboardUnits: .imperial)

        let a = metric.fuelCost(metres: 143_000, avgSpeedMS: 22)
        let b = imperial.fuelCost(metres: 143_000, avgSpeedMS: 22)

        XCTAssertEqual(a.liters, b.liters)
        XCTAssertEqual(a.cost, b.cost)
    }

    // MARK: - Британский микс не выражается

    /// Мили + литры + имперские мили на галлон — осознанный пропуск 0.6.7.
    ///
    /// Наш галлон американский ВЕЗДЕ (`litresPerGallon`, `mpgConstant`), и
    /// имперский молча разошёлся бы с полем цены: одно и то же слово «галлон»
    /// значило бы в расходе 4.546 л, а в цене 3.785. Поэтому мильная приборка
    /// даёт американский галлон и только его, а «британский микс» в 0.6.7 не
    /// делается вовсе — не как недоделка, а как решение.
    func testAMileDashboardMeansAmericanGallons() {
        XCTAssertEqual(ConsumptionUnit.forDashboard(.miles).volumeUnit, .gallons)
        XCTAssertEqual(ConsumptionUnit.forDashboard(.km).volumeUnit, .liters)
        // Что галлон именно американский по обе стороны экрана — держит
        // `ConsumptionUnitTests.testTheGallonIsAmericanOnBothSidesOfTheScreen`.
    }

    /// И сама комбинация «литры на сотню миль» больше не выражается: перевода
    /// расхода под единицу расстояния в `DistanceUnit` НЕТ. Сторож смотрит в
    /// исходник, потому что вернуть такую функцию — это одна строка, и
    /// собранное с ней приложение будет выглядеть работающим.
    func testTheLitresPerHundredMilesConversionIsGoneFromTheArithmetic() throws {
        let url = UnitGuard.repoRoot().appendingPathComponent("TripTrackShared/DistanceUnit.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let code = UnitGuard.strip(text).code.joined(separator: "\n")

        XCTAssertFalse(code.contains("consumptionPer100"),
                       "перевод расхода под единицу расстояния вернулся в общую арифметику")
        XCTAssertFalse(code.contains("per100Km"),
                       "перевод расхода под единицу расстояния вернулся в общую арифметику")
    }

    // MARK: - Глобальной настройки расхода больше нет

    /// Диалект расхода и объём топлива не имеют права спрашивать настройку
    /// человека: она одна на весь аккаунт, а машин в гараже несколько.
    ///
    /// Это чинит живой баг, у которого обе половины опасны. Прямая: экран
    /// поездки печатал объём по ГЛОБАЛЬНОМУ ключу мимо машины, и поездка на
    /// тойоте выходила в галлонах, если в гараже стояла американка. Обратная и
    /// худшая: сегмент «л/100 | mpg» на карточке КОНКРЕТНОЙ машины писал в ту
    /// же глобальную настройку — и она уезжала на сервер, переводя в галлоны
    /// весь аккаунт.
    func testNoVehicleScreenReadsTheAccountWideVolumeSetting() throws {
        var violations: [String] = []

        for path in Self.vehicleScreens {
            for (index, line) in try Self.code(of: path).enumerated() {
                for token in Self.accountWideTokens where line.contains(token) {
                    violations.append(
                        "\(path):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty,
                      "экран машины снова спрашивает настройку аккаунта:\n"
                      + violations.joined(separator: "\n"))
    }

    /// Сторож проверяет сам себя. Без этого он самый опасный вид зелёного:
    /// читает файлы, ничего не находит и выглядит работающим.
    func testTheVolumeGuardCatchesAPlantedLine() {
        let planted = UnitGuard.strip(
            #"""
            @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
            let dialect = vehicle.consumptionUnit(app: distanceUnit)
            """#).code

        XCTAssertTrue(Self.accountWideTokens.contains { planted[0].contains($0) },
                      "сторож не видит чтение настройки аккаунта")
        XCTAssertFalse(Self.accountWideTokens.contains { planted[1].contains($0) },
                       "сторож принял помашинный диалект за глобальную настройку")
    }

    /// Экраны, которым настройка аккаунта про объём топлива запрещена.
    private static let vehicleScreens = [
        "TripTrack/Models/ConsumptionUnit.swift",
        "TripTrack/Views/Trips/TripDetailView.swift",
        "TripTrack/Views/Profile/VehicleDetailView.swift",
        "TripTrack/Views/Garage/VehicleEditFormView.swift"
    ]

    /// Ровно те написания, которыми настройка аккаунта читалась и писалась до
    /// 0.6.7. Ключ — строковым ЛИТЕРАЛОМ: именно он делает чтение глобальным,
    /// а `ConsumptionUnit.volumeUnit` рядом — это ВЫВЕДЕННЫЙ объём этой машины,
    /// то самое, чем глобальный заменили.
    private static let accountWideTokens = [
        "\"volumeUnit\"", "setVolumeUnit",
        "ConsumptionUnit.current", "ConsumptionUnit.storageKey", "consumptionUnitRaw"
    ]

    private static func code(of path: String) throws -> [String] {
        let url = UnitGuard.repoRoot().appendingPathComponent(path)
        return UnitGuard.strip(try String(contentsOf: url, encoding: .utf8)).code
    }

    /// И у самого типа больше нет глобального умолчания, из которого его можно
    /// прочитать мимо машины: ни ключа в `UserDefaults`, ни `current`.
    func testTheDialectHasNoGlobalFallbackLeft() throws {
        let url = UnitGuard.repoRoot()
            .appendingPathComponent("TripTrack/Models/ConsumptionUnit.swift")
        let code = UnitGuard.strip(try String(contentsOf: url, encoding: .utf8)).code
            .joined(separator: "\n")

        XCTAssertFalse(code.contains("UserDefaults"),
                       "диалект расхода снова читается из настроек аккаунта")
        XCTAssertFalse(code.contains("storageKey"),
                       "у диалекта расхода снова появился ключ хранения")
    }
}
