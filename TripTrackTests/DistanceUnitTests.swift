import XCTest
@testable import TripTrack

/// Арифметика `DistanceUnit` — калька `ConsumptionUnitTests`, и по той же
/// причине: единственная точка перевода в проекте обязана быть проверена
/// числами, а не глазами.
///
/// Половина этих тестов держит то, что НЕ меняется. Хранение и награды
/// остаются метрическими навсегда: опыт, уровень машины и бейджи считаются по
/// километрам при любой настройке, а лежат они в базе. Конвертированное число,
/// попавшее в награду, сдвинуло бы уровень у всех пользователей задним числом
/// — это единственная поломка версии, которую не чинит следующий релиз.
/// Поэтому «километры — это тождество» проверяется СТРОГИМ равенством: тест
/// обязан упасть, если однажды кто-нибудь «на всякий случай» переведёт и их.
final class DistanceUnitTests: XCTestCase {

    // MARK: - Контракт хранения

    /// `rawValue` — не подпись и не имя случая. Ровно эти две строки лежат в
    /// ключе `UserDefaults`, в колонке `UserSettingsEntity.distanceUnit` и в
    /// поле `SettingsSyncPayload.distanceUnit`. Переименование случая молча
    /// потеряет выбор человека и разойдётся с сервером.
    func testRawValuesAreTheStoredContract() {
        XCTAssertEqual(DistanceUnit.km.rawValue, "km")
        XCTAssertEqual(DistanceUnit.miles.rawValue, "miles")
        XCTAssertEqual(DistanceUnit(rawValue: "km"), .km)
        XCTAssertEqual(DistanceUnit(rawValue: "miles"), .miles)
        XCTAssertEqual(DistanceUnit.storageKey, "distanceUnit")
        XCTAssertEqual(SettingsManager.distanceUnitKey, DistanceUnit.storageKey)
    }

    /// Чужой клиент и будущая версия читаются как ничто, а не как мили.
    func testUnknownRawValueIsNotAUnit() {
        XCTAssertNil(DistanceUnit(rawValue: "kilometres"))
        XCTAssertNil(DistanceUnit(rawValue: ""))
        XCTAssertNil(DistanceUnit(rawValue: "MILES"))
    }

    // MARK: - Константы

    /// Международная миля определена ТОЧНО, и записана она точно: «1609» и
    /// «1.609» — это два разных приближения, которые разойдутся с сервером и
    /// друг с другом на длинной поездке.
    func testMileConstantIsExact() {
        XCTAssertEqual(DistanceUnit.metresPerMile, 1609.344)
        XCTAssertEqual(DistanceUnit.metresPerFoot, 0.3048)
    }

    // MARK: - Расстояние

    func testMetresBecomeMiles() {
        XCTAssertEqual(DistanceUnit.miles.distance(fromMetres: 1609.344), 1.0, accuracy: 1e-12)
        // Марафон: 42 195 м — это 26.2 мили, число, которое американец знает
        // лучше, чем 42,2.
        XCTAssertEqual(DistanceUnit.miles.distance(fromMetres: 42_195), 26.2188, accuracy: 0.0001)
        XCTAssertEqual(DistanceUnit.miles.distance(fromMetres: 100_000), 62.137, accuracy: 0.001)
    }

    /// Километр — это метры, делённые на тысячу, и ничего больше. Строгое
    /// равенство, без `accuracy`.
    func testKilometresAreExactlyMetresOverAThousand() {
        XCTAssertEqual(DistanceUnit.km.distance(fromMetres: 1234.5), 1.2345)
        XCTAssertEqual(DistanceUnit.km.distance(fromMetres: 0), 0)
        XCTAssertEqual(DistanceUnit.km.metres(fromDistance: 1.2345), 1234.5)
    }

    /// Ввёл пробег — вышел из поля — вернулся: должно стоять то же число.
    /// Ровно это делает поле пробега в паспорте машины на каждой смене
    /// единицы.
    func testRoundTripThroughMetresLosesNothing() {
        let metres: [Double] = [0, 1, 5, 400, 999.5, 1609.344, 12_345.6,
                                100_000, 987_654.321, 40_075_000]
        for unit in DistanceUnit.allCases {
            for m in metres {
                let back = unit.metres(fromDistance: unit.distance(fromMetres: m))
                XCTAssertEqual(back, m, accuracy: max(1e-9, abs(m) * 1e-12),
                               "\(m) м не пережили круг через \(unit.rawValue)")
            }
        }
    }

    /// Ноль остаётся нулём, знак сохраняется. Отрицательное расстояние —
    /// признак сломанного семпла, и превращать его в положительное значило бы
    /// прятать поломку внутри арифметики.
    func testZeroAndNegative() {
        for unit in DistanceUnit.allCases {
            XCTAssertEqual(unit.distance(fromMetres: 0), 0)
            XCTAssertEqual(unit.metres(fromDistance: 0), 0)
            XCTAssertLessThan(unit.distance(fromMetres: -5000), 0)
            XCTAssertEqual(unit.metres(fromDistance: unit.distance(fromMetres: -5000)),
                           -5000, accuracy: 1e-9)
        }
    }

    // MARK: - Скорость

    func testSpeed() {
        // Метр в секунду — это ровно 3.6 км/ч и 2.2369 mph.
        XCTAssertEqual(DistanceUnit.km.speed(fromMetresPerSecond: 1), 3.6)
        XCTAssertEqual(DistanceUnit.miles.speed(fromMetresPerSecond: 1), 2.23694, accuracy: 0.00001)
        // 100 км/ч = 62.1 mph — цифра с приборки.
        XCTAssertEqual(DistanceUnit.miles.speed(fromMetresPerSecond: 100 / 3.6),
                       62.137, accuracy: 0.001)
    }

