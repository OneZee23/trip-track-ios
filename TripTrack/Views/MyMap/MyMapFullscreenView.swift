import SwiftUI
import MapKit

/// Fullscreen memory map (Figma 449:129): everything hides except the top
/// scrim, a top-left close button and a bottom dark stats pill. Camera is
/// handed off both ways for continuity.
struct MyMapFullscreenView: View {
    @ObservedObject var vm: MyMapViewModel
    var mode: MyMapMode
    var initialRegion: MKCoordinateRegion?
    var onDismiss: (MKCoordinateRegion) -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentRegion: MKCoordinateRegion?

    var body: some View {
        ZStack {
            MyMapRepresentable(
                glow: vm.glow,
                routeSegments: vm.routeSegments,
                cityDots: vm.cityDots,
                mode: mode,
                onCameraSettled: { currentRegion = $0 },
                initialRegion: initialRegion
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
                    .ignoresSafeArea(edges: .top)
                Spacer()
            }
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Button {
                        if let currentRegion { onDismiss(currentRegion) }
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mymap_fullscreen_close")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                Spacer()

                HStack(spacing: 7) {
                    Circle().fill(AppTheme.accent).frame(width: 8, height: 8)
                    Text("\(MyMapView.groupedNumber(vm.totalKm2, lang.language)) \(AppStrings.km2Short(lang.language)) · \(vm.regionCount) \(AppStrings.regionsGenitive(lang.language, count: vm.regionCount))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 9)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 14)
            }
        }
        .preferredColorScheme(.dark)
    }
}
