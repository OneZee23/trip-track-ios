import SwiftUI

/// Плитка итога «Атласа»: число крупно, подпись под ним.
///
/// ОДНА на обзор и на карточку региона. До 0.8.1 их было две копии, и
/// разъехались они ровно там, где это видно: у региона подпись сжималась
/// вместе с числом, потому что `minimumScaleFactor` стоял на всей колонке —
/// «172 мили здоровые, и даже не видно, что это новых дорог» (владелец на
/// устройстве 26 сентября). Теперь ужимается ТОЛЬКО число, а подпись имеет
/// право на вторую строку и не мельчает никогда.
///
/// Высота у плиток ряда общая (`maxHeight: .infinity` внутри `HStack`):
/// «68 поездок» рядом с «1 697 км» иначе давало ступеньку.
struct AtlasStatTile: View {
    let value: String
    let label: String
    var accent: Bool = false
    /// Нажимаемая плитка получает шеврон: если нажатие что-то открывает —
    /// это видно, если не открывает — не притворяемся (CLAUDE.md).
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { tile }
                .buttonStyle(PressableCardStyle())
        } else {
            tile
        }
    }

    private var tile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(AppType.statValue)
                .tracking(AppType.statValueTracking)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .foregroundStyle(accent ? AtlasTheme.accent : AtlasTheme.ink)
            HStack(spacing: 3) {
                Text(label)
                    .font(AppType.statCaption)
                    .tracking(AppType.statCaptionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(AtlasTheme.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AtlasTheme.secondary.opacity(0.8))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.statRadius))
    }
}

/// Ряд плиток. Существует ради одной строки — общей высоты, — но именно её
/// забывали оба места показа.
struct AtlasStatRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            content
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
