import SwiftUI

/// GPS accuracy pill (Figma 428:124): word label + colored dot, four states —
/// точный (≤10м, green) / средний (10–35м, yellow) / слабый (>35м, red) /
/// потерян (stale fix, amber). Thresholds mirror the recording pipeline
/// (`maxRecordAccuracy` 65м drops points beyond). Tap shows the legend.
struct GPSIndicatorView: View {
    let accuracy: Double // meters; 0 = no fix yet
    var isStale: Bool = false
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var showTooltip = false
    @State private var autoDismissTask: DispatchWorkItem?

    enum Signal {
        /// No fix accepted yet — the receiver is still warming up. This is
        /// NOT a weak signal, and calling it one is what made the screen read
        /// as broken: a red «GPS слабый» sitting there the whole time you
        /// wait, when the honest answer is «ещё ищем».
        case searching
        case accurate, medium, weak, lost

        var color: Color {
            switch self {
            case .searching: return Color(red: 0x8E/255, green: 0x8E/255, blue: 0x93/255)
            case .accurate:  return Color(red: 0x30/255, green: 0xD1/255, blue: 0x58/255)
            case .medium:    return Color(red: 0xFF/255, green: 0xD6/255, blue: 0x0A/255)
            case .weak:      return Color(red: 0xFF/255, green: 0x45/255, blue: 0x3A/255)
            case .lost:      return Color(red: 0xF5/255, green: 0xA6/255, blue: 0x23/255)
            }
        }

        func label(_ lang: LanguageManager.Language) -> String {
            switch self {
            case .searching: return AppStrings.gpsSearching(lang)
            case .accurate:  return AppStrings.gpsAccurate(lang)
            case .medium:    return AppStrings.gpsMedium(lang)
            case .weak:      return AppStrings.gpsWeak(lang)
            case .lost:      return AppStrings.gpsLost(lang)
            }
        }
    }

    private var signal: Signal {
        if isStale { return .lost }
        guard accuracy > 0 else { return .searching }
        if accuracy <= 10 { return .accurate }
        if accuracy <= 35 { return .medium }
        return .weak
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(signal.color)
                .frame(width: 8, height: 8)

            Text(signal.label(lang.language))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.72))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .onTapGesture {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showTooltip.toggle()
            }
            scheduleAutoDismiss()
        }
        .overlay(alignment: .topTrailing) {
            if showTooltip {
                tooltipCard
                    .offset(y: 44)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }

    /// Figma 428:124 legend: three signal grades with plain-word explanations.
    private var tooltipCard: some View {
        let c = AppTheme.colors(for: scheme)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(signal.color)
                Text(AppStrings.gpsAccuracyTitle(lang.language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { showTooltip = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(c.cardAlt, in: Circle())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if signal == .searching {
                    legendRow(signal: .searching, detail: AppStrings.gpsLegendSearching(lang.language))
                }
                legendRow(signal: .accurate, detail: AppStrings.gpsLegendAccurate(lang.language))
                legendRow(signal: .medium, detail: AppStrings.gpsLegendMedium(lang.language))
                legendRow(signal: .weak, detail: AppStrings.gpsLegendWeak(lang.language))
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(c.card)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(c.border, lineWidth: 1)
        )
    }

    private func legendRow(signal: Signal, detail: String) -> some View {
        let c = AppTheme.colors(for: scheme)
        return HStack(spacing: 8) {
            Circle().fill(signal.color).frame(width: 8, height: 8)
            Text(signal.label(lang.language))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(c.text)
            Spacer(minLength: 6)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(c.textSecondary)
        }
    }

    private func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        guard showTooltip else { return }
        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.3)) { showTooltip = false }
        }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: task)
    }
}
