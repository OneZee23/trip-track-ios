import Combine
import Foundation

/// The explanatory screen leads to the system's decision, including refusal.
/// In particular, an unsuccessful request never traps someone in onboarding.
@MainActor
final class OnboardingPermissionCoordinator: ObservableObject {
    enum Step {
        case location, background, notifications
    }

    @Published private(set) var isRequesting = false
    private let permissions: OnboardingPermissionRequesting
    private var requestID: UUID?

    init(permissions: OnboardingPermissionRequesting? = nil) {
        self.permissions = permissions ?? OnboardingSystemPermissions()
    }

    func proceed(from step: Step, completion: @escaping () -> Void) {
        guard !isRequesting else { return }
        let id = UUID()
        requestID = id
        isRequesting = true
        let finish: () -> Void = { [weak self] in
            guard let self, self.requestID == id else { return }
            self.requestID = nil
            self.isRequesting = false
            completion()
        }

        switch step {
        case .location:
            permissions.requestLocation(.whenInUse, completion: finish)
        case .background:
            var requestedMotion = false
            permissions.requestLocation(.always) { [weak self] in
                guard let self, self.requestID == id, !requestedMotion else { return }
                requestedMotion = true
                // Never put Motion & Fitness on top of a location decision.
                self.permissions.requestMotion(completion: finish)
            }
        case .notifications:
            permissions.requestNotifications(completion: finish)
        }
    }
}

@MainActor
protocol OnboardingPermissionRequesting: AnyObject {
    func requestLocation(_ access: OnboardingLocationRequest.Access, completion: @escaping () -> Void)
    func requestMotion(completion: @escaping () -> Void)
    func requestNotifications(completion: @escaping () -> Void)
}
