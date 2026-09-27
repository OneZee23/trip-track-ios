import SwiftUI

/// Первая строка панели «Мест»: «Места · Бета» и переключатель «Список · Карта».
///
/// Закреплена во всех положениях (спека §3.2). Отдельного слоя у верхнего
/// края экрана нет — по той же причине, по которой его больше нет у «Атласа»:
/// на телефонах с большой безопасной зоной он наезжал на часы, а заголовок
/// принадлежит той панели, в которой лежит содержимое.
///
/// Переключатель НЕ меняет экраны, он двигает панель: «Список» ведёт её
/// наверх, «Карта» — вниз. Поэтому активный сегмент это не отдельное
/// состояние, а отражение нынешнего положения: в половине активен «Список».
struct PlacesPanelHeader: View {
    let title: String
    let listTitle: String
    let mapTitle: String
    /// Какое положение сейчас — от него зависит активный сегмент.
    let stop: PlacesPanelStop
    var onBeta: () -> Void
    var onList: () -> Void
    var onMap: () -> Void

    /// Высота строки числом: от неё считается высота каждого положения, а та
    /// обязана быть известна ДО разметки.
    static let height: CGFloat = 44

    private var mapIsActive: Bool { stop == .map }

    var body: some View {
        HStack(spacing: 12) {
            // Чип «Бета» стоит ВПЛОТНУЮ к слову (зазор 6): он подпись к
            // «Местам», а не отдельный контрол рядом.
            HStack(spacing: 6) {
                Text(title)
                    .font(AppType.title)
                    .tracking(AppType.titleTracking)
                    .foregroundStyle(AtlasTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                AtlasBetaChip(action: onBeta, identifier: "places_beta_chip")
            }
            Spacer(minLength: 8)
            modeSwitch
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AtlasTheme.sideInset)
    }

    /// Капсула 36 на поле, сегменты 30 с радиусом 9, активный на карточке.
    ///
    /// Нарисована на 36, а ПАЛЕЦ получает 44 (спека §7). Поэтому фон рисуется
    /// фоном фиксированной высоты, а рамка сегмента — 44: раздуй капсулу до
    /// 44, и она перестала бы помещаться в строку заголовка, которая сама 44.
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            segment(listTitle, id: "places_mode_list", active: !mapIsActive, action: onList)
            segment(mapTitle, id: "places_mode_map", active: mapIsActive, action: onMap)
        }
        .padding(.horizontal, 3)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AtlasTheme.searchBackground)
                .frame(height: 36)
        }
    }

    private func segment(_ title: String, id: String, active: Bool,
                         action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Text(title)
                .font(active ? AppType.chipActive : AppType.chip)
                .foregroundStyle(active ? AtlasTheme.ink : AtlasTheme.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AtlasTheme.card)
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                }
                .frame(height: Self.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}
