import SwiftUI

/// Floating play / stop button for `RouteMapView` route playback.
/// 44×44 hit target satisfies HIG; visible chrome stays as a
/// 36-icon-on-44-frame circle so the look matches the existing map
/// expand button row.
struct RoutePlaybackButton: View {
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
        }
    }
}
