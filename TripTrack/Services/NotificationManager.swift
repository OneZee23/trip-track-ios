import Foundation
import UserNotifications

final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false

    // Notification category identifiers
    static let tripStartPromptCategory = "TRIP_START_PROMPT"
    static let tripStopPromptCategory = "TRIP_STOP_PROMPT"
    static let tripAutoStartedCategory = "TRIP_AUTO_STARTED"
    /// 0.7.0. Пуш админу о чужой регистрации. В «Входящие» не попадает —
    /// сервер его не записывает, — поэтому нажатие просто открывает
    /// приложение: вести некуда, и притворяться, что есть, не надо.
    static let newAccountCategory = "NEW_ACCOUNT"
    /// 0.8.1. «Твоя?» после черновика, начатого приложением в «Напоминаниях».
    static let tripDraftConfirmCategory = "TRIP_DRAFT_CONFIRM"

    // Action identifiers
    static let startRecordingAction = "START_RECORDING"
    static let skipAction = "SKIP"
    static let stopNowAction = "STOP_NOW"
    static let continueAction = "CONTINUE_RECORDING"
    static let confirmDraftAction = "CONFIRM_DRAFT"
    static let discardDraftAction = "DISCARD_DRAFT"

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

        // «Моя» работает без открытия приложения; «Удалить» — только с
        // разблокированного телефона: стирать поездку с экрана блокировки
        // может кто угодно.
        let confirmDraft = UNNotificationAction(
            identifier: Self.confirmDraftAction,
            title: AppStrings.draftConfirm(lang),
            options: []
        )
        let discardDraft = UNNotificationAction(
            identifier: Self.discardDraftAction,
            title: AppStrings.draftDiscard(lang),
            options: [.destructive, .authenticationRequired]
        )
        let draftCategory = UNNotificationCategory(
            identifier: Self.tripDraftConfirmCategory,
            actions: [confirmDraft, discardDraft],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            startCategory, stopCategory, autoStartCategory, draftCategory
        ])
    }

    // MARK: - Send Notifications

    // `sendTripStartPrompt` (0.8.0, «Напоминания» ждали ответа) удалена в
    // 0.8.1 — раунд 1 ревью, пункт 9: с этой версии «Напоминания» пишут
    // черновик сразу (`sendDraftStartedNotification`), и звать её больше
    // некому. Категория `tripStartPromptCategory`, её действия и разбор
    // нажатий в `didReceive` ОСТАЮТСЯ: уведомление, доставленное ЕЩЁ 0.8.0,
    // может дождаться обновления в Центре уведомлений, и нажатие на него
    // обязано сработать так же, как раньше.

    /// `minutes == nil` — режим «напоминания»: спрашиваем и ничего не делаем
    /// сами, поэтому и обещать автозавершение в тексте нельзя.
    func sendTripStopPrompt(minutes: Int?, reason: AppStrings.TripStopReason) {
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

    /// The car was detected, the app tried to start recording, and the start
    /// was refused. Silence here is worse than a notification: the driver has
    /// every reason to think the trip is being recorded, and finds out at the
    /// end of the road that it never was.
    func sendAutoStartFailedNotification(reason: MapViewModel.StartRefusal?) {
        let lang = currentLang()
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifAutoStartFailedTitle(lang)
        content.body = AppStrings.notifAutoStartFailedBody(lang, reason: reason)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "trip-auto-start-failed",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// «Поездка сохранена: 12,4 км · 23 мин».
    ///
    /// Единица читается СВЕЖО, а не запоминается в поле: уведомление
    /// собирается через минуты после того, как сервис проснулся, и человек мог
    /// за это время переключить настройку — или её мог привезти пул со второго
    /// телефона. Строка на экране блокировки правится потом только удалением.
    func sendAutoStopNotification(metres: Double, duration: String) {
        let lang = currentLang()
        let unit = DistanceUnit.current
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifAutoStopTitle(lang)
        content.body = AppStrings.notifAutoStopSummary(
            lang,
            distance: Measure.distance(metres: metres, unit: unit, lang: lang, style: .tenths),
            time: duration)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "trip-auto-stopped",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Черновик начат: только в Центре уведомлений, без звука и баннера
    /// (спека §3.1).
    static func draftStartedContent(lang: LanguageManager.Language) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifDraftStartedTitle(lang)
        content.body = AppStrings.notifDraftStartedBody(lang)
        content.interruptionLevel = .passive
        return content
    }

    /// «Поездка записана: 7.4 км. Твоя?» — с действиями «Моя» и «Удалить».
    static func draftConfirmContent(tripId: UUID, metres: Double,
                                    lang: LanguageManager.Language,
                                    unit: DistanceUnit) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = AppStrings.notifDraftConfirmTitle(lang)
        content.body = AppStrings.notifDraftConfirmBody(
            lang, distance: Measure.distance(metres: metres, unit: unit, lang: lang, style: .tenths))
        content.sound = .default
        content.categoryIdentifier = tripDraftConfirmCategory
        content.userInfo = ["tripId": tripId.uuidString]
        return content
    }

    /// «Пишу поездку» не про КОНКРЕТНУЮ поездку — одновременно пишется не
    /// больше одной (`startRecording`'s re-entry guard), поэтому один
    /// идентификатор на все черновики. «Твоя?» — про эту поездку и только её.
    private static let draftStartedId = "trip-draft-started"
    private static func draftConfirmId(_ tripId: UUID) -> String { "trip-draft-\(tripId.uuidString)" }

    func sendDraftStartedNotification() {
        let request = UNNotificationRequest(identifier: Self.draftStartedId,
                                            content: Self.draftStartedContent(lang: currentLang()),
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Единица читается свежо — как у `sendAutoStopNotification`.
    func sendDraftConfirmPrompt(tripId: UUID, metres: Double) {
        let request = UNNotificationRequest(
            identifier: Self.draftConfirmId(tripId),
            content: Self.draftConfirmContent(tripId: tripId, metres: metres,
                                              lang: currentLang(), unit: DistanceUnit.current),
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Вопрос решён («Моя» или «Удалить») — ни «Пишу поездку», ни «Твоя?» этой
    /// поездки не остаётся в Центре уведомлений (спека §3.2: без следа).
    /// Действие над уведомлением обычно убирает его само, но тап по телу
    /// «Твоя?» (открывает поездку, не решение) этого не делает, а «Пишу
    /// поездку» — отдельное, более раннее уведомление, которое действие над
    /// «Твоя?» никогда не трогает.
    func clearDraftNotifications(tripId: UUID) {
        let ids = [Self.draftStartedId, Self.draftConfirmId(tripId)]
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
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
        case Self.confirmDraftAction, Self.discardDraftAction:
            if let raw = userInfo["tripId"] as? String, let id = UUID(uuidString: raw) {
                DraftDecisionQueue.shared.enqueue(
                    id, response.actionIdentifier == Self.confirmDraftAction ? .confirm : .discard)
                NotificationCenter.default.post(name: .draftTripDecisionQueued, object: nil)
            }
        case UNNotificationDefaultActionIdentifier:
            // Tapped the notification body — route by category. Local trip-
            // start prompt opens the recording tab; remote pushes deep-link
            // into trip detail (REACTION / COMMENT — both carry `tripId` in
            // the payload) or open the social tab (FOLLOW).
            if category == Self.tripStartPromptCategory {
                NotificationCenter.default.post(name: .autoTripStartRequested, object: nil)
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            } else if category == Self.tripDraftConfirmCategory,
                      let raw = userInfo["tripId"] as? String, let id = UUID(uuidString: raw) {
                // Тап по телу вопроса открывает поездку: плашка «Это твоя
                // поездка?» там же.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openTripDetail, object: id)
                }
            } else if category == "REACTION" || category == "COMMENT" || category == "COMPANION_ACCEPTED" {
                // `COMPANION_ACCEPTED` only ever notifies the trip's OWNER
                // (`dispatchAcceptedSideEffects` on the backend) — the
                // `tripId` in its payload is a trip this device already
                // owns/can open, exactly like a reaction or comment push,
                // so it follows the identical deep-link shape.
                if let tripIdString = userInfo["tripId"] as? String,
                   let tripId = UUID(uuidString: tripIdString) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: .openTripDetail, object: tripId)
                    }
                }
                Task { @MainActor in
                    await NotificationsInboxStore.shared.refresh()
                }
            } else if category == "FOLLOW" || category == "COMPANION_INVITE" {
                // `COMPANION_INVITE`'s `tripId` points to a trip the
                // recipient cannot view yet (a still-pending invite has no
                // view access — see `resolveTripAccess`), so unlike
                // `COMPANION_ACCEPTED` above it can't deep-link into trip
                // detail. Follows `FOLLOW`'s existing shape instead: land
                // on the feed tab (where the notifications bell — and now
                // the invite's decision card — is one tap away) rather than
                // a route that could only ever 403.
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
        if Self.refreshesInbox(category) {
            // Refresh the inbox synchronously with banner display — this
            // is the canonical "foreground push received" hook (vs
            // `application(_:didReceiveRemoteNotification:)` which only
            // fires for `content-available: 1` data pushes we don't send).
            Task { @MainActor in
                await NotificationsInboxStore.shared.refresh()
            }
        }
        completionHandler(Self.presentationOptions(for: category))
    }

    /// Что показать в форграунде, чистой функцией — чтобы правило проверялось
    /// тестом, а не пушем на телефоне: поднять `UNNotification` с нужной
    /// категорией в юнит-тесте нечем.
    ///
    /// Local trip-start / trip-stop prompts are presented inline via the
    /// recording UI itself, so silencing them in foreground avoids a double
    /// surface. Remote pushes DO get a foreground banner — the user is
    /// already in the app, so a quiet announcement is the right interaction
    /// (matches Strava, Twitter).
    static func presentationOptions(for category: String) -> UNNotificationPresentationOptions {
        switch category {
        case "REACTION", "FOLLOW", "COMMENT", "COMPANION_INVITE", "COMPANION_ACCEPTED",
             newAccountCategory:
            return [.banner, .sound]
        default:
            return []
        }
    }

    /// Приход какого пуша меняет «Входящие». `NEW_ACCOUNT` — НЕ меняет:
    /// бэкенд его не записывает (`NotificationsService.record` не зовётся),
    /// и лишний запрос показал бы тот же список.
    static func refreshesInbox(_ category: String) -> Bool {
        switch category {
        case "REACTION", "FOLLOW", "COMMENT", "COMPANION_INVITE", "COMPANION_ACCEPTED":
            return true
        default:
            return false
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let autoTripStartRequested = Notification.Name("autoTripStartRequested")
    static let autoTripStopRequested = Notification.Name("autoTripStopRequested")
    static let autoTripContinueRequested = Notification.Name("autoTripContinueRequested")
}
