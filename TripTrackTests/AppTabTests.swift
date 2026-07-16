import XCTest
@testable import TripTrack

final class AppTabTests: XCTestCase {

    // MARK: legacy index mapping
    func testLegacyIndexMapping() {
        XCTAssertEqual(AppTab.fromLegacyIndex(0), .home)   // old Feed
        XCTAssertEqual(AppTab.fromLegacyIndex(1), .record) // old Record
        XCTAssertEqual(AppTab.fromLegacyIndex(2), .maps)   // old Regions → Maps
    }

    func testLegacyIndexOutOfRangeFallsBackToHome() {
        XCTAssertEqual(AppTab.fromLegacyIndex(3), .home)
        XCTAssertEqual(AppTab.fromLegacyIndex(-1), .home)
        XCTAssertEqual(AppTab.fromLegacyIndex(99), .home)
    }

    // MARK: rawValue stability (storage contract)
    func testRawValuesAreStable() {
        XCTAssertEqual(AppTab.home.rawValue, "home")
        XCTAssertEqual(AppTab.maps.rawValue, "maps")
        XCTAssertEqual(AppTab.record.rawValue, "record")
        XCTAssertEqual(AppTab.groups.rawValue, "groups")
        XCTAssertEqual(AppTab.profile.rawValue, "profile")
    }

    // MARK: migration
    private func makeDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testMigrationMapsLegacyRegionsToMaps() {
        let d = makeDefaults("AppTabTests.migrate1")
        d.set(2, forKey: "selectedTab")            // legacy "Regions"
        AppTab.migrateLegacySelectedTabIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: "selectedTabV2"), "maps")
    }

    func testMigrationMapsLegacyFeedToHome() {
        let d = makeDefaults("AppTabTests.migrate2")
        d.set(0, forKey: "selectedTab")
        AppTab.migrateLegacySelectedTabIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: "selectedTabV2"), "home")
    }

    func testMigrationNoLegacyLeavesNewKeyUnset() {
        let d = makeDefaults("AppTabTests.migrate3")
        AppTab.migrateLegacySelectedTabIfNeeded(defaults: d)
        XCTAssertNil(d.string(forKey: "selectedTabV2")) // fresh install → @AppStorage default applies
    }

    func testMigrationDoesNotOverwriteExistingNewKey() {
        let d = makeDefaults("AppTabTests.migrate4")
        d.set(2, forKey: "selectedTab")
        d.set("profile", forKey: "selectedTabV2")  // already migrated / user moved
        AppTab.migrateLegacySelectedTabIfNeeded(defaults: d)
        XCTAssertEqual(d.string(forKey: "selectedTabV2"), "profile") // untouched
    }
}
