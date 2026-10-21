import XCTest
@testable import TripTrack

/// Переключатель флага в админке стоит в том, что люди видят на самом деле.
final class AdminFlagTests: XCTestCase {
    private func decode(_ json: String) throws -> AdminFlag {
        try JSONDecoder().decode(AdminFlag.self, from: Data(json.utf8))
    }

    /// `fogMetal` вшит включённым: «по умолчанию» обязано выглядеть
    /// включённым, иначе «включить и выключить» погасило бы туман у всех.
    func testDefaultShowsTheBuiltInValue() throws {
        let flag = try decode(#"{"name":"fogMetal","enabled":null,"builtIn":true}"#)
        XCTAssertEqual(flag.effective, true)
    }

    func testAServerValueWins() throws {
        let flag = try decode(#"{"name":"fogMetal","enabled":false,"builtIn":true}"#)
        XCTAssertEqual(flag.effective, false)
    }

    /// Сервер без `builtIn` — значение неизвестно, и экран не угадывает.
    func testUnknownStaysUnknown() throws {
        let flag = try decode(#"{"name":"fogMetal","enabled":null}"#)
        XCTAssertNil(flag.effective)
    }
}
