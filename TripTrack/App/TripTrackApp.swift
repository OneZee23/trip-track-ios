import SwiftUI

@main
struct TripTrackApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var languageManager = LanguageManager()
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false

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
            // Extract trip ID from path: triptrack://trip/{uuid}
            let tripIdString = url.pathComponents.dropFirst().first ?? ""
            if let tripId = UUID(uuidString: tripIdString) {
                NotificationCenter.default.post(name: .openTripDetail, object: tripId)
            }
        default:
            break
        }
    }
}
