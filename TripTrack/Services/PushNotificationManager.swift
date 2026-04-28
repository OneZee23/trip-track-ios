import Foundation
import UIKit
import UserNotifications
import OSLog

private let pushLog = Logger(subsystem: "com.triptrack", category: "push")

/// Handles APNs registration + device-token roundtrip with the server.
/// Local notifications stay in `NotificationManager`; this is purely about
/// remote pushes (reactions, follows, future comments).
@MainActor
final class PushNotificationManager {
    static let shared = PushNotificationManager()

    /// The most-recent device token reported by APNs, hex-encoded. We persist
    /// it across launches so that on subsequent sign-ins we can replay the
    /// same token to the server without waiting for APNs to re-deliver it.
    private(set) var deviceToken: String? {
        didSet {
            if let t = deviceToken {
                UserDefaults.standard.set(t, forKey: Keys.token)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.token)
            }
        }
    }

    private enum Keys {
        static let token = "com.triptrack.push.deviceToken"
    }

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: Keys.token)
    }

    /// Asks iOS to register for remote notifications. The actual token comes
    /// back via `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Safe to call multiple times — iOS dedupes.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Called by AppDelegate when APNs hands us a token. We stash it and, if
    /// the user is signed in, push it to the server so backend can dispatch
    /// notifications to this device.
    func handleDeviceToken(_ tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        let isNew = deviceToken != hex
        deviceToken = hex
        pushLog.log("APNs token received (len=\(hex.count), new=\(isNew))")
        if AuthService.shared.isSignedIn {
            Task { await syncTokenToServer() }
        }
    }

    /// Called by AppDelegate when APNs registration fails. Token stays as-is
    /// (could be a stale one from prior boot) — we just log so we know not to
    /// expect dispatches.
    func handleRegistrationError(_ error: Error) {
        pushLog.error("APNs registration failed: \(error.localizedDescription)")
    }

    /// Pushes the current token to the backend. Called after sign-in and
    /// whenever APNs hands us a fresh token. No-op if we don't have a token
    /// yet (the AppDelegate callback will fire it once one arrives).
    func syncTokenToServer() async {
        guard AuthService.shared.isSignedIn, let token = deviceToken else { return }
        let body = DeviceTokenRequest(
            apnsToken: token,
            localUserId: SettingsManager.shared.localUserId.uuidString,
            environment: Self.environment
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                APIEndpoint.deviceToken, body: body)
            pushLog.log("device token synced to server")
        } catch {
            pushLog.error("device token sync failed: \(error.localizedDescription)")
        }
    }

    // Build environment maps to APNs environment (sandbox vs production).
    // Backend uses this to pick the right APNs gateway.
    private static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

struct DeviceTokenRequest: Encodable {
    let apnsToken: String
    let localUserId: String
    let environment: String
}
