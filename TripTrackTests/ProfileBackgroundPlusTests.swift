import XCTest
@testable import TripTrack

/// Премиум-фоны профиля (0.8.0, спека §2, пункт 1).
///
/// Главное, что здесь сторожится, — НЕ количество вариантов, а правило «когда
/// «Плюс» кончился»: выбор в базе остаётся, а рисуется бесплатное. Правило
/// живёт в одном резолвере (`ProfileBackground.effective`), потому что мест
/// показа три — герой «Я», «Мой профиль», чужой профиль, — и своим `if` в
/// каждом оно однажды разошлось бы на одном из них.
final class ProfileBackgroundPlusTests: XCTestCase {

    func testElevenFreeBackgroundsAndEightPlusOnes() {
        let free = ProfileBackground.allCases.filter { !$0.isPlus }
        let plus = ProfileBackground.allCases.filter(\.isPlus)

        // Одиннадцать бесплатных — это «без фона» плюс десять пресетов,
        // ровно те, что были до 0.8.0.
        XCTAssertEqual(free.count, 11)
        XCTAssertEqual(plus.count, 8)
        XCTAssertTrue(free.contains(.none))
        XCTAssertFalse(ProfileBackground.none.isPlus)
    }

    /// Идентификаторы — контракт с сервером: он их белым списком проверяет и
    /// незнакомое отбрасывает. Записаны буквально, чтобы переименование
    /// кейса не увезло фон у всех, кто его выбрал.
    func testPlusIdentifiersMatchTheServerWhitelist() {
        XCTAssertEqual(
            Set(ProfileBackground.allCases.filter(\.isPlus).map(\.rawValue)),
            ["plus_nebula", "plus_lava", "plus_glacier", "plus_neon",
             "plus_carbon", "plus_gold", "plus_tropic", "plus_storm"]
        )
    }

    /// Бесплатные идентификаторы не тронуты 0.8.0: у людей они уже лежат в
    /// базе и на сервере.
    func testFreeIdentifiersAreUnchanged() {
        XCTAssertEqual(
            Set(ProfileBackground.allCases.filter { !$0.isPlus }.map(\.rawValue)),
            ["", "sunset", "ocean", "forest", "mountain", "midnight",
             "dawn", "copper", "slate", "aurora", "sand"]
        )
    }

    func testWithoutPlusAPremiumBackgroundRendersAsNone() {
        for bg in ProfileBackground.allCases.filter(\.isPlus) {
            XCTAssertEqual(bg.effective(isPlus: false), .none, "\(bg.rawValue)")
            XCTAssertEqual(bg.effective(isPlus: true), bg, "\(bg.rawValue)")
        }
    }

    /// Бесплатный фон не зависит от подписки ни в одну сторону.
    func testFreeBackgroundsIgnorePlus() {
        for bg in ProfileBackground.allCases.filter({ !$0.isPlus }) {
            XCTAssertEqual(bg.effective(isPlus: false), bg)
            XCTAssertEqual(bg.effective(isPlus: true), bg)
        }
    }

    func testUnknownIdentifierIsNoBackground() {
        XCTAssertEqual(ProfileBackground.effective(id: "plus_from_the_future", isPlus: true), .none)
        XCTAssertEqual(ProfileBackground.effective(id: nil, isPlus: true), .none)
        XCTAssertEqual(ProfileBackground.effective(id: "", isPlus: true), .none)
    }

    /// Строковый вход и разобранный обязаны отвечать одинаково — иначе два
    /// места показа, зовущие разные перегрузки, разъедутся.
    func testStringAndValueResolversAgree() {
        XCTAssertEqual(
            ProfileBackground.effective(id: "plus_gold", isPlus: false),
            ProfileBackground.plusGold.effective(isPlus: false))
        XCTAssertEqual(
            ProfileBackground.effective(id: "plus_gold", isPlus: true),
            ProfileBackground.plusGold.effective(isPlus: true))
    }

    /// У фона, который что-то рисует, обязан быть градиент: пустой список у
    /// непустого варианта — прозрачный баннер, то есть молчаливая дыра.
    func testEveryPremiumBackgroundHasColours() {
        for bg in ProfileBackground.allCases.filter(\.isPlus) {
            XCTAssertGreaterThanOrEqual(bg.gradient.count, 2, "\(bg.rawValue)")
            XCTAssertFalse(bg.displayName.isEmpty, "\(bg.rawValue)")
        }
    }
}
