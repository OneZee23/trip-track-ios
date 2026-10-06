import XCTest
import CoreLocation
@testable import TripTrack

@MainActor
final class OnboardingPermissionTests: XCTestCase {
    func testLocationDenialStillAdvancesOnce() {
        let client = FakePermissions()
        let coordinator = OnboardingPermissionCoordinator(permissions: client)
        var advances = 0
        coordinator.proceed(from: .location) { advances += 1 }
        XCTAssertTrue(coordinator.isRequesting)
        XCTAssertEqual(client.calls, ["whenInUse"])
        // The system response deliberately has no Bool gate. Both refusal
        // and consent are completed decisions and allow onboarding to proceed.
        client.locationCompletion?()
        client.locationCompletion?()
        XCTAssertEqual(advances, 1)
        XCTAssertFalse(coordinator.isRequesting)
    }

    func testBackgroundWaitsForLocationBeforeMotionAndForMotionBeforeAdvancing() {
        let client = FakePermissions()
        let coordinator = OnboardingPermissionCoordinator(permissions: client)
        var advances = 0
        coordinator.proceed(from: .background) { advances += 1 }
        XCTAssertEqual(client.calls, ["always"])
        XCTAssertEqual(advances, 0)
        client.locationCompletion?()
        client.locationCompletion?()
        XCTAssertEqual(client.calls, ["always", "motion"])
        XCTAssertEqual(advances, 0)
        XCTAssertTrue(coordinator.isRequesting)
        client.motionCompletion?()
        XCTAssertEqual(advances, 1)
        XCTAssertFalse(coordinator.isRequesting)
    }

    func testDoubleTapCannotIssueAnotherPermissionRequest() {
        let client = FakePermissions()
        let coordinator = OnboardingPermissionCoordinator(permissions: client)
        var advances = 0
        coordinator.proceed(from: .background) { advances += 1 }
        coordinator.proceed(from: .background) { XCTFail("Duplicate tap must be ignored") }
        XCTAssertEqual(client.calls, ["always"])
        client.locationCompletion?()
        coordinator.proceed(from: .notifications) { XCTFail("Motion has not resolved yet") }
        XCTAssertEqual(client.calls, ["always", "motion"])
        client.motionCompletion?()
        XCTAssertEqual(advances, 1)
    }

    func testUnavailableOrPreviouslyAnsweredPermissionsCompleteSynchronously() {
        let client = FakePermissions()
        client.completeImmediately = true
        let coordinator = OnboardingPermissionCoordinator(permissions: client)
        var advances = 0
        for step in [OnboardingPermissionCoordinator.Step.location, .background, .notifications] {
            coordinator.proceed(from: step) { advances += 1 }
            XCTAssertFalse(coordinator.isRequesting)
        }
        XCTAssertEqual(advances, 3)
        XCTAssertEqual(client.calls, ["whenInUse", "always", "motion", "notifications"])
    }

    func testLateCompletionFromPreviousPageCannotFinishNextPage() {
        let client = FakePermissions()
        let coordinator = OnboardingPermissionCoordinator(permissions: client)
        var advances = 0
        coordinator.proceed(from: .location) { advances += 1 }
        let oldCompletion = client.locationCompletion
        oldCompletion?()
        coordinator.proceed(from: .notifications) { advances += 1 }
        oldCompletion?()
        XCTAssertEqual(advances, 1)
        XCTAssertTrue(coordinator.isRequesting)
        client.notificationCompletion?()
        XCTAssertEqual(advances, 2)
    }

