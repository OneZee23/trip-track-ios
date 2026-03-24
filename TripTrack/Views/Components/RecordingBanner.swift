import SwiftUI

struct RecordingBanner: View {
    let distance: Double    // km
    let duration: String
    let onTap: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.4 : 1.0)
                    .opacity(pulse ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }

                Text("REC")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.red)

                Text(String(format: "%.1f km", distance))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)

                Text("·")
                    .foregroundStyle(AppTheme.textTertiary)

                Text(duration)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassBackground(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }
}
