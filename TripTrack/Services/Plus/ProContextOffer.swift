import Foundation

/// Момент, в который приложение само предлагает PRO — состояние 11 матрицы.
///
/// Три момента, и все три отвечают на РАЗНЫЙ вопрос человека. Четвёртого не
/// заводить: спека сняла M2 нарочно, а каждый новый лист платит вниманием, и
/// платит им человек, который ни о чём не просил.
enum ProOfferMoment: String, CaseIterable, Equatable {
    /// M1 — «Уже десять поездок. Профиль можно оформить».
    case tenTrips
    /// M3 — «Твой маршрут может быть любого цвета» на месяце с приложением.
    case oneMonth
    /// M4 — «PRO закончился». СТАТУС, а не порог: счётчика у него нет.
    case expired
}

/// Показывать ли предложение и какое — ЧИСТОЙ функцией.
///
/// Чистой, потому что проверять здесь надо КАЛЕНДАРЬ: «не чаще одного листа в
/// 30 дней», «два отказа подряд дают паузу 90 дней», «три отказа выключают
/// навсегда». Ни одно из этих правил нельзя проверить открытым экраном — на
/// это ушли бы месяцы, — а ошибка в любом из них выглядит как приложение,
/// которое просит денег у человека, уже трижды сказавшего «нет».
///
/// Запреты стоят ПЕРЕД выбором момента и в порядке «сначала то, что не
/// обсуждается»: подписка, витрина, сеть, первая сессия. Порядок не
/// переставлять — он и есть правило.
enum ProContextOffer {

    /// Раньше пятой поездки и семи дней не предлагаем ничего: человек ещё не
    /// понял, зачем ему приложение, и ответ на «купи» у него один.
    static let minTrips = 5
    static let minDays = 7
    /// Не чаще одного листа в 30 дней.
    static let cooldownDays = 30
    /// Два «Не сейчас» подряд — пауза 90 дней.
    static let declinesForPause = 2
    static let pauseDays = 90
    /// Три отказа всего — больше не предлагаем НИКОГДА.
    static let maxDeclines = 3
    /// Порог момента M1.
    static let tripsForFirstOffer = 10
    /// Порог момента M3.
    static let daysForSecondOffer = 30

    /// Всё, от чего зависит ответ. Структурой, а не десятью параметрами: вызов
    /// на десять аргументов однажды получил бы их в другом порядке, а тип
    /// у половины один и тот же.
    struct Input {
        var now: Date
        /// Подписка активна — предлагать нечего.
        var isPlus: Bool
        /// Витрина не продаёт платное (РФ) — платного на экране не бывает
        /// вовсе (правило `PlusGate`).
        var storefrontHidesPlus: Bool
        var tripCount: Int
        /// Когда человек впервые запустил приложение. `nil` — не знаем, и
        /// тогда «семь дней» считать не от чего: молчим.
        var firstLaunchAt: Date?
        /// Когда подписка закончилась. Не `nil` — момент M4.
        var proExpiredAt: Date?
        var lastOfferAt: Date?
        var consecutiveDeclines: Int
        var totalDeclines: Int
        /// Уже показанные ОДНОРАЗОВЫЕ моменты.
        var shownMoments: Set<ProOfferMoment>
        /// Первая сессия человека — не предлагаем.
        var isFirstSession: Bool
        /// В этой сессии он только что записал поездку — не предлагаем: он
        /// смотрит на свой итог, а не на витрину.
        var recordedTripThisSession: Bool
        /// Есть ли сеть. Без неё лист привёл бы на витрину без цен.
        var hasNetwork: Bool
        /// Мы на «Ленте» или на «Я». Запись, экран поездки и лист ручной
        /// поездки исключены самим этим флагом.
        var onEligibleScreen: Bool
        /// Лист в этой сессии уже показывали.
        var alreadyShownThisSession: Bool
    }

