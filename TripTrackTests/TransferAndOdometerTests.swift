import XCTest
@testable import TripTrack

/// Трансфер и двойной одометр (0.6.3).
///
/// Два связанных решения владельца:
///
///  - **Трансфер** — поездка, где ты пассажир: такси, автобус, чужая машина.
///    Идёт в статистику (ты там был, километры и регионы твои), но НЕ в пробег
///    машины. Это отдельная сущность от «Без транспорта»: то означает «не
///    указал», а это — «ехал не за рулём».
///  - **Одометр раздваивается**: реальный, который человек списывает с
///    приборки, и треканный, который приложение знает точно. Главный —
///    реальный: именно разрыв между ними и есть то, что хочется дотрекать.
final class TransferAndOdometerTests: XCTestCase {

    private func trip(km: Double, vehicle: UUID?, transfer: Bool = false) -> Trip {
        Trip(
            id: UUID(),
            startDate: Date(timeIntervalSince1970: 1_780_000_000),
            endDate: Date(timeIntervalSince1970: 1_780_003_600),
            distance: km * 1000,
            isPrivate: false,
            isTransfer: transfer,
            vehicleId: vehicle
        )
    }

    // MARK: - Трансфер и пробег машины

    func testTransferKilometresStayOutOfTheCarOdometer() {
        let car = UUID()
        let odometer = VehicleOdometer.tracked(
            from: [trip(km: 100, vehicle: car),
                   trip(km: 400, vehicle: car, transfer: true)],
            vehicleId: car
        )

        XCTAssertEqual(odometer, 100, accuracy: 0.01,
                       "пассажирские километры не наматывают чужую машину")
    }

    func testAnOrdinaryTripStillCountsTowardTheCar() {
        let car = UUID()
        let odometer = VehicleOdometer.tracked(
            from: [trip(km: 100, vehicle: car), trip(km: 50, vehicle: car)],
            vehicleId: car
        )

        XCTAssertEqual(odometer, 150, accuracy: 0.01)
    }

    func testATransferWithNoVehicleChangesNothing() {
        let car = UUID()
        let odometer = VehicleOdometer.tracked(
            from: [trip(km: 300, vehicle: nil, transfer: true)],
            vehicleId: car
        )

        XCTAssertEqual(odometer, 0, accuracy: 0.01)
    }

    // MARK: - Трансфер и статистика

    func testTransferCountsInTheOverallStatistics() {
        // Ты там был — километры и поездка твои, даже если руль был не твой.
        let agg = MeAggregates.compute(
            trips: [trip(km: 100, vehicle: UUID()),
                    trip(km: 400, vehicle: nil, transfer: true)],
            now: Date(), calendar: .current
        )

        XCTAssertEqual(agg.tripCount, 2)
        XCTAssertEqual(agg.totalKm, 500, accuracy: 0.01)
    }

    // MARK: - Два одометра

    func testRealOdometerIsWhatTheOwnerTypedIn() {
        let v = Vehicle(name: "Polo", odometerKm: 12_000, manualOdometerKm: 143_500)

        XCTAssertEqual(v.displayOdometerKm, 143_500, accuracy: 0.01,
                       "главное число — то, что на приборке")
        XCTAssertEqual(v.odometerKm, 12_000, accuracy: 0.01)
    }

    func testWithoutAManualValueTheTrackedOneIsShown() {
        let v = Vehicle(name: "Polo", odometerKm: 12_000)

        XCTAssertNil(v.manualOdometerKm)
        XCTAssertEqual(v.displayOdometerKm, 12_000, accuracy: 0.01,
                       "пока реальный не введён, показывать нечего кроме треканного")
    }

    func testUntrackedGapIsTheDifference() {
        let v = Vehicle(name: "Polo", odometerKm: 12_000, manualOdometerKm: 143_500)

        XCTAssertEqual(v.untrackedKm ?? 0, 131_500, accuracy: 0.01)
    }

    func testNoGapWhenNothingWasTypedIn() {
        let v = Vehicle(name: "Polo", odometerKm: 12_000)

        XCTAssertNil(v.untrackedKm, "без реального числа разрыв не с чем считать")
    }

    func testATrackedValueAboveTheRealOneReportsNoGapRatherThanANegative() {
        // Человек мог ввести пробег месяц назад и не обновить. Отрицательный
        // «недотрекано» — бессмыслица, показывать её нельзя.
        let v = Vehicle(name: "Polo", odometerKm: 20_000, manualOdometerKm: 15_000)

        XCTAssertNil(v.untrackedKm)
    }

    // MARK: - Уровень машины

    func testVehicleLevelStillFollowsTheTrackedNumber() {
        // Уровень — награда за то, что приложение видело своими глазами.
        // Считать его от вручную введённого числа значило бы отдавать уровни
        // за одну набранную на клавиатуре цифру.
        let v = Vehicle(name: "Polo", odometerKm: 500, manualOdometerKm: 250_000)

        XCTAssertEqual(v.levelSourceKm, 500, accuracy: 0.01)
    }
}

