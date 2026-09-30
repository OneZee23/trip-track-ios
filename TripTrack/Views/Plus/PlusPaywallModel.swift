import Foundation
import StoreKit

/// Тариф «как его надо показать», отвязанный от StoreKit.
///
/// Существует ради одной проверки: строки пейвола — «Год», «29,99 € в год»,
/// «7 дней бесплатно, потом …» — обязаны собираться из ответа Apple, а не из
/// литералов, и проверить это можно только там, где `Product` собрать нечем.
/// `Product` не создаётся руками ни в одном тесте: у него нет
/// инициализатора вовсе.
/// Тариф, разобранный из ответа Apple.
///
/// `Equatable` у него НЕТ нарочно: с 0.8.4 он несёт `format` — функцию печати
/// цены, взятую у витрины, — а равенство двух функций не значит ничего.
/// Сравнивать тарифы никто не сравнивает; понадобится — пусть не соберётся и
/// автор напишет `==` руками по числам, а не получит синтезированное молча.
struct PlusProductInfo {
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
    /// Цена ЧИСЛОМ, для арифметики выгоды (`ProPriceMath`). `displayPrice`
    /// разобрать обратно нельзя: в нём валюта, разделитель и сторона знака той
    /// витрины, где стоит человек.
    let price: Decimal?
    /// Печать числа ТЕМ ЖЕ стилем, которым Apple напечатала `displayPrice`.
    /// Своего форматтера у нас нет и быть не должно (правило 0.8.0): «1,67 €»
    /// в Германии и «€1.67» в Ирландии — это решение витрины, не наше.
    let format: ((Decimal) -> String)?

    init(id: String,
         displayPrice: String,
         period: Period,
         trialDays: Int?,
         price: Decimal? = nil,
         format: ((Decimal) -> String)? = nil) {
        self.id = id
        self.displayPrice = displayPrice
        self.period = period
        self.trialDays = trialDays
        self.price = price
        self.format = format
    }
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
            // Неделя обещается ТОЛЬКО годовому и только тому, кому Apple её
            // даст. До 0.8.4 подпись собиралась у обоих тарифов: у месячного
            // `introductoryOffer` тоже существует, и пейвол обещал бесплатную
            // неделю там, где её нет ни при каких условиях.
            let trial = (info.period == .yearly && eligibleForIntro) ? info.trialDays : nil
            let caption = trial.map {
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
            trialDays: trial,
            price: product.price,
            format: { $0.formatted(product.priceFormatStyle) }
        )
    }
}
