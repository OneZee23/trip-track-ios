import CoreLocation

/// Core Location has no completion handler for an Always upgrade. Keeping
/// While Using can leave the status unchanged, and Allow Once can suppress the
/// upgrade entirely. Neither result is consent, nor a reason to block the app.
struct OnboardingLocationRequest {
    enum Access {
        case whenInUse, always
    }

    enum Event {
        case statusChanged, becameActive, noPromptCheck
    }

    let access: Access
    let initialStatus: CLAuthorizationStatus
    var sawInactive = false
    var returnedActive = false

    static func needsRequest(_ access: Access, status: CLAuthorizationStatus) -> Bool {
        switch (access, status) {
        case (.whenInUse, .notDetermined), (.always, .authorizedWhenInUse):
            return true
        default:
            // Always isn't requested after refusing the preceding location
            // request. Restricted and previously answered requests also pass.
            return false
        }
    }

    func isFinished(status: CLAuthorizationStatus, event: Event, isActive: Bool) -> Bool {
        guard isActive else { return false }
        if status != initialStatus { return status != .notDetermined }

        guard access == .always, initialStatus == .authorizedWhenInUse else { return false }
        // A same-status delegate event may arrive AFTER didBecomeActive and
        // replace a scheduled lifecycle check. Keep the lifecycle evidence.
        if returnedActive { return true }
        switch event {
        case .statusChanged:
            // Assigning the delegate produces an initial callback too. It
            // cannot tell us whether someone answered the pending prompt.
            return false
        case .becameActive:
            return sawInactive
        case .noPromptCheck:
            return !sawInactive
        }
    }
}
