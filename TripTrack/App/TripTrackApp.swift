import SwiftUI
import CoreText

@main
struct TripTrackApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var languageManager = LanguageManager()
    /// Gates the whole window. See `StoreHealth` — the app must not draw a
    /// library it could not open.
    @StateObject private var storeHealth = StoreHealth.shared
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    /// AppDelegate adapter — only purpose is receiving APNs device-token
    /// callbacks, which SwiftUI's `App` doesn't expose directly.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
        // Translate the pre-0.6.0 Int tab selection into the new AppTab key
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
        // The services below write to CoreData on the way up — auto-trip
        // recovery, the sync queue, and (through SyncCoordinator →
        // recoverPendingEntities → SettingsManager) the settings row itself.
        // Starting them against a store that failed to open is precisely what
        // recreated a real user's settings row and left his level reading
        // zero, so they wait until the store is actually attached.
        // `StoreRecoveryView` drives the retry that releases them.
        if StoreHealth.shared.isOpen {
            AppBootstrap.startServicesOnce()
            StartupTrace.mark("app init done (services started)")
        } else {
            StartupTrace.mark("app init done — STORE NOT OPEN, services held")
        }
    }

    var body: some Scene {
        WindowGroup {
            if !storeHealth.isOpen {
                // Deliberately the FIRST branch: onboarding, the feed and every
                // screen behind them read CoreData, and an empty-looking app is
                // the bug this release exists to remove. The screen depends on
                // ThemeManager, LanguageManager, AppStrings and AppTheme only —
                // all UserDefaults-backed — so it cannot itself touch the store.
                StoreRecoveryView()
                    .environmentObject(themeManager)
                    .environmentObject(languageManager)
                    .environment(\.locale, languageManager.language.locale)
                    .onAppear { themeManager.applyToWindows() }
            } else if hasCompletedOnboarding {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(themeManager)
                    .environmentObject(languageManager)
                    // SwiftUI reads `.textCase(.uppercase)`, date pickers and
                    // every system formatter off the environment locale. It
                    // defaults to the DEVICE language, which is not what the
                    // user picked in «Язык» — and on Turkish the difference is
                    // visible: `.uppercase` on the device locale turns «i»
                    // into «I» instead of «İ».
                    .environment(\.locale, languageManager.language.locale)
                    // The theme is painted onto the WINDOW, not handed down as
                    // `preferredColorScheme` — see `ThemeManager.paint` for why
                    // the environment could not carry it. `init` runs before
                    // there is a window, so the saved mode lands here.
                    .onAppear { themeManager.applyToWindows() }
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
                    .task {
                        // Keep the on-device journal alive across relaunches:
                        // the system store only holds THIS process, so sweep
                        // it into our own files now and every couple of
                        // minutes while the app is in front. The background
                        // sweep below is the one that catches a kill.
                        await LogArchive.shared.startPeriodicSweep()
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
                    .environment(\.locale, languageManager.language.locale)
                    .onAppear { themeManager.applyToWindows() }
            }
        }
        // Going to the background is the last thing that happens before most
        // process deaths — sweep the system log into our own files there, or a
        // relaunch loses everything that was said since the last periodic one.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await LogArchive.shared.sweep() }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Universal links arrive here too (`.onOpenURL` delivers both). The
        // web page at `trip-track.app/u/<id>` is what a phone WITHOUT the app
        // gets; with the app installed iOS hands us the URL directly and the
        // browser never opens.
        if url.scheme == "https" || url.scheme == "http" {
            handleWebLink(url)
            return
        }
        guard url.scheme == "triptrack" else { return }

        switch url.host {
        // `triptrack://profile/<uuid>` — what the web landing page's «Открыть
        // в приложении» button fires, and the fallback on a device where
        // universal links aren't associated yet.
        case "profile", "u":
            let idString = url.pathComponents.dropFirst().first ?? ""
            if let id = UUID(uuidString: idString) {
                NotificationCenter.default.post(name: .openUserProfile, object: id)
            }
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

    /// `https://trip-track.app/u/<uuid>` → that person's profile.
    ///
    /// Only our own host, and only the paths we publish in the
    /// apple-app-site-association file: anything else the system hands us
    /// (or a crafted link) falls through and does nothing, rather than
    /// steering the app off an arbitrary URL.
    private func handleWebLink(_ url: URL) {
        let host = url.host?.lowercased()
        guard host == "trip-track.app" || host == "www.trip-track.app" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return }
        switch parts[0] {
        case "u":
            if let id = UUID(uuidString: parts[1]) {
                NotificationCenter.default.post(name: .openUserProfile, object: id)
            }
        default:
            break
        }
    }
}
