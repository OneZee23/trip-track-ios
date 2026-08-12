import SwiftUI
import MapKit

/// Full-screen, interactive route viewer presented from both TripDetailView
/// and SocialTripDetailView when the user wants to see the route bigger
/// than the poster hero render. Carries no business logic — just
/// RouteMapView pinned to the edges plus a close button over the top-left.
///
/// Chrome per Figma 117:1803: a white close circle top-left, a «+» / «−» pair
/// on the right edge, and the speed legend as a glass card along the bottom.
struct FullscreenMapSheet: View {
    let coordinates: [CLLocationCoordinate2D]
    var speeds: [Double] = []
    var fogCutoffDate: Date?
    /// Social trips pass `true` — their preview polyline is sparsely sampled
    /// and the gap-splitting in RouteMapView would zero out the bounds.
    var treatAsPreview: Bool = false
    /// Used only for the speed legend's "km/h" header. Default keeps the
    /// social call site (speeds empty → no legend) unchanged.
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
            // legend explains the colours from the opposite corner.
            VStack(spacing: 0) {
                HStack {
                    mapCircleButton(systemImage: "xmark", label: AppStrings.closeSheet(language)) {
                        dismiss()
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 12) {
                    if !speeds.isEmpty {
                        SpeedLegendView(language: language, initiallyExpanded: true)
                    }
                    Spacer(minLength: 0)
                    zoomControls
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            // Clears the «Apple Maps · Legal» strip along the bottom edge,
            // which Apple requires to stay visible and which the legend was
            // sitting directly on top of.
            .padding(.bottom, 36)
        }
    }

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
