import XCTest
@testable import TripTrack

final class FuelCurrencyTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: FuelCurrency.storageKey)
        super.tearDown()
    }

    func testDefaultCurrency() {
        UserDefaults.standard.removeObject(forKey: FuelCurrency.storageKey)
        XCTAssertEqual(FuelCurrency.current, "€")
    }

    func testStorageKey() {
        XCTAssertEqual(FuelCurrency.storageKey, "fuelCurrency")
    }

    func testDefaultSymbol() {
        XCTAssertEqual(FuelCurrency.defaultSymbol, "€")
    }

    func testCurrentReadsUserDefaults() {
        UserDefaults.standard.set("$", forKey: FuelCurrency.storageKey)
        XCTAssertEqual(FuelCurrency.current, "$")
    }

    func testAllCurrenciesHaveSymbols() {
        for currency in FuelCurrency.allCases {
            XCTAssertFalse(currency.symbol.isEmpty, "\(currency) has empty symbol")
        }
    }

    /// The picker shows symbol, name and ISO code side by side, so a blank or
    /// duplicated code would render two rows that look like the same currency.
    func testAllCurrenciesHaveDistinctCodesAndNames() {
        let codes = FuelCurrency.allCases.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "duplicate ISO codes: \(codes)")
        for currency in FuelCurrency.allCases {
            XCTAssertEqual(currency.code.count, 3, "\(currency) code is not a 3-letter ISO code")
            XCTAssertFalse(currency.name(.ru).isEmpty, "\(currency) has no Russian name")
            XCTAssertFalse(currency.name(.en).isEmpty, "\(currency) has no English name")
        }
    }

    /// The picker's order is the canon's: the currencies this app's people
    /// refuel in come first.
    func testPickerOrderStartsWithTheCanonSet() {
        let leading = FuelCurrency.allCases.prefix(8).map(\.code)
        XCTAssertEqual(leading, ["RUB", "USD", "EUR", "KZT", "GEL", "TRY", "CNY", "BYN"])
    }

    func testFuelCurrencyOnTrip() {
        let trip = Trip(fuelCurrency: "$")
        XCTAssertEqual(trip.fuelCurrency, "$")
    }

    func testFuelCurrencyDefaultNilOnTrip() {
        let trip = Trip()
        XCTAssertNil(trip.fuelCurrency)
    }
}
