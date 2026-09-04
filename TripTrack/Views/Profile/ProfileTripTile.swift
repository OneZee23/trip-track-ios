import SwiftUI

/// «История» cell in GRID mode (Figma 1862:167): a 72pt map thumbnail over a
/// two-line caption. Same trip and same tap target as `ProfileTripCardView` —
/// the grid trades the metric strip for density, so only the title and the
/// «дата · километры» line survive.
struct ProfileTripTile: View {
    let trip: Trip
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    /// The grid is two columns inside the screen's 16pt margins, so a real
    /// tile measures ~157–190pt across every supported device. Snapshotting at
    /// a representative 175 keeps MKMapSnapshotter's aspect near the slot's;
    /// leaving the view's feed-sized 340pt default would render a wide image
    /// that `.fill` then crops into a squashed strip.
    private static let thumbWidth: CGFloat = 175
    private static let thumbHeight: CGFloat = 72

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        Button {
            Haptics.tap()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail(c)

                VStack(alignment: .leading, spacing: 1) {
                    Text(titleText)
                        .font(.inter(12, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(metaText)
                        .font(.inter(10, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
            }
            // Not `.surfaceCard()`: the thumbnail is flush with the tile's top
            // edge, so the tile has to clip its own content — and clipping
            // after surfaceCard would take the shadow with it. Same fill and
            // shadow values as `SurfaceCard`, applied in the order a full-bleed
            // image needs: background, clip, then shadow.
            .background(RoundedRectangle(cornerRadius: 14).fill(c.card))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile_trip_tile")
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private func thumbnail(_ c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        if coords.count > 1 {
            // A real street-map snapshot, not the beige plate Figma draws —
            // tiles are cached per trip+theme+size, so a grid scroll stays as
            // cheap as the feed's.
            MapSnapshotPreview(
                coordinates: coords,
                tripId: trip.id,
                height: Self.thumbHeight,
                width: Self.thumbWidth
            )
            .frame(height: Self.thumbHeight)
            .frame(maxWidth: .infinity)
            // No radius of its own: the thumbnail is flush with three of the
            // tile's edges, so the tile's own 14pt clip already rounds the two
            // corners that need it. Rounding here as well curved the BOTTOM
            // corners too, over card fill, leaving two pale notches mid-tile.
        } else {
            // With fewer than two points MapSnapshotPreview returns before it
            // can mark itself failed, so it shimmers forever — and a whole grid
            // of that reads as a screen still loading. Same guard and failed
            // chrome the feed card uses, sized down to the thumbnail.
            ZStack {
                Rectangle().fill(c.cardAlt)
                Image(systemName: "map.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .frame(height: Self.thumbHeight)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Text

    /// Deliberately identical to `ProfileTripCardView.titleText` — the same
    /// trip must not be named one thing in list mode, another in grid mode and
    /// a third on the detail screen. See that property for why an unnamed trip
    /// is headed by its region.
    private var titleText: String {
        if trip.hasDisplayableName,
           let t = TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language),
           !t.isEmpty {
            return t
        }
        if let region = RegionDisplay.localized(trip.region, language: lang.language), !region.isEmpty {
            return region
        }
        return ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)
    }

    /// «6 апр · 1 240 км» — ProfileTripRow's meta line minus the car, which
    /// has no room at 10pt in a half-width tile.
    private var metaText: String {
        let date = ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)
        let km = "\(GarageFormat.odometer(trip.distanceKm, lng: lang.language)) \(AppStrings.km(lang.language))"
        return "\(date) · \(km)"
    }
}
