import XCTest
@testable import TripTrack

/// Тумблеры видимости на ПРОВОДЕ (0.6.3).
///
/// `ProfileUpdateRequest` кодируется руками — свой `encode(to:)` и свой
/// `CodingKeys`, — потому что отсутствующее поле означает «не менять», и
/// автоматический синтез слал бы `null` там, где надо молчать. Цена этого
/// решения: **новое поле, не добавленное в оба списка, молча не уезжает.**
///
/// Ровно это и случилось при первом заходе: `setVisibility` отправлял пустой
/// объект, сервер отвечал 200 (все поля опциональны), клиент считал, что
/// сохранил, — и вся фича не работала при зелёной сборке и зелёных тестах.
/// Эти тесты существуют, чтобы такое не могло повториться молча.
final class VisibilityWireTests: XCTestCase {

    private func encoded(_ req: ProfileUpdateRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(req)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func empty() -> ProfileUpdateRequest {
        ProfileUpdateRequest(
            displayName: nil, avatarEmoji: nil, profileBackground: nil,
            profileLevel: nil, profileXp: nil, currentStreak: nil,
            bestStreak: nil, activeVehicleId: nil, language: nil,
            showOnPublicMap: nil)
    }

    // MARK: - Каждый флаг действительно уезжает

    func testCountersFlagReachesTheWire() throws {
        var req = empty()
        req.countersPublic = false

        let json = try encoded(req)

        XCTAssertEqual(json["countersPublic"] as? Bool, false)
    }

    func testStatsFlagReachesTheWire() throws {
        var req = empty()
        req.statsPublic = false

        XCTAssertEqual(try encoded(req)["statsPublic"] as? Bool, false)
    }

    func testMapFlagReachesTheWire() throws {
        var req = empty()
        req.mapPublic = false

        XCTAssertEqual(try encoded(req)["mapPublic"] as? Bool, false)
    }

    func testAchievementsFlagReachesTheWire() throws {
        var req = empty()
        req.achievementsPublic = false

        XCTAssertEqual(try encoded(req)["achievementsPublic"] as? Bool, false)
    }

    func testTrueIsSentAsTrueAndNotDroppedAsADefault() throws {
        var req = empty()
        req.mapPublic = true

        XCTAssertEqual(try encoded(req)["mapPublic"] as? Bool, true)
    }

    // MARK: - Молчание там, где надо молчать

    func testAnUntouchedFlagIsAbsentEntirely() throws {
        var req = empty()
        req.mapPublic = false

        let json = try encoded(req)

        // Отсутствие ключа = «не менять». `null` сервер прочитал бы как
        // указание, а PATCH с одним тумблером потушил бы остальные три.
        XCTAssertNil(json["statsPublic"])
        XCTAssertNil(json["countersPublic"])
        XCTAssertNil(json["achievementsPublic"])
    }

    func testAVisibilityPushCarriesNothingElse() throws {
        var req = empty()
        req.statsPublic = false

        let json = try encoded(req)

        // Сервер валидирует DTO целиком: лишнее поле в этом же запросе уронило
        // бы вместе с собой всё остальное — так в августе восемь аккаунтов
        // остались без имени.
        XCTAssertEqual(json.keys.sorted(), ["statsPublic"])
    }

    func testProfileSyncNeverShipsVisibilityFlags() throws {
        // Зеркало клиента, отправленное на каждой синхронизации профиля,
        // затирало бы серверные флаги. Их шлёт только явный тумблер.
        let json = try encoded(empty())

        XCTAssertNil(json["countersPublic"])
        XCTAssertNil(json["statsPublic"])
        XCTAssertNil(json["mapPublic"])
        XCTAssertNil(json["achievementsPublic"])
    }

    // MARK: - Гейт «сервер умеет эти флаги»

    func testFlagsAreUnknownWhenTheServerSendsNone() throws {
        // Бэкенд без фичи не шлёт ни одного ключа. Схлопнуть это в «всё
        // открыто» значит показать рабочие тумблеры там, где сохранять их
        // некуда, — тот же fake-succeed, ради которого заведён гейт у isPublic.
        let json = """
        {"id":"\(UUID().uuidString)","email":null,"displayName":"A","isPublic":true}
        """.data(using: .utf8)!

        let me = try JSONDecoder().decode(MeResponse.self, from: json)

        XCTAssertNil(ProfileVisibilityFlags(me))
    }

    func testFlagsAreKnownWhenTheServerSendsThem() throws {
        let json = """
        {"id":"\(UUID().uuidString)","email":null,"displayName":"A","isPublic":true,
         "countersPublic":true,"statsPublic":false,"mapPublic":true,"achievementsPublic":false}
        """.data(using: .utf8)!

        let me = try JSONDecoder().decode(MeResponse.self, from: json)
        let flags = try XCTUnwrap(ProfileVisibilityFlags(me))

        XCTAssertFalse(flags.stats)
        XCTAssertFalse(flags.achievements)
        XCTAssertTrue(flags.counters)
    }

    func testAPartialAnswerStillCountsAsSupportedAndFillsTheRestOpen() throws {
        // Сервер может научиться слать блок раньше, чем все четыре ключа.
        // Половина ответа — это поддержка, а не её отсутствие.
        let json = """
        {"id":"\(UUID().uuidString)","email":null,"displayName":"A","isPublic":true,
         "mapPublic":false}
        """.data(using: .utf8)!

        let me = try JSONDecoder().decode(MeResponse.self, from: json)
        let flags = try XCTUnwrap(ProfileVisibilityFlags(me))

        XCTAssertFalse(flags.map)
        XCTAssertTrue(flags.stats)
    }
}
