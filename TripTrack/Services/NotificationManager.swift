import Foundation
import UserNotifications

final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false

    // Notification category identifiers
    static let tripStartPromptCategory = "TRIP_START_PROMPT"
    static let tripStopPromptCategory = "TRIP_STOP_PROMPT"
    static let tripAutoStartedCategory = "TRIP_AUTO_STARTED"

    // Action identifiers
    static let startRecordingAction = "START_RECORDING"
    static let skipAction = "SKIP"
    static let stopNowAction = "STOP_NOW"
    static let continueAction = "CONTINUE_RECORDING"

    // Request identifiers
    static let autoStopDeadlineId = "trip-auto-stop-deadline"

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            Task { @MainActor in
                self?.isAuthorized = granted
                if granted {
                    self?.registerCategories()
                }
                completion(granted)
            }
        }
    }

    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                let authorized = settings.authorizationStatus == .authorized
                self?.isAuthorized = authorized
                if authorized {
                    self?.registerCategories()
                }
            }
        }
    }

    // MARK: - Categories

    func reregisterCategories() {
        registerCategories()
    }

    private func registerCategories() {
        let lang = LanguageManager.currentLanguage

        let startAction = UNNotificationAction(
            identifier: Self.startRecordingAction,
            title: AppStrings.notifTripStartAction(lang),
            options: []  // Run in background — starts recording + shows Live Activity
        )
        let skipAction = UNNotificationAction(
            identifier: Self.skipAction,
            title: AppStrings.notifSkipAction(lang),
            options: []
        )
        let startCategory = UNNotificationCategory(
            identifier: Self.tripStartPromptCategory,
            actions: [startAction, skipAction],
            intentIdentifiers: []
        )

        let stopAction = UNNotificationAction(
            identifier: Self.stopNowAction,
            title: AppStrings.notifStopNowAction(lang),
            options: [.foreground]
        )
        let continueAction = UNNotificationAction(
            identifier: Self.continueAction,
            title: AppStrings.notifContinueAction(lang),
            options: []
        )
        let stopCategory = UNNotificationCategory(
            identifier: Self.tripStopPromptCategory,
            actions: [stopAction, continueAction],
            intentIdentifiers: []
        )

        let autoStartStopAction = UNNotificationAction(
            identifier: Self.stopNowAction,
            title: AppStrings.notifStopNowAction(lang),
            options: []
        )
        let autoStartCategory = UNNotificationCategory(
            identifier: Self.tripAutoStartedCategory,
            actions: [autoStartStopAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            startCategory, stopCategory, autoStartCategory
        ])
    }

    // MARK: - Send Notifications

    func sendTripStartPrompt(deviceName: String) {
        let lang = currentLang()
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifTripStartTitle(lang)
        content.body = AppStrings.notifTripStartBody(lang, deviceName: deviceName)
        content.sound = .default
        content.categoryIdentifier = Self.tripStartPromptCategory

        let request = UNNotificationRequest(
            identifier: "trip-start-prompt",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendTripStopPrompt(minutes: Int, reason: AppStrings.TripStopReason) {
        let lang = currentLang()
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifTripStopTitle(lang)
        content.body = AppStrings.notifTripStopBody(lang, minutes: minutes, reason: reason)
        content.sound = .default
        content.categoryIdentifier = Self.tripStopPromptCategory

        let request = UNNotificationRequest(
            identifier: "trip-stop-prompt",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendAutoStartNotification() {
        let lang = currentLang()
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifAutoStartTitle(lang)
        content.body = AppStrings.notifAutoStartBody(lang)
        content.sound = .default
        content.categoryIdentifier = Self.tripAutoStartedCategory

        let request = UNNotificationRequest(
            identifier: "trip-auto-started",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func sendAutoStopNotification(distanceKm: Double, duration: String) {
        let lang = currentLang()
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifAutoStopTitle(lang)
        content.body = AppStrings.notifAutoStopSummary(lang, km: String(format: "%.1f", distanceKm), time: duration)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "trip-auto-stopped",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancelTripStopPrompt() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["trip-stop-prompt"]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["trip-stop-prompt"]
        )
    }

    // MARK: - Helpers

    private func currentLang() -> LanguageManager.Language {
        LanguageManager.currentLanguage
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case Self.startRecordingAction:
            NotificationCenter.default.post(name: .autoTripStartRequested, object: nil)
        case Self.stopNowAction:
            NotificationCenter.default.post(name: .autoTripStopRequested, object: nil)
        case Self.continueAction:
            NotificationCenter.default.post(name: .autoTripContinueRequested, object: nil)
        case UNNotificationDefaultActionIdentifier:
            // Tapped the notification body — route by category. Local trip-
            // start prompt opens the recording tab; remote pushes deep-link
            // into trip detail (REACTION / COMMENT — both carry `tripId` in
            // the payload) or open the social tab (FOLLOW).
            if category == Self.tripStartPromptCategory {
                NotificationCenter.default.post(name: .autoTripStartRequested, object: nil)
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            } else if category == "REACTION" || category == "COMMENT" {
                if let tripIdString = userInfo["tripId"] as? String,
                   let tripId = UUID(uuidString: tripIdString) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .openTripDetail, object: tripId)
                    }
                }
                Task { @MainActor in
                    await NotificationsInboxStore.shared.refresh()
                }
            } else if category == "FOLLOW" {
                NotificationCenter.default.post(name: .switchToFeedTab, object: nil)
                Task { @MainActor in
                    await NotificationsInboxStore.shared.refresh()
                }
            }
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier
        // Local trip-start / trip-stop prompts are presented inline via the
        // recording UI itself, so silencing them in foreground avoids a
        // double surface. Remote social pushes (REACTION / FOLLOW / COMMENT)
        // DO get a foreground banner — the user is already in the app, so a
        // quiet announcement is the right interaction (matches Strava,
        // Twitter).
        switch category {
        case "REACTION", "FOLLOW", "COMMENT":
            // Refresh the inbox synchronously with banner display — this
            // is the canonical "foreground push received" hook (vs
            // `application(_:didReceiveRemoteNotification:)` which only
            // fires for `content-available: 1` data pushes we don't send).
            Task { @MainActor in
                await NotificationsInboxStore.shared.refresh()
            }
            completionHandler([.banner, .sound])
        default:
            completionHandler([])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let autoTripStartRequested = Notification.Name("autoTripStartRequested")
    static let autoTripStopRequested = Notification.Name("autoTripStopRequested")
    static let autoTripContinueRequested = Notification.Name("autoTripContinueRequested")
}
