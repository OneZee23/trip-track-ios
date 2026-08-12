import SwiftUI

/// Stat card of the trip-detail «Детали» grid (Figma 6.1.0 poster spec):
/// colored ExtraBold value + baseline unit on top, tiny uppercase label
/// below. Shared by the owner detail (10 cards) and the social detail
/// (8 cards — no fuel/cost).
struct DetailStatCard: View {
    /// One number and the unit that follows it. Most cards are a single
    /// segment («21.5» + «км»); a duration is two («4» + «ч», «58» + «мин»),
    /// which is how the canon writes time — never as a clock reading.
    struct Segment: Equatable {
        let value: String
        var unit: String = ""
    }

    let segments: [Segment]
    let label: String
    let color: Color
    var staggerIndex: Int = 0
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    init(segments: [Segment], label: String, color: Color, staggerIndex: Int = 0) {
        self.segments = segments
        self.label = label
        self.color = color
        self.staggerIndex = staggerIndex
    }

    init(value: String, unit: String = "", label: String, color: Color, staggerIndex: Int = 0) {
        self.init(
            segments: [Segment(value: value, unit: unit)],
            label: label, color: color, staggerIndex: staggerIndex
        )
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 6) {
            // Concatenated Text, not an HStack: «4 ч 58 мин» has to shrink as
            // ONE piece of type. Separate views each apply the scale factor for
            // themselves, and a tight cell ends up with a small «4» beside a
            // full-size «58».
            valueText(c)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

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
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(Double(staggerIndex) * 0.05)) {
                appeared = true
            }
        }
    }

    /// «4 ч 58 мин» as a single run of text — numbers in the card's colour,
    /// units small and secondary.
    private func valueText(_ c: AppTheme.Colors) -> Text {
        let big = Font.system(size: 23, weight: .heavy).monospacedDigit()
        let small = Font.system(size: 13)
        var out = AttributedString()
        for (i, seg) in segments.enumerated() {
            if i > 0 {
                var gap = AttributedString(" ")
                gap.font = small
                out += gap
            }
            var value = AttributedString(seg.value)
            value.font = big
            value.foregroundColor = color
            out += value
            if !seg.unit.isEmpty {
                var unit = AttributedString(" \(seg.unit)")
                unit.font = small
                unit.foregroundColor = c.textSecondary
                out += unit
            }
        }
        return Text(out)
    }
}
