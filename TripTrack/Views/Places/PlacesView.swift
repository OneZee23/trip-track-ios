import SwiftUI

/// Вкладка «Места» (0.6.8, Figma 2895:160 · S1/S2). В волне 1 — только шапка
/// и пустой экран: слот занят, содержимое приходит волнами 2–3 (модель v14,
/// матчинг, список мест и экран места).
///
/// Форма пустого экрана — та же, что у пустых экранов 0.6.2:
/// `EmptyStateIllustration`, заголовок, одна фраза. Сцена — своя,
/// `empty_places`: дорога, булавка на обочине и пустой указатель; нарисована
/// владельцем 12 сентября в ряд с остальными пустыми сценами 0.6.2.
struct PlacesView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            // Шапка вкладки — как у ленты и у прежних «Групп»: 28 heavy, −0.56.
            HStack {
                Text(AppStrings.tabPlaces(l))
                    .font(.inter(28, weight: .heavy))
                    .tracking(-0.56)
                    .foregroundStyle(c.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 10)

            Spacer(minLength: 0)

            emptyState(c: c, l: l)
                .padding(.horizontal, 36)

            Spacer(minLength: 0)
        }
        // Плавающий таб-бар: содержимое обязано уходить из-под него.
        .padding(.bottom, CustomTabBar.clearance)
        .frame(maxWidth: .infinity)
        .background(c.bg.ignoresSafeArea())
    }

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            EmptyStateIllustration(name: "empty_places", size: 148)

            Text(AppStrings.placesEmptyTitle(l))
                .font(.inter(21, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.top, 22)

            Text(AppStrings.placesEmptyBody(l))
                .font(.inter(14))
                .lineSpacing(6)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .accessibilityIdentifier("places_empty")
    }
}
