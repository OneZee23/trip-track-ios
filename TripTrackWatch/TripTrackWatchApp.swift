import SwiftUI

@main
struct TripTrackWatchApp: App {
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(session)
        }
    }
}
