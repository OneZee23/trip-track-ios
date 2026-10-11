import Foundation

/// Что экран «Ваш PRO» говорит о подписке — одной строкой (0.8.9).
///
/// До 0.8.9 строка PRO на «Я» вела подписчика прямо в системный лист Apple, и
/// первым, что он там видел, была кнопка «Отменить подписку» — ни слова о том,
/// что у него включено. Решение владельца 11 октября: сначала свой экран —
/// что входит и когда следующее списание, — а «Управлять подпиской в App
/// Store» строкой на нём, видимой без прокрутки. Отмена остаётся в двух
/// касаниях: прятать её глубже запрещают правило ревью 3.1.2 и законы о
/// простом отказе от подписки, и это не обсуждается.
///
/// Отсюда главное правило строки: **она не обещает списание, которого не
/// будет.** Отменившему продление (`willAutoRenew == false`) — «PRO работает
/// до…», без цены. Apple промолчала (`nil`) — дата без слова о продлении, а не
/// «продлится»: молчание не означает ни того, ни другого.
enum ProManageLine: Equatable {
    /// Пробный период, продлится: «Пробный период до 18 окт., потом 24,99 € в год».
    case trialRenews(until: Date, price: String, period: PlusProductInfo.Period)
    /// Оплаченный период, продлится: «Продлится 12 окт. 2027 · 24,99 € в год».
    case renews(on: Date, price: String, period: PlusProductInfo.Period)
    /// Продление отключено: «Продление отключено. PRO работает до 12 окт.».
    case endsOn(Date)
    /// Дата есть, а про продление или цену Apple не сказала: «PRO до 12 окт.».
    case until(Date)
    /// Оплата не прошла, Apple ещё пытается. PRO работает.
    case billingProblem
    /// Даты нет вовсе — строку не печатаем.
    case unknown

    /// - Parameters:
    ///   - status: строка PRO на «Я». Экран открывается только у подписчика,
    ///     остальные статусы сюда не приходят и дают `.unknown`.
    ///   - productPrice: цена ДЕЙСТВУЮЩЕГО тарифа строкой витрины. `nil` —
    ///     продукты не приехали или тариф неизвестен.
    ///   - willAutoRenew: см. `PlusStore.willAutoRenew`.
    static func resolve(
        status: ProStatus,
        period: PlusProductInfo.Period?,
        productPrice: String?,
        willAutoRenew: Bool?
    ) -> ProManageLine {
        switch status {
        case .grace:
            return .billingProblem
        case .trial(let until?):
            return line(date: until, isTrial: true, period: period,
                        price: productPrice, renews: willAutoRenew)
        case .active(let until?):
            return line(date: until, isTrial: false, period: period,
                        price: productPrice, renews: willAutoRenew)
        case .proWithoutStore(let until?):
            // Цену не печатаем: продлится подписка там, где её купили, и цена
            // у той витрины своя, а местная её не продаёт вовсе.
            return line(date: until, isTrial: false, period: period,
                        price: nil, renews: willAutoRenew)
        default:
            return .unknown
        }
    }

    private static func line(
        date: Date, isTrial: Bool, period: PlusProductInfo.Period?,
        price: String?, renews: Bool?
    ) -> ProManageLine {
        switch renews {
        case false?:
            return .endsOn(date)
        case true?:
            guard let price, let period else { return .until(date) }
            return isTrial ? .trialRenews(until: date, price: price, period: period)
                           : .renews(on: date, price: price, period: period)
        case nil:
            return .until(date)
        }
    }

    /// Текст строки. Дату печатает вызывающий одним форматтером на язык.
    func text(_ lang: LanguageManager.Language, date format: (Date) -> String) -> String? {
        switch self {
        case let .trialRenews(until, price, period):
            return AppStrings.proManageTrialRenews(lang, date: format(until),
                                                   price: price, yearly: period == .yearly)
        case let .renews(on, price, period):
            return AppStrings.proManageRenews(lang, date: format(on),
                                              price: price, yearly: period == .yearly)
        case .endsOn(let date):
            return AppStrings.proManageEndsOn(lang, date: format(date))
        case .until(let date):
            return AppStrings.proManageUntil(lang, date: format(date))
        case .billingProblem:
            return AppStrings.meProGraceSub(lang)
        case .unknown:
            return nil
        }
    }
}
