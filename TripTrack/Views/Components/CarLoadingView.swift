import SwiftUI

/// Animated car loading indicator — TripTrack's branded replacement for ProgressView.
struct CarLoadingView: View {
    enum Size {
        case compact   // inline, small (e.g. thumbnail placeholder)
        case standard  // full-size with optional text
    }

    var size: Size = .standard
    var text: String? = nil

    @State private var driving = false
    @State private var rocking = false
    @State private var dotPhase = false

    private var iconSize: CGFloat { size == .compact ? 18 : 28 }
    private var dotSize: CGFloat { size == .compact ? 3 : 4 }
    private var dotSpacing: CGFloat { size == .compact ? 6 : 10 }
    private var driveRange: CGFloat { size == .compact ? 12 : 24 }
    private var roadWidth: CGFloat { size == .compact ? 50 : 80 }

    var body: some View {
        VStack(spacing: size == .compact ? 6 : 14) {
            ZStack {
                // Dashed road line
                RoundedRectangle(cornerRadius: 1)
                    .fill(AppTheme.textTertiary.opacity(0.3))
                    .frame(width: roadWidth, height: 2)
                    .offset(y: iconSize * 0.55)

                // Road dots (animated sequential)
                HStack(spacing: dotSpacing) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(AppTheme.textTertiary)
                            .frame(width: dotSize, height: dotSize)
                            .opacity(dotPhase ? (i % 2 == 0 ? 0.8 : 0.3) : (i % 2 == 0 ? 0.3 : 0.8))
                    }
                }
                .offset(y: iconSize * 0.55)
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: dotPhase
                )

                // Car driving left ↔ right
                Image(systemName: "car.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .offset(x: driving ? driveRange : -driveRange)
                    .rotationEffect(.degrees(rocking ? 3 : -3))
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                        value: driving
                    )
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever(autoreverses: true),
                        value: rocking
                    )
            }

            if size == .standard, let text {
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textTertiary)
            }
        }
        .onAppear {
            driving = true
            rocking = true
            dotPhase = true
        }
    }
}
