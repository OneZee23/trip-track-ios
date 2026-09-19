import Foundation
import StoreKit

/// Тариф «как его надо показать», отвязанный от StoreKit.
///
/// Существует ради одной проверки: строки пейвола — «Год», «29,99 € в год»,
/// «7 дней бесплатно, потом …» — обязаны собираться из ответа Apple, а не из
/// литералов, и проверить это можно только там, где `Product` собрать нечем.
/// `Product` не создаётся руками ни в одном тесте: у него нет
/// инициализатора вовсе.
struct PlusProductInfo: Equatable {
    enum Period: String, Equatable { case yearly, monthly }

    let id: String
    /// Цена СТРОКОЙ, ровно как её напечатала витрина Apple. Ни числа, ни
    /// валюты отдельно здесь нет и быть не должно: валюту, разделитель и
    /// сторону знака решает `Product.displayPrice`, и пересобрать это своим
    /// форматтером — значит однажды показать «29.99 €» там, где витрина пишет
    /// «€29.99».
    let displayPrice: String
    let period: Period
    /// Длина вводного бесплатного предложения в днях. `nil` — предложения нет
    /// (месячный) или оно не бесплатное.
    let trialDays: Int?
}

/// Один тариф на пейволе.
struct PlusPlan: Identifiable, Equatable {
    let id: String
    let period: PlusProductInfo.Period
    /// «Год» / «Месяц».
    let title: String
    /// «29,99 € в год».
    let price: String
    /// «7 дней бесплатно, потом 29,99 € в год» — только там, где триал есть.
    let caption: String?
    /// Выделен и выбран при открытии. Годовой (спека §1).
    let isDefault: Bool
}

/// Сборка тарифов — чистая функция, потому что проверять здесь надо СТРОКИ.
enum PlusPaywallModel {
    /// Годовой всегда первым и всегда выбранным по умолчанию — решение спеки,
    /// а не порядок, в котором Apple вернула продукты (он не обещан).
    /// - Parameter eligibleForIntro: даст ли Apple вводное предложение ЭТОМУ
    ///   Apple ID (`PlusStore.introEligible`). Параметр обязателен и без
    ///   значения по умолчанию нарочно — тот же рычаг, что у `Measure.unit:`:
    ///   новое место показа не соберётся, не сказав вслух, проверено ли
    ///   право. `introductoryOffer` у продукта существует ВСЕГДА, поэтому
    ///   строить подпись по нему значит обещать бесплатную неделю тому, кто
    ///   её уже съел, — и списать полную цену сразу (Review 3.1.2).
    static func plans(
        _ infos: [PlusProductInfo],
        eligibleForIntro: Bool,
        lang: LanguageManager.Language
    ) -> [PlusPlan] {
        let ordered = infos.sorted { a, _ in a.period == .yearly }
        return ordered.map { info in
            let price = info.period == .yearly
                ? AppStrings.plusPerYear(lang, price: info.displayPrice)
                : AppStrings.plusPerMonth(lang, price: info.displayPrice)
            let caption = (eligibleForIntro ? info.trialDays : nil).map {
                AppStrings.plusTrialCaption(lang, days: $0, price: price)
            }
            return PlusPlan(
                id: info.id,
                period: info.period,
                title: info.period == .yearly
                    ? AppStrings.plusPlanYear(lang)
                    : AppStrings.plusPlanMonth(lang),
                price: price,
                caption: caption,
                isDefault: info.period == .yearly
            )
        }
    }

    /// Что выбрано при открытии листа. Годовой; если его не привезли —
    /// первый из тех, что привезли, а не «ничего».
    static func defaultSelection(_ plans: [PlusPlan]) -> String? {
        plans.first(where: \.isDefault)?.id ?? plans.first?.id
    }

    /// Сколько дней в периоде предложения. Месяц у Apple — тридцать дней, год —
    /// триста шестьдесят пять: точные календарные границы здесь не нужны,
    /// число попадает только в подпись «N дней бесплатно».
    static func days(unit: Product.SubscriptionPeriod.Unit, value: Int) -> Int {
        switch unit {
        case .day:   return value
        case .week:  return value * 7
        case .month: return value * 30
        case .year:  return value * 365
        @unknown default: return value
        }
    }
}

extension PlusProductInfo {
    /// Разбор настоящего продукта Apple. Не тестируется напрямую и не должен:
    /// предмет проверки — строки, которые из него собираются.
    init?(product: Product) {
        guard let subscription = product.subscription else { return nil }
        let period: Period
        switch subscription.subscriptionPeriod.unit {
        case .year:  period = .yearly
        case .month: period = .monthly
        default:     return nil
        }
        var trial: Int?
        if let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial {
            trial = PlusPaywallModel.days(
                unit: offer.period.unit, value: offer.period.value)
        }
        self.init(
            id: product.id,
            displayPrice: product.displayPrice,
            period: period,
            trialDays: trial
        )
    }
}
