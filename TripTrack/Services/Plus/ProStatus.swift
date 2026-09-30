import Foundation

/// Куда ведёт нажатие по строке PRO.
///
/// Четыре ответа, и `nothing` с `none` — разные: у первого строка есть, но не
/// нажимается (покупка ждёт одобрения, и предлагать купить второй раз нельзя),
/// у второго строки нет вовсе (витрина платного не продаёт).
enum ProRowDestination: Equatable {
    case paywall
    case manageSubscription
    case nothing
    case none
}

/// Что человек видит в строке PRO на экране «Я» — восемь ответов.
///
/// Вынесено из `PlusRow` чистым типом по той же причине, по которой это
/// сделано у `DashboardUnits` и `AutoTripPolicy`: до 0.8.4 строка знала три
/// состояния и решала сама внутри `body`, а состояний восемь, два из них про
/// витрину, и проверить такое открытым экраном нельзя.
///
/// **Порядок разбора нельзя переставить.** Он тот же, что у `PlusGate`: право
/// первым, витрина второй. Купленная на другой витрине подписка обязана честно
/// работать там, где местная больше ничего не продаёт (состояние 17а), — иначе
/// человек, переехавший в другую страну, теряет то, за что заплатил.
enum ProStatus: Equatable {
    /// Никогда не покупал, витрина продаёт.
    case none
    /// Идут бесплатные дни.
    case trial(until: Date?)
    /// Оплаченный период.
    case active(until: Date?)
    /// Был и кончился.
    case expired(on: Date?)
    /// Оплата не прошла, Apple ещё пытается. PRO при этом РАБОТАЕТ.
    case grace
    /// Покупка ждёт одобрения (Ask To Buy).
    ///
    /// Живёт только в памяти той сессии, где покупку начали: StoreKit не даёт
    /// запроса про висящий запрос, а сохранённый флаг показывал бы «ждём»
    /// вечно тому, кому родитель отказал. После перезапуска строка честно
    /// падает на настоящее право.
    case pending
    /// Подписки нет И витрина платного не продаёт — строки нет вовсе (17).
    case hiddenStorefront
    /// Подписка есть, а витрина не продаёт (17а): оформление работает и
    /// меняется, продлевать негде.
    case proWithoutStore(until: Date?)

    /// - Parameters:
    ///   - state: право от StoreKit (`PlusStore.State`). Отдельных булевых
    ///     `isTrial`/`isGrace` здесь нет нарочно: перечисление уже существует,
    ///     а два булева выражали бы невозможное «триал и грейс одновременно».
    ///   - isPending: покупка ждёт одобрения В ЭТОЙ сессии.
    ///   - storefrontHidesPlus: витрина устройства платного не продаёт.
    static func resolve(
        state: PlusStore.State,
        expires: Date?,
        isPending: Bool,
        storefrontHidesPlus: Bool
    ) -> ProStatus {
        // Право первым — так же, как в `PlusGate.allows`.
        switch state {
        case .active, .trial, .grace:
            if storefrontHidesPlus { return .proWithoutStore(until: expires) }
            switch state {
            case .trial:  return .trial(until: expires)
            case .grace:  return .grace
            default:      return .active(until: expires)
            }
        case .none, .expired:
            // Продлевать негде — строка, ведущая в пустоту, хуже отсутствующей.
            if storefrontHidesPlus { return .hiddenStorefront }
            if isPending { return .pending }
            return state == .expired ? .expired(on: expires) : .none
        }
    }

    /// Рисуется ли строка вообще.
    var showsRow: Bool { self != .hiddenStorefront }

    var destination: ProRowDestination {
        switch self {
        case .none, .expired:                      return .paywall
        case .trial, .active, .grace,
             .proWithoutStore:                     return .manageSubscription
        case .pending:                             return .nothing
        case .hiddenStorefront:                    return .none
        }
    }

    /// Заголовок один на все статусы — имя продукта. Исключение одно:
    /// у закончившейся он свой и несёт дату, потому что «TripTrack PRO» над
    /// подписью «вернётся с подпиской» читалось бы как действующая подписка.
    func rowTitle(lang: LanguageManager.Language) -> String {
        switch self {
        case .expired(let on):
            // Дату могли не узнать вовсе (Apple молчит с первого запуска).
            // Тогда остаётся «PRO закончился» — и пробел на месте даты надо
            // СХЛОПНУТЬ, а не подрезать: у турецкого и казахского токен стоит
            // в СЕРЕДИНЕ шаблона («PRO {date} tarihinde bitti»), и обрезка
            // концов оставляла бы двойной пробел внутри строки. Поймано
            // повторным ревью задачи 2 — первая правка чинила 11 языков из 13,
            // а сторож на остальных двух проходил вакуумно.
            return Self.squeezingSpaces(
                AppStrings.meProExpired(lang)
                    .replacingOccurrences(of: "{date}", with: Self.shortDate(on, lang)))
        case .hiddenStorefront:
            return ""
        default:
            return AppStrings.meProNone(lang)
        }
    }

    func rowSubtitle(lang: LanguageManager.Language) -> String {
        switch self {
        case .none:
            return AppStrings.meProNoneSub(lang)
        case .trial(let until):
            return dated(AppStrings.meProTrialSub(lang), until, lang)
        case .active(let until), .proWithoutStore(let until):
            return dated(AppStrings.meProActiveSub(lang), until, lang)
        case .expired:
            return AppStrings.meProExpiredSub(lang)
        case .grace:
            return AppStrings.meProGraceSub(lang)
        case .pending:
            return AppStrings.meProPendingSub(lang)
        case .hiddenStorefront:
            return ""
        }
    }

    /// Даты в строке нет — показываем общее описание набора, как это делала
    /// строка до 0.8.4. `expiresAt` у StoreKit опционален, и обещать «до»
    /// без даты нечем.
    private func dated(_ template: String, _ date: Date?,
                       _ lang: LanguageManager.Language) -> String {
        guard let date else { return AppStrings.meProNoneSub(lang) }
        return template.replacingOccurrences(of: "{date}",
                                             with: Self.shortDate(date, lang))
    }

    /// Двойные пробелы в один, концы подрезаны. Нужна там, где подстановка
    /// могла оказаться пустой в СЕРЕДИНЕ строки.
    static func squeezingSpaces(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// «12 окт» — день и месяц своим порядком для каждого языка. Года нет
    /// нарочно: подписка живёт год, и «до 12 окт» читается однозначно, а
    /// полная дата в строке шириной с профиль обрезается.
    private static let formatters = LocalizedDateFormatter.templates("dMMM")

    static func shortDate(_ date: Date?, _ lang: LanguageManager.Language) -> String {
        guard let date else { return "" }
        return formatters[lang]?.string(from: date) ?? ""
    }
}
