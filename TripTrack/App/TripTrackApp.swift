import SwiftUI
import CoreText

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
        StartupTrace.mark("app init begin")
        // Bundled fonts are registered at runtime instead of via Info.plist
        // UIAppFonts — Info.plist is skip-worktree-protected local config in
        // this repo, so the registration must live in code. PressStart2P =
        // pixel brand font; Handjet Black = LVL tag (Components spec);
        // Inter (5 weights) = the design's actual typeface (see AppFont).
        for font in ["PressStart2P-Regular", "Handjet-Black", "Inter-Regular",
                     "Inter-Medium", "Inter-SemiBold", "Inter-Bold", "Inter-ExtraBold"] {
            if let fontURL = Bundle.main.url(forResource: font, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
            }
        }
        // Translate the pre-6.1.0 Int tab selection into the new AppTab key
        // BEFORE any view reads @AppStorage(AppTab.storageKey).
        AppTab.migrateLegacySelectedTabIfNeeded()
        #if DEBUG
        // Simulator-only: `-seed-map-demo` fills an empty store with drives so
        // «Моя карта» has regions, clusters and cards to show. Compiled out of
        // release builds; does nothing unless the argument is passed.
        if DebugMapSeed.isRequested {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(AppTab.maps.rawValue, forKey: AppTab.storageKey)
            DebugMapSeed.run(territory: TerritoryManager())
        }
        #endif
        // Crash reporting MUST start first — otherwise any panic in the
        // services below would crash silently. No-op when SENTRY_DSN
        // is empty (dev / simulator).
        SentryService.start()
        // Persisted cold-launch counter feeds the rating-prompt eligibility
        // check ("only ask after a real engaged session, not on day 1").
        RatingPromptService.recordLaunch()
        // Handle background relaunch by significant location change
        // iOS relaunches the app after force-quit when cell tower changes
        AutoTripService.shared.handleBackgroundLaunch()
        SyncQueue.shared.configure(transport: APISyncTransport.shared)
        SyncCoordinator.shared.start()
        // Diagnostic — verifies our ISO date parser produces UTC-correct
        // dates. Output goes to OSLog under subsystem `com.triptrack`,
        // category `iso-date`. Single call per cold launch.
        ISODate.runSelfTest()
        StartupTrace.mark("app init done (services started)")
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
