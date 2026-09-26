import SwiftUI
import StoreKit

/// Витрина «Плюса» — единственное место, где что-то продаётся.
///
/// Открывается из замка на любой из пяти точек (`PlusGate`), из строки «Плюс»
/// в профиле и из настроек. Домашний лист, а не `SubscriptionStoreView`: тот
/// приносит свою типографику и свои карточки, и посреди наших тёплых карточек
/// читается как чужое приложение — ровно то, за что в этом проекте запрещены
/// системные диалоги.
///
/// Что обязано быть на экране ДО покупки, иначе ревью Apple отказывает: цена,
/// период, длина бесплатного периода, «Восстановить покупки», ссылки на
/// условия и на политику приватности, подвал автопродления. Ни одно из этого
/// не спрятано за скроллом нарочно — лист ровно такой высоты, какой нужен.
struct PlusPaywallSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var store = PlusStore.shared

    /// Выбранный тариф. `nil` только до того, как приехали продукты.
    @State private var selectedId: String?
    /// Что сказать под кнопкой о прошлой попытке. Сбрасывается в `.none`
    /// перед каждой новой: строка про позавчерашний сбой над идущей покупкой
    /// хуже, чем ничего.
    @State private var notice: PlusStore.PurchaseMessage = .none

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let plans = PlusPaywallModel.plans(
            infos, eligibleForIntro: store.introEligible, lang: l)

        VStack(spacing: 0) {
            grabber
            header(c, l)
            features(c, l)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if plans.isEmpty {
                Text(AppStrings.plusPricesUnavailable(l))
                    .font(.inter(13))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            } else {
                planRow(plans, c)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            buyButton(plans, c, l)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            noticeLine(c, l)

            restoreButton(l)
                .padding(.top, 10)

            legalLinks(c, l)
                .padding(.top, 8)

            Text(AppStrings.plusAutoRenewFooter(l))
                .font(.inter(10.5))
                .foregroundStyle(c.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 22)
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
        .contentSizedSheet(background: c.bg)
        .presentationDragIndicator(.hidden)
        // `children: .contain`, а не голый идентификатор: без него SwiftUI
        // схлопывает лист в ОДИН элемент доступности, и кнопки внутри
        // («Восстановить покупки», крестик) пропадают и из VoiceOver, и из
        // дерева UI-тестов.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plus_paywall")
        // Продукты грузятся один раз за запуск; лист лишь досылает запрос,
        // если открылся раньше, чем приехал ответ Apple.
        .task {
            if store.products.isEmpty { await store.loadProducts() }
            if selectedId == nil {
                selectedId = PlusPaywallModel.defaultSelection(
                    PlusPaywallModel.plans(infos,
                                           eligibleForIntro: store.introEligible,
                                           lang: lang.language))
            }
        }
    }

    /// Продукты Apple → строки. Считается в `body`, но это `compactMap` по
    /// ДВУМ элементам: разворачивать его в состояние значило бы завести второй
    /// источник правды о том, что сейчас продаётся.
    private var infos: [PlusProductInfo] {
        store.products.compactMap(PlusProductInfo.init(product:))
    }

    // MARK: - Куски

    private var grabber: some View {
        Capsule()
            .fill(.primary.opacity(0.18))
            .frame(width: 34, height: 5)
            .padding(.top, 8)
    }

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 8) {
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
                .accessibilityIdentifier("plus_close")
            }
            .padding(.horizontal, 16)

            Text(AppStrings.plusTitle(l))
                .font(.inter(26, weight: .bold))
                .kerning(-0.3)
                .foregroundStyle(c.text)

            Text(AppStrings.plusPaywallSubtitle(l))
                .font(.inter(13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
        }
        .padding(.top, 6)
    }

    /// Пять строк — ровно те пять, что открывает `PlusFeature`. Список
    /// закрытый: шестая строка здесь означала бы обещание, которого гейт не
    /// выполняет.
    private func features(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            featureRow("photo.artframe", AppStrings.plusFeatureBackgrounds(l), c)
            featureRow("person.crop.circle.badge.checkmark",
                       AppStrings.plusFeatureAvatarFrame(l), c)
            featureRow("car.side", AppStrings.plusFeatureCardStyle(l), c)
            featureRow("scribble.variable", AppStrings.plusFeatureRouteLine(l), c)
            featureRow("point.topleft.down.curvedto.point.bottomright.up",
                       AppStrings.plusFeatureManualTrip(l), c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func featureRow(
        _ icon: String, _ text: String, _ c: AppTheme.Colors
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
            Text(text)
                .font(.inter(13.5))
                .foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Два тарифа рядом, а не столбиком: столбик добавляет листу ещё сотню
    /// пунктов высоты, и подвал автопродления уезжает за нижний край — то
    /// самое, чего ревью Apple не прощает.
    private func planRow(_ plans: [PlusPlan], _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            ForEach(plans) { plan in
                Button {
                    Haptics.selection()
                    selectedId = plan.id
                } label: {
                    planCard(plan, selected: selectedId == plan.id, c)
                }
                .buttonStyle(PressableCardStyle())
            }
        }
    }

    private func planCard(
        _ plan: PlusPlan, selected: Bool, _ c: AppTheme.Colors
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.title)
                .font(.inter(13, weight: .bold))
                .foregroundStyle(selected ? AppTheme.accent : c.text)
            Text(plan.price)
                .font(.inter(14, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption = plan.caption {
                Text(caption)
                    .font(.inter(10.5))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(selected ? AppTheme.accentBg : c.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? AppTheme.accent : c.border,
                        lineWidth: selected ? 1.6 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func buyButton(
        _ plans: [PlusPlan], _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        let product = store.products.first { $0.id == selectedId }
        return Button {
            guard let product else { return }
            Haptics.action()
            notice = .none
            Task {
                let outcome = await store.purchase(product)
                notice = PlusStore.message(for: outcome)
                if case .success = outcome { dismiss() }
            }
        } label: {
            ZStack {
                Text(AppStrings.plusSubscribe(l))
                    .font(.inter(16, weight: .bold))
                    .opacity(store.isBusy ? 0 : 1)
                if store.isBusy {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 14).fill(AppTheme.accent))
        }
        .buttonStyle(PressableCardStyle())
        .disabled(product == nil || store.isBusy)
        .opacity(product == nil ? 0.45 : 1)
        .accessibilityIdentifier("plus_buy")
    }

    /// Итог прошлой попытки. Отмену НЕ комментирует: человек закрыл лист сам,
    /// и сообщать ему об этом — то же самое, что спорить.
    @ViewBuilder
    private func noticeLine(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        switch notice {
        case .none:
            EmptyView()
        case .pending:
            noticeText(AppStrings.plusPurchasePending(l), c.textSecondary)
        case .failed:
            noticeText(AppStrings.plusPurchaseFailed(l), AppTheme.red)
        }
    }

    private func noticeText(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.inter(12, weight: .medium))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .accessibilityIdentifier("plus_notice")
    }

    /// Обязательна для ревью и обязана работать у любого, кто когда-то платил
    /// — в том числе на новом телефоне и после переустановки.
    private func restoreButton(_ l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            Task {
                notice = .none
                notice = await store.restore()
            }
        } label: {
            Text(AppStrings.plusRestore(l))
                .font(.inter(13, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .disabled(store.isBusy)
        .accessibilityIdentifier("plus_restore")
    }

    private func legalLinks(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        HStack(spacing: 14) {
            Link(AppStrings.plusTermsLink(l), destination: AppConfig.termsURL(l))
            Text("·").foregroundStyle(c.textTertiary)
            Link(AppStrings.plusPrivacyLink(l), destination: AppConfig.privacyPolicyURL(l))
        }
        .font(.inter(11.5))
        .tint(c.textSecondary)
    }
}
