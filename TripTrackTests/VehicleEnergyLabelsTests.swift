import XCTest
@testable import TripTrack

/// The passport's electricity block names its own price (0.8.9).
///
/// Its second row read «Цена топлива» beside «8 ₽/кВт·ч»: the fuel block's
/// title, copied one section down. On a plug-in hybrid both blocks are on
/// screen together, and two «Цена топлива» rows with different prices read as
/// a bug in the numbers rather than in the words.
final class VehicleEnergyLabelsTests: XCTestCase {
    func testElectricityBlockNamesElectricityPrice() throws {
        let url = UnitGuard.repoRoot().appendingPathComponent("TripTrack/Views/Profile/VehicleDetailView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard let start = source.range(of: "AppStrings.electricSectionLabel(l)"),
              let end = source.range(of: "AppStrings.electricRangeLabel(l)", range: start.upperBound..<source.endIndex)
        else { return XCTFail("The electricity block moved; point this test at it") }
        let block = source[start.upperBound..<end.lowerBound]
        XCTAssertTrue(block.contains("AppStrings.electricPriceSection(l)"),
                      "The electricity block must name the price of electricity")
        XCTAssertFalse(block.contains("AppStrings.fuelPriceRow(l)"),
                       "The electricity block must not borrow the fuel price title")
    }

    func testElectricityPriceDiffersFromFuelPriceInEveryLanguage() {
        for lang in LanguageManager.Language.allCases {
            XCTAssertNotEqual(AppStrings.electricPriceSection(lang), AppStrings.fuelPriceRow(lang), "\(lang)")
        }
    }
}
