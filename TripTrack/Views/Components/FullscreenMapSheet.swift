import SwiftUI
import MapKit

/// Full-screen, interactive route viewer presented from both TripDetailView
/// and SocialTripDetailView when the user wants to see the route bigger
/// than the poster hero render. Carries no business logic — just
/// RouteMapView pinned to the edges plus a close button over the top-left.
///
/// Chrome per Figma 117:1803: a white close circle top-left, a «+» / «−» pair
/// on the right edge, and the speed key as a full-width glass plaque along
/// the bottom (117:1836).
struct FullscreenMapSheet: View {
    let coordinates: [CLLocationCoordinate2D]
    /// m/s, aligned with `coordinates` — paints the route and sets the top
    /// end of the speed plaque's scale.
    var speeds: [Double] = []
    var fogCutoffDate: Date?
    /// Social trips pass `true` — their preview polyline is sparsely sampled
    /// and the gap-splitting in RouteMapView would zero out the bounds.
    var treatAsPreview: Bool = false
    /// Used only for the speed plaque's "km/h" unit. Default keeps the
    /// social call site (speeds empty → no plaque) unchanged.
    var language: LanguageManager.Language = .en

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// Bumped by the zoom buttons; the map reads the change, not the value.
    @State private var zoomTick = 0

    var body: some View {
        ZStack {
            RouteMapView(
                coordinates: coordinates,
                speeds: speeds,
                isInteractive: true,
                fogCutoffDate: fogCutoffDate,
                treatAsPreview: treatAsPreview,
                zoomTick: zoomTick
            )
            .ignoresSafeArea()

            // The chrome deliberately does NOT ignore the safe area, so every
            // control lands inside it instead of being nudged there by hand.
            // Layout follows what every map app has taught people: the way out
            // is top-left, the zoom is thumb-height on the right, and the
            // colour key runs along the bottom edge under both.
            VStack(spacing: 0) {
                HStack {
                    mapCircleButton(systemImage: "xmark", label: AppStrings.closeSheet(language)) {
                        dismiss()
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    zoomControls
                }

                if let topKmh = topSpeedKmh {
                    speedKeyPlaque(topKmh)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            // Clears the «Apple Maps · Legal» strip along the bottom edge,
            // which Apple requires to stay visible and which the speed key was
            // sitting directly on top of.
            .padding(.bottom, 36)
        }
    }

    // MARK: - Speed key

    /// The route's real top speed in km/h, straight from the series the sheet
    /// is already handed. `nil` when the caller ships no speeds (social
    /// previews) or nothing ever moved — a 0…0 scale is not a scale.
    private var topSpeedKmh: Double? {
        guard let fastestMS = speeds.max(), fastestMS > 0 else { return nil }
        return fastestMS * 3.6
    }

    /// The colour key as a plaque across the bottom instead of a card in the
    /// corner. The old legend listed the four fixed bands behind a chevron: it
    /// explained the palette but never this drive — the trip's own top speed,
    /// the one number the colours are about, was printed nowhere in the app.
    private func speedKeyPlaque(_ topKmh: Double) -> some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(alignment: .leading, spacing: 7) {
            Capsule()
                .fill(Self.speedGradient(topKmh: topKmh))
                .frame(height: 6)

            HStack(spacing: 8) {
                Text("0 \(AppStrings.kmh(language))")
                Spacer(minLength: 8)
                Text("\(Int(topKmh.rounded())) \(AppStrings.kmh(language))")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(c.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassBackground(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fullscreen_speed_key")
    }

    /// The ramp is `SpeedColorScale`'s own thresholds laid on a 0…`topKmh`
    /// axis, so the colour under any point of the bar is the colour the route
    /// is painted at that speed and the key can't drift from the polyline.
    /// Bands the trip never reached are simply never reached: a 60 km/h drive
    /// gets a green-to-yellow bar, not the full-palette lie.
    private static func speedGradient(topKmh: Double) -> LinearGradient {
        let bands = SpeedColorScale.bands
        var stops: [Gradient.Stop] = [.init(color: bands[0].color, location: 0)]
        for (i, band) in bands.enumerated() {
            guard i + 1 < bands.count, let upper = band.upperKmh, upper < topKmh else { break }
            stops.append(.init(color: bands[i + 1].color, location: CGFloat(upper / topKmh)))
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Zoom

    /// «+» / «−» as one grouped control — pinch is not the only way people zoom
    /// a map, and it is a poor one when the other hand is holding a phone.
    private var zoomControls: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            zoomButton(systemImage: "plus", label: language == .ru ? "Приблизить" : "Zoom in") {
                zoomTick += 1
            }
            Rectangle()
                .fill(c.textTertiary.opacity(0.25))
                .frame(width: 26, height: 1)
            zoomButton(systemImage: "minus", label: language == .ru ? "Отдалить" : "Zoom out") {
                zoomTick -= 1
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.card)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        )
    }

    private func zoomButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 44, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("fullscreen_map_\(systemImage)")
    }

    private func mapCircleButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(c.card))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("fullscreen_map_\(systemImage)")
    }
}