    func testAnsweredLocationRequestsNeverAskAgainOrAskAlwaysAfterDenial() {
        for status in [CLAuthorizationStatus.denied, .restricted, .authorizedAlways] {
            XCTAssertFalse(OnboardingLocationRequest.needsRequest(.whenInUse, status: status))
            XCTAssertFalse(OnboardingLocationRequest.needsRequest(.always, status: status))
        }
        XCTAssertTrue(OnboardingLocationRequest.needsRequest(.whenInUse, status: .notDetermined))
        XCTAssertFalse(OnboardingLocationRequest.needsRequest(.always, status: .notDetermined))
        XCTAssertFalse(OnboardingLocationRequest.needsRequest(.whenInUse, status: .authorizedWhenInUse))
        XCTAssertTrue(OnboardingLocationRequest.needsRequest(.always, status: .authorizedWhenInUse))
    }

    func testInitialLocationCallbackDoesNotStandForAUserDecision() {
        let request = OnboardingLocationRequest(access: .whenInUse, initialStatus: .notDetermined)
        XCTAssertFalse(request.isFinished(status: .notDetermined, event: .statusChanged, isActive: true))
        XCTAssertFalse(request.isFinished(status: .notDetermined, event: .noPromptCheck, isActive: true))
        for status in [CLAuthorizationStatus.denied, .restricted, .authorizedWhenInUse, .authorizedAlways] {
            XCTAssertTrue(request.isFinished(status: status, event: .statusChanged, isActive: true))
            XCTAssertFalse(request.isFinished(status: status, event: .statusChanged, isActive: false))
        }
    }

    func testAlwaysKeepWhileUsingCompletesAfterSystemSheetCloses() {
        var request = OnboardingLocationRequest(access: .always, initialStatus: .authorizedWhenInUse)
        XCTAssertFalse(request.isFinished(status: .authorizedWhenInUse, event: .statusChanged, isActive: true))
        request.sawInactive = true
        XCTAssertFalse(request.isFinished(status: .authorizedWhenInUse, event: .noPromptCheck, isActive: false))
        request.returnedActive = true
        XCTAssertTrue(request.isFinished(status: .authorizedWhenInUse, event: .becameActive, isActive: true))
        // A late, unchanged-status delegate callback must not erase the
        // lifecycle evidence (Core Location can deliver accuracy changes too).
        XCTAssertTrue(request.isFinished(status: .authorizedWhenInUse, event: .statusChanged, isActive: true))
    }

    func testSuppressedAlwaysUpgradeCompletesWithoutClaimingItWasGranted() {
        let request = OnboardingLocationRequest(access: .always, initialStatus: .authorizedWhenInUse)
        XCTAssertTrue(request.isFinished(status: .authorizedWhenInUse, event: .noPromptCheck, isActive: true))
        XCTAssertFalse(request.isFinished(status: .authorizedWhenInUse, event: .noPromptCheck, isActive: false))
        XCTAssertEqual(request.initialStatus, .authorizedWhenInUse)
    }

    func testAlwaysChangeWaitsUntilTheAppIsActiveBeforeMotionCanStart() {
        var request = OnboardingLocationRequest(access: .always, initialStatus: .authorizedWhenInUse)
        request.sawInactive = true
        XCTAssertFalse(request.isFinished(status: .authorizedAlways, event: .statusChanged, isActive: false))
        request.returnedActive = true
        XCTAssertTrue(request.isFinished(status: .authorizedAlways, event: .becameActive, isActive: true))
    }

    private final class FakePermissions: OnboardingPermissionRequesting {
        var calls: [String] = []
        var completeImmediately = false
        var locationCompletion: (() -> Void)?
        var motionCompletion: (() -> Void)?
        var notificationCompletion: (() -> Void)?

        func requestLocation(_ access: OnboardingLocationRequest.Access, completion: @escaping () -> Void) {
            calls.append(access == .whenInUse ? "whenInUse" : "always")
            locationCompletion = completion
            if completeImmediately { completion() }
        }

        func requestMotion(completion: @escaping () -> Void) {
            calls.append("motion")
            motionCompletion = completion
            if completeImmediately { completion() }
        }

        func requestNotifications(completion: @escaping () -> Void) {
            calls.append("notifications")
            notificationCompletion = completion
            if completeImmediately { completion() }
        }
    }
}