    func testSpeedRoundTrip() {
        for unit in DistanceUnit.allCases {
            for ms in [0.0, 1.0, 5.5, 13.9, 27.8, 83.0] {
                let back = unit.metresPerSecond(fromSpeed: unit.speed(fromMetresPerSecond: ms))
                XCTAssertEqual(back, ms, accuracy: 1e-9,
                               "\(ms) м/с не пережили круг через \(unit.rawValue)")
            }
        }
    }

    // MARK: - Высота

    /// Метры при километрах не трогаются ВООБЩЕ — строгое равенство. Высота
    /// сегодня форматируется функцией про пробег (`GarageFormat.odometer`), и
    /// конверсия, встроенная туда, увезла бы её в мили ×0.621 молча.
    func testElevationInMetresIsIdentity() {
        for m in [0.0, 1.0, 640.0, 2_500.0, -12.0] {
            XCTAssertEqual(DistanceUnit.km.elevation(fromMetres: m), m)
        }
    }

    func testElevationInFeet() {
        XCTAssertEqual(DistanceUnit.miles.elevation(fromMetres: 0.3048), 1.0, accuracy: 1e-12)
        XCTAssertEqual(DistanceUnit.miles.elevation(fromMetres: 1000), 3280.84, accuracy: 0.01)
        XCTAssertEqual(DistanceUnit.miles.elevation(fromMetres: 640), 2099.74, accuracy: 0.01)
    }

    // MARK: - Расход

    /// Сотня миль длиннее сотни километров, поэтому литров на неё уходит
    /// БОЛЬШЕ. Сегодня выбор миль меняет подпись на «л/100 миль», а число
    /// оставляет километровым — это живой баг, а не новая работа.
    func testConsumptionGrowsWithTheLongerHundred() {
        XCTAssertEqual(DistanceUnit.miles.consumptionPer100(fromPer100Km: 8),
                       12.874752, accuracy: 1e-9)
        XCTAssertGreaterThan(DistanceUnit.miles.consumptionPer100(fromPer100Km: 8), 8)
    }

    func testConsumptionInKilometresIsIdentity() {
        for value in [0.0, 4.2, 7.8, 22.0] {
            XCTAssertEqual(DistanceUnit.km.consumptionPer100(fromPer100Km: value), value)
            XCTAssertEqual(DistanceUnit.km.per100Km(fromConsumptionPer100: value), value)
        }
    }

    func testConsumptionRoundTrip() {
        for unit in DistanceUnit.allCases {
            for value in [4.2, 7.8, 9.4, 22.0] {
                let back = unit.per100Km(fromConsumptionPer100: unit.consumptionPer100(fromPer100Km: value))
                XCTAssertEqual(back, value, accuracy: 1e-12)
            }
        }
    }

    // MARK: - Порог точности

    /// Точность обязана меняться на одном и том же ФИЗИЧЕСКОМ расстоянии, а не
    /// на числе, которое случайно читается как «10». Десять километров — это
    /// 6.2 мили.
    func testTenthsThresholdIsTheSameDistanceInBothUnits() {
        XCTAssertEqual(DistanceUnit.km.tenthsBelow, 10)
        XCTAssertEqual(DistanceUnit.miles.tenthsBelow, 6)
        let tenKilometresInMiles = DistanceUnit.miles.distance(fromMetres: 10_000)
        XCTAssertEqual(tenKilometresInMiles, DistanceUnit.miles.tenthsBelow, accuracy: 0.3,
                       "порог у миль обязан стоять там же, где километровый — около 6.2 мили")
    }

    // MARK: - Догадка по региону

    private func guess(_ region: String) -> DistanceUnit {
        DistanceUnit.guessFromRegion(Locale(identifier: "en_\(region)"))
    }

    /// Мильных стран три с половиной, и список закрыт.
    func testMilesAreGuessedForTheFourMileCountries() {
        XCTAssertEqual(guess("US"), .miles)
        XCTAssertEqual(guess("GB"), .miles)
        XCTAssertEqual(guess("LR"), .miles)  // Либерия
        XCTAssertEqual(guess("MM"), .miles)  // Мьянма
    }

    /// Здесь и живёт вся цена вопроса «регион, а не язык»: во всех четырёх
    /// странах ниже говорят по-английски, и все четыре метрические. Догадка по
    /// языку (`Language.locale` у нас прибит к `en_US`) объявила бы их
    /// мильными.
    func testEnglishSpeakingMetricCountriesStayMetric() {
        for region in ["AU", "CA", "IN", "IE", "NZ", "ZA"] {
            XCTAssertEqual(guess(region), .km, "\(region) метрическая")
        }
    }

    func testEveryoneElseIsMetric() {
        for region in ["RU", "DE", "FR", "KZ", "UA", "BR", "TR", "ID"] {
            XCTAssertEqual(guess(region), .km, "\(region)")
        }
    }

    /// Локаль без региона («en», «ru») — не повод угадывать: неизвестность
    /// читается как километры, ровно как неизвестное значение в хранилище.
    func testALocaleWithoutARegionIsMetric() {
        XCTAssertEqual(DistanceUnit.guessFromRegion(Locale(identifier: "en")), .km)
        XCTAssertEqual(DistanceUnit.guessFromRegion(Locale(identifier: "")), .km)
    }
}
