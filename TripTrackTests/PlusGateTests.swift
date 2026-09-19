import XCTest
@testable import TripTrack

/// `PlusGate.allows` — единственная дверь, через которую любая из пяти
/// платных вещей спрашивает «мне можно?» (спека §2, §3).
///
/// Таблица 3×5: три состояния человека × пять фич. Состояний три, не четыре
/// — `isPlus` побеждает `storefrontHidesPlus` всегда, поэтому «плюс есть и
/// витрина прячет» и «плюс есть, витрина не прячет» дают один и тот же
/// ответ (спека §1: уже купленный «Плюс» честно работает даже на витрине,
/// которая больше платное не продаёт).
final class PlusGateTests: XCTestCase {

    private func assertAllFeatures(
        isPlus: Bool, storefrontHidesPlus: Bool, expect level: PlusAccessLevel,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for feature in PlusFeature.allCases {
            XCTAssertEqual(
                PlusGate.allows(feature, isPlus: isPlus, storefrontHidesPlus: storefrontHidesPlus),
                level,
                "\(feature) — isPlus:\(isPlus) storefrontHidesPlus:\(storefrontHidesPlus)",
                file: file, line: line
            )
        }
    }

    // MARK: - Три состояния × пять фич

    /// Нет плюса, витрина продаёт (не РФ) — замок.
    func testNoPlusOrdinaryStorefrontIsLocked() {
        assertAllFeatures(isPlus: false, storefrontHidesPlus: false, expect: .locked)
    }

    /// Нет плюса, витрина не продаёт (РФ) — платного не видно вовсе.
    func testNoPlusRussianStorefrontIsHidden() {
        assertAllFeatures(isPlus: false, storefrontHidesPlus: true, expect: .hidden)
    }

    /// Плюс есть, витрина продаёт — открыто.
    func testPlusOrdinaryStorefrontIsOpen() {
        assertAllFeatures(isPlus: true, storefrontHidesPlus: false, expect: .open)
    }

    /// Плюс есть, витрина больше не продаёт — ВСЁ РАВНО открыто. Купленный
    /// до смены региона (или на другой витрине) «Плюс» не гаснет молча.
    func testPlusOnAHidingStorefrontStillWorks() {
        assertAllFeatures(isPlus: true, storefrontHidesPlus: true, expect: .open)
    }

    // MARK: - Пять фич поимённо, чтобы список не усох незаметно

    func testAllFiveFeaturesExist() {
        XCTAssertEqual(Set(PlusFeature.allCases.map(String.init(describing:))), [
            "profileBackgrounds", "avatarFrame", "vehicleCardStyle",
            "routeLineStyle", "manualTrip",
        ])
    }

    func testEachFeatureLockedIndividually() {
        for feature in PlusFeature.allCases {
            XCTAssertEqual(
                PlusGate.allows(feature, isPlus: false, storefrontHidesPlus: false),
                .locked
            )
        }
    }
}
