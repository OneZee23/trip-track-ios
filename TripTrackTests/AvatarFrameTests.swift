import XCTest
@testable import TripTrack

/// Рамка аватара и значок «Плюс» (0.8.0, спека §2, пункт 2).
final class AvatarFrameTests: XCTestCase {

    func testSixFramesPlusNoFrame() {
        XCTAssertEqual(AvatarFrame.allCases.filter(\.isPlus).count, 6)
        XCTAssertFalse(AvatarFrame.none.isPlus)
    }

    /// Идентификаторы — контракт с сервером (белый список).
    func testIdentifiersMatchTheServerWhitelist() {
        XCTAssertEqual(
            Set(AvatarFrame.allCases.filter(\.isPlus).map(\.rawValue)),
            ["frame_gold", "frame_carbon", "frame_neon",
             "frame_chrome", "frame_laurel", "frame_flame"]
        )
    }

    /// Незнакомая строка — «без рамки», а не падение: пришедшая из будущей
    /// версии рамка не имеет права уронить чужой профиль.
    func testUnknownRawValueDecodesToNoFrame() {
        XCTAssertEqual(AvatarFrame.from("frame_from_the_future"), AvatarFrame.none)
        XCTAssertEqual(AvatarFrame.from(nil), AvatarFrame.none)
        XCTAssertEqual(AvatarFrame.from(""), AvatarFrame.none)
        XCTAssertEqual(AvatarFrame.from("frame_gold"), AvatarFrame.gold)
    }

    func testWithoutPlusEveryFrameRendersAsNone() {
        for frame in AvatarFrame.allCases.filter(\.isPlus) {
            XCTAssertEqual(frame.effective(isPlus: false), AvatarFrame.none, "\(frame.rawValue)")
            XCTAssertEqual(frame.effective(isPlus: true), frame, "\(frame.rawValue)")
        }
        XCTAssertEqual(AvatarFrame.effective(id: "frame_neon", isPlus: false), AvatarFrame.none)
        XCTAssertEqual(AvatarFrame.effective(id: "frame_neon", isPlus: true), AvatarFrame.neon)
    }

    func testEveryFrameHasColours() {
        for frame in AvatarFrame.allCases.filter(\.isPlus) {
            XCTAssertGreaterThanOrEqual(frame.colors.count, 3, "\(frame.rawValue)")
            XCTAssertFalse(frame.displayName.isEmpty, "\(frame.rawValue)")
        }
        XCTAssertTrue(AvatarFrame.none.colors.isEmpty)
    }

    // MARK: - Значок

    /// Таблица видимости значка. Своя карточка подчиняется тумблеру
    /// приватности, чужая — нет: прятать чужой значок своей настройкой
    /// приложение не имеет права.
    func testBadgeVisibilityTable() {
        // (isPlus, isOwn, showsOwnBadge) → показывать ли
        let table: [(Bool?, Bool, Bool, Bool)] = [
            (true,  false, true,  true),
            (true,  false, false, true),   // чужой значок тумблер не гасит
            (true,  true,  true,  true),
            (true,  true,  false, false),  // свой — гасит
            (false, false, true,  false),
            (false, true,  true,  false),
            (nil,   false, true,  false),  // «не сказано» — рисовать нечего
            (nil,   true,  true,  false),
        ]
        for (isPlus, isOwn, showsOwn, expected) in table {
            XCTAssertEqual(
                PlusBadgeVisibility.shows(isPlus: isPlus, isOwn: isOwn, showsOwnBadge: showsOwn),
                expected,
                "isPlus=\(String(describing: isPlus)) own=\(isOwn) toggle=\(showsOwn)")
        }
    }

    /// «Сервер молчит» — это «подписки нет», и одинаково для всех трёх
    /// косметик чужого профиля: фона, рамки и значка. Пока правило стояло
    /// трижды по месту, значок при `nil` гас, а фон и рамка показывались —
    /// то есть истёкший подписчик, у которого сервер не вычистил поле,
    /// оставался с премиум-фоном вопреки «Плюс кончился → бесплатное».
    func testServerSilenceMeansNoPlusForEveryCosmetic() {
        XCTAssertFalse(PlusBadgeVisibility.saysPlus(nil))
        XCTAssertFalse(PlusBadgeVisibility.saysPlus(false))
        XCTAssertTrue(PlusBadgeVisibility.saysPlus(true))

        let silent = PlusBadgeVisibility.saysPlus(nil)
        XCTAssertEqual(
            ProfileBackground.effective(id: "plus_gold", isPlus: silent), .none)
        XCTAssertEqual(
            AvatarFrame.effective(id: "frame_gold", isPlus: silent), AvatarFrame.none)
        XCTAssertFalse(
            PlusBadgeVisibility.shows(isPlus: nil, isOwn: false, showsOwnBadge: true))

        // А сказанное «да» одинаково зажигает все три.
        let said = PlusBadgeVisibility.saysPlus(true)
        XCTAssertEqual(
            ProfileBackground.effective(id: "plus_gold", isPlus: said), .plusGold)
        XCTAssertEqual(
            AvatarFrame.effective(id: "frame_gold", isPlus: said), AvatarFrame.gold)
        XCTAssertTrue(
            PlusBadgeVisibility.shows(isPlus: true, isOwn: false, showsOwnBadge: true))
    }

    /// Автор в ленте и в комментариях — один и тот же DTO, и косметика в нём
    /// опциональна: старый сервер ключей не шлёт, и разбор обязан пройти.
    func testAuthorDecodesWithoutThePlusKeys() throws {
        let json = """
        {"id":"\(UUID().uuidString)","displayName":"A","avatarEmoji":"🚗","profileLevel":4}
        """
        let author = try JSONDecoder().decode(SocialAuthor.self, from: Data(json.utf8))
        XCTAssertNil(author.isPlus)
        XCTAssertNil(author.avatarFrame)

        let withPlus = """
        {"id":"\(UUID().uuidString)","displayName":"A","avatarEmoji":"🚗",
         "profileLevel":4,"isPlus":true,"avatarFrame":"frame_gold"}
        """
        let plus = try JSONDecoder().decode(SocialAuthor.self, from: Data(withPlus.utf8))
        XCTAssertEqual(plus.isPlus, true)
        XCTAssertEqual(AvatarFrame.from(plus.avatarFrame), AvatarFrame.gold)
    }
}
