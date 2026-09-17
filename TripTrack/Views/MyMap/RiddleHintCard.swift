import SwiftUI

/// Что печатает карточка НЕрешённой загадки — посчитано ДО `body`.
///
/// Отдельная модель, а не `DiscoveryCardModel` с флагом: у той в основании
/// лежит `Discovery`, то есть УЖЕ НАЙДЕННОЕ, — с датой находки, символом
/// печати, счётчиком первооткрывателей и координатой. У нерешённой загадки нет
/// ни одного из этих полей, и половина карточки состояла бы из проверок «а
/// этого ещё не случилось». Общего у двух карточек — только вёрстка, и её
/// повторить дешевле, чем свести два разных вопроса в один тип.
///
/// Координаты здесь НЕТ ни в каком виде — ни точки загадки, ни центра круга.
/// Карточка отвечает «что ищется и далеко ли это», а «где именно» — это и есть
/// сама загадка. Держит `RiddleHintCardTests`.
struct RiddleHintCardModel: Identifiable, Equatable {
    /// `Riddle.id` — «<type>:<geohash7>», он же id подсказки на карте.
    let id: String
    /// «ЗАГАДКА» — та же шапка, что у решённой (`AppStrings.sealKind`).
    let kindLabel: String
    /// Про что она: «Где-то здесь дорога перевалит через хребет».
    let line: String
    /// «решается проездом» — правило игры, настоящим временем.
    let ruleLine: String
    /// «12 км до круга». `nil`, когда открытое УЖЕ внутри круга: «0 км» — это
    /// не ответ, а след формулы (то же правило, что у строки журнала).
    let distanceLine: String?

    /// Расстояние приходит УЖЕ НАПЕЧАТАННЫМ и с явной единицей: карточка сама
    /// ничего не делит и не подписывает — это работа `Measure` (канон
    /// «честные единицы»).
    ///
    /// Само расстояние считает `JournalBuilder.nearby` — до КРАЯ круга, от
    /// центроидов открытого. Второго счёта здесь нет нарочно: журнал и
    /// карточка обязаны говорить одно и то же число.
    static func make(
        riddle: Journal.NearbyRiddle,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> RiddleHintCardModel {
        RiddleHintCardModel(
            id: riddle.id,
            kindLabel: AppStrings.sealKind(lang, kind: .riddle),
            line: RiddleCopy.line(for: riddle.type, lang),
            ruleLine: AppStrings.cardSolvedByDriving(lang),
            distanceLine: riddle.metresToEdge > 0
                ? AppStrings.journalRiddleDistance(
                    lang,
                    distance: Measure.distance(
                        metres: riddle.metresToEdge, unit: unit, lang: lang))
                : nil
        )
    }
}

/// Карточка нерешённой загадки: «?», строка про что она, правило и расстояние.
///
/// Открывается из двух мест и выглядит в них одинаково — тап по значку или по
/// кольцу на «Атласе» и строка группы «Загадки рядом» в журнале. Кнопки «На
/// карте» у неё нет ни в одном из них: с карты она вела бы туда, где человек
/// уже стоит, а из журнала — к кругу, середина которого смещена нарочно и
/// ничего не отвечает.
///
/// Карты внутри тоже нет — в отличие от карточки РЕШЁННОЙ загадки, где кружок
/// на снимке это напоминание о форме вопроса, на который уже есть ответ.
struct RiddleHintCard: View {
    let model: RiddleHintCardModel

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Text("?")
                    .font(.inter(24, weight: .heavy))
                    .foregroundStyle(Color(SealPainter.ring(for: .riddle)))
                    .frame(width: 56, height: 56)
                    .background(
                        Color(SealPainter.ring(for: .riddle)).opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.kindLabel)
                        .font(.inter(11, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(SealPainter.ring(for: .riddle)))

                    Text(model.line)
                        .font(.inter(17, weight: .heavy))
                        .foregroundStyle(c.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.ruleLine)
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer(minLength: 20)
            }

            if let distance = model.distanceLine {
                Text(distance)
                    .font(.inter(13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }

            // Обязательство ODbL, как и у карточки решённой загадки: объекты
            // загадок выведены из OpenStreetMap, и назвать источник надо там,
            // где человек видит производное.
            Text(AppStrings.osmAttribution(lang.language))
                .font(.inter(11))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mymap_riddle_card")
    }
}
