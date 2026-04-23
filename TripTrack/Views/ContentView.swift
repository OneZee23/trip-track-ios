import SwiftUI

extension Notification.Name {
    static let tripSuggestionTapped = Notification.Name("tripSuggestionTapped")
    static let switchToFeedWithRegionFilter = Notification.Name("switchToFeedWithRegionFilter")
    static let switchToFeedTab = Notification.Name("switchToFeedTab")
    static let feedScrollToTop = Notification.Name("feedScrollToTop")
    static let switchToTrackingTab = Notification.Name("switchToTrackingTab")
    static let openTripDetail = Notification.Name("openTripDetail")
    static let navigateToTrip = Notification.Name("navigateToTrip")
    static let dismissTripSummary = Notification.Name("dismissTripSummary")
    static let tripDeleted = Notification.Name("tripDeleted")
    static let tripRecordingEnded = Notification.Name("tripRecordingEnded")
    static let territoryRebuilt = Notification.Name("territoryRebuilt")
    static let syncPullCompleted = Notification.Name("syncPullCompleted")
    static let tripPrivacyChanged = Notification.Name("tripPrivacyChanged")
    /// Server returned `USER_BANNED` on any authenticated endpoint. AuthService
    /// observes this and triggers `signOut()` — local data stays intact so the
    /// user can still view (read-only) what they already have on device.
    static let userBanned = Notification.Name("userBanned")
}

/// Payload for `.tripPrivacyChanged` — lets the feed optimistically remove/add the
/// affected card instead of waiting for the server round-trip.
struct PrivacyChangePayload {
    let tripId: UUID
    let isPrivate: Bool
}

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @State private var selectedTab = 0
    @Environment(\.colorScheme) private var systemScheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        ZStack(alignment: .bottom) {
            switch selectedTab {
            case 0:
                FeedView(tripManager: mapVM.tripManager, selectedTab: $selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case 1:
                TrackingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.colorScheme, mapVM.isDarkMap ? .dark : systemScheme)
            case 2:
                RegionsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                EmptyView()
            }

            // Custom glass tab bar — hidden on Record tab entirely
            if selectedTab != 1 {
                CustomTabBar(selectedTab: $selectedTab)
                    .environment(\.colorScheme, (selectedTab == 1 && mapVM.isDarkMap) ? .dark : systemScheme)
            }
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(edges: .bottom)
        .environmentObject(mapVM)
        .fullScreenCover(isPresented: $mapVM.showBadgeCelebration) {
            BadgeCelebrationView(
                badges: mapVM.pendingBadges,
                onDismiss: {
                    mapVM.pendingBadges = []
                    mapVM.showBadgeCelebration = false
                    // Show trip summary after celebration (if there's a pending trip)
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        mapVM.showPendingSummary()
                    }
                }
            )
            .environmentObject(lang)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripSuggestionTapped)) { _ in
            selectedTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToFeedWithRegionFilter)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToFeedTab)) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTrackingTab)) { _ in
            selectedTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTripDetail)) { notification in
            if let tripId = notification.object as? UUID {
                // Switch to feed tab and navigate to trip detail
                selectedTab = 0
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    NotificationCenter.default.post(name: .navigateToTrip, object: tripId)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissTripSummary)) { _ in
            // Dismiss any showing summary/celebration when deep-linking to trip detail
            mapVM.lastCompletedTrip = nil
            mapVM.showBadgeCelebration = false
            mapVM.pendingBadges = []
        }
        .onAppear {
            // Clean up demo trip for users who onboarded before 0.1.1
            mapVM.tripManager.deleteDemoTripIfNeeded()
            // Configure auto-trip detection
            AutoTripService.shared.configure(mapViewModel: mapVM)
            AutoTripService.shared.startIfNeeded()
        }
    }
}

#Preview {
    ContentView()
}
