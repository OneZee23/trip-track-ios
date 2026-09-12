import XCTest
@testable import TripTrack

/// Подпись строки «Клубы — скоро» в профиле: то же, что печатал тизер
/// (число из листа ожидания или приглашение быть первым), плюс «вы записаны»
/// у телефона, который в списке.
final class ProfileClubsRowTests: XCTestCase {

    func testCountAndJoined() {
        XCTAssertEqual(ProfileClubsRow.subtitle(total: 6, joined: true, lang: .ru),
                       "Уже ждут 6 человек · вы записаны")
        XCTAssertEqual(ProfileClubsRow.subtitle(total: 6, joined: true, lang: .en),
                       "6 people already waiting · you're on the list")
    }

    func testCountNotJoined() {
        XCTAssertEqual(ProfileClubsRow.subtitle(total: 6, joined: false, lang: .ru),
                       "Уже ждут 6 человек")
    }

    func testNobodyYet() {
        XCTAssertEqual(ProfileClubsRow.subtitle(total: 0, joined: false, lang: .ru),
                       AppStrings.groupsWaitlistFirst(.ru))
        XCTAssertEqual(ProfileClubsRow.subtitle(total: 0, joined: false, lang: .en),
                       "You could be the first")
    }

    /// Записан, а счётчик не пришёл (сервер ответил «joined», кэш без total —
    /// или ответ ещё в пути). Записанный телефон сам в счётчике, значит ждёт
    /// как минимум один: «Вы можете быть первым · вы записаны» противоречило
    /// бы само себе.
    func testJoinedCountsItselfWhenTotalIsZero() {
        let s = ProfileClubsRow.subtitle(total: 0, joined: true, lang: .ru)
        XCTAssertTrue(s.hasPrefix(AppStrings.groupsWaitlistCount(.ru, count: 1)), s)
        XCTAssertTrue(s.hasSuffix(" · " + AppStrings.clubsRowJoined(.ru)), s)
    }
}
