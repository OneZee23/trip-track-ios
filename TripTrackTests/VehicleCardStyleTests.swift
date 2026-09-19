import XCTest
@testable import TripTrack

/// Фон карточки машины (0.8.0, спека §2, пункт 3).
final class VehicleCardStyleTests: XCTestCase {

    func testEightStylesPlusNone() {
        XCTAssertEqual(VehicleCardStyle.allCases.filter(\.isPlus).count, 8)
        XCTAssertFalse(VehicleCardStyle.none.isPlus)
    }

    func testIdentifiersMatchTheServerWhitelist() {
        XCTAssertEqual(
            Set(VehicleCardStyle.allCases.filter(\.isPlus).map(\.rawValue)),
            ["card_carbon", "card_gold", "card_neon", "card_racing",
             "card_chrome", "card_matte", "card_camo", "card_sunset"]
        )
    }

    /// Незнакомая строка — обычная карточка, а не падение чужого гаража.
    func testUnknownRawValueDecodesToNone() {
        XCTAssertEqual(VehicleCardStyle.from("card_from_the_future"), VehicleCardStyle.none)
        XCTAssertEqual(VehicleCardStyle.from(nil), VehicleCardStyle.none)
        XCTAssertEqual(VehicleCardStyle.from(""), VehicleCardStyle.none)
        XCTAssertEqual(VehicleCardStyle.from("card_gold"), VehicleCardStyle.gold)
    }

    func testWithoutPlusEveryStyleRendersAsNone() {
        for style in VehicleCardStyle.allCases.filter(\.isPlus) {
            XCTAssertEqual(style.effective(isPlus: false), VehicleCardStyle.none, "\(style.rawValue)")
            XCTAssertEqual(style.effective(isPlus: true), style, "\(style.rawValue)")
        }
    }

    func testEveryStyleHasColours() {
        for style in VehicleCardStyle.allCases.filter(\.isPlus) {
            XCTAssertEqual(style.colors.count, 2, "\(style.rawValue)")
            XCTAssertFalse(style.displayName.isEmpty, "\(style.rawValue)")
        }
        XCTAssertTrue(VehicleCardStyle.none.colors.isEmpty)
    }

    /// Чужая машина везёт фон опциональным полем: старый сервер ключа не
    /// шлёт, и гараж обязан открыться.
    func testPublicVehicleDecodesWithoutCardStyle() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Land Cruiser","avatarEmoji":"🚙",
         "level":3,"odometerKm":142000}
        """
        let d = JSONDecoder()
        let v = try d.decode(PublicVehicle.self, from: Data(json.utf8))
        XCTAssertNil(v.cardStyle)
        XCTAssertEqual(VehicleCardStyle.from(v.cardStyle), VehicleCardStyle.none)
    }

    func testPublicVehicleReadsCardStyleWhenSent() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Land Cruiser","avatarEmoji":"🚙",
         "level":3,"odometerKm":142000,"cardStyle":"card_racing"}
        """
        let v = try JSONDecoder().decode(PublicVehicle.self, from: Data(json.utf8))
        XCTAssertEqual(VehicleCardStyle.from(v.cardStyle), VehicleCardStyle.racing)
    }
}
