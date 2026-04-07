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

    func testFuelCurrencyOnTrip() {
        let trip = Trip(fuelCurrency: "$")
        XCTAssertEqual(trip.fuelCurrency, "$")
    }

    func testFuelCurrencyDefaultNilOnTrip() {
        let trip = Trip()
        XCTAssertNil(trip.fuelCurrency)
    }
}
