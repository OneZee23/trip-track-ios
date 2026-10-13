import SwiftUI
import StoreKit

/// Чаевые: три кнопки и «спасибо».
///
/// **Лист не обещает ничего.** Ни доступа, ни значка, ни строчки в списке
/// поддержавших — правило 3.1.1 запрещает продавать за расходуемую покупку
/// что-либо, и обходить это «символическим» подарком не будем: подарок и есть
/// обещание. Единственный ответ на покупку — тост «Спасибо!».
///
/// Цены приходят из `Product.displayPrice` и только оттуда. Ни «0,99 €», ни
/// «$0.99» здесь не написаны: валюту решает витрина, и человеку в Грузии
/// нарисованный евро — это цена, которой он не увидит на списании.
struct TipJarSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var jar = TipJarService.shared

    @State private var toastItem: ToastItem?
    /// Чаевые прошли — лист показывает «Спасибо!» (состояние 20).
    @State private var thanked = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            Capsule()
                .fill(.primary.opacity(0.18))
                .frame(width: 34, height: 5)
                .padding(.top, 8)

            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            if thanked {
                thanksState(c, l)
            } else {
            Text(AppStrings.tipsTitle(l))
                .font(.inter(21, weight: .bold))
                .foregroundStyle(c.text)
                .padding(.top, 2)

            Text(AppStrings.tipsText(l))
                .font(.inter(13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            if jar.products.isEmpty {
                Text(AppStrings.plusPricesUnavailable(l))
                    .font(.inter(13))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 26)
            } else {
                VStack(spacing: 10) {
                    ForEach(jar.products, id: \.id) { product in
                        tipButton(product, c)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 26)
            }
            }
        }
        .contentSizedSheet(background: c.bg)
        .presentationDragIndicator(.hidden)
        // `children: .contain`, а не голый идентификатор: без него SwiftUI
        // схлопывает лист в ОДИН элемент доступности, и кнопки внутри
        // («Восстановить покупки», крестик) пропадают и из VoiceOver, и из
        // дерева UI-тестов.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tip_jar")
        .toast(item: $toastItem)
        .task { await jar.load() }
    }

    /// Состояние 20: «Спасибо!». Сердце 64 на приглушённом фоне, короткое
    /// спасибо и — ВТОРОЙ раз, уже после списания — то же обещание, что до
    /// него: приложение останется бесплатным. Ни одного акцентного элемента:
    /// чаевые не продают ничего, и терракота здесь была бы обещанием.
    private func thanksState(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 30))
                .foregroundStyle(c.textSecondary)
                .frame(width: 64, height: 64)
                .background(Circle().fill(c.cardAlt))

            Text(AppStrings.tipsThanks(l))
                .font(.inter(21, weight: .bold))
                .foregroundStyle(c.text)

            Text(AppStrings.tipsThanksText(l))
                .font(.inter(13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text(AppStrings.close(l))
                    .font(AppType.action)
                    .foregroundStyle(c.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("tip_jar_close")
        }
        .padding(.top, 8)
        .padding(.bottom, 20)
        .accessibilityIdentifier("tip_jar_thanks")
    }

    private func tipButton(_ product: Product, _ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.action()
            Task {
                await jar.buy(product)
                guard jar.phase == .succeeded else { return }
                Haptics.success()
                // Состояние 20 — СОСТОЯНИЕ листа, а не тост.
                //
                // Тост несёт одно поле, и второе обещание («приложение
                // останется бесплатным») в него физически не влезало: строка
                // была переведена на тринадцать языков и не показывалась
                // нигде (находка финального ревью). А макет и рисует здесь
                // состояние: сердце, «Спасибо!», текст и «Закрыть».
                thanked = true
            }
        } label: {
            HStack(spacing: 12) {
                Text(tipTitle(product))
                    .font(.inter(14.5, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(product.displayPrice)
                    .font(.inter(14.5, weight: .heavy))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(c.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableCardStyle())
        .disabled(jar.phase == .purchasing)
        .opacity(jar.phase == .purchasing ? 0.5 : 1)
    }

    private func tipTitle(_ product: Product) -> String {
        switch product.id {
        case TipJarService.tipID:
            return AppStrings.tipsCoffee(lang.language)
        case TipJarService.tipMediumID:
            return AppStrings.tipsMeal(lang.language)
        case TipJarService.tipLargeID:
            return AppStrings.tipsFuel(lang.language)
        default:
            return product.displayName
        }
    }
}
