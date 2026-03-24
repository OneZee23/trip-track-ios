import SwiftUI
import MapKit

struct TripCompleteSummaryView: View {
    let trip: Trip
    var completionData: TripCompletionData?
    let onAddPhoto: () -> Void
    let onAddNotes: () -> Void
    let onDone: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var showXP = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ScrollView {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(c.textTertiary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Title
            Text(lang.language == .ru ? "Поездка завершена!" : "Trip complete!")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(c.text)
                .padding(.top, 20)

            // Route preview
            if trip.trackPoints.count > 1 {
                RouteMapView(
                    coordinates: trip.trackPoints.map(\.coordinate),
                    speeds: trip.trackPoints.map(\.speed)
                )
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                summaryStatCard(
                    value: String(format: "%.1f", trip.distanceKm),
                    unit: AppStrings.km(lang.language),
                    label: AppStrings.distance(lang.language),
                    color: AppTheme.green,
                    c: c
                )
                summaryStatCard(
                    value: trip.formattedDuration,
                    unit: "",
                    label: AppStrings.duration(lang.language),
                    color: AppTheme.accent,
                    c: c
                )
                summaryStatCard(
                    value: String(format: "%.0f", trip.averageSpeedKmh),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.avgSpeed(lang.language),
                    color: AppTheme.blue,
                    c: c
                )
                summaryStatCard(
                    value: String(format: "%.0f", trip.maxSpeedKmh),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.maxSpeed(lang.language),
                    color: AppTheme.red,
                    c: c
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Gamification section
            if let data = completionData {
                gamificationSection(data: data, c: c)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onAddPhoto) {
                    Label(
                        lang.language == .ru ? "Фото" : "Photo",
                        systemImage: "camera.fill"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppTheme.accentBg, in: RoundedRectangle(cornerRadius: 12))
                }

                Button(action: onAddNotes) {
                    Label(
                        lang.language == .ru ? "Заметка" : "Note",
                        systemImage: "pencil"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppTheme.accentBg, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Done button
            Button(action: onDone) {
                Text(lang.language == .ru ? "Готово" : "Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        }
        .background(c.bg)
    }

    // MARK: - Gamification Section

    private func gamificationSection(data: TripCompletionData, c: AppTheme.Colors) -> some View {
        VStack(spacing: 10) {
            // XP earned
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(AppTheme.accent)
                Text("+\(data.xpEarned) XP")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                if data.didLevelUp {
                    Text("LEVEL UP!")
                        .font(.custom("PressStart2P-Regular", size: 9))
                        .foregroundStyle(data.newRank.color)
                }
            }

            // Profile progress
            progressRow(
                icon: "person.fill",
                label: data.newRank.title(lang.language),
                detail: "LVL \(data.newLevel)",
                progress: LevelSystem.progressToNextLevel(xp: data.newXP, level: data.newLevel),
                color: data.newRank.color,
                didLevelUp: data.didLevelUp,
                c: c
            )

            // Vehicle progress
            if data.vehicleOdometerAfter > 0 {
                progressRow(
                    icon: "car.fill",
                    label: String(format: "%.0f km", data.vehicleOdometerAfter),
                    detail: "LVL \(data.vehicleLevelAfter)",
                    progress: VehicleLevelSystem.progressToNext(
                        km: data.vehicleOdometerAfter,
                        level: data.vehicleLevelAfter
                    ),
                    color: AppTheme.blue,
                    didLevelUp: data.didVehicleLevelUp,
                    c: c
                )
            }

            // Streak
            if data.currentStreak > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                    Text(lang.language == .ru
                        ? "\(data.currentStreak) дн. подряд"
                        : "\(data.currentStreak) day streak")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                }
            }

            // Repeat route info
            if let road = data.roadCard, !road.isNew, road.timesDriven > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                    Text(lang.language == .ru
                        ? "Вы проехали этот маршрут уже \(road.timesDriven) раз"
                        : "You've driven this route \(road.timesDriven) times")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                }
            }

            // New badges
            if !data.newBadges.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.badges(lang.language))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(c.textSecondary)

                    HStack(spacing: 10) {
                        ForEach(data.newBadges.prefix(5)) { badge in
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(badge.color.opacity(0.15))
                                        .frame(width: 40, height: 40)
                                        .shadow(color: badge.color.opacity(0.3), radius: 6)

                                    Image(systemName: badge.icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(badge.color)
                                }

                                let count = data.repeatedBadgeCounts[badge.id] ?? 0
                                if badge.isRepeatable && count > 1 {
                                    Text("x\(count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(badge.color)
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 14)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { showXP = true } }
    }

    private func progressRow(
        icon: String, label: String, detail: String,
        progress: Double, color: Color, didLevelUp: Bool,
        c: AppTheme.Colors
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                    Text(detail)
                        .font(.custom("PressStart2P-Regular", size: 8))
                        .foregroundStyle(color)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(c.cardAlt).frame(height: 5)
                        Capsule()
                            .fill(color)
                            .frame(width: max(2, geo.size.width * progress), height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private func summaryStatCard(value: String, unit: String, label: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }
}
