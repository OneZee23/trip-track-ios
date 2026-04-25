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

/// Preference carrying whether the currently-presented leaf view wants the
/// bottom CustomTabBar hidden (trip-detail screens want the bigger canvas).
/// Using a PreferenceKey keeps tab-bar control local to the view hierarchy
/// instead of threading bindings through every intermediate container.
struct HideTabBarPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        // Any descendant requesting "hide" wins — detail screens want it gone.
        value = value || nextValue()
    }
}

extension View {
    /// Signal to the root container that this view (and while it's on-screen)
    /// prefers the CustomTabBar to be hidden. Use with `.onPreferenceChange`
    /// on the container or let `ContentView` handle it via its existing wiring.
    func hideAppTabBar(_ hide: Bool = true) -> some View {
        preference(key: HideTabBarPreferenceKey.self, value: hide)
    }
}

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @State private var selectedTab = 0
    @State private var hideTabBar = false
    @Environment(\.colorScheme) private var systemScheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: systemScheme)
        return ZStack(alignment: .bottom) {
            // Paint the theme background across the entire window, including
            // below the bottom safe area. Previously the feed's own black bg
            // only extended to the safe-area edge, so the strip around the
            // home indicator fell through to the system window color and
            // read as an out-of-place slab on devices with a chin (iPhone
            // 12, etc.). Painting bg here keeps the screen visually whole.
            c.bg.ignoresSafeArea()

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

            // Custom glass tab bar — hidden on Record tab, and also while any
            // descendant trip-detail view declared `.hideAppTabBar()`.
            if selectedTab != 1 && !hideTabBar {
                CustomTabBar(selectedTab: $selectedTab)
                    .environment(\.colorScheme, (selectedTab == 1 && mapVM.isDarkMap) ? .dark : systemScheme)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(HideTabBarPreferenceKey.self) { newValue in
            withAnimation(.easeInOut(duration: 0.25)) {
                hideTabBar = newValue
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
