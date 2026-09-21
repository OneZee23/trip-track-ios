import XCTest
@testable import TripTrack

/// Выключатель платного: при `PlusAvailability.isEnabled == false` витрина
/// прячет «Плюс» для всех, включая США; при включённом — только РФ.
final class PlusAvailabilityTests: XCTestCase {
    func testDisabledHidesPlusOnEveryStorefront() {
        for code in ["USA", "DEU", "GEO", "RUS", nil] {
            XCTAssertTrue(PlusStore.hidesPlus(countryCode: code, available: false), "\(code ?? "nil")")
        }
    }

    func testEnabledHidesPlusOnlyInRussia() {
        XCTAssertTrue(PlusStore.hidesPlus(countryCode: "RUS", available: true))
        XCTAssertTrue(PlusStore.hidesPlus(countryCode: "ru", available: true))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: "USA", available: true))
        XCTAssertFalse(PlusStore.hidesPlus(countryCode: nil, available: true))
    }

    /// 0.8.0 уезжает выключенным. Тест падает в тот день, когда константу
    /// переключат, — чтобы вместе с ней перечитали чек-лист товаров в ASC.
    func testShippedBuildKeepsPlusHidden() {
        XCTAssertFalse(PlusAvailability.isEnabled)
        XCTAssertTrue(PlusStore.hidesPlus(countryCode: "USA"))
    }
}
