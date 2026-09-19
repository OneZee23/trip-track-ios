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

            Text(AppStrings.tipTitle(l))
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.top, 2)

            Text(AppStrings.tipSubtitle(l))
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
        .contentSizedSheet(background: c.bg)
        .presentationDragIndicator(.hidden)
        // `children: .contain`, а не голый идентификатор: без него SwiftUI
        // схлопывает лист в ОДИН элемент доступности, и кнопки внутри
        // («Восстановить покупки», крестик) пропадают и из VoiceOver, и из
        // дерева UI-тестов.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tip_jar")
        .toast(item: $toastItem)
        .task { if jar.products.isEmpty { await jar.load() } }
    }

    private func tipButton(_ product: Product, _ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.action()
            Task {
                await jar.buy(product)
                guard jar.phase == .succeeded else { return }
                Haptics.success()
                toastItem = ToastItem(
                    type: .success, message: AppStrings.tipThanks(lang.language))
            }
        } label: {
            HStack(spacing: 12) {
                Text(product.displayName)
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
}
