import SwiftUI
import MapKit
import PhotosUI

struct TripCompleteSummaryView: View {
    let trip: Trip
    var completionData: TripCompletionData?
    let onPhotoSaved: (UIImage) -> Void
    let onDone: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @State private var showXP = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var savedPhotoCount = 0
    /// Figma 147:1251: OFF by default — trips stay private until the user
    /// opts in. Applied on «Готово».
    @State private var publishToFeed = false

    var body: some View {
        // The finish screen is light-themed by design (Figma 147:1190) —
        // celebration reads better on the warm cream, independent of theme.
        let c = AppTheme.colors(for: .light)

        ScrollView {
        VStack(spacing: 0) {
            // No drag grabber: the sheet is presented with interactive
            // dismiss disabled (ContentView), and Figma 147:1190 has none —
            // showing the affordance would advertise a dead gesture.
            confettiHeader
                .padding(.top, 18)

            // Title
            Text(AppStrings.tripFinishedTitle(lang.language))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.top, 8)

            // Route preview (speed-gradient polylines via RouteMapView)
            if trip.trackPoints.count > 1 {
                RouteMapView(
                    coordinates: trip.trackPoints.map(\.coordinate),
                    speeds: trip.trackPoints.map(\.speed)
                )
                .frame(height: 139)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.top, 14)
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
                    // Figma 147:1190: time is neutral dark, not accent.
                    color: c.text,
                    c: c
                )
                summaryStatCard(
                    value: String(format: "%.0f", trip.displayAverageSpeedKmh(SettingsManager.shared.avgSpeedMode)),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.avgSpeed(lang.language),
                    color: AppTheme.blue,
                    c: c
                )
                summaryStatCard(
                    value: String(format: "%.0f", trip.maxSpeedKmh),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.maxShort(lang.language),
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

            // Publish row (Figma 147:1251): OFF by default; the footnote is
            // the privacy invariant. Applied on «Готово».
            publishRow(c)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // Photo + Done, side by side (Figma bottom row).
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: savedPhotoCount > 0 ? "checkmark.circle.fill" : "camera.fill")
                            .font(.system(size: 15))
                        Text(savedPhotoCount > 0
                             ? "\(AppStrings.photoShort(lang.language)) (\(savedPhotoCount))"
                             : AppStrings.photoShort(lang.language))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 1))
                }

                Button {
                    if publishToFeed {
                        mapVM.tripManager.updatePrivacy(for: trip.id, isPrivate: false)
                        NotificationCenter.default.post(
                            name: .tripPrivacyChanged,
                            object: PrivacyChangePayload(tripId: trip.id, isPrivate: false)
                        )
                    }
                    onDone()
                } label: {
                    Text(AppStrings.done(lang.language))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
                }
                .accessibilityIdentifier("summary_done")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onPhotoSaved(image)
                        savedPhotoCount += 1
                    }
                    selectedPhotoItem = nil
                }
            }
        }
        }
        .background(c.bg)
        .environment(\.colorScheme, .light)
    }

    /// Eight static rotated confetti squares (Figma header decoration).
    private var confettiHeader: some View {
        let pieces: [(color: Color, rotation: Double, x: CGFloat, y: CGFloat)] = [
            (AppTheme.accent, 18, -120, 8), (Color(red: 0xF5/255, green: 0xBE/255, blue: 0x1E/255), -24, -78, -6),
            (Color(red: 0x2E/255, green: 0xAE/255, blue: 0x50/255), 40, -30, 10), (AppTheme.accent, -12, 12, -8),
            (Color(red: 0x38/255, green: 0x84/255, blue: 0xE0/255), 28, 48, 6), (AppTheme.red, -35, 88, -4),
            (Color(red: 0x50/255, green: 0xBE/255, blue: 0xD2/255), 12, 124, 9), (AppTheme.accent, -20, 156, -2),
        ]
        return ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(piece.color)
                    .frame(width: 6, height: 6)
                    .rotationEffect(.degrees(piece.rotation))
                    .offset(x: piece.x, y: piece.y)
            }
        }
        .frame(height: 24)
        .allowsHitTesting(false)
    }

    /// «Опубликовать в ленту» + subtitle + privacy footnote + toggle.
    private func publishRow(_ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 38, height: 38)
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.publishToFeed(lang.language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                Text(AppStrings.publishToFeedSubtitle(lang.language))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text(AppStrings.publishFootnote(lang.language))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $publishToFeed)
                .labelsHidden()
                .tint(AppTheme.accent)
                .accessibilityLabel(AppStrings.publishToFeed(lang.language))
                .accessibilityIdentifier("publish_toggle")
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    // MARK: - Gamification Section

    private func gamificationSection(data: TripCompletionData, c: AppTheme.Colors) -> some View {
        VStack(spacing: 10) {
            // XP earned (Figma 147:1190: bare «+N XP» ↔ pixel LEVEL UP pill)
            HStack {
                Text("+\(data.xpEarned) XP")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                if data.didLevelUp {
                    Text("LEVEL UP!")
                        .font(.custom("PressStart2P-Regular", size: 9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.11, green: 0.11, blue: 0.11)))
                        .overlay(Capsule().strokeBorder(AppTheme.accent, lineWidth: 1.5))
                }
            }

            // Single rank progress row — vehicle progression lives in the
            // garage, not on the finish card (Figma 147:1232).
            progressRow(
                icon: "person.fill",
                label: data.newRank.title(lang.language),
                detail: "LVL \(data.newLevel)",
                progress: LevelSystem.progressToNextLevel(xp: data.newXP, level: data.newLevel),
                color: data.newRank.color,
                didLevelUp: data.didLevelUp,
                c: c
            )

            // Streak (Figma 147:1241: «14 дней подряд»)
            if data.currentStreak > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                    Text(AppStrings.streakDaysInARow(lang.language, n: data.currentStreak))
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
                    Text(AppStrings.repeatRouteTimes(lang.language, n: road.timesDriven))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                }
            }

            // New badges — Figma: 46pt tinted circle + the badge NAME below
            // (repeat count folds into the name row when applicable).
            if !data.newBadges.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(data.newBadges.prefix(4)) { badge in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(badge.color.opacity(0.15))
                                    .frame(width: 46, height: 46)
                                    .shadow(color: badge.color.opacity(0.3), radius: 6)

                                Image(systemName: badge.icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(badge.color)
                            }

                            let count = data.repeatedBadgeCounts[badge.id] ?? 0
                            Text(badge.isRepeatable && count > 1
                                 ? "\(badge.title(lang.language)) ×\(count)"
                                 : badge.title(lang.language))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(badge.color)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(width: 74)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        // XP card (Figma 147:1190): warm tint + accent border + accent glow.
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0xFF/255, green: 0xF7/255, blue: 0xF0/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.accent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: AppTheme.accent.opacity(0.12), radius: 16, y: 4)
        // Entrance fade-in keyed on showXP, triggered from onAppear below.
        .opacity(showXP ? 1 : 0)
        .scaleEffect(showXP ? 1 : 0.97)
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
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .heavy).monospacedDigit())
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
            }
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }
}
