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
    var fuelCurrency: String = "€"
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 0) {
            headerRow(c)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Text(trip.title ?? formattedDateFallback)
                .font(.system(size: 17, weight: .heavy))
                .tracking(-0.1)
                .foregroundStyle(c.text)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            mapSection(c)

            metricsStrip(c)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if !trip.earnedBadgeIds.isEmpty {
                TripBadgesRow(
                    badgeIds: trip.earnedBadgeIds,
                    maxVisible: 4,
                    size: 22
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Header Row

    private func headerRow(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        let resolvedName: String = {
            if let n = vehicleName?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
            return isRu ? "Без авто" : "No vehicle"
        }()
        return HStack(spacing: 10) {
            Circle()
                .fill(AppTheme.accentBg)
                .frame(width: 34, height: 34)
                .overlay {
                    if let vehicle, vehicle.isPixelAvatar {
                        vehicle.avatarView(size: 28)
                    } else if vehicle != nil {
                        Text(vehicleEmoji)
                            .font(.system(size: 17))
                    } else {
                        // Fallback for trips with no attached vehicle (typical
                        // for trips synced down from server where the original
                        // device never assigned one). Generic car keeps the
                        // header structure identical across cards instead of
                        // collapsing into a "lone avatar + date" look.
                        Image(systemName: "car.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(c.textTertiary)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(resolvedName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // Privacy pill renders for BOTH states so the row is
                    // structurally identical card-to-card. Public is the
                    // less alarming color (accent vs orange) so it doesn't
                    // pull the eye over actually-private content.
                    privacyPill(c, isPrivate: trip.isPrivate, isRu: isRu).fixedSize()
                }
                Text(formattedDateShort)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // Claim leftover space so the trailing photo pill (when present)
            // and the absence of one produce identical alignment across cards.
            // Without this, an empty `Spacer()` and the optional pill caused
            // the same intrinsic-width drift that hit SocialFeedCardView.
            .frame(maxWidth: .infinity, alignment: .leading)

            if !trip.photos.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                    Text("+\(trip.photos.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(c.cardAlt, in: Capsule())
                .fixedSize()
            }
        }
    }

    private func privacyPill(_ c: AppTheme.Colors, isPrivate: Bool, isRu: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: isPrivate ? "lock.fill" : "globe")
                .font(.system(size: 8, weight: .bold))
            Text(isPrivate
                 ? (isRu ? "Только Вы" : "Only you")
                 : (isRu ? "Видна всем" : "Public"))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(isPrivate ? .orange : AppTheme.accent)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isPrivate ? Color.orange : AppTheme.accent).opacity(0.15), in: Capsule())
    }

    // MARK: - Map Section

    @ViewBuilder
    private func mapSection(_ c: AppTheme.Colors) -> some View {
        if trip.previewCoordinates.count > 1 {
            MapSnapshotPreview(
                coordinates: trip.previewCoordinates,
                tripId: trip.id,
                height: 180
            )
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(
                Rectangle()
                    .stroke(c.border, lineWidth: 0.5)
                    .opacity(0.3)
            )
        }
    }

    // MARK: - Metrics Strip

    private func metricsStrip(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 4) {
            metricBlock(
                value: String(format: "%.1f", trip.distanceKm),
                unit: AppStrings.km(lang.language),
                label: AppStrings.distance(lang.language),
                c: c
            )
            metricBlock(
                value: trip.formattedDuration,
                unit: "",
                label: AppStrings.duration(lang.language),
                c: c
            )
            metricBlock(
                value: String(format: "%.0f", trip.averageSpeedKmh),
                unit: AppStrings.kmh(lang.language),
                label: AppStrings.avgSpeed(lang.language),
                c: c
            )
        }
    }

    private func metricBlock(value: String, unit: String, label: String, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy).monospacedDigit())
                    .tracking(-0.2)
                    .foregroundStyle(c.text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                }
            }
            .lineLimit(1)

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Formatters

    private var formattedDateFallback: String {
        FeedCardDateFormatter.formatter(for: lang.language).string(from: trip.startDate)
    }

    private var formattedDateShort: String {
        var result = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        if let region = trip.region {
            result += " · \(region)"
        }
        return result
    }
}
