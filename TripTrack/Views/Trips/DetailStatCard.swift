import SwiftUI

/// Stat card of the trip-detail «Детали» grid (Figma 6.1.0 poster spec):
/// colored ExtraBold value + baseline unit on top, tiny uppercase label
/// below. Shared by the owner detail (10 cards) and the social detail
/// (8 cards — no fuel/cost).
struct DetailStatCard: View {
    let value: String
    var unit: String = ""
    let label: String
    let color: Color
    var staggerIndex: Int = 0
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 23, weight: .heavy).monospacedDigit())
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13))
                        .foregroundStyle(c.textSecondary)
                }
            }

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.2)
                .textCase(.uppercase)
                .foregroundStyle(c.textTertiary)
                // Long localized labels ("НАБОР ВЫСОТЫ") must fit the ~155pt
                // cell without wrapping under the value.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(Double(staggerIndex) * 0.05)) {
                appeared = true
            }
        }
    }
}
