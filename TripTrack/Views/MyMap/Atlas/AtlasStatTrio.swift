import SwiftUI

/// Тройка чисел «Атласа» в одной белой карточке (спека §3.6).
///
/// Одна карточка на три колонки, а не три карточки: это ОДИН итог, прочитанный
/// с трёх сторон, и разнесённый по карточкам он читался тремя разными
/// сведениями. Прежний `AtlasStatTile` остаётся у карточки региона, где
/// плитки и вправду отдельные.
///
/// **Роли набора взяты у приложения, а не из чисел спеки, и это решение.**
/// Спека называет 22/700 для числа и 20/700 для заголовка секции, объясняя
/// их словами «как в карточке поездки» и «как на экране „Я“». В приложении
/// эти же роли — `AppType.statValue` (19/800) и `AppType.section` (16/700):
/// канон снят с экрана «Я» 26 сентября по прямому решению владельца («он
/// офигенен, я хочу чтобы также было по всему приложению»). Чек-лист спеки
/// требует совпадения ИМЕННО с «Я» и с карточкой поездки, поэтому здесь
/// стоят компоненты приложения; литеральные числа спеки с ними расходятся, и
/// это расхождение вынесено владельцу отдельным вопросом.
struct AtlasStatTrio: View {
    struct Column: Identifiable {
        let id: String
        /// Число без единицы: «189», «72».
        let value: String
        /// Единица в ту же строку, тише и мельче: «миль». `nil` у счётного.
        var unit: String?
        /// Подпись капсом под числом: «НОВЫХ ДОРОГ».
        let caption: String
        /// Колонка, которая куда-то ведёт, получает шеврон: если нажатие
        /// что-то открывает — это видно (CLAUDE.md).
        var action: (() -> Void)?
    }

    let columns: [Column]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            // Крупный шрифт переносит тройку в столбик по одному числу —
            // ничего не режется и не мельчает (спека §7).
            if typeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(columns) { column($0) }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns) { column($0) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
    }

    @ViewBuilder
    private func column(_ item: Column) -> some View {
        let body = VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.value)
                    .font(AppType.statValue)
                    .tracking(AppType.statValueTracking)
                    .monospacedDigit()
                    .foregroundStyle(AtlasTheme.ink)
                if let unit = item.unit {
                    Text(unit)
                        .font(AppType.statUnit)
                        .foregroundStyle(AtlasTheme.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            HStack(spacing: 3) {
                Text(item.caption)
                    .font(AppType.statCaption)
                    .tracking(AppType.statCaptionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(AtlasTheme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if item.action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AtlasTheme.secondary.opacity(0.8))
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let action = item.action {
            Button(action: action) { body }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("atlas_stat_" + item.id)
        } else {
            body.accessibilityIdentifier("atlas_stat_" + item.id)
        }
    }
}
