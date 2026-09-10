import SwiftUI

/// Плашка «REC» поверх ленты, пока идёт запись.
///
/// Расстояние приезжает сюда в МЕТРАХ и подписывается `Measure`. До 0.6.7
/// строка собиралась как `String(format: "%.1f km", distance)`: английское
/// «km» и английская точка мимо всех тринадцати языков — на немецком телефоне
/// «12.4 km» вместо «12,4 км», и ни одна таблица переводов об этой строке не
/// знала, потому что её там не было.
struct RecordingBanner: View {
    /// Метры, а не километры: единица выбирается на показе, и хранить её
    /// внутри параметра значило бы решить за экран.
    let metres: Double
    let duration: String
    let onTap: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var distanceUnit
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

                Text(Measure.distance(
                    metres: metres, unit: distanceUnit, lang: lang.language, style: .tenths))
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
