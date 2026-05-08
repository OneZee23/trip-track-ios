import SwiftUI

@main
struct TripTrackApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var languageManager = LanguageManager()
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    /// AppDelegate adapter — only purpose is receiving APNs device-token
    /// callbacks, which SwiftUI's `App` doesn't expose directly.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Crash reporting MUST start first — otherwise any panic in the
        // services below would crash silently. No-op when SENTRY_DSN
        // is empty (dev / simulator).
        SentryService.start()
        // Handle background relaunch by significant location change
        // iOS relaunches the app after force-quit when cell tower changes
        AutoTripService.shared.handleBackgroundLaunch()
        SyncQueue.shared.configure(transport: APISyncTransport.shared)
        SyncCoordinator.shared.start()
        // Diagnostic — verifies our ISO date parser produces UTC-correct
        // dates. Output goes to OSLog under subsystem `com.triptrack`,
        // category `iso-date`. Single call per cold launch.
        ISODate.runSelfTest()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(themeManager)
                    .environmentObject(languageManager)
                    .preferredColorScheme(themeManager.preferredColorScheme)
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
                    .task {
                        AuthService.shared.checkAuthStatus()
                        // Replay APNs registration each cold launch — iOS rotates
                        // device tokens on rare occasions, and the only way to
                        // catch that is to ask for a fresh one. Idempotent;
                        // `PushNotificationManager` skips the server roundtrip
                        // if the token hasn't actually changed.
                        if NotificationManager.shared.isAuthorized {
                            PushNotificationManager.shared.registerForRemoteNotifications()
                            if AuthService.shared.isSignedIn {
                                await PushNotificationManager.shared.syncTokenToServer()
                            }
                        }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(themeManager)
                    .environmentObject(languageManager)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "triptrack" else { return }

        switch url.host {
        case "recording":
            NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
        case "trip":
            // Dismiss the finished Live Activity since user tapped through
            LiveActivityManager.shared.endActivity()
            // Dismiss any summary/celebration screens that might be showing
            NotificationCenter.default.post(name: .dismissTripSummary, object: nil)
            // Extract trip ID from path: triptrack://trip/{uuid}
            let tripIdString = url.pathComponents.dropFirst().first ?? ""
            if let tripId = UUID(uuidString: tripIdString) {
                // Small delay to let dismissals complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .openTripDetail, object: tripId)
                }
            }
        default:
            break
        }
    }
}
