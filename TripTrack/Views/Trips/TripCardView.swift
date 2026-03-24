import SwiftUI
import CoreLocation

struct TripCardView: View {
    let trip: Trip
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Route preview map
            RouteMapView(coordinates: trip.trackPoints.map(\.coordinate), speeds: trip.trackPoints.map(\.speed))
                .frame(height: 120)
                .allowsHitTesting(false)

            // Info section
            VStack(alignment: .leading, spacing: 8) {
                // Title + Date
                if let title = trip.title {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                Text(formattedDate)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textSecondary)

                // Stats row
                HStack(spacing: 16) {
                    TripStatLabel(
                        icon: "location.fill",
                        value: String(format: "%.1f %@", trip.distanceKm, AppStrings.km(lang.language)),
                        color: AppTheme.green
                    )
                    TripStatLabel(
                        icon: "timer",
                        value: trip.formattedDuration,
                        color: AppTheme.accent
                    )
                    if trip.maxSpeedKmh > 0 {
                        TripStatLabel(
                            icon: "speedometer",
                            value: String(format: "%.0f %@", trip.maxSpeedKmh, AppStrings.kmh(lang.language)),
                            color: AppTheme.blue
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .padding(.trailing, 16)
                .padding(.bottom, 18)
        }
        .surfaceCard(cornerRadius: 20)
    }

    private static let dateFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM yyyy, HH:mm"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM yyyy, HH:mm"
        return (ru, en)
    }()

    private var formattedDate: String {
        let fmts = Self.dateFormatters
        return (lang.language == .ru ? fmts.ru : fmts.en).string(from: trip.startDate)
    }
}

// MARK: - Trip Stat Label

private struct TripStatLabel: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color.opacity(0.6))
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}
