import XCTest
@testable import TripTrack

/// Пустое приглашение DRIVE2 на странице машины — только для СНГ
/// (владелец, 23 окт 2026). Таблица: язык, регион, ответ.
final class Drive2AudienceTests: XCTestCase {
    func testInviteTable() {
        let cases: [(LanguageManager.Language, String?, Bool)] = [
            (.ru, nil, true), (.uk, "UA", true), (.kk, "KZ", true),
            (.ru, "DE", true),
            (.en, "RU", true), (.de, "kz", true), (.en, "BY", true),
            (.en, "US", false), (.de, "DE", false), (.pt, "BR", false),
            (.tr, "TR", false), (.pl, "PL", false), (.en, nil, false),
        ]
        for (language, region, expected) in cases {
            XCTAssertEqual(
                Drive2Audience.invitesOnPage(language: language, region: region), expected,
                "\(language) \(region ?? "nil")")
        }
    }
}
