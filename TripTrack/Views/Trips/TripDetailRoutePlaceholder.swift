import SwiftUI
import CoreLocation

/// A useful, static first frame while the street tiles arrive. No shimmer,
/// moving car or blank MapKit grid competing with the navigation transition.
struct TripDetailRoutePlaceholder: View {
    let coordinates: [CLLocationCoordinate2D]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack {
            c.cardAlt
            if coordinates.count > 1 {
                LightRoutePreview(coordinates: coordinates, accentColor: AppTheme.accent)
                    .padding(32)
            } else {
                Image(systemName: "map")
                    .font(.title)
                    .foregroundStyle(c.textTertiary)
            }
        }
        .accessibilityIdentifier("detail_map_placeholder")
        .allowsHitTesting(false)
    }
}
