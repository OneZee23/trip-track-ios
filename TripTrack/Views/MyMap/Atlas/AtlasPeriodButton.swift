import SwiftUI

/// Кнопка периода в заголовке вкладки (спека §3.2).
///
/// Круг 36 с одной иконкой и БЕЗ текста — текста на ней нет никогда. Как
/// называется выбранный период, говорит заголовок блока сводки
/// («Исследовано 24…27 сент.»): два места, называющие одно и то же, однажды
/// разъедутся, а на кнопке в 36 pt имя периода и не поместится.
///
/// В пустом атласе кнопки нет вовсе — фильтровать нечего.
struct AtlasPeriodButton: View {
    /// Выбран ли период. Выбранная кнопка залита `soft` и несёт точку
    /// акцента в правом верхнем углу.
    let isFiltered: Bool
    /// «Период: всё время» или «Период: 24…27 сентября, выбран» (спека §7).
    let accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "calendar")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isFiltered ? AtlasTheme.accentInk : AtlasTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(background)

                if isFiltered {
                    Circle()
                        .fill(AtlasTheme.accent)
                        .frame(width: 8, height: 8)
                        // Обводка цветом фона — чтобы точка читалась и на
                        // карте, и на бумаге заголовка.
                        .overlay(Circle().strokeBorder(AtlasTheme.background, lineWidth: 2))
                        .offset(x: 2, y: -2)
                }
            }
            // Цель 44 × 44 при круге 36 (спека §7).
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityIdentifier("atlas_period")
    }

    @ViewBuilder
    private var background: some View {
        if isFiltered {
            Circle().fill(AtlasTheme.accentSoft)
        } else {
            Color.clear.atlasGlass(Circle())
        }
    }
}