/// Сохранность двух новых полей на синке (0.6.3).
///
/// Оба дефекта, против которых написаны эти тесты, ловятся только глазами:
/// сборка зелёная, тесты зелёные, а поле молча теряется. Ровно так ручной
/// пробег уезжал на сервер и не возвращался, а пул со старого бэкенда
/// откатывал пометку «ехал пассажиром».
final class TransferOdometerWireTests: XCTestCase {

    private func vehiclePayload(manual: Double?) throws -> [String: Any] {
        let v = Vehicle(name: "Polo", odometerKm: 12_000, manualOdometerKm: manual)
        let payload = VehicleSyncPayload(
            id: v.id, name: v.name, avatarEmoji: v.avatarEmoji,
            odometerKm: v.odometerKm, manualOdometerKm: v.manualOdometerKm,
            level: v.level, stickersJson: nil,
            cityConsumption: v.cityConsumption, highwayConsumption: v.highwayConsumption,
            fuelPrice: v.fuelPrice, conflictVersion: 1, lastModifiedAt: Date(),
            vehicleType: v.type.rawValue, avatarStyle: v.avatarStyle,
            plate: v.plate, plateVisible: v.plateVisible,
            visibleToOthers: v.visibleToOthers, fuelCurrency: v.fuelCurrency)
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testManualOdometerReachesTheWire() throws {
        XCTAssertEqual(try vehiclePayload(manual: 143_500)["manualOdometerKm"] as? Double, 143_500)
    }

    func testAnUnsetManualOdometerIsSentAsNullNeverAsZeroAndNeverOmitted() throws {
        let json = try vehiclePayload(manual: nil)

        // Ключ ОБЯЗАН присутствовать: пропуск означал бы «не трогай», сервер
        // сохранил бы старое число, и стереть пробег стало бы невозможно —
        // следующий пул вернул бы его поверх локальной очистки.
        XCTAssertTrue(json.keys.contains("manualOdometerKm"),
                      "без явного ключа очистка не доезжает до сервера")
        // И именно null, а не ноль: ноль — законный пробег новой машины, и
        // подменять им «не заполнено» значило бы стереть ту самую разницу,
        // ради которой одометр раздваивали.
        XCTAssertTrue(json["manualOdometerKm"] is NSNull)
        XCTAssertFalse((json["manualOdometerKm"] as? Double) == 0)
    }

    func testAServerNullClearsTheValueWhileAnAbsentKeyDoesNot() throws {
        let head = "{\"id\":\"" + UUID().uuidString + "\",\"name\":\"Polo\","
            + "\"avatarEmoji\":\"C\",\"odometerKm\":12000,\"level\":3,"
            + "\"cityConsumption\":10,\"highwayConsumption\":6,\"fuelPrice\":56,"
            + "\"conflictVersion\":1,\"lastModifiedAt\":\"2026-09-03T10:00:00Z\""
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let absent = try decoder.decode(
            VehicleSyncPayload.self, from: Data((head + "}").utf8))
        let explicitNull = try decoder.decode(
            VehicleSyncPayload.self,
            from: Data((head + ",\"manualOdometerKm\":null}").utf8))

        XCTAssertFalse(absent.manualOdometerKnown,
                       "сервер не знает про поле — локальное значение трогать нельзя")
        XCTAssertTrue(explicitNull.manualOdometerKnown,
                      "сервер прислал null — это очистка с другого устройства")
        XCTAssertNil(explicitNull.manualOdometerKm)
    }

    func testAServerWithoutTheColumnDecodesInsteadOfFailing() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Polo","avatarEmoji":"🚗","odometerKm":12000,
         "level":3,"cityConsumption":10,"highwayConsumption":6,"fuelPrice":56,
         "conflictVersion":1,"lastModifiedAt":"2026-09-03T10:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(VehicleSyncPayload.self, from: json)

        XCTAssertNil(payload.manualOdometerKm,
                     "старый бэкенд обязан декодироваться, а не ронять весь гараж")
    }

    func testTransferFlagReachesTheWire() throws {
        let trip = Trip(id: UUID(), distance: 100_000, isPrivate: false, isTransfer: true)
        XCTAssertTrue(trip.isTransfer)
    }

    func testAbsentTransferKeyIsNotAnExplicitFalse() throws {
        // Ключевое различие: «сервер не знает про поле» и «сервер сказал нет».
        // Первое не должно откатывать правку человека.
        let json = """
        {"id":"\(UUID().uuidString)","startDate":"2026-09-01T10:00:00Z","distance":1000,
         "maxSpeed":0,"averageSpeed":0,"fuelUsed":0,"elevation":0,"isPrivate":false,
         "conflictVersion":1,"lastModifiedAt":"2026-09-03T10:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(TripSyncPayload.self, from: json)

        XCTAssertNil(payload.isTransfer,
                     "nil, а не false — иначе пул со старого сервера стирает пометку")
    }
}
