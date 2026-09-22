import SwiftUI

/// «Бета» рядом с заголовком «Атлас».
///
/// Тот же повод, что был у убранного 15 сентября значка (`9e67f99d`): «карта
/// ещё дорабатывается». Тогда его сняли, потому что он объяснял карту,
/// которой на экране уже не было, — редизайн 0.7.0 (ночная карта, туман,
/// находки) как раз подводил её под собственное имя. Теперь объясняемая карта
/// снова ЗДЕСЬ: сам атлас ещё будет меняться до релизной версии, и владелец
/// хочет знать, что на нём заметили. Живёт до неё же — см. «Журнал и
/// карточки» в CLAUDE.md.
///
/// **Хит-тест гасится у САМИХ надписей, а не у заголовка целиком.** Жесты
/// карты под текстом красть нельзя, и до 22 сентября `.allowsHitTesting(false)`
/// стоял на всей колонке заголовка, а значок «переопределял» его себе —
/// переопределить нельзя: SwiftUI спрашивает разрешение сверху вниз, и
/// запрет на родителе закрывает всё поддерево. Значок не нажимался с самого
/// появления (19 сен), и нашёл это владелец на устройстве. Пустое место
/// колонки и `Spacer` жестов и так не берут — их берёт только нарисованное,
/// поэтому запрет и переехал на две надписи. Держит `AtlasBetaChipTests`.
struct AtlasBetaChip: View {
    let action: () -> Void

    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(AppStrings.atlasBetaChip(lang.language))
                .font(.inter(10, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.accent.opacity(0.28), in: Capsule())
                .overlay(Capsule().stroke(AppTheme.accent.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(PressableCardStyle())
        .allowsHitTesting(true)
        .accessibilityIdentifier("atlas_beta_chip")
        .accessibilityLabel(AppStrings.atlasBetaTitle(lang.language))
    }
}
