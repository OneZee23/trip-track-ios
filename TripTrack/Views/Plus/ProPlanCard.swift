import SwiftUI

/// The selected plan has both a checkmark and a tinted surface; colour alone
/// must not be the only way to identify the current billing period.
struct ProPlanCard: View {
    let title: String
    /// «Неделя бесплатно» акцентом или «1,67 € в месяц» серым.
    let subtitle: String?
    /// Акцентная подпись — только у бесплатной недели: это обещание, а не
    /// справка.
    let subtitleIsAccent: Bool
    /// «−44 %». `nil` — посчитать не из чего или выгоды нет (`ProPriceMath`).
    let savingText: String?
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.selection()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                    .font(.inter(16, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isSelected ? AppTheme.accent : c.textSecondary)
                        .accessibilityHidden(true)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(AppType.meta)
                        .foregroundStyle(subtitleIsAccent ? AppTheme.accent : c.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AppTheme.accentBg : c.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? AppTheme.accent : c.border,
                                  lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if let savingText {
                    Text(savingText)
                        .font(.inter(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule().fill(AppTheme.accent))
                        .fixedSize()
                        .offset(x: -10, y: -10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
