import Foundation
import StoreKit

/// Тариф «как его надо показать», отвязанный от StoreKit.
///
/// Существует ради одной проверки: строки пейвола — «Год · 19,99 €», «Неделя
/// бесплатно», «−44 %» — обязаны собираться из ответа Apple, а не из
/// литералов, и проверить это можно только там, где `Product` собрать нечем.
/// `Product` не создаётся руками ни в одном тесте: у него нет инициализатора
/// вовсе.
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

/// Один тариф на пейволе — состояния 1, 4, 5 матрицы 0.8.4.
struct PlusPlan: Identifiable, Equatable {
    let id: String
    let period: PlusProductInfo.Period
    /// «Год · 19,99 €» — период и цена ОДНОЙ строкой (макет 0.8.4). До него
    /// это были два поля, и карточка склеивала их сама; склейка переехала
    /// сюда, потому что порядок «период · цена» и разделитель — часть копии,
    /// а копия живёт в таблицах перевода.
    let title: String
    /// «Неделя бесплатно», «1,67 € в месяц» или «Без пробной недели».
    let caption: String?
    /// Акцентом печатается ТОЛЬКО обещание недели: это обещание, а не справка.
    /// Терракота в этой версии закреплена за покупкой и за числами.
    let captionIsAccent: Bool
    /// «−44 %» на верхней кромке. `nil` — посчитать не из чего или выгоды нет.
    let savingPercent: Int?
    /// Цена ровно такой, какой её напечатала витрина. Нужна кнопке
    /// («Оформить за {price} в год») и строке условий.
    let displayPrice: String
    /// Выделен и выбран при открытии. Годовой (спека §1).
    let isDefault: Bool
    /// Даст ли Apple бесплатную неделю ПО ЭТОМУ тарифу. Решает и подпись, и
    /// текст кнопки, и строку условий — один ответ на три места.
    let hasFreeWeek: Bool
}

/// Сборка тарифов — чистая функция, потому что проверять здесь надо СТРОКИ.
enum PlusPaywallModel {
    /// Длина бесплатного предложения, которую обещает КОПИЯ макета: «Неделя
    /// бесплатно».
    ///
    /// Копия говорит «неделя», а Apple присылает ЧИСЛО дней, и разойтись этим
    /// двум нельзя: обещать неделю там, где витрина даёт три дня, — это
    /// Review 3.1.2. Поэтому вся трёхчастная подача триала (подпись, кнопка,
    /// условия) включается только при РОВНО семи днях; при любом другом числе
    /// пейвол показывает состояние 4 («недели не положено») и не обещает
    /// ничего. Недообещать безопасно, переобещать — нет.
    static let freeWeekDays = 7

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
        // Выгода и «в месяц» считаются ОДИН раз на таблицу, а не на карточку:
        // оба числа про ПАРУ тарифов, и посчитать их внутри годового значило
        // бы читать оттуда месячный.
        let yearlyPrice = ordered.first { $0.period == .yearly }?.price
        let monthlyPrice = ordered.first { $0.period == .monthly }?.price
        let saving = ProPriceMath.savingPercent(yearly: yearlyPrice, monthly: monthlyPrice)
        let perMonth = ProPriceMath.perMonth(
            yearly: yearlyPrice,
            format: ordered.first { $0.period == .yearly }?.format)

        return ordered.enumerated().map { index, info in
            let week = info.period == .yearly
                && eligibleForIntro
                && info.trialDays == freeWeekDays

            let caption: String?
            let accent: Bool
            switch info.period {
            case .yearly:
                if week {
                    caption = AppStrings.proPlanYearTrial(lang)
                    accent = true
                } else {
                    caption = perMonth.map { AppStrings.proPlanYearPerMonth(lang, price: $0) }
                    accent = false
                }
            case .monthly:
                caption = AppStrings.proPlanMonthSub(lang)
                accent = false
            }

            return PlusPlan(
                id: info.id,
                period: info.period,
                title: info.period == .yearly
                    ? AppStrings.proPlanYear(lang, price: info.displayPrice)
                    : AppStrings.proPlanMonth(lang, price: info.displayPrice),
                caption: caption,
                captionIsAccent: accent,
                savingPercent: info.period == .yearly ? saving : nil,
                displayPrice: info.displayPrice,
                isDefault: index == 0,
                hasFreeWeek: week
            )
        }
    }

    /// Что выбрать при открытии. `nil` только когда продуктов нет вовсе.
    static func defaultSelection(_ plans: [PlusPlan]) -> String? {
        plans.first { $0.isDefault }?.id ?? plans.first?.id
    }

    /// Длина вводного предложения в днях из периода Apple.
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
