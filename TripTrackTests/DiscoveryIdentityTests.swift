import XCTest
import CoreLocation
@testable import TripTrack

/// Находка не синхронизируется (сервер — волна 3), поэтому её `id` обязан
/// выводиться из содержимого: два телефона одного человека, независимо
/// разобрав один и тот же трек, обязаны поставить ОДНУ печать. Векторы
/// заморожены — поменяется пространство имён, форма строки или алгоритм,
/// упадёт этот тест, а не разъедутся печати на двух телефонах.
final class DiscoveryIdentityTests: XCTestCase {

    func testIdIsDeterministicUUIDv5() {
        XCTAssertEqual(
            Discovery.id(kind: .secret, key: "komsomolsky").uuidString,
            "8A37654B-9D15-5AAB-92F6-ED2C3B8B4406"
        )
        XCTAssertEqual(
            Discovery.id(kind: .riddle, key: "lighthouse-anapa").uuidString,
            "08304055-7D26-538F-86AD-7659E445FE74"
        )
        XCTAssertEqual(
            Discovery.id(kind: .milestone, key: "above2000:2026-09-16").uuidString,
            "B9C27CE7-4F53-50E8-AA0A-4A8F87CA0A17"
        )
        XCTAssertEqual(Discovery.id(kind: .secret, key: "komsomolsky"),
                       Discovery.id(kind: .secret, key: "komsomolsky"))
    }

    /// Вид входит в строку, а не только ключ: секреты и загадки лежат в разных
    /// каталогах и однажды поделят одно имя.
    func testKindSeparatesKeys() {
        XCTAssertNotEqual(Discovery.id(kind: .riddle, key: "x"),
                          Discovery.id(kind: .secret, key: "x"))
        XCTAssertNotEqual(Discovery.id(kind: .milestone, key: "x"),
                          Discovery.id(kind: .secret, key: "x"))
    }

    /// Версия 5 и вариант RFC 4122 — по битам, а не по вере: id уедет на
    /// сервер в волне 3 и будет разобран чужим кодом.
    func testIdCarriesVersionAndVariantBits() {
        let bytes = withUnsafeBytes(of: Discovery.id(kind: .secret, key: "komsomolsky").uuid) { Array($0) }
        XCTAssertEqual(bytes[6] >> 4, 5)
        XCTAssertEqual(bytes[8] >> 6, 0b10)
    }

    /// Пространство имён заморожено НАВСЕГДА — та же клятва, что у `Place`.
    func testNamespaceIsFrozen() {
        XCTAssertEqual(Discovery.namespace.uuidString, "5A3C8B2E-7F10-4C6E-9D21-0E6B3A9F4C11")
    }

    /// Находка сама считает свой `id`: собрать её с чужим id нечем.
    func testDiscoveryDerivesItsOwnId() {
        let found = Discovery(
            kind: .riddle,
            key: "lighthouse-anapa",
            tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 44.894, longitude: 37.316),
            foundAt: Date(),
            symbol: .lighthouse,
            title: "Анапский маяк"
        )
        XCTAssertEqual(found.id, Discovery.id(kind: .riddle, key: "lighthouse-anapa"))
        XCTAssertFalse(found.verified)
    }

    /// Разбор ВОССТАНАВЛИВАЕТ id из ключа, а не верит присланному: чужой id
    /// разъехался бы с ключом, выведенный сходится по определению.
    func testDecodingRebuildsIdFromKey() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000000","kind":"riddle","key":"lighthouse-anapa",
         "tripId":"11111111-1111-1111-1111-111111111111","latitude":44.894,"longitude":37.316,
         "foundAt":0,"symbol":"light.beacon.max","verified":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Discovery.self, from: json)
        XCTAssertEqual(decoded.id, Discovery.id(kind: .riddle, key: "lighthouse-anapa"))
        XCTAssertEqual(decoded.coordinate.latitude, 44.894, accuracy: 0.0001)
        XCTAssertEqual(decoded.symbol, .lighthouse)
    }

    /// Круг «закодировать → разобрать» не теряет ни координату, ни имя.
    func testCodableRoundTrip() throws {
        let found = Discovery(
            kind: .milestone,
            key: "\(Milestone.easternmost.rawValue):2026-09-16",
            tripId: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: 43.0, longitude: 131.9),
            foundAt: Date(timeIntervalSince1970: 1_758_000_000),
            symbol: .extreme
        )
        let data = try JSONEncoder().encode(found)
        XCTAssertEqual(try JSONDecoder().decode(Discovery.self, from: data), found)
    }

    /// `rawValue` — контракт хранения: колонка в базе и половина ключа id.
    func testRawValuesAreStorageContract() {
        XCTAssertEqual(DiscoveryKind.secret.rawValue, "secret")
        XCTAssertEqual(DiscoveryKind.riddle.rawValue, "riddle")
        XCTAssertEqual(DiscoveryKind.milestone.rawValue, "milestone")
        XCTAssertEqual(SealSymbol.generic.rawValue, "seal")
        XCTAssertEqual(SealSymbol.allCases.count, 17)
        XCTAssertEqual(Milestone.allCases.count, 10)
        XCTAssertEqual(Milestone.above2000.rawValue, "above2000")
        XCTAssertEqual(Set(SealSymbol.allCases.map(\.rawValue)).count, SealSymbol.allCases.count)
    }
}
