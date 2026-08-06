import XCTest
@testable import TripTrack

/// `RegionDisplay` renders the stored (raw, either-language) geocoder region
/// in the APP language: RU → short Figma-canon form, EN → Apple-style name.
final class RegionDisplayTests: XCTestCase {
    func testEnglishStoredRendersRussianShort() {
        XCTAssertEqual(RegionDisplay.localized("Krasnodar Krai", language: .ru), "Краснодар. край")
        XCTAssertEqual(RegionDisplay.localized("Moscow Oblast", language: .ru), "Моск. обл.")
        XCTAssertEqual(RegionDisplay.localized("Republic of Karelia", language: .ru), "Карелия")
    }

    func testEnglishStoredStaysEnglish() {
        XCTAssertEqual(RegionDisplay.localized("Krasnodar Krai", language: .en), "Krasnodar Krai")
    }

    func testRussianStoredRendersEnglish() {
        XCTAssertEqual(RegionDisplay.localized("Краснодарский край", language: .en), "Krasnodar Krai")
        XCTAssertEqual(RegionDisplay.localized("Московская область", language: .en), "Moscow Oblast")
    }

    func testRussianShortFormRecognized() {
        // Round-trip stability: a short form fed back in resolves to itself.
        XCTAssertEqual(RegionDisplay.localized("Моск. обл.", language: .ru), "Моск. обл.")
    }

    func testFederalCities() {
        XCTAssertEqual(RegionDisplay.localized("Saint Petersburg", language: .ru), "Санкт-Петербург")
        XCTAssertEqual(RegionDisplay.localized("Москва", language: .en), "Moscow")
    }

    func testCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(RegionDisplay.localized("  krasnodar krai ", language: .ru), "Краснодар. край")
    }

    func testUnknownRegionPassesThrough() {
        XCTAssertEqual(RegionDisplay.localized("Île-de-France", language: .ru), "Île-de-France")
        XCTAssertEqual(RegionDisplay.localized("Bavaria", language: .en), "Bavaria")
    }

    func testNilAndEmptyPassThrough() {
        XCTAssertNil(RegionDisplay.localized(nil, language: .ru))
        XCTAssertEqual(RegionDisplay.localized("", language: .ru), "")
    }
}
