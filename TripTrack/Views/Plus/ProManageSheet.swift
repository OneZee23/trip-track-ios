import SwiftUI
import StoreKit

/// «Ваш PRO» — экран подписчика между строкой PRO на «Я» и системным листом
/// Apple (0.8.9, решение владельца 11 октября).
///
/// До него строка вела подписчика прямо в лист Apple, где первой стояла кнопка
/// «Отменить подписку», — без слова о том, что у человека включено. Здесь три
/// вещи, и порядок их — решение:
///
/// 1. **Что с подпиской** — одна строка `ProManageLine`: дата и следующее
///    списание, честно (отменившему продление — без цены).
/// 2. **Что у вас включено** — пять функций с его собственным выбором.
/// 3. **«Управлять подпиской в App Store»** — строкой, ВИДИМОЙ БЕЗ ПРОКРУТКИ
///    (она приколочена под списком, а не в его конце), и подписью «сменить
///    тариф или отменить — там же». Отмена остаётся в двух касаниях: прятать
///    её глубже запрещают правило ревью 3.1.2 и законы о простом отказе от
///    подписки. Держит `ProManageSheetTests`.
///
/// Функции открывают СВОИ витрины, но не поверх этого листа: лист закрывается
/// и отдаёт выбор наверх (`onOpen`), а «Я» открывает витрину своим путём, —
/// два листа подряд UIKit не даёт (тот же приём, что `pendingPaywall` у
/// `ProShowcaseHost`).
struct ProManageSheet: View {
    /// Что открыть после закрытия листа.
    enum Destination: Equatable {
        case showcase(ProShowcaseKind)
        case manualTrip
    }

    let status: ProStatus
    let onOpen: (Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var store = PlusStore.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(c, l)
                    included(c, l)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            appStoreRow(c, l)
        }
        .background(c.bg)
        .overlay(alignment: .topTrailing) { closeButton(c) }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro_manage")
        // Цена тарифа нужна строке подписки, а продукты могли не приехать:
        // экран открывают с «Я», куда витрина не заходила.
        .task { if store.products.isEmpty { await store.loadProducts() } }
    }

    // MARK: - Подписка

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(AppStrings.proManageTitle(l))
                    .font(.interScaled(30, weight: .heavy, relativeTo: .title))
                    .kerning(AppType.titleTracking)
                    .foregroundStyle(c.text)
                ProBadge(height: 18)
            }
            if let text = line.text(l, date: { Self.formatters[l]?.string(from: $0) ?? "" }) {
                Text(text)
                    .font(.interScaled(15, relativeTo: .subheadline))
                    .foregroundStyle(status == .grace ? AppTheme.red : c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pro_manage_line")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Место под крестик: он лежит слоем выше.
        .padding(.trailing, 44)
        .padding(.top, 24)
    }

    private var line: ProManageLine {
        let info = store.products.first { $0.id == store.currentProductID }
            .flatMap(PlusProductInfo.init(product:))
        return ProManageLine.resolve(status: status,
                                     period: info?.period,
                                     productPrice: info?.displayPrice,
                                     willAutoRenew: store.willAutoRenew)
    }

    // MARK: - Что включено

    private func included(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionLabel(text: AppStrings.proManageIncluded(l))
            VStack(spacing: 0) {
                ForEach(Array(PlusFeature.allCases.enumerated()), id: \.element) { index, feature in
                    row(feature, c, l)
                    if index < PlusFeature.allCases.count - 1 {
                        Divider().overlay(c.border).padding(.leading, 54)
                    }
                }
            }
            .padding(.horizontal, 14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    @ViewBuilder
    private func row(_ feature: PlusFeature, _ c: AppTheme.Colors,
                     _ l: LanguageManager.Language) -> some View {
        let target = destination(for: feature)
        let content = HStack(spacing: 12) {
            Image(systemName: feature.proIcon)
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.proTitle(l))
                    .font(.interScaled(16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(c.text)
                Text(choice(for: feature, l))
                    .font(.interScaled(13, relativeTo: .footnote))
                    .foregroundStyle(c.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Шеврон — только там, где нажатие что-то открывает. Фон карточки
            // выбирают в форме САМОЙ машины, и отсюда идти некуда.
            if target != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())

        if let target {
            Button {
                Haptics.tap()
                dismiss()
                onOpen(target)
            } label: { content }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("pro_manage_\(feature.proIcon)")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pro_manage_\(feature.proIcon)")
        }
    }

    private func destination(for feature: PlusFeature) -> Destination? {
        switch feature {
        case .profileBackgrounds: return .showcase(.profileBackground)
        case .avatarFrame:        return .showcase(.avatarFrame)
        case .routeLineStyle:     return .showcase(.routeLine)
        case .manualTrip:         return ManualTripEntry.isVisible ? .manualTrip : nil
        case .vehicleCardStyle:   return nil
        }
    }

    /// Что выбрано сейчас — имя собственное варианта, а у отсутствия выбора
    /// слово «Обычный»: строка отвечает на «что у меня включено», и пустая
    /// подпись читалась бы сбоем.
    private func choice(for feature: PlusFeature, _ l: LanguageManager.Language) -> String {
        switch feature {
        case .profileBackgrounds:
            let bg = ProfileBackground.effective(id: settings.profileBackground, isPlus: true)
            return bg == .none ? AppStrings.cosmeticDefaultOption(l) : bg.displayName
        case .avatarFrame:
            let frame = AvatarFrame.effective(id: settings.avatarFrame, isPlus: true)
            return frame == .none ? AppStrings.cosmeticDefaultOption(l) : frame.displayName
        case .routeLineStyle:
            let line = RouteLineStyle.stored
            return line == .speed ? AppStrings.routeLineSpeedGradient(l) : line.displayName
        case .vehicleCardStyle:
            return AppStrings.proManageVehicleCardWhere(l)
        case .manualTrip:
            return AppStrings.proManageManualOn(l)
        }
    }

    // MARK: - App Store

    /// Дверь к системному листу: отмена, смена тарифа, возврат — там. Стоит
    /// ПОД скроллом, а не в его конце: ищущий отмену видит её без прокрутки
    /// на любом телефоне и при любом размере текста.
    private func appStoreRow(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 6) {
            Button {
                Haptics.tap()
                PlusRow.openManageSubscriptions()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 17))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    Text(AppStrings.proManageAppStore(l))
                        .font(.interScaled(16, weight: .medium, relativeTo: .body))
                        .foregroundStyle(c.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .surfaceCard(cornerRadius: 16)
            .accessibilityIdentifier("pro_manage_app_store")

            Text(AppStrings.proManageAppStoreHint(l))
                .font(.interScaled(12, relativeTo: .caption))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        // Приколоченный низ растёт с текстом не дальше первого размера
        // доступности: на самом крупном он занимал полэкрана, и список
        // функций над ним сжимался до одного заголовка. Строка остаётся
        // крупной и видимой — так же ведут себя нижние панели системы.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func closeButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(c.cardAlt))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .padding(.trailing, 10)
        .accessibilityLabel(AppStrings.close(lang.language))
        .accessibilityIdentifier("pro_manage_close")
    }

    private static let formatters = LocalizedDateFormatter.templates("dMMMyyyy")
}
