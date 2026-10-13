import SwiftUI

/// Шапка подсостояния шторки: назад, заголовок, закрыть (спека §3.9).
///
/// Живёт ВНУТРИ шторки, а не поверх карты, и это не вкусовщина. До 27
/// сентября заголовок региона стоял отдельным слоем у верхнего края экрана —
/// и наезжал на часы и индикаторы: «шапка наслаивается с остальными
/// элементами телефона сверху, некрасиво, хрен пойми куда нажимать»
/// (владелец на устройстве). Заголовок объекта принадлежит шторке, в которой
/// этот объект открыт, и уезжает вместе с ней.
///
/// Выходов ДВА, и они ведут в разные места: «назад» возвращает туда, откуда
/// пришли (список или сводка), × закрывает подсостояние до сводки. Кнопка,
/// повторяющая соседнюю, была бы лишней — эти две не повторяются.
struct AtlasSubstateHeader: View {
    let title: String
    /// Вторая строка под заголовком: «Россия · с апреля 2026» у региона,
    /// «Краснодарский край · в тумане» у города (спека §3.9).
    var subtitle: String?
    var backLabel: String
    var closeLabel: String
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            circle("chevron.left", label: backLabel, id: "atlas_substate_back", action: onBack)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppType.headerTitle)
                    .foregroundStyle(AtlasTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle)
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            circle("xmark", label: closeLabel, id: "atlas_substate_close", action: onClose)
        }
        .padding(.horizontal, AtlasTheme.sideInset)
        .accessibilityElement(children: .contain)
    }

    /// Круг 40 по макету, но поле нажатия 44 × 44 — правило спеки §7 и
    /// CLAUDE.md сразу: цель пальца не бывает меньше сорока четырёх.
    private func circle(_ icon: String, label: String, id: String,
                        action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AtlasTheme.ink)
                .frame(width: 40, height: 40)
                .background(AtlasTheme.chip, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
