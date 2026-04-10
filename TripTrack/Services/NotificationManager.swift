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

    private func registerCategories() {
        let lang = LanguageManager.currentLanguage

        let startAction = UNNotificationAction(
            identifier: Self.startRecordingAction,
            title: AppStrings.notifTripStartAction(lang),
            options: [.foreground]
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

        let autoStartCategory = UNNotificationCategory(
            identifier: Self.tripAutoStartedCategory,
            actions: [],
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

    func sendTripStopPrompt(minutes: Int) {
        let lang = currentLang()
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifTripStopTitle(lang)
        content.body = AppStrings.notifTripStopBody(lang, minutes: minutes)
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
        switch response.actionIdentifier {
        case Self.startRecordingAction:
            NotificationCenter.default.post(name: .autoTripStartRequested, object: nil)
        case Self.stopNowAction:
            NotificationCenter.default.post(name: .autoTripStopRequested, object: nil)
        case Self.continueAction:
            NotificationCenter.default.post(name: .autoTripContinueRequested, object: nil)
        default:
            // Tapped the notification itself (not an action button)
            if response.notification.request.content.categoryIdentifier == Self.tripStartPromptCategory {
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Don't show notification banner when the app is in foreground
        completionHandler([])
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let autoTripStartRequested = Notification.Name("autoTripStartRequested")
    static let autoTripStopRequested = Notification.Name("autoTripStopRequested")
    static let autoTripContinueRequested = Notification.Name("autoTripContinueRequested")
}
