import SwiftUI
import MapKit

private enum FeedCardDateFormatter {
    static let ruFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()
    static let enFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()
    static func formatter(for lang: LanguageManager.Language) -> DateFormatter {
        lang == .ru ? ruFormatter : enFormatter
    }
}

struct FeedTripCardView: View {
    let trip: Trip
    var vehicleName: String?
    var vehicleEmoji: String = "🚗"
    var vehicle: Vehicle?
    var fuelCurrency: String = "₽"
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 0) {
                // Top: car emoji + vehicle name / date + photo badge
                HStack(spacing: 10) {
                    Circle()
                        .fill(AppTheme.accentBg)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Text(vehicleEmoji)
                                .font(.system(size: 18))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        if let name = vehicleName, !name.isEmpty {
                            Text(name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(c.text)
                                .lineLimit(1)
                        }

                        Text(formattedDateShort)
                            .font(.system(size: 12))
                            .foregroundStyle(c.textTertiary)
                    }

                    Spacer()

                    if !trip.photos.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(c.textTertiary)
                            Text("+\(trip.photos.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(c.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(c.cardAlt, in: Capsule())
                    }
                }
                .padding(.bottom, 10)

                // Trip title
                Text(trip.title ?? formattedDateFallback)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(c.text)
                    .lineLimit(2)
                    .padding(.bottom, 12)

                // Route preview on map
                if trip.previewCoordinates.count > 1 {
                    MapSnapshotPreview(
                        coordinates: trip.previewCoordinates,
                        tripId: trip.id
                    )
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 12)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(c.cardAlt)
                        .frame(height: 80)
                        .overlay {
                            Image(systemName: "map")
                                .font(.system(size: 24))
                                .foregroundStyle(c.textTertiary)
                        }
                        .padding(.bottom, 12)
                }

                // Primary stats: 3-column grid (distance, duration, avg speed)
                HStack(spacing: 4) {
                    statBlock(
                        value: String(format: "%.1f", trip.distanceKm),
                        unit: " \(AppStrings.km(lang.language))",
                        label: AppStrings.distance(lang.language),
                        c: c
                    )
                    statBlock(
                        value: trip.formattedDuration,
                        unit: "",
                        label: AppStrings.duration(lang.language),
                        c: c
                    )
                    statBlock(
                        value: String(format: "%.0f", trip.averageSpeedKmh),
                        unit: " \(AppStrings.kmh(lang.language))",
                        label: AppStrings.avgSpeed(lang.language),
                        c: c
                    )
                }

                // Earned badges
                if !trip.earnedBadgeIds.isEmpty {
                    TripBadgesRow(
                        badgeIds: trip.earnedBadgeIds,
                        maxVisible: 4,
                        size: 22
                    )
                    .padding(.top, 4)
                }

            }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Stat Block

    private func statBlock(value: String, unit: String, label: String, c: AppTheme.Colors, size: CGFloat = 20) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: size, weight: .heavy))
                    .foregroundStyle(c.text)
                Text(unit)
                    .font(.system(size: size * 0.65, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }
            .lineLimit(1)

            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: - Formatters

    private var formattedDateFallback: String {
        FeedCardDateFormatter.formatter(for: lang.language).string(from: trip.startDate)
    }

    private var formattedDateShort: String {
        var result = FeedCardDateFormatter.formatter(for: lang.language).string(from: trip.startDate)
        if let region = trip.region {
            result += " · \(region)"
        }
        return result
    }
}

