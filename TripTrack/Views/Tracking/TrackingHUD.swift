import SwiftUI

struct TrackingHUD: View {
    let speed: Double
    let altitude: Double
    let distance: Double
    let duration: String
    let isRecording: Bool
    let onToggleRecording: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if isExpanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Compact: single row with speed + button
    private var compactContent: some View {
        HStack(spacing: 12) {
            SpeedometerView(speed: speed, compact: true)

            Spacer()

            // Mini stats
            HStack(spacing: 14) {
                MiniStat(icon: "road.lanes", value: String(format: "%.1f", distance), unit: "km")
                MiniStat(icon: "clock", value: duration, unit: nil)
            }

            Spacer()

            recordButton(compact: true)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Expanded: full stats + big button
    private var expandedContent: some View {
        VStack(spacing: 14) {
            SpeedometerView(speed: speed)

            HStack(spacing: 20) {
                StatView(value: String(format: "%.0f m", altitude), label: "Altitude")
                StatView(value: String(format: "%.1f km", distance), label: "Distance")
                StatView(value: duration, label: "Time")
            }

            recordButton(compact: false)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Record button
    private func recordButton(compact: Bool) -> some View {
        Button(action: onToggleRecording) {
            Group {
                if compact {
                    Image(systemName: isRecording ? "stop.fill" : "play.fill")
                        .font(.title3)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: isRecording ? "stop.fill" : "record.circle")
                            .font(.body)
                        Text(isRecording ? "Stop" : "Start Trip")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 14 : 0)
            .padding(.vertical, compact ? 10 : 12)
            .background(isRecording ? Color.red : Color.green)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 12 : 14))
        }
    }
}

// MARK: - Mini stat for compact mode
private struct MiniStat: View {
    let icon: String
    let value: String
    let unit: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
            if let unit {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Compact") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            TrackingHUD(
                speed: 67.3,
                altitude: 245,
                distance: 12.4,
                duration: "01:23:45",
                isRecording: true,
                onToggleRecording: {}
            )
        }
    }
    .preferredColorScheme(.dark)
}
