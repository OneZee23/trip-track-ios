import XCTest
@testable import TripTrack

/// Авторские секреты: каталог и хеш ячейки.
///
/// Хеш — единственное, что уезжает в бандл: координаты секрета в приложении
/// нет вовсе, иначе список «найди сам» читался бы прямо из файла.
final class SecretCatalogTests: XCTestCase {

    /// Замороженный вектор. Его нельзя пересчитать под новый код: по этим
    /// числам сверяются секреты, уже найденные людьми, — как у
    /// `PlaceIdentityTests`.
    func testTruncatedHashIsFrozen() {
        XCTAssertEqual(SecretHash.truncated(salt: "tt-secrets-v1", geohash7: "ubcr4xk"),
                       2_566_105_652)
    }

    /// Первые ЧЕТЫРЕ байта SHA-256, big-endian, и никак иначе: перепутанный
    /// порядок байт даёт другое число на тех же данных и тихо ломает весь
    /// набор.
    func testHashIsTheFirstFourBytesBigEndian() {
        let value = SecretHash.truncated(salt: "tt-secrets-v1", geohash7: "ubcr4xk")
        XCTAssertEqual(String(format: "%08x", value), "98f3aa34")
    }

    func testSaltAndCellBothChangeTheHash() {
        let base = SecretHash.truncated(salt: "tt-secrets-v1", geohash7: "ubcr4xk")
        XCTAssertNotEqual(base, SecretHash.truncated(salt: "tt-secrets-v2", geohash7: "ubcr4xk"))
        XCTAssertNotEqual(base, SecretHash.truncated(salt: "tt-secrets-v1", geohash7: "ubcr4xm"))
    }

    /// В волне 2 список пуст — но соль уже та, с которой поедут хеши волны 5.
    func testBundledCatalogHasTheVersionOneSaltAndNoSecretsYet() {
        let catalog = BundleSecretCatalog()
        XCTAssertEqual(catalog.salt, "tt-secrets-v1")
        XCTAssertTrue(catalog.all().isEmpty)
    }

    func testCatalogReadsRecordsFromItsFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("secrets-\(UUID().uuidString).json")
        let payload: [String: Any] = [
            "v": 1, "salt": "tt-secrets-v1",
            "secrets": [
                ["id": "komsomolsky", "hashes": [2_566_105_652, 7],
                 "reach": 400, "symbol": "seal", "polygon": false] as [String: Any],
            ],
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let catalog = BundleSecretCatalog(url: url)
        XCTAssertEqual(catalog.salt, "tt-secrets-v1")
        XCTAssertEqual(catalog.all().count, 1)
        let record = try XCTUnwrap(catalog.all().first)
        XCTAssertEqual(record.id, "komsomolsky")
        XCTAssertEqual(record.hashes.first, 2_566_105_652)
        XCTAssertEqual(record.reach, 400)
        XCTAssertEqual(record.symbol, .generic)
        XCTAssertFalse(record.polygon)
    }

    /// Файла нет — пустой каталог с версионной солью, а не падение.
    func testMissingFileKeepsTheDefaultSalt() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-secrets-\(UUID().uuidString).json")
        let catalog = BundleSecretCatalog(url: url)
        XCTAssertEqual(catalog.salt, "tt-secrets-v1")
        XCTAssertTrue(catalog.all().isEmpty)
    }
}