    static func moment(_ input: Input) -> ProOfferMoment? {
        guard !isBlocked(input) else { return nil }
        guard let moment = pick(input) else { return nil }
        // Скрытая витрина (РФ) закрывает ПРЕДЛОЖЕНИЕ, но не ИЗВЕЩЕНИЕ.
        //
        // §11 спеки запрещает лист при скрытой витрине, а матрица требует
        // обратного для 17а: «окончание ведёт в 17, M4 с одной кнопкой
        // „Понятно"». Противоречие разрешено по смыслу: M1 и M3 продают, и на
        // витрине, которая не продаёт, им делать нечего; M4 не продаёт ничего
        // — он сообщает, что оформление откатилось к бесплатному, а поездки
        // на месте. Не сказать об этом значило бы молча сменить человеку
        // профиль.
        if input.storefrontHidesPlus, moment != .expired { return nil }
        return moment
    }

    /// Продаёт ли этот момент. `false` — извещение, и кнопка у него одна
    /// («Понятно»), потому что вести некуда.
    static func sells(_ moment: ProOfferMoment, storefrontHidesPlus: Bool) -> Bool {
        !storefrontHidesPlus
    }

    /// Запреты. Вынесены отдельно, чтобы их можно было спросить по одному:
    /// «почему не показали» — вопрос, который задают чаще, чем «что показать».
    static func isBlocked(_ input: Input) -> Bool {
        // Не обсуждается ни при каких моментах.
        if input.isPlus { return true }
        // Витрины здесь НЕТ нарочно: она решает не «показывать ли вообще», а
        // «какие моменты можно» — см. `moment(_:)`.
        if !input.hasNetwork { return true }
        if input.isFirstSession { return true }
        if input.recordedTripThisSession { return true }
        if !input.onEligibleScreen { return true }
        if input.alreadyShownThisSession { return true }

        // Трижды сказанное «нет» — это ответ, а не пауза.
        if input.totalDeclines >= maxDeclines { return true }

        // Слишком рано: человек ещё не понял, зачем ему приложение.
        if input.tripCount < minTrips { return true }
        guard let firstLaunch = input.firstLaunchAt else { return true }
        if days(from: firstLaunch, to: input.now) < minDays { return true }

        if let last = input.lastOfferAt {
            let since = days(from: last, to: input.now)
            if since < cooldownDays { return true }
            if input.consecutiveDeclines >= declinesForPause, since < pauseDays {
                return true
            }
        }
        return false
    }

    /// Какой момент выигрывает.
    ///
    /// `.expired` первым: человек, у которого PRO БЫЛО и кончилось, отвечает
    /// на другой вопрос — не «зачем это», а «вернуть ли». И он единственный
    /// повторяемый: это статус, у него нет порога, который можно перейти один
    /// раз (спека §11). Повторы при этом всё равно ограничены — общим
    /// окном 30 дней и тремя отказами.
    private static func pick(_ input: Input) -> ProOfferMoment? {
        if input.proExpiredAt != nil { return .expired }
        if input.tripCount >= tripsForFirstOffer,
           !input.shownMoments.contains(.tenTrips) {
            return .tenTrips
        }
        if let firstLaunch = input.firstLaunchAt,
           days(from: firstLaunch, to: input.now) >= daysForSecondOffer,
           !input.shownMoments.contains(.oneMonth) {
            return .oneMonth
        }
        return nil
    }

    /// Целые СУТКИ между двумя точками. Секундами, а не календарём: вопрос
    /// здесь «сколько прошло», а не «какой сегодня день», и часовой пояс,
    /// сменившийся в поездке, не имеет права подарить человеку лишний лист.
    static func days(from: Date, to: Date) -> Int {
        Int(to.timeIntervalSince(from) / 86_400)
    }

    /// Какую фичу открывает кнопка момента. Момент обещает конкретную вещь, и
    /// вести он обязан на её страницу, а не в общий список.
    static func feature(for moment: ProOfferMoment) -> PlusFeature {
        switch moment {
        case .tenTrips: return .profileBackgrounds
        case .oneMonth: return .routeLineStyle
        case .expired:  return .profileBackgrounds
        }
    }
}
