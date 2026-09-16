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

    // MARK: - Комсомольский в бандле

    /// Центр bbox микрорайона Комсомольский (Краснодар, OSM way/582275604) и
    /// его ячейка geohash-7. Число заморожено вместе с хешами: пересчитать
    /// его под новый контур значит объявить ненайденным то, что люди уже
    /// нашли.
    private static let komsomolskyCentreCell = "ub5b1y2"
    /// Ячеек покрытия — ровно столько же, сколько печатает бэкендовый
    /// `tools/secret-cells.ts --polygon` по ТОМУ ЖЕ контуру. Разойдясь, две
    /// стороны дадут секрет, который телефон находит, а сервер не
    /// подтверждает.
    private static let komsomolskyCellCount = 139

    func testBundledCatalogCarriesKomsomolsky() throws {
        let catalog = BundleSecretCatalog()
        XCTAssertEqual(catalog.salt, "tt-secrets-v1")
        let record = try XCTUnwrap(catalog.all().first { $0.id == "komsomolsky" })
        // Площадной: совпадение ячейки и есть находка, `reach` не участвует.
        XCTAssertTrue(record.polygon)
        XCTAssertEqual(record.reach, 0)
        XCTAssertGreaterThanOrEqual(record.hashes.count, Self.komsomolskyCellCount)
    }

    /// Хеш ячейки центра района лежит в бандле и считается той же функцией,
    /// какой его считал `Tools/build_secrets.py --authored`.
    func testCentreCellHashIsInTheBundle() throws {
        let catalog = BundleSecretCatalog()
        let record = try XCTUnwrap(catalog.all().first { $0.id == "komsomolsky" })
        let expected = SecretHash.truncated(salt: catalog.salt, geohash7: Self.komsomolskyCentreCell)
        XCTAssertEqual(expected, 3_577_933_936)
        XCTAssertTrue(record.hashes.contains(expected))
    }

    /// В бандле нет ни координаты, ни названия, ни истории — только `id`,
    /// хеши и форма записи. Проверка идёт по СЫРОМУ файлу, а не по
    /// разобранной записи: поле, добавленное мимо `SecretRecord`, разбор
    /// молча пропустил бы.
    func testBundledFileCarriesNothingButHashes() throws {
        let url = try XCTUnwrap(BundleSecretCatalog.bundledURL())
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let payload = try XCTUnwrap(raw as? [String: Any])
        let secrets = try XCTUnwrap(payload["secrets"] as? [[String: Any]])
        let entry = try XCTUnwrap(secrets.first { $0["id"] as? String == "komsomolsky" })
        XCTAssertEqual(Set(entry.keys), ["id", "hashes", "reach", "symbol", "polygon"])
        // Печать — гравюра Комсомольского, СТРОКОЙ: в дереве без неё запись
        // разбирается в `.generic`, и проверять разобранное значение здесь
        // нельзя — проверяется контракт файла.
        XCTAssertEqual(entry["symbol"] as? String, "seal.komsomolsky")
        XCTAssertEqual((entry["hashes"] as? [Int])?.count, Self.komsomolskyCellCount)
    }

    /// Незнакомая печать не роняет разбор ВСЕГО файла: иначе одна строка из
    /// следующей версии стирала бы с телефона все секреты сразу.
    func testUnknownSymbolFallsBackToGenericWithoutLosingTheRecord() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("secrets-\(UUID().uuidString).json")
        let payload: [String: Any] = [
            "v": 1, "salt": "tt-secrets-v1",
            "secrets": [
                ["id": "future", "hashes": [1], "reach": 0,
                 "symbol": "seal.not.drawn.yet", "polygon": true] as [String: Any],
                ["id": "komsomolsky", "hashes": [2], "reach": 0,
                 "symbol": "seal", "polygon": true] as [String: Any],
            ],
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let catalog = BundleSecretCatalog(url: url)
        XCTAssertEqual(catalog.all().count, 2)
        XCTAssertEqual(catalog.all().first?.symbol, .generic)
        XCTAssertTrue(catalog.all().first?.polygon ?? false)
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
