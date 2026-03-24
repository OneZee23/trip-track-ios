import SwiftUI

struct StatView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 70)
    }
}

#Preview {
    HStack(spacing: 24) {
        StatView(value: "245 m", label: "Altitude")
        StatView(value: "12.4 km", label: "Distance")
        StatView(value: "01:23", label: "Time")
    }
    .padding()
    .background(.ultraThinMaterial)
    .preferredColorScheme(.dark)
}
