import Foundation

/// Память контекстного предложения — что показывали, когда и сколько раз
/// человек сказал «нет».
///
/// В `UserDefaults`, и это осознанно: запись должна переживать убийство
/// приложения на парковке (тот же довод, что у `places.pendingHistory`), а
/// строки в CoreData у неё нет — предмет тут не поездка и не место, а
/// поведение приложения. Личного в ней нет: четыре числа и два множества
/// имён моментов.
///
/// Хранилище приходит параметром, чтобы тест не писал в контейнер симулятора:
/// правило, купленное `PrivacyZoneDisciplineTests` — оставшаяся от соседнего
/// прогона настройка красит чужой тест в другом конце набора.
struct ProOfferLedger {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let lastOfferAt = "pro.offer.lastAt.v1"
        static let consecutiveDeclines = "pro.offer.declinesInARow.v1"
        static let totalDeclines = "pro.offer.declinesTotal.v1"
        static let shownMoments = "pro.offer.shown.v1"
        static let firstLaunchAt = "pro.offer.firstLaunchAt.v1"
        static let proExpiredAt = "pro.offer.proExpiredAt.v1"
    }

    // MARK: - Чтение

    var lastOfferAt: Date? { date(Key.lastOfferAt) }
    var consecutiveDeclines: Int { defaults.integer(forKey: Key.consecutiveDeclines) }
    var totalDeclines: Int { defaults.integer(forKey: Key.totalDeclines) }
    var proExpiredAt: Date? { date(Key.proExpiredAt) }

    var shownMoments: Set<ProOfferMoment> {
        let raw = defaults.stringArray(forKey: Key.shownMoments) ?? []
        // Незнакомое имя (момент из будущей версии, откатились назад) молча
        // отбрасывается: список показанного — не контракт, и ронять из-за него
        // предложение нельзя.
        return Set(raw.compactMap(ProOfferMoment.init(rawValue:)))
    }

    /// Когда человек впервые запустил приложение.
    ///
    /// Записывается ОДИН раз и только если ключа ещё нет: перезапись сдвинула
    /// бы «семь дней» на каждом запуске, и порог входа не наступил бы никогда.
    /// `nil` до первой записи — и тогда предложение молчит (правило
    /// `ProContextOffer`).
    var firstLaunchAt: Date? { date(Key.firstLaunchAt) }

    // MARK: - Запись

    /// Отметить первый запуск. Идемпотентно.
    func rememberFirstLaunchIfNeeded(_ now: Date = Date()) {
        guard defaults.object(forKey: Key.firstLaunchAt) == nil else { return }
        defaults.set(now.timeIntervalSince1970, forKey: Key.firstLaunchAt)
    }

    /// Лист показан.
    func recordShown(_ moment: ProOfferMoment, at now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastOfferAt)
        var shown = defaults.stringArray(forKey: Key.shownMoments) ?? []
        if !shown.contains(moment.rawValue) { shown.append(moment.rawValue) }
        defaults.set(shown, forKey: Key.shownMoments)
    }

    /// «Не сейчас». Считается и подряд, и всего: два подряд дают паузу,
    /// три всего выключают предложение навсегда.
    func recordDecline() {
        defaults.set(consecutiveDeclines + 1, forKey: Key.consecutiveDeclines)
        defaults.set(totalDeclines + 1, forKey: Key.totalDeclines)
    }

    /// «Подробнее о PRO» — человек пошёл смотреть.
    ///
    /// Счётчик ПОДРЯД сбрасывается, а общий нет: интерес отменяет паузу, но
    /// не стирает историю отказов. Иначе «нет, нет, посмотрел, нет, нет,
    /// посмотрел» обходило бы правило трёх отказов вечно.
    func recordInterest() {
        defaults.set(0, forKey: Key.consecutiveDeclines)
    }

    /// Подписка кончилась — повод для момента M4. Пишется один раз на
    /// окончание; продление снимает отметку.
    func recordProExpired(at date: Date?) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: Key.proExpiredAt)
        } else {
            defaults.removeObject(forKey: Key.proExpiredAt)
        }
    }

    // MARK: -

    private func date(_ key: String) -> Date? {
        guard let stamp = defaults.object(forKey: key) as? Double else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    #if DEBUG
    /// Для тестов: забыть всё. В продукте двери сюда нет — предложение не
    /// сбрасывается ничем, кроме удаления приложения, иначе правило трёх
    /// отказов обходилось бы переустановкой настроек.
    func forgetEverythingForTesting() {
        for key in [Key.lastOfferAt, Key.consecutiveDeclines, Key.totalDeclines,
                    Key.shownMoments, Key.firstLaunchAt, Key.proExpiredAt] {
            defaults.removeObject(forKey: key)
        }
    }
    #endif
}
