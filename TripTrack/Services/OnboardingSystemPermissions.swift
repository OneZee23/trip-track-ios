import CoreLocation
import CoreMotion
import UIKit
import UserNotifications

/// Owns each system request until it has resolved. This instance belongs to
/// onboarding, not a singleton: a dismissed view must not leave a stale action
/// that advances a later onboarding session.
@MainActor
final class OnboardingSystemPermissions: NSObject, OnboardingPermissionRequesting, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationRequest: OnboardingLocationRequest?
    private var locationCompletion: (() -> Void)?
    private var fallbackTask: Task<Void, Never>?
    private var resolutionTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        NotificationCenter.default.addObserver(
            self, selector: #selector(willResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    deinit {
        fallbackTask?.cancel()
        resolutionTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func requestLocation(_ access: OnboardingLocationRequest.Access, completion: @escaping () -> Void) {
        let status = locationManager.authorizationStatus
        guard OnboardingLocationRequest.needsRequest(access, status: status) else {
            completion()
            return
        }
        // The coordinator prevents re-entrance. Keep a second guard here so a
        // new caller cannot replace a live permission sheet's completion.
        guard locationRequest == nil else { return }
        locationRequest = OnboardingLocationRequest(access: access, initialStatus: status)
        locationCompletion = completion
        switch access {
        case .whenInUse:
            locationManager.requestWhenInUseAuthorization()
        case .always:
            locationManager.requestAlwaysAuthorization()
            // iOS may show no upgrade at all (Allow Once / already requested).
            // Only an uninterrupted ACTIVE app can take this exit. While the
            // system sheet is visible, its lifecycle/status events own exit.
            fallbackTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.resolveLocation(after: .noPromptCheck)
            }
        }
    }

    func requestMotion(completion: @escaping () -> Void) {
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() == .notDetermined else {
            completion()
            return
        }
        MotionDetector.requestAuthorization { _ in
            Task { @MainActor in completion() }
        }
    }

    func requestNotifications(completion: @escaping () -> Void) {
        // requestAuthorization returns immediately for already answered
        // prompts, and preserves NotificationManager's category registration.
        NotificationManager.shared.requestAuthorization { granted in
            Task { @MainActor in
                if granted {
                    PushNotificationManager.shared.registerForRemoteNotifications()
                }
                completion()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        scheduleLocationResolution(after: .statusChanged)
    }

    @objc private func willResignActive() {
        locationRequest?.sawInactive = true
    }

    @objc private func didBecomeActive() {
        if locationRequest?.sawInactive == true {
            locationRequest?.returnedActive = true
        }
        scheduleLocationResolution(after: .becameActive)
    }

    private func scheduleLocationResolution(after event: OnboardingLocationRequest.Event) {
        guard locationRequest != nil else { return }
        // A delegate callback may precede the system sheet's dismissal. Give
        // UIKit a turn to finish its transition before asking for Motion.
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.resolveLocation(after: event)
        }
    }

    private func resolveLocation(after event: OnboardingLocationRequest.Event) {
        guard let request = locationRequest,
              request.isFinished(
                status: locationManager.authorizationStatus,
                event: event,
                isActive: UIApplication.shared.applicationState == .active
              ) else { return }
        let completion = locationCompletion
        locationCompletion = nil
        locationRequest = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        resolutionTask?.cancel()
        resolutionTask = nil
        completion?()
    }
}
