import SwiftUI

struct ProfileRoadScene: View {
    let time: RoadSceneTime
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(time.assetName)
            .resizable().interpolation(.none)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, AppTheme.colors(for: scheme).roadHeroCard.opacity(scheme == .dark ? 0.2 : 0.42)],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 25)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
