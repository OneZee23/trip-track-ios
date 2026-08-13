import SwiftUI

/// What the colours of the route mean — as a line of type in the seam
/// between the map and the trip's details, not as a control on the map.
///
/// It used to be a collapsed pill floating over the route, opened by
/// tapping a speedometer glyph. That cost a corner of the map, a piece of
/// state, and — for anyone who never tapped it — the answer itself: the
/// route was drawn in five colours nobody explained. Here it is always
/// legible, always the same height, and there is nothing to tap.
///
/// Rows come from `SpeedColorScale.legendRows()`, the same source the
/// polyline is coloured from, so the key can't drift from the route.
struct RouteSpeedKeyStrip: View {
    let language: LanguageManager.Language

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Group {
            if typeSize >= .accessibility1 {
                // At accessibility sizes the row can't fit; let it scroll
                // rather than truncate the bands into nonsense.
                ScrollView(.horizontal, showsIndicators: false) {
                    row(c).padding(.horizontal, 16)
                }
            } else {
                row(c).padding(.horizontal, 16)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(c.bg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail_speed_key")
    }

    private func row(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(SpeedColorScale.legendRows().enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(entry.color)
                        .frame(width: 16, height: 4)
                    Text(entry.range)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            Text(AppStrings.kmh(language))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(c.textTertiary)
                .lineLimit(1)
        }
        .minimumScaleFactor(0.8)
    }
}
