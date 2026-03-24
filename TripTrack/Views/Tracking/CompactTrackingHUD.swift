import SwiftUI

struct CompactTrackingHUD: View {
    let speed: Double       // km/h
    let altitude: Double    // meters
    let distance: Double    // km
    let duration: String
    let isPaused: Bool
    let onPause: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @State private var pausePulse = false

    private var speedColor: Color {
        switch speed {
        case ..<40: return AppTheme.green
        case 40..<80: return AppTheme.accent
        default: return AppTheme.red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top highlight
            LinearGradient(
                colors: [.clear, .white.opacity(0.12), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            VStack(spacing: 10) {
                // Top row: speed + pause button
                HStack(alignment: .bottom) {
                    // Speed group
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text("\(Int(speed))")
                            .font(.system(size: 44, weight: .heavy).monospacedDigit())
                            .foregroundStyle(speedColor)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: Int(speed))

                        Text(AppStrings.kmh(lang.language))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppTheme.textTertiary)
                            .padding(.bottom, 3)
                    }

                    Spacer()

                    // Pause button with pulse when paused
                    Button {
                        Haptics.action()
                        onPause()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(isPaused ? AppTheme.green : AppTheme.accent)
                            .frame(width: 48, height: 48)
                            .background(
                                (isPaused ? AppTheme.green : AppTheme.accent).opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .overlay {
                                if isPaused {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(AppTheme.green.opacity(pausePulse ? 0.0 : 0.4), lineWidth: 2)
                                        .scaleEffect(pausePulse ? 1.15 : 1.0)
                                        .animation(
                                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                            value: pausePulse
                                        )
                                }
                            }
                    }
                    .onChange(of: isPaused) { _, newValue in
                        pausePulse = newValue
                    }
                }

                // Bottom row: 3 stats with separators
                HStack(spacing: 0) {
                    CompactStat(icon: "mountain.2", value: "\(Int(altitude))", unit: AppStrings.m(lang.language), color: AppTheme.blue)

                    Divider()
                        .frame(height: 20)
                        .overlay(AppTheme.border)

                    CompactStat(icon: "timer", value: duration, unit: nil, color: AppTheme.accent)

                    Divider()
                        .frame(height: 20)
                        .overlay(AppTheme.border)

                    CompactStat(icon: "location.fill", value: String(format: "%.1f", distance), unit: AppStrings.km(lang.language), color: AppTheme.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .glassBackground(cornerRadius: 20)
        .padding(.horizontal, 10)
    }
}

// MARK: - Compact Stat

private struct CompactStat: View {
    let icon: String
    let value: String
    let unit: String?
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color.opacity(0.7))

            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: value)

            if let unit {
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
