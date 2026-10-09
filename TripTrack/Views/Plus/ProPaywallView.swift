import SwiftUI
import StoreKit

/// Native PRO storefront. The offer stays pinned; the feature list scrolls
/// according to its real size, including translations and Dynamic Type.
struct ProPaywallView: View {
    /// С какой функции пришли. Не `nil` — витрина открывается СРАЗУ на
    /// странице этой функции: на замок человек нажимает посреди дела, и список
    /// из пяти строк отвечает не на его вопрос.
    let feature: PlusFeature?
    /// Откуда открыли. `manualTrip` меняет ТОЛЬКО экран «Ты в PRO»: у него
    /// единственная кнопка, и ведёт она обратно к набранной поездке, а не в
    /// витрину фонов (состояние 36б).
    var origin: ProBoughtView.Origin = .storefront
    let onPickBackground: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var store = PlusStore.shared

    /// Выбранный тариф. `nil` только до того, как приехали продукты.
    @State private var selectedId: String?
    /// Пытались ли уже загрузить цены. Своё, а не из стора: «продуктов нет»
    /// и «мы ещё не спрашивали» — разные состояния экрана (1б против 1а), а
    /// `PlusStore.products` отвечает на оба одинаково пустым массивом.
    @State private var didTryLoading = false
    /// Итог прошлой попытки покупки.
    @State private var notice: PlusStore.PurchaseMessage = .none
    /// Что сказать поверх экрана о прошлой попытке — состояния 8 и 10.
    @State private var toast: ToastItem?
    /// Открыта ли демонстрация и на какой странице. `nil` — виден список.
    @State private var demo: PlusFeature?
    /// Снимок данных для страниц демонстрации. Один раз, до показа: маршрут
    /// поднимается из базы, а страницы листают пальцем.
    @State private var demoData: ProDemoData?
    /// Покупка только что прошла — экран становится «Ты в PRO» (состояние 9).
    ///
    /// Своё состояние, а не `PlusAccess.isPlus`: право приезжает и у того, кто
    /// открыл витрину, УЖЕ будучи подписчиком (из строки «Я» — «управлять»), и
    /// он не покупал сейчас ничего. «Куплено» показывается тому, кто нажал
    /// кнопку, а не тому, у кого есть подписка.
    @State private var justBought = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let plans = PlusPaywallModel.plans(
            infos, eligibleForIntro: store.introEligible, lang: l)
        let phase = Self.phase(justBought: justBought,
                               productsLoaded: didTryLoading,
                               hasPlans: !plans.isEmpty,
                               isBusy: store.isBusy,
                               notice: notice)

