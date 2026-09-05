import XCTest
@testable import TripTrack

/// Поля паспорта на ПРОВОДЕ.
///
/// Тесты существуют ради одного класса ошибки, который в этом проекте
/// повторился дважды: клиент шлёт поле, сервер его не знает и молча
/// выбрасывает — сборка зелёная, лог пустой, а человек видит, что настройка
/// «не сохранилась». Так три релиза врал тумблер видимости машины, и так же
/// терялись силуэт и тип при переустановке.
///
/// Здесь проверяется обе половины провода: что поле УХОДИТ и что оно
/// ПРИМЕНЯЕТСЯ, — и отдельно, что молчание сервера не считается ответом.
final class VehiclePassportWireTests: XCTestCase {

    private func encode(_ p: VehicleSyncPayload) throws -> [String: Any] {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(p)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sample(
        about: String? = "Первая своя",
        make: String? = "Volkswagen",
        model: String? = "Polo",
        year: Int? = 2019,
        bodyType: String? = "car",
        mapVisible: Bool? = true,
        photosVisible: Bool? = false,
        isArchived: Bool? = false,
        soldAt: Date? = nil
    ) -> VehicleSyncPayload {
        VehicleSyncPayload(
            id: UUID(), name: "Полторашка", avatarEmoji: "🚗", odometerKm: 143_500,
            level: 12, stickersJson: nil, cityConsumption: 10, highwayConsumption: 6,
            fuelPrice: 56, conflictVersion: 1, lastModifiedAt: Date(),
            about: about, make: make, model: model, year: year, bodyType: bodyType,
            mapVisible: mapVisible, photosVisible: photosVisible,
            isArchived: isArchived, soldAt: soldAt
        )
    }

    // MARK: - Уходит

    func testEveryPassportFieldReachesTheWire() throws {
        let json = try encode(sample())
        for key in ["about", "make", "model", "year", "bodyType",
                    "mapVisible", "photosVisible", "isArchived"] {
            XCTAssertNotNil(json[key], "поле «\(key)» не уходит на сервер")
        }
        XCTAssertEqual(json["make"] as? String, "Volkswagen")
        XCTAssertEqual(json["year"] as? Int, 2019)
    }

    /// Ложь тоже обязана уезжать. `false` — это ответ человека («фотографии
    /// не показывать»), а не отсутствие ответа, и выбросить его как «пустое»
    /// значит открыть то, что просили закрыть.
    func testFalseIsSentAndNotDroppedAsEmpty() throws {
        let json = try encode(sample(mapVisible: false, photosVisible: false))
        XCTAssertEqual(json["mapVisible"] as? Bool, false)
        XCTAssertEqual(json["photosVisible"] as? Bool, false)
    }

    /// А вот `nil` уезжать НЕ должен: он означает «клиент про поле молчит»,
    /// и сервер обязан оставить сохранённое.
    func testNilFieldsAreOmittedRatherThanSentAsNull() throws {
        let json = try encode(sample(about: nil, make: nil, model: nil, year: nil,
                                     bodyType: nil, mapVisible: nil,
                                     photosVisible: nil, isArchived: nil))
        for key in ["about", "make", "model", "year", "bodyType",
                    "mapVisible", "photosVisible", "isArchived"] {
            XCTAssertNil(json[key], "«\(key)» уехал ключом, хотя клиенту нечего сказать")
        }
    }

    // MARK: - Возвращается

    func testPassportSurvivesTheRoundTrip() throws {
        let original = sample(about: "Отцовская", make: "Toyota", model: "Land Cruiser 200",
                              year: 2014, bodyType: "crossover",
                              mapVisible: false, photosVisible: true, isArchived: true)
        let data = try { () -> Data in
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
            return try e.encode(original)
        }()
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let back = try d.decode(VehicleSyncPayload.self, from: data)

        XCTAssertEqual(back.about, "Отцовская")
        XCTAssertEqual(back.make, "Toyota")
        XCTAssertEqual(back.model, "Land Cruiser 200")
        XCTAssertEqual(back.year, 2014)
        XCTAssertEqual(back.bodyType, "crossover")
        XCTAssertEqual(back.mapVisible, false)
        XCTAssertEqual(back.photosVisible, true)
        XCTAssertEqual(back.isArchived, true)
    }

    /// Сервер, который про паспорт не знает, обязан декодироваться — иначе
    /// один старый инстанс роняет весь гараж, а не одно поле.
    func testAServerWithoutPassportColumnsStillDecodes() throws {
        let old = """
        {"id":"\(UUID().uuidString)","name":"Нива","avatarEmoji":"🚙",
         "odometerKm":38400,"level":22,"cityConsumption":10,
         "highwayConsumption":6,"fuelPrice":56,"conflictVersion":3,
         "lastModifiedAt":"2026-09-04T00:00:00Z"}
        """
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let p = try d.decode(VehicleSyncPayload.self, from: Data(old.utf8))

        XCTAssertEqual(p.name, "Нива")
        // Всё паспортное — `nil`, то есть «сервер молчит». Именно nil, а не
        // умолчание: умолчание затёрло бы то, что человек настроил локально.
        XCTAssertNil(p.about)
        XCTAssertNil(p.make)
        XCTAssertNil(p.mapVisible)
        XCTAssertNil(p.photosVisible)
        XCTAssertNil(p.isArchived)
    }

    // MARK: - Силуэт и тип: те, что терялись молча

    func testSilhouetteAndTypeAreOnTheWire() throws {
        let p = VehicleSyncPayload(
            id: UUID(), name: "Пчела", avatarEmoji: "🏍", odometerKm: 4100,
            level: 7, stickersJson: nil, cityConsumption: 10, highwayConsumption: 6,
            fuelPrice: 56, conflictVersion: 1, lastModifiedAt: Date(),
            vehicleType: "moto", avatarStyle: "motorcycle"
        )
        let json = try encode(p)
        XCTAssertEqual(json["vehicleType"] as? String, "moto",
                       "тип не уходит — после переустановки мотоцикл станет легковушкой")
        XCTAssertEqual(json["avatarStyle"] as? String, "motorcycle",
                       "силуэт не уходит — вся фича 0.6.2 не переживает смену устройства")
    }
}
