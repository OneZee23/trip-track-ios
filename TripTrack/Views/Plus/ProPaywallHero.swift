import SwiftUI

/// Герой витрины PRO — полоса 64 с ЕГО профилем на первом премиальном фоне.
///
/// Не украшение: это ответ на «как это будет выглядеть у меня». Поэтому имя,
/// аватар и число поездок берутся настоящие, а фон и рамка — те, которых у
/// него пока нет (`plus_nebula`, `frame_gold`). Витрина обещает не абстрактный
/// набор, а его собственный профиль после покупки.
///
/// Число поездок опционально: пока оно не посчитано, его нет вовсе. Ноль на
/// свежей установке читался бы как поломка, а не как «поездок ещё нет» — то же
/// решение, что у `ProfileHeroCard.showsStats`.
struct ProPaywallHero: View {
    let name: String
    let avatarEmoji: String
    let trips: Int?
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager

    /// Первый премиальный фон и первая премиальная рамка. Названы константами,
    /// чтобы «первый» не разъехался с порядком в витринах задачи 7.
    static let background: ProfileBackground = .plusNebula
    static let frame: AvatarFrame = .gold

    var body: some View {
        let l = lang.language
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 12) {
                Text(avatarEmoji)
                    .font(.inter(20))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.18)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                    .avatarFrame(Self.frame, lineWidth: 3)

                HStack(spacing: 8) {
                    Text(name)
                        .font(.inter(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    ProBadge()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let trips {
                    Text(AppStrings.nounTrips(l, trips))
                        .font(AppType.meta)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .fixedSize()
                }

                // Шеврон, как у пяти строк набора, и по той же причине: тап
                // открывает демонстрацию фона профиля. Одного нажимного
                // отклика здесь не хватает — `PressableCardStyle` стоит в
                // проекте на КАЖДОЙ карточке, в том числе на тех, что ничего
                // не открывают, и сигналом «здесь есть куда перейти» он не
                // читается (находка ревью). В макете герой нарисован
                // статичным блоком, но тап по нему назван в §3 спеки — раз
                // интерактив есть, у него обязан быть свой признак.
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 64)
            .background(Self.background.view())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("pro_hero")
        .accessibilityElement(children: .combine)
    }
}
