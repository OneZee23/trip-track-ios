import XCTest
@testable import TripTrack

@MainActor
final class CosmeticRetentionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: CosmeticRetentionStore!
    private let accountA = "account:A"
    private let accountB = "account:B"

    override func setUp() async throws {
        suite = "CosmeticRetentionTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        store = CosmeticRetentionStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        store = nil
        defaults = nil
    }

    private var choices: [(CosmeticRetentionStore.Key, String, String)] {
        [(.init(.profileBackground), ProfileBackground.plusLava.rawValue, ProfileBackground.ocean.rawValue),
         (.init(.avatarFrame), AvatarFrame.flame.rawValue, AvatarFrame.none.rawValue),
         (.init(.vehicleCard, vehicleID: UUID()), VehicleCardStyle.carbon.rawValue, VehicleCardStyle.none.rawValue),
         (.init(.routeLine), RouteLineStyle.amber.rawValue, RouteLineStyle.speed.rawValue)]
    }

    func testPaidChoiceSurvivesExpiryFreeChoiceRelaunchAndRenewalForAllFourObjects() {
        for (key, premium, free) in choices {
            store.selected(premium, replacing: "", key: key, owner: accountA, isPlus: true)
            // Expiry doesn't mutate stored appearance; effective rendering gates it.
            XCTAssertEqual(ProShowcase.previewID(for: key.kind, current: premium, tried: nil,
                isPlus: false, storefrontHidesPlus: false), "")
            store.selected(free, replacing: premium, key: key, owner: accountA, isPlus: false)
            XCTAssertEqual(store.retainedID(key: key, owner: accountA, current: free), premium)

            let reopened = CosmeticRetentionStore(defaults: defaults)
            let restored = reopened.restorations(owner: accountA, current: [key: free])
            XCTAssertEqual(restored[key], premium)
            reopened.didRestore(key: key, owner: accountA, premium: premium)
            XCTAssertTrue(reopened.restorations(owner: accountA, current: [key: free]).isEmpty,
                          "once acknowledged, repeated StoreKit refreshes must not reapply it")
            store = reopened
        }
    }

    func testChoosingFreeWhileProIsActiveIsPermanentEvenIfTheVisibleChoiceIsUnchanged() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        let premium = ProfileBackground.plusLava.rawValue
        let free = ProfileBackground.ocean.rawValue
        store.selected(free, replacing: premium, key: key, owner: accountA, isPlus: false)
        store.selected(free, replacing: free, key: key, owner: accountA, isPlus: true)
        XCTAssertNil(store.retainedID(key: key, owner: accountA, current: free))
        XCTAssertTrue(store.restorations(owner: accountA, current: [key: free]).isEmpty)
    }

    func testSeveralTemporaryFreeChoicesKeepOneOriginalPremiumChoice() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        let premium = ProfileBackground.plusLava.rawValue
        store.selected("ocean", replacing: premium, key: key, owner: accountA, isPlus: false)
        store.selected("forest", replacing: "ocean", key: key, owner: accountA, isPlus: false)
        XCTAssertEqual(store.retainedID(key: key, owner: accountA, current: "forest"), premium)
        XCTAssertEqual(store.restorations(owner: accountA, current: [key: "forest"])[key], premium)
    }

    func testSwitchingFromAToBAndBackCannotRestoreAIntoB() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        let premium = ProfileBackground.plusLava.rawValue
        store.selected("ocean", replacing: premium, key: key, owner: accountA, isPlus: false)
        XCTAssertNil(store.retainedID(key: key, owner: accountB, current: "ocean"))
        XCTAssertTrue(store.restorations(owner: accountB, current: [key: "ocean"]).isEmpty)
        XCTAssertEqual(store.restorations(owner: accountA, current: [key: "ocean"])[key], premium,
                       "returning to the same unchanged account can restore its own choice")
    }

    func testBChoosingFreeCannotAdoptAsExistingPremiumAndAWillNotOverwriteBsChoice() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        let premium = ProfileBackground.plusLava.rawValue
        store.activate(owner: accountA)
        store.selected("ocean", replacing: premium, key: key, owner: accountB, isPlus: false)
        XCTAssertNil(store.retainedID(key: key, owner: accountB, current: "ocean"))
        XCTAssertTrue(store.restorations(owner: accountB, current: [key: "ocean"]).isEmpty)
        XCTAssertTrue(store.restorations(owner: accountA, current: [key: "ocean"]).isEmpty)
    }

    func testPendingRestoreForAStaysInactiveAfterBChangesTheSameResource() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        let premium = ProfileBackground.plusLava.rawValue
        store.selected("ocean", replacing: premium, key: key, owner: accountA, isPlus: false)
        store.selected("ocean", replacing: "ocean", key: key, owner: accountB, isPlus: false)
        XCTAssertTrue(store.restorations(owner: accountB, current: [key: "ocean"]).isEmpty)
        XCTAssertTrue(store.restorations(owner: accountA, current: [key: "ocean"]).isEmpty,
                      "matching text alone doesn't prove ownership after an account switch")
    }

    func testTemporarilyLockedKeychainNeverFallsBackToGuestRestoration() {
        let localID = UUID()
        let accountID = UUID()
        XCTAssertNil(SettingsManager.cosmeticOwner(accountRead: .unavailable(-25308), localID: localID))
        XCTAssertNil(SettingsManager.cosmeticOwner(accountRead: .value(Data("broken".utf8)), localID: localID))
        XCTAssertEqual(SettingsManager.cosmeticOwner(accountRead: .missing, localID: localID),
                       "local:\(localID.uuidString)")
        XCTAssertEqual(SettingsManager.cosmeticOwner(
            accountRead: .value(Data(accountID.uuidString.utf8)), localID: localID),
                       "account:\(accountID.uuidString)")
    }

    func testNewerRemoteChoiceIsNotOverwrittenAndReadDoesNotErasePendingChoice() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        let premium = ProfileBackground.plusLava.rawValue
        store.selected("ocean", replacing: premium, key: key, owner: accountA, isPlus: false)
        XCTAssertTrue(store.restorations(owner: accountA, current: [key: "forest"]).isEmpty)
        XCTAssertNil(store.retainedID(key: key, owner: accountA, current: "forest"))
        XCTAssertEqual(store.restorations(owner: accountA, current: [key: "ocean"])[key], premium)
    }

    func testVehicleRetentionBelongsToThatVehicleOnlyAndDeletionDoesNotResurrectIt() {
        let first = CosmeticRetentionStore.Key(.vehicleCard, vehicleID: UUID())
        let second = CosmeticRetentionStore.Key(.vehicleCard, vehicleID: UUID())
        store.selected("", replacing: VehicleCardStyle.carbon.rawValue,
                       key: first, owner: accountA, isPlus: false)
        XCTAssertTrue(store.restorations(owner: accountA, current: [second: ""]).isEmpty)
        XCTAssertTrue(store.restorations(owner: accountA, current: [:]).isEmpty)
    }

    func testFreeSelectionAfterNewerRemotePremiumRetainsTheNewPremiumChoice() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        let previousPremium = ProfileBackground.plusLava.rawValue
        let remotePremium = ProfileBackground.plusNebula.rawValue
        store.selected("ocean", replacing: previousPremium, key: key, owner: accountA, isPlus: false)

        // Sync writes the current appearance directly. A subsequent local
        // selection must reserve that new paid choice, not the stale Lava.
        store.selected("forest", replacing: remotePremium, key: key, owner: accountA, isPlus: false)

        let reopened = CosmeticRetentionStore(defaults: defaults)
        XCTAssertEqual(reopened.retainedID(key: key, owner: accountA, current: "forest"), remotePremium)
        XCTAssertEqual(reopened.restorations(owner: accountA, current: [key: "forest"])[key], remotePremium)
    }

    func testFreeSelectionAfterNewerRemoteFreeChoiceDoesNotReviveTheOldReserve() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        store.selected("ocean", replacing: ProfileBackground.plusLava.rawValue,
                       key: key, owner: accountA, isPlus: false)

        // Forest arrived remotely. Even selecting the old temporary Ocean
        // again must not make the previous Lava reservation valid again.
        store.selected("ocean", replacing: "forest", key: key, owner: accountA, isPlus: false)

        let reopened = CosmeticRetentionStore(defaults: defaults)
        XCTAssertNil(reopened.retainedID(key: key, owner: accountA, current: "ocean"))
        XCTAssertTrue(reopened.restorations(owner: accountA, current: [key: "ocean"]).isEmpty)
    }

    func testUnknownOrFreeExistingChoiceNeverMakesARetentionPromise() {
        let key = CosmeticRetentionStore.Key(.profileBackground)
        store.selected("ocean", replacing: "future_premium", key: key, owner: accountA, isPlus: false)
        XCTAssertNil(store.retainedID(key: key, owner: accountA, current: "ocean"))
        XCTAssertTrue(store.restorations(owner: accountA, current: [key: "ocean"]).isEmpty)
    }

    func testWipingLocalDataAlsoRemovesRetainedChoices() {
        let key = CosmeticRetentionStore.Key(.avatarFrame)
        store.selected("", replacing: AvatarFrame.flame.rawValue, key: key, owner: accountA, isPlus: false)
        store.wipe()
        let reopened = CosmeticRetentionStore(defaults: defaults)
        XCTAssertTrue(reopened.restorations(owner: accountA, current: [key: ""]).isEmpty)
        XCTAssertNil(defaults.object(forKey: CosmeticRetentionStore.storageKey))
    }
}
