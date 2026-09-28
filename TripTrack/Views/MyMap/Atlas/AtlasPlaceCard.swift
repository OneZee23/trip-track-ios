import SwiftUI

/// Карточка выбранного места в слоте (спека §3.7, доски 3, 21, 25…28, S6).
///
/// Три строки и крестик, больше ничего. Адрес, расстояние от дома, время в
/// пути и статистика живут на экране места — здесь их нет не по забывчивости:
/// карточка отвечает на «что это и сколько раз», а не пересказывает экран,
/// который открывается одним нажатием.
///
/// Выносок над булавками нет вовсе (принцип 1): всё, что говорится о
/// выбранном месте, говорится ЗДЕСЬ, в одном слоте у нижнего края.
struct AtlasPlaceCard: View {
    /// Что нарисовано в плитке 44 (спека §3.7): булавка у места, дом у дома.
    /// Третий вид — пунктирная точка у несохранённой остановки — появится
    /// вместе с подсказками на «Атласе»; их там пока нет вовсе.
    enum Tile { case place, home }

    var tile: Tile = .place
    let name: String
    /// Одна строка смысла: «Здесь 12 раз · 20 сент.».
    let line: String
    /// Действие словами, а не стрелкой: «Открыть место».
    let actionTitle: String
    let onOpen: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Высота карточки из спеки. Числом, а не по содержимому: от неё
    /// считается верх слота, а значит и место кнопок карты над ней.
    static let height: CGFloat = 96

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tileView
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppType.itemTitle)
                    .foregroundStyle(AtlasTheme.ink)
                    .lineLimit(2)
                Text(line)
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
                    .lineLimit(1)
                action
            }
            Spacer(minLength: 0)
            closeButton
        }
        .padding(12)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 12, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlas_place_card")
    }

    private var tileView: some View {
        Image(systemName: tile == .home ? "house.fill" : "mappin")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(AtlasTheme.accentInk)
            .frame(width: 44, height: 44)
            .background(AtlasTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    /// Текстовая ссылка с шевроном, а не стрелка и не троеточие: «если
    /// нажатие что-то открывает — это видно» (CLAUDE.md). Поле нажатия 44 по
    /// высоте при строке в 18.
    private var action: some View {
        Button(action: onOpen) {
            HStack(spacing: 3) {
                Text(actionTitle)
                    .font(AppType.button)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(AtlasTheme.accent)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("atlas_place_open")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AtlasTheme.secondary)
                .frame(width: 36, height: 36)
                .background(AtlasTheme.chip, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("atlas_place_close")
    }
}
