import SwiftUI

/// Две карточки над «Историей» в «Мои»: вопрос про дом и подсказка «Похоже на
/// путешествие».
///
/// Обе — предложения, а не действия. Приложение само не создаёт ничего и не
/// запоминает дом, пока человек не нажал: правило умеет ошибаться, и цена
/// ошибки должна оставаться нулевой. Карточки ничего не считают — им приносят
/// готовые слова; правило живёт в `JourneySuggester`, а место откуда взять
/// подпись знает экран.

/// «Это твой дом?» — один раз за всё время.
///
/// Без дома подсказок нет вовсе, поэтому вопрос стоит того, чтобы занять
/// место над историей. Карта тут была бы честнее пина, но `MapSnapshotPreview`
/// рисует МАРШРУТ (ему нужны минимум две точки, и он ставит старт и финиш) —
/// на одной координате он либо пуст, либо врёт про поездку, которой не было.
struct HomeQuestionCard: View {
    /// «Краснодар» из геокод-кэша или координата, если имени нет.
    let place: String
    let onYes: () -> Void
    let onNo: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accentBg)
                    Image(systemName: "house.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.homeQuestionTitle(l))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(c.text)
                    Text(place)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                    Text(AppStrings.homeQuestionHint(l))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                CardChoiceButton(title: AppStrings.homeYes(l), isPrimary: true, action: onYes)
                CardChoiceButton(title: AppStrings.homeNo(l), isPrimary: false, action: onNo)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("home_question_card")
    }
}

/// «Похоже на путешествие: Владикавказ, Тбилиси · 6 поездок».
///
/// «Не сейчас», а не «Нет»: карточка уходит навсегда для ЭТОЙ цепочки, но те
/// же поездки человек соберёт руками — отказ ничего не удаляет.
struct JourneySuggestionBanner: View {
    /// «Владикавказ, Тбилиси · 6 поездок» — собрано экраном.
    let subtitle: String
    let onCombine: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accentBg)
                    Image(systemName: "map.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.journeySuggestTitle(l))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(c.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                CardChoiceButton(title: AppStrings.journeySuggestCombine(l), isPrimary: true, action: onCombine)
                CardChoiceButton(title: AppStrings.journeyNotNow(l), isPrimary: false, action: onDismiss)
            }
        }
        .padding(14)
        .background(AppTheme.accentBg, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("journey_suggestion_banner")
    }
}

/// Одна из двух кнопок под вопросом. Отдельным типом, а не копией в каждой
/// карточке: обе карточки задают вопрос одной формы, и разъехавшиеся на
/// пиксель кнопки читались бы как разные экраны.
private struct CardChoiceButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isPrimary ? c.card : c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    // Вторая кнопка — `cardAlt` С ОБВОДКОЙ, а не `card`.
                    // На баннере (он лежит на `accentBg`) белая плашка читалась
                    // кнопкой, а в карточке дома `card` совпал с её же
                    // поверхностью — и «Нет» превратился в подпись, по которой
                    // никто не догадается нажать. Кнопка обязана выглядеть
                    // кнопкой на ЛЮБОЙ из двух подложек, а не на той, где её
                    // рисовали первой.
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isPrimary ? AppTheme.accent : c.cardAlt)
                        .overlay {
                            if !isPrimary {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(c.textTertiary.opacity(0.35), lineWidth: 1)
                            }
                        }
                }
        }
        // Отклик в момент касания: обе кнопки что-то запоминают навсегда, и
        // «нажалось или нет» человек должен видеть пальцем, а не по тому,
        // исчезла карточка или нет.
        .buttonStyle(PressableCardStyle())
    }
}
