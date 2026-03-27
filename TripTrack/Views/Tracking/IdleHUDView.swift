import SwiftUI

struct IdleHUDView: View {
    let totalKm: Double
    let tripCount: Int
    let onStartTrip: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @State private var isPressing = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    private let holdDuration: CGFloat = 0.4

    var body: some View {
        VStack(spacing: 0) {
            // Pulsing accent ring with pixel car
            ZStack {
                // Outer pulsing glow
                Circle()
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .modifier(PulseRingModifier())

                // Main ring
                Circle()
                    .stroke(AppTheme.accent.opacity(0.7), lineWidth: 2.5)
                    .frame(width: 82, height: 82)

                // Orange glow fill
                Circle()
                    .fill(AppTheme.accent.opacity(0.2))
                    .frame(width: 82, height: 82)

                Image("PixelCar")
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 46, height: 46)
            }
            .padding(.top, 32)
            .padding(.bottom, 20)

            Text(AppStrings.readyToRide(lang.language))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 6)

            if totalKm > 0 || tripCount > 0 {
                Text("\(formatKmWithSeparator(totalKm)) \(AppStrings.totalKm(lang.language)) · \(tripCount) \(AppStrings.trips(lang.language))")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 28)
            } else {
                Spacer().frame(height: 20)
            }

            // Start button — hold to begin recording
            ZStack {
                // Progress border that fills during hold
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.accent)

                // White progress overlay on top
                RoundedRectangle(cornerRadius: 16)
                    .trim(from: 0, to: holdProgress)
                    .stroke(.white.opacity(0.35), lineWidth: 3)

                HStack(spacing: 10) {
                    Image(systemName: isPressing ? "circle.fill" : "play.fill")
                        .font(.system(size: isPressing ? 10 : 16))
                        .contentTransition(.symbolEffect(.replace))
                    Text(isPressing
                         ? (lang.language == .ru ? "Удерживайте..." : "Hold...")
                         : AppStrings.startTrip(lang.language))
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .scaleEffect(isPressing ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPressing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        startHoldTimer()
                    }
                    .onEnded { _ in
                        cancelHold()
                    }
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .onAppear {
                // Subtle pulse hint on the button
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.02
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.75))
                )
        )
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 20)
    }

    private static let kmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        return f
    }()

    private func formatKmWithSeparator(_ km: Double) -> String {
        Self.kmFormatter.string(from: NSNumber(value: km)) ?? "\(Int(km))"
    }

    // MARK: - Hold-to-Start Logic

    private func startHoldTimer() {
        holdProgress = 0
        let step: CGFloat = 0.03
        let increment = step / holdDuration

        holdTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(step), repeats: true) { timer in
            holdProgress += increment
            if holdProgress >= 1.0 {
                timer.invalidate()
                holdTimer = nil
                isPressing = false
                holdProgress = 0

                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
                onStartTrip()
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        isPressing = false
        withAnimation(.easeOut(duration: 0.2)) {
            holdProgress = 0
        }
    }
}

// MARK: - Quick Stat Card

private struct QuickStatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .surfaceCard(cornerRadius: 14)
    }
}

// MARK: - Pulse Ring Animation

private struct PulseRingModifier: ViewModifier {
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(animate ? 1.1 : 1.0)
            .opacity(animate ? 0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
