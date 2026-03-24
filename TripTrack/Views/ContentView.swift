import SwiftUI

extension Notification.Name {
    static let tripSuggestionTapped = Notification.Name("tripSuggestionTapped")
    static let switchToFeedWithRegionFilter = Notification.Name("switchToFeedWithRegionFilter")
    static let switchToFeedTab = Notification.Name("switchToFeedTab")
    static let feedScrollToTop = Notification.Name("feedScrollToTop")
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
        .onAppear {
            if UserDefaults.standard.bool(forKey: "needsDemoTrip") {
                mapVM.tripManager.createDemoTrip()
                UserDefaults.standard.removeObject(forKey: "needsDemoTrip")
            }
        }
    }
}

#Preview {
    ContentView()
}
