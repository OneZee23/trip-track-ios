import SwiftUI

/// Compact legend that decodes the route's speed colouring (the user couldn't
/// tell which colour mapped to which speed). Reads `SpeedColorScale` so it
/// always matches the painted polyline. Collapsible — tap the header to hide
/// the rows on a small map. Takes `language` explicitly (no EnvironmentObject)
/// so it drops cleanly onto `RouteMapView` overlays, including full-screen
/// covers that don't inherit the environment.
struct SpeedLegendView: View {
    let language: LanguageManager.Language
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10, weight: .semibold))
                    Text(AppStrings.kmh(language))
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(Array(SpeedColorScale.legendRows().enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(row.color)
                            .frame(width: 14, height: 4)
                        Text(row.range)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