        ZStack(alignment: .topTrailing) {
            if phase == .bought {
                ProBoughtView(origin: origin,
                              data: demoData ?? .placeholder(
                                  name: heroName,
                                  emoji: SettingsManager.shared.avatarEmoji),
                              until: store.displayExpiry,
                              isTrial: store.state == .trial,
                              yearlyPrice: plans.first { $0.period == .yearly }?.displayPrice,
                              onPickBackground: onPickBackground,
                              onClose: onClose)
            } else {
                VStack(spacing: 0) {
                    scrollingContent(c, l, phase)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    footer(c, l, phase, plans)
                }
                closeButton(c, phase)
            }
        }
        .background(c.bg)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: notice)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: phase)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // `children: .contain`, а не голый идентификатор: без него SwiftUI
        // схлопывает экран в ОДИН элемент доступности, и кнопки внутри
        // пропадают и из VoiceOver, и из дерева UI-тестов.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plus_paywall")
        .toast(item: $toast)
        .task { await load() }
    }

    // MARK: - Состояние

    /// Какое из состояний матрицы сейчас на экране — чистой функцией.
    ///
    /// Неудача и пустое восстановление — НЕ фазы: это тосты поверх витрины
    /// (состояния 8 и 10), а тарифы и кнопка остаются на месте.
    ///
    /// `justBought` — признак НАЖАТИЯ, а не наличия подписки: витрину
    /// открывает и действующий подписчик (из строки «Я»), и показывать ему
    /// «Ты в PRO» значило бы поздравить его с покупкой, которой не было.
    static func phase(
        justBought: Bool,
        productsLoaded: Bool,
        hasPlans: Bool,
        isBusy: Bool,
        notice: PlusStore.PurchaseMessage
    ) -> ProPaywallPhase {
        if justBought { return .bought }
        if isBusy { return .purchasing }
        if notice == .pending { return .pending }
        if !productsLoaded { return .loading }
        if !hasPlans { return .pricesFailed }
        return .priced
    }

    /// Продукты Apple → строки. Считается в `body`, но это `compactMap` по
    /// ДВУМ элементам: разворачивать его в состояние значило бы завести второй
    /// источник правды о том, что сейчас продаётся.
    private var infos: [PlusProductInfo] {
        store.products.compactMap(PlusProductInfo.init(product:))
    }

    private func load() async {
        if store.products.isEmpty { await store.loadProducts() }
        didTryLoading = true
        if selectedId == nil {
            selectedId = PlusPaywallModel.defaultSelection(
                PlusPaywallModel.plans(infos,
                                       eligibleForIntro: store.introEligible,
                                       lang: lang.language))
        }
        if demoData == nil {
            let snapshot = await ProDemoData.current(lang: lang.language)
            demoData = snapshot
            if demo == nil, let feature = feature { demo = feature }
        }
    }

    private var selectedPlan: PlusPlan? {
        let plans = PlusPaywallModel.plans(
            infos, eligibleForIntro: store.introEligible, lang: lang.language)
        return plans.first { $0.id == selectedId } ?? plans.first
    }

    // MARK: - Верх

    @ViewBuilder
    private func scrollingContent(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language, _ phase: ProPaywallPhase
    ) -> some View {
        if let demo, let demoData {
            ProDemoPager(start: demo, data: demoData, onBack: { self.demo = nil })
        } else {
            ScrollView { column(c, l, phase) }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("pro_features_scroll")
        }
    }

    private func column(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language, _ phase: ProPaywallPhase
    ) -> some View {
        VStack(spacing: 20) {
            header(c, l)
            // Имя и аватар — из снимка, когда он приехал: у витрины не должно
            // быть второго источника того же самого.
            ProPaywallHero(name: demoData?.name ?? heroName,
                           avatarEmoji: demoData?.avatarEmoji
                               ?? SettingsManager.shared.avatarEmoji,
                           onTap: { openDemo(.profileBackgrounds) })
            if phase.showsFeatureSet {
                featureGroup(AppStrings.proGroupVisible(l),
                             PlusFeature.allCases.filter(\.isVisibleToOthers), c, l)
                featureGroup(AppStrings.proGroupPrivate(l),
                             PlusFeature.allCases.filter { !$0.isVisibleToOthers }, c, l)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// Имя для героя и для заглушки «Куплено». Читается у той же двери, что
    /// и снимок данных, — второго правила про имя у платной части быть не
    /// должно.
    private var heroName: String {
        ProDemoData.currentName(lang: lang.language)
    }

    private func header(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.proTitle(l))
                .font(.interScaled(30, weight: .heavy, relativeTo: .title))
                .kerning(AppType.titleTracking)
                .foregroundStyle(c.text)
            Text(AppStrings.proPromise(l))
                .font(.interScaled(15, relativeTo: .subheadline))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Место под крестик: он лежит слоем выше и накрыл бы вторую строку.
        .padding(.trailing, 44)
        .padding(.vertical, 12)
    }

    private func featureGroup(
        _ title: String,
        _ features: [PlusFeature],
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.interScaled(16, weight: .bold, relativeTo: .headline))
                .foregroundStyle(c.text)
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.element) { index, feature in
                    ProFeatureRow(icon: feature.proIcon,
                                  title: feature.proTitle(l),
                                  subtitle: feature.proSubtitle(l),
                                  onTap: { openDemo(feature) })
                    if index < features.count - 1 {
                        Divider().overlay(c.border).padding(.leading, 40)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Демонстрация функции. Ждёт снимок данных: страница без него показала
    /// бы пустое превью там, где обещан его собственный профиль.
    private func openDemo(_ feature: PlusFeature) {
        guard demoData != nil else { return }
        demo = feature
    }

    // MARK: - Крестик

    @ViewBuilder
    private func closeButton(_ c: AppTheme.Colors, _ phase: ProPaywallPhase) -> some View {
        Button {
            Haptics.tap()
            // Из демонстрации крестик возвращает в список, а не закрывает
            // витрину: у страницы есть «Назад», но верхний правый угол — это
            // «уйти отсюда», и уходить он должен на один шаг.
            if demo != nil { demo = nil } else { onClose() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(c.cardAlt))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!phase.allowsClose)
        .opacity(phase.allowsClose ? 1 : 0.4)
        .padding(.trailing, 10)
        .padding(.top, 4)
        .accessibilityIdentifier("plus_close")
    }

    // MARK: - Подвал

    private func footer(
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language,
        _ phase: ProPaywallPhase,
        _ plans: [PlusPlan]
    ) -> some View {
        VStack(spacing: 0) {
            tariffArea(c, l, phase, plans)
                .padding(.top, 4)

            actionArea(c, l, phase)
                .padding(.top, 10)

            termsLine(c, l, phase)
            if phase.showsLinks {
                linksRow(c, l)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background {
            c.bg
            // The surface reaches the edge; controls stay in the safe area.
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(c.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private func tariffArea(
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language,
        _ phase: ProPaywallPhase,
        _ plans: [PlusPlan]
    ) -> some View {
        if phase.showsPlanRow {
            HStack(spacing: 8) {
                ForEach(plans) { plan in
                    ProPlanCard(title: plan.title,
                                subtitle: plan.caption,
                                subtitleIsAccent: plan.captionIsAccent,
                                savingText: plan.savingPercent.map {
                                    AppStrings.proPlanSave(l, percent: $0)
                                },
                                isSelected: plan.id == selectedId,
                                onTap: { selectedId = plan.id })
                    .accessibilityIdentifier("pro_plan_\(plan.id)")
                    .disabled(!phase.allowsTariffChange)
                }
            }
            .opacity(phase.dimsChrome ? 0.4 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pro_plans")
        } else if phase.showsTariffSkeleton {
            HStack(spacing: 8) {
                skeletonCard(c)
                skeletonCard(c)
            }
            .accessibilityIdentifier("pro_plans_skeleton")
        } else if phase.showsPricesFailedCard {
            infoCard(title: AppStrings.proPricesFailed(l),
                     text: AppStrings.proPricesFailedSub(l),
                     c)
        } else if phase.showsPendingCard {
            infoCard(title: AppStrings.proDeferredTitle(l),
                     text: AppStrings.proDeferredText(l),
                     c)
        }
    }

    private func skeletonCard(_ c: AppTheme.Colors) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(c.cardAlt)
            .frame(height: 64)
            .frame(maxWidth: .infinity)
            .shimmer()
    }

    private func infoCard(
        title: String, text: String, _ c: AppTheme.Colors
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppType.itemValue)
                .foregroundStyle(c.text)
            Text(text)
                .font(AppType.body)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(c.border, lineWidth: 1)
        )
        .accessibilityIdentifier("pro_info_card")
    }

    // MARK: - Кнопка

    /// Исчерпывающий `switch`, а не цепочка `if/else if`: потеря ветки здесь
    /// не ловится ни одним тестом (свойства фазы остаются верными, а кнопка с
    /// экрана исчезает), зато ломает компиляцию — см. `ProPaywallPhase
    /// .FooterAction`.
    @ViewBuilder
    private func actionArea(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language, _ phase: ProPaywallPhase
    ) -> some View {
        switch phase.footerAction {
        case .buy:
            buyButton(l, phase)
        case .retry:
            wideButton(AppStrings.retry(l)) {
                Task {
                    didTryLoading = false
                    await store.loadProducts()
                    didTryLoading = true
                }
            }
            .accessibilityIdentifier("pro_retry")
        case .acknowledge:
            wideButton(AppStrings.commonOk(l), action: onClose)
                .accessibilityIdentifier("pro_pending_ok")
        case .none:
            EmptyView()
        }
    }

    private func buyButton(
        _ l: LanguageManager.Language, _ phase: ProPaywallPhase
    ) -> some View {
        let plan = selectedPlan
        let product = store.products.first { $0.id == plan?.id }
        return Button {
            guard let product else { return }
            Haptics.action()
            notice = .none
            Task {
                let outcome = await store.purchase(product)
                notice = PlusStore.message(for: outcome)
                // Отмену человеком тостом НЕ сопровождаем: он закрыл
                // системный лист сам, и сообщать ему об этом — то же, что
                // спорить.
                if notice == .failed {
                    toast = ToastItem(type: .error, message: AppStrings.proFailed(l))
                }
                if case .success = outcome { justBought = true }
            }
        } label: {
            ZStack {
                // Без цен кнопка стоит ПУСТОЙ и приглушённой (состояние 1а):
                // текст «Оформить» без суммы обещал бы покупку, цены которой
                // мы ещё не знаем.
                if let plan {
                    Text(ctaTitle(l, plan))
                        .font(AppType.button)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(phase.showsSpinnerInButton ? 0 : 1)
                }
                if phase.showsSpinnerInButton {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.accent)
            )
        }
        .buttonStyle(PressableCardStyle())
        .disabled(product == nil || store.isBusy)
        .opacity(product == nil ? 0.4 : 1)
        .accessibilityIdentifier("plus_buy")
    }

    private func wideButton(
        _ title: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(AppType.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accent)
                )
        }
        .buttonStyle(PressableCardStyle())
    }

    /// Что написано на кнопке. Обещание недели — только у того тарифа, который
    /// её действительно даёт (`hasFreeWeek`); иначе кнопка называет цену.
    private func ctaTitle(_ l: LanguageManager.Language, _ plan: PlusPlan) -> String {
        if plan.hasFreeWeek { return AppStrings.proCtaTrial(l) }
        switch plan.period {
        case .yearly:  return AppStrings.proCtaYear(l, price: plan.displayPrice)
        case .monthly: return AppStrings.proCtaMonth(l, price: plan.displayPrice)
        }
    }

    // MARK: - Условия и ссылки

    @ViewBuilder
    private func termsLine(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language, _ phase: ProPaywallPhase
    ) -> some View {
        if phase.showsBuyButton {
            Text(termsText(l))
                .font(AppType.caption)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .accessibilityIdentifier("pro_terms")
        }
    }

    private func termsText(_ l: LanguageManager.Language) -> String {
        guard let plan = selectedPlan, plan.hasFreeWeek else {
            return AppStrings.proTermsAuto(l)
        }
        return AppStrings.proTermsTrial(l, price: plan.displayPrice)
    }

    /// «Восстановить покупки · Условия · Конфиденциальность» — три РАЗНЫХ
    /// нажатия, поэтому три строки, а не одна склеенная: у одной строки на
    /// три адресата не может быть трёх целей нажатия.
    private func linksRow(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        HStack(spacing: 6) {
            Group {
                Button {
                    Haptics.tap()
                    Task {
                        notice = .none
                        notice = await store.restore()
                        // `.none` от восстановления означает две разные вещи:
                        // «подписка нашлась» и «на этом Apple ID её нет».
                        // Различает их `isPlus` — и это состояние 10, у
                        // которого своя строка. Третьего значения у
                        // `PurchaseMessage` заводить не пришлось.
                        if notice == .none, !store.isPlus {
                            toast = ToastItem(type: .info,
                                              message: AppStrings.proRestoreNone(l))
                        } else if notice == .failed {
                            toast = ToastItem(type: .error,
                                              message: AppStrings.proFailed(l))
                        }
                    }
                } label: {
                    Text(AppStrings.plusRestore(l))
                        .font(.inter(12, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
                .accessibilityIdentifier("plus_restore")

                Text(verbatim: "·").foregroundStyle(c.textTertiary)
            }
            Link(AppStrings.plusTermsLink(l), destination: AppConfig.termsURL(l))
            Text(verbatim: "·").foregroundStyle(c.textTertiary)
            Link(AppStrings.plusPrivacyLink(l), destination: AppConfig.privacyPolicyURL(l))
        }
        .font(.inter(12, weight: .medium))
        .tint(c.textSecondary)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
    }
}
