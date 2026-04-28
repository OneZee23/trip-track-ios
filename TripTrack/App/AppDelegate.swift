import UIKit
import UserNotifications

/// Minimal AppDelegate wired into the SwiftUI lifecycle via
/// `@UIApplicationDelegateAdaptor`. Exists so we can receive the APNs
/// device-token callbacks — those don't bubble through SwiftUI's `App`
/// surface yet.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    // MARK: - APNs

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRegistrationError(error)
        }
    }

    // MARK: - Silent / data pushes (handled foreground)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Server may eventually send `content-available: 1` data pushes (e.g.
        // refresh feed badge counts). For now we just acknowledge so APNs
        // doesn't think the app is unreachable.
        completionHandler(.noData)
    }
}
