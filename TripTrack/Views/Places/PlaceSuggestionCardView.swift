import SwiftUI

/// Строка подсказки «Похоже, вы здесь бываете»: имя, сколько поездок тут
/// начиналось или заканчивалось, и кнопка «Сохранить как место».
///
/// Кнопка одна и она — ВСЯ строка, а не вложенная в неё: вложенная кнопка
/// повторила бы баг «Вступить» из каталога клубов, где внешняя кнопка
/// перехватывает тап (см. чип у отметки в CLAUDE.md, «Места»). Поэтому
/// «Сохранить как место» — подпись действия внутри строки, а нажимается
/// строка целиком.
struct PlaceSuggestionCardView: View {
    let suggestion: PlaceSuggestion
    let onSave: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        Button {
            Haptics.tap()
            onSave()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(AppTheme.accentBg)
                    Image(systemName: "mappin")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.name ?? AppStrings.placeSuggestUnnamed(l))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(AppStrings.placeSuggestTrips(l, trips: tripsCount(l)))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(2)
                    Text(AppStrings.placeSuggestSave(l))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.top, 1)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("place_suggestion_\(suggestion.cell)")
    }

    /// «3 поездки» — счётное существительное через CLDR, не через `if .ru`.
    private func tripsCount(_ l: LanguageManager.Language) -> String {
        "\(AppStrings.formattedCount(suggestion.trips, lang: l)) \(AppStrings.nounTrips(l, suggestion.trips))"
    }
}

/// «Как появляются места» — три строки и кнопка к последней поездке.
///
/// Показывается, пока мест меньше трёх И подсказать нечего: экран обязан
/// объяснять себя делом, а не пустотой. Как только подсказки появились,
/// карточка уходит — она объясняла ровно то, что теперь видно строками.
struct PlacesHowItWorksCard: View {
    /// `nil` — поездок ещё нет вовсе, и кнопка не рисуется: вести некуда.
    let onOpenLastTrip: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.placesHowTitle(l))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(c.text)
            row("record.circle", AppStrings.placesHowMark(l), c)
            row("hand.tap", AppStrings.placesHowTap(l), c)
            row("sparkles", AppStrings.placesHowSuggest(l), c)
            if let onOpenLastTrip {
                Button {
                    Haptics.tap()
                    onOpenLastTrip()
                } label: {
                    Text(AppStrings.placesOpenLastTrip(l))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("places_open_last_trip")
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("places_how_card")
    }

    private func row(_ icon: String, _ text: String, _ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
