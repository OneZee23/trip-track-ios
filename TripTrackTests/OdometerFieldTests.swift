import XCTest
@testable import TripTrack

/// Поле ручного пробега — единственный вход, где ошибка с единицей попадает
/// В БАЗУ и не чинится следующим релизом.
///
/// Всё остальное в 0.6.7 — показ: напечатали не то, поправили, перепечатали.
/// Здесь человек списывает число с приборной панели, и оно уезжает в
/// `VehicleEntity.manualOdometerKm`, на сервер и на второй телефон. Разобранное
/// не в той единице, оно уже неотличимо от настоящего: экран при открытии
/// переведёт его обратно тем же коэффициентом и покажет ровно то, что набрали.
/// Приложение ни разу себе не противоречит — заметить нечем.
///
/// Ровно так 0.6.7 и сломала бы гараж, если бы остановилась на «единице
/// человека»: у американца с тойотой поле разбирало бы километровую панель как
/// мили, и 142 000 уезжали бы в базу как 228 527. Поэтому разбор вынесен из
/// экрана сюда, чистой функцией: правило обязан держать тест, а не открытая
/// форма на телефоне.
final class OdometerFieldTests: XCTestCase {

    // MARK: - Тот самый сценарий владельца

    /// «У меня целиком по приложению я американец — у меня мили. При этом у
    /// меня тойота с литрами и километрами на приборке».
    ///
    /// Человек набирает 142000, глядя на панель. В базу обязаны уехать
    /// 142 000 КИЛОМЕТРОВ — то есть ровно то, что он видит, — а не 228 527,
    /// которые получились бы из разбора по единице приложения.
    func testAnAmericanTypingAMetricToyotaDashboardStoresKilometres() {
        let toyota = Vehicle(name: "Тойота", dashboardUnits: .metric)
        let unit = toyota.dashboardUnit(app: .miles)

        XCTAssertEqual(OdometerField.storedKm("142000", unit: unit), 142_000)
        // Именно та цифра, которой быть не должно: разбор по единице
        // приложения. Названа вслух, чтобы тест падал узнаваемо.
        XCTAssertNotEqual(OdometerField.storedKm("142000", unit: unit),
                          OdometerField.storedKm("142000", unit: .miles))
    }

    /// И обратный: «в РФ американка с милями и галлонами». 88 235 на мильной
    /// панели — это 142 000 км в базе.
    func testARussianTypingAnImperialDashboardStoresTheSameCar() {
        let mustang = Vehicle(name: "Мустанг", dashboardUnits: .imperial)
        let unit = mustang.dashboardUnit(app: .km)

        XCTAssertEqual(try XCTUnwrap(OdometerField.storedKm("88235", unit: unit)),
                       142_000, accuracy: 1)
    }

    /// Машина без выбора («как в приложении») ведёт себя ровно как до 0.6.7:
    /// что человек выбрал себе, в том и поле. Это и есть смысл умолчания —
    /// миграция никому не меняет показания.
    func testAVehicleWithNoChoiceFollowsThePerson() {
        let plain = Vehicle(name: "Без выбора")

        XCTAssertEqual(OdometerField.storedKm("142000", unit: plain.dashboardUnit(app: .km)),
                       142_000)
        XCTAssertEqual(try XCTUnwrap(
            OdometerField.storedKm("142000", unit: plain.dashboardUnit(app: .miles))),
                       228_527, accuracy: 1)
    }

    // MARK: - Разбор

    func testKilometresGoInUntouched() {
        XCTAssertEqual(OdometerField.storedKm("0", unit: .km), 0)
        XCTAssertEqual(OdometerField.storedKm("38420", unit: .km), 38_420)
    }

    func testMilesBecomeKilometres() {
        XCTAssertEqual(try XCTUnwrap(OdometerField.storedKm("1", unit: .miles)),
                       1.609344, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(OdometerField.storedKm("62137", unit: .miles)),
                       100_000, accuracy: 1)
    }

    /// Пустое поле — это «не вводили», а не ноль. Ноль стёр бы разрыв
    /// «недотрекано» у человека, который просто очистил строку, чтобы
    /// перенабрать.
    func testAnEmptyFieldIsNotZero() {
        XCTAssertNil(OdometerField.storedKm("", unit: .km))
        XCTAssertNil(OdometerField.storedKm("   ", unit: .miles))
    }

    /// Не-число не должно превратиться в ноль: `Double("12ab")` и так `nil`,
    /// но правило записано, потому что поле фильтрует ввод отдельно от разбора.
    func testJunkParsesToNothing() {
        XCTAssertNil(OdometerField.storedKm("—", unit: .km))
        XCTAssertNil(OdometerField.storedKm("12 000", unit: .km))
    }

    // MARK: - Показ

    /// Обратная половина: километры из базы → то, что стоит в поле.
    func testFieldTextSpeaksTheDashboard() {
        XCTAssertEqual(OdometerField.fieldText(km: 142_000, unit: .km), "142000")
        XCTAssertEqual(OdometerField.fieldText(km: 142_000, unit: .miles), "88235")
        XCTAssertEqual(OdometerField.fieldText(km: nil, unit: .km), "")
    }

    /// Круг «база → поле → база» не обязан сходиться до километра (в поле
    /// целые мили), но обязан сходиться до единицы показа. Больше — значит
    /// поле разбирается не тем, чем печатается, и каждое открытие формы
    /// двигало бы пробег.
    func testRoundTripStaysWithinOneUnitOfDisplay() throws {
        for unit in DistanceUnit.allCases {
            for km in [0.0, 1.0, 38_420.0, 100_000.0, 142_000.0, 999_999.0] {
                let back = try XCTUnwrap(
                    OdometerField.storedKm(OdometerField.fieldText(km: km, unit: unit), unit: unit))
                XCTAssertEqual(back, km, accuracy: unit.metres(fromDistance: 1) / 1000,
                               "\(km) км не пережили круг через \(unit.rawValue)")
            }
        }
    }

    /// Именно поэтому форма сравнивает СТРОКИ, а не километры, решая
    /// «менялось ли»: у миль круг не сходится сам с собой на единицы
    /// километров, и сравнение чисел объявляло бы пробег изменившимся при
    /// каждом сохранении — лишняя запись и лишняя операция в очереди синка.
    func testTheMileRoundTripDoesNotComeBackBitwise() throws {
        let shown = OdometerField.fieldText(km: 100_000, unit: .miles)
        let back = try XCTUnwrap(OdometerField.storedKm(shown, unit: .miles))

        XCTAssertNotEqual(back, 100_000)
        XCTAssertEqual(back, 100_000, accuracy: 2)
    }
}
