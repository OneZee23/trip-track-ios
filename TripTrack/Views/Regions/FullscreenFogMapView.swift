import SwiftUI
import MapKit

struct FullscreenFogMapView: View {
    let visitedGeohashes: Set<String>
    let tripPolylines: [MKPolyline]
    let isDark: Bool
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack {
            ScratchMapView(
                visitedGeohashes: visitedGeohashes,
                tripPolylines: tripPolylines,
                isDark: isDark
            )
            .ignoresSafeArea()

            // Close button — top trailing, aligned with nav bar level
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(c.text)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 16)
                Spacer()
            }
        }
        .preferredColorScheme(isDark ? .dark : nil)
    }
}
