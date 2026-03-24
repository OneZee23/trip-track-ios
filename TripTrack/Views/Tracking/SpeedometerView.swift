import SwiftUI

struct SpeedometerView: View {
    let speed: Double
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(Int(speed))")
                .font(.system(size: compact ? 36 : 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("km/h")
                .font(compact ? .caption : .subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SpeedometerView(speed: 87)
        SpeedometerView(speed: 87, compact: true)
    }
    .preferredColorScheme(.dark)
}
