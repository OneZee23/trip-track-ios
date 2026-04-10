import SwiftUI

@main
struct TripTrackApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var languageManager = LanguageManager()
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

    init() {
        // Handle background relaunch by significant location change
        // iOS relaunches the app after force-quit when cell tower changes
        AutoTripService.shared.handleBackgroundLaunch()
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
