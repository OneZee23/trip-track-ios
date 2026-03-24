import SwiftUI
import MapKit

struct TripShareCardView: View {
    let trip: Trip
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // A card designed to be rendered as an image for sharing
        // Size: roughly 375x500 (Instagram story friendly)
        VStack(spacing: 0) {
            // Route map preview at top (60% of card)
            if trip.trackPoints.count > 1 {
                RouteMapView(
                    coordinates: trip.trackPoints.map(\.coordinate),
                    speeds: trip.trackPoints.map(\.speed)
                )
                .frame(height: 300)
                .allowsHitTesting(false)
            }

            // Info section
            VStack(alignment: .leading, spacing: 12) {
                // Title or date
                Text(trip.title ?? formattedDate)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.colors(for: scheme).text)

                // Stats row
                HStack(spacing: 16) {
                    shareStatItem(
                        value: String(format: "%.1f", trip.distanceKm),
                        unit: AppStrings.km(lang.language),
                        icon: "location.fill",
                        color: AppTheme.green
                    )
                    shareStatItem(
                        value: trip.formattedDuration,
                        unit: AppStrings.duration(lang.language),
                        icon: "timer",
                        color: AppTheme.accent
                    )
                    shareStatItem(
                        value: String(format: "%.0f", trip.maxSpeedKmh),
                        unit: AppStrings.kmh(lang.language),
                        icon: "speedometer",
                        color: AppTheme.blue
                    )
                }

                // Branding
                HStack {
                    Spacer()
                    Text("TripTrack")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.colors(for: scheme).textTertiary)
                }
            }
            .padding(20)
            .background(AppTheme.colors(for: scheme).bg)
        }
        .frame(width: 375)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(AppTheme.colors(for: scheme).border, lineWidth: 1)
        )
    }

    private func shareStatItem(value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.colors(for: scheme).text)
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.colors(for: scheme).textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private static let dateFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM yyyy"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM yyyy"
        return (ru, en)
    }()

    private var formattedDate: String {
        let fmts = Self.dateFormatters
        return (lang.language == .ru ? fmts.ru : fmts.en).string(from: trip.startDate)
    }
}
