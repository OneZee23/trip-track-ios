import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Colors

private let accentOrange = Color(red: 1.0, green: 0.584, blue: 0.0)
private let accentRed = Color(red: 1.0, green: 0.231, blue: 0.188)
private let lightBg = Color(red: 0.949, green: 0.949, blue: 0.969)
private let darkBg = Color(red: 0.11, green: 0.11, blue: 0.12)

// MARK: - Adaptive colors

private struct WidgetColors {
    let bg: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let cellBg: Color
    let buttonBg: Color

    static func from(isDark: Bool) -> WidgetColors {
        isDark ? .dark : .light
    }

    static let light = WidgetColors(
        bg: lightBg,
        text: Color.black.opacity(0.85),
        textSecondary: Color.black.opacity(0.45),
        textTertiary: Color.black.opacity(0.3),
        cellBg: Color.black.opacity(0.04),
        buttonBg: Color.black.opacity(0.05)
    )

    static let dark = WidgetColors(
        bg: darkBg,
        text: Color.white.opacity(0.9),
        textSecondary: Color.white.opacity(0.5),
        textTertiary: Color.white.opacity(0.35),
        cellBg: Color.white.opacity(0.08),
        buttonBg: Color.white.opacity(0.1)
    )
}

// MARK: - Widget

struct TripTrackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            if context.state.isFinished {
                FinishedLockScreenView(context: context)
                    .widgetURL(URL(string: "triptrack://trip/\(context.attributes.tripId.uuidString)"))
            } else {
                LiveLockScreenView(context: context)
                    .widgetURL(URL(string: "triptrack://recording"))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.isFinished {
                        Image("app_icon")
                            .resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(context.state.speedKmh))").font(.title2.bold())
                            + Text(" km/h").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmtDist(context.state.distanceKm)).font(.title2.bold())
                        + Text(context.state.isRu ? " км" : " km").font(.caption).foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isFinished {
                        Text(context.state.finalDuration ?? "").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        timerText(context: context).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.isFinished {
                        HStack(spacing: 12) {
                            Button(intent: PauseTripIntent()) {
                                HStack(spacing: 6) {
                                    Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text(context.state.isPaused
                                         ? (context.state.isRu ? "Продолжить" : "Resume")
                                         : (context.state.isRu ? "Пауза" : "Pause"))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                            Button(intent: StopTripIntent()) {
                                Image(systemName: "square.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(accentRed)
                                    .frame(width: 48).padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .background(accentRed.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            } compactLeading: {
                if context.state.isFinished {
                    Image("app_icon")
                        .resizable().scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Label {
                        Text("\(Int(context.state.speedKmh))").font(.caption.bold())
                    } icon: {
                        Image(systemName: "location.fill").foregroundStyle(accentOrange)
                    }
                }
            } compactTrailing: {
                Text(fmtDist(context.state.distanceKm) + (context.state.isRu ? " км" : " km")).font(.caption)
            } minimal: {
                if context.state.isFinished {
                    Image("app_icon")
                        .resizable().scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "location.fill")
                        .foregroundStyle(accentOrange)
                }
            }
            .widgetURL(context.state.isFinished
                ? URL(string: "triptrack://trip/\(context.attributes.tripId.uuidString)")
                : URL(string: "triptrack://recording"))
        }
    }

    @ViewBuilder
    private func timerText(context: ActivityViewContext<TripActivityAttributes>) -> some View {
        if context.state.isPaused, let elapsed = context.state.elapsedAtPause {
            Text(fmtTime(elapsed)).monospacedDigit()
        } else if context.state.isPaused {
            Text("--:--").monospacedDigit()
        } else {
            let adj = context.attributes.startDate.addingTimeInterval(context.state.pausedDuration)
            Text(timerInterval: adj...(.distantFuture), countsDown: false).monospacedDigit()
        }
    }

    private func fmtDist(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
    }

    private func fmtTime(_ s: TimeInterval) -> String {
        let t = max(0, Int(s)); let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Live Recording Lock Screen

private struct LiveLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>
    private var isRu: Bool { context.state.isRu }
    private var isPixel: Bool { context.attributes.vehicleAvatar.hasPrefix("pixel_car_") }
    private var c: WidgetColors { .from(isDark: context.state.isDarkMode) }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: Header + TripTrack label
            HStack(spacing: 10) {
                // Car icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentOrange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    if isPixel {
                        Image(context.attributes.vehicleAvatar)
                            .resizable().scaledToFit()
                            .frame(width: 28, height: 28)
                    } else {
                        Text(context.attributes.vehicleAvatar)
                            .font(.system(size: 18))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(context.state.isPaused
                             ? (context.state.isRu ? "На паузе" : "Paused")
                             : (context.state.isRu ? "Запись маршрута" : "Recording"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        if !context.state.isPaused {
                            Circle().fill(accentRed).frame(width: 6, height: 6)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill").font(.system(size: 10))
                        Text(context.attributes.vehicleName).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                // TripTrack branding
                Text("TripTrack")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.bottom, 10)

            // Row 2: Stats
            HStack(spacing: 8) {
                statCell(
                    label: isRu ? "ВРЕМЯ В ПУТИ" : "TIME",
                    value: { timerValue }
                )
                statCell(
                    label: isRu ? "ПРОЙДЕНО" : "DIST",
                    value: {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(fmtDist(context.state.distanceKm))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(c.text)
                            Text(context.state.isRu ? "км" : "km")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                )
            }
            .padding(.bottom, 8)

            // Row 3: Controls
            HStack(spacing: 8) {
                Button(intent: PauseTripIntent()) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text(context.state.isPaused
                             ? (context.state.isRu ? "Продолжить" : "Resume")
                             : (context.state.isRu ? "Пауза" : "Pause"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
                .background(c.buttonBg, in: RoundedRectangle(cornerRadius: 12))

                Button(intent: StopTripIntent()) {
                    Image(systemName: "square.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentRed)
                        .frame(width: 52, height: 36)
                }
                .buttonStyle(.plain)
                .background(accentRed.opacity(context.state.isDarkMode ? 0.2 : 0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .activityBackgroundTint(c.bg)
    }

    private func statCell<V: View>(label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(c.textTertiary)
                .tracking(0.4)
            value()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(c.cellBg, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var timerValue: some View {
        Group {
            if context.state.isPaused, let elapsed = context.state.elapsedAtPause {
                Text(fmtTime(elapsed))
            } else if context.state.isPaused {
                Text("--:--")
            } else {
                let adj = context.attributes.startDate.addingTimeInterval(context.state.pausedDuration)
                Text(timerInterval: adj...(.distantFuture), countsDown: false)
            }
        }
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(c.text)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func fmtDist(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
    }

    private func fmtTime(_ s: TimeInterval) -> String {
        let t = max(0, Int(s)); let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Gradient colors (finished screen)

private let gradientStart = Color(red: 1.0, green: 0.78, blue: 0.47)
private let gradientEnd = Color(red: 1.0, green: 0.63, blue: 0.31)

// MARK: - Finished Lock Screen

private struct FinishedLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>
    private var isRu: Bool { context.state.isRu }
    private var isPixel: Bool { context.attributes.vehicleAvatar.hasPrefix("pixel_car_") }

    var body: some View {
        VStack(spacing: 0) {
            // Row 1: vehicle avatar + text + AppIcon
            HStack(spacing: 12) {
                // Left: vehicle avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 44, height: 44)
                    if isPixel {
                        Image(context.attributes.vehicleAvatar)
                            .resizable().scaledToFit()
                            .frame(width: 32, height: 32)
                    } else {
                        Text(context.attributes.vehicleAvatar)
                            .font(.system(size: 22))
                    }
                }

                // Center: title + subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRu ? "Маршрут сохранен" : "Route saved")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineLimit(1)
                    Text(summaryText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Right: AppIcon
                Image("app_icon")
                    .resizable().scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.bottom, 12)

            // Row 2: Glass CTA button
            Text(isRu ? "Открыть автодневник" : "Open trip diary")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [gradientStart, gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(accentOrange)
    }

    private var summaryText: String {
        let d = context.state.distanceKm < 10
            ? String(format: "%.1f", context.state.distanceKm)
            : String(format: "%.0f", context.state.distanceKm)
        let u = isRu ? "км" : "km"
        return "\(context.attributes.vehicleName) • \(d) \(u) • \(context.state.finalDuration ?? "--:--")"
    }
}
