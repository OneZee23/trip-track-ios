import ActivityKit
import SwiftUI
import WidgetKit

struct TripTrackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            // Lock Screen banner
            if context.state.isFinished {
                FinishedLockScreenView(context: context)
                    .widgetURL(URL(string: "triptrack://trip/\(context.attributes.tripId.uuidString)"))
            } else {
                LiveLockScreenView(context: context)
                    .widgetURL(URL(string: "triptrack://recording"))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.isFinished {
                        VStack(alignment: .leading, spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            Text("Done")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(context.state.speedKmh))")
                                .font(.title2.bold())
                            + Text(" km/h")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formattedDistance(context.state.distanceKm))
                            .font(.title2.bold())
                        + Text(" km")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isFinished {
                        if let dur = context.state.finalDuration {
                            Text(dur)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } else {
                        durationView(context: context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.isFinished {
                        HStack(spacing: 16) {
                            Button(intent: PauseTripIntent()) {
                                Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                    .font(.body.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                            Button(intent: StopTripIntent()) {
                                Image(systemName: "stop.fill")
                                    .font(.body.bold())
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            } compactLeading: {
                if context.state.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label {
                        Text("\(Int(context.state.speedKmh))")
                            .font(.caption.bold())
                    } icon: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                    }
                }
            } compactTrailing: {
                Text(formattedDistance(context.state.distanceKm) + " km")
                    .font(.caption)
            } minimal: {
                if context.state.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.blue)
                }
            }
            .widgetURL(context.state.isFinished
                ? URL(string: "triptrack://trip/\(context.attributes.tripId.uuidString)")
                : URL(string: "triptrack://recording")
            )
        }
    }

    // MARK: - Duration View

    @ViewBuilder
    private func durationView(context: ActivityViewContext<TripActivityAttributes>) -> some View {
        if context.state.isPaused {
            let elapsed = Date().timeIntervalSince(context.attributes.startDate) - context.state.pausedDuration
            Text(formatDuration(elapsed))
                .monospacedDigit()
        } else {
            let adjustedStart = context.attributes.startDate.addingTimeInterval(context.state.pausedDuration)
            Text(timerInterval: adjustedStart...(.distantFuture), countsDown: false)
                .monospacedDigit()
        }
    }

    // MARK: - Helpers

    private func formattedDistance(_ km: Double) -> String {
        if km < 10 {
            return String(format: "%.1f", km)
        }
        return String(format: "%.0f", km)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Live Recording Lock Screen

private struct LiveLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        VStack(spacing: 0) {
            // Branding header
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
                Text("TripTrack")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Main content
            HStack(spacing: 12) {
                // Speed
                VStack(spacing: 2) {
                    Text("\(Int(context.state.speedKmh))")
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("km/h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64)

                // Divider
                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: 36)

                // Distance + Duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "road.lanes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formattedDistance(context.state.distanceKm) + " km")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        durationView
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }

                Spacer()

                // Buttons
                HStack(spacing: 8) {
                    Button(intent: PauseTripIntent()) {
                        Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Circle())

                    Button(intent: StopTripIntent()) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Duration

    @ViewBuilder
    private var durationView: some View {
        if context.state.isPaused {
            let elapsed = Date().timeIntervalSince(context.attributes.startDate) - context.state.pausedDuration
            Text(formatDuration(elapsed))
        } else {
            let adjustedStart = context.attributes.startDate.addingTimeInterval(context.state.pausedDuration)
            Text(timerInterval: adjustedStart...(.distantFuture), countsDown: false)
        }
    }

    private func formattedDistance(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Finished Trip Lock Screen

private struct FinishedLockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        VStack(spacing: 0) {
            // Branding header
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("TripTrack")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Tap to view details")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Summary
            HStack(spacing: 0) {
                // Distance
                VStack(spacing: 2) {
                    Text(formattedDistance(context.state.distanceKm))
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("km")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: 32)

                // Duration
                VStack(spacing: 2) {
                    Text(context.state.finalDuration ?? "--:--")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: 32)

                // Avg Speed
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", context.state.averageSpeedKmh ?? 0))
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("avg km/h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func formattedDistance(_ km: Double) -> String {
        km < 10 ? String(format: "%.1f", km) : String(format: "%.0f", km)
    }
}
