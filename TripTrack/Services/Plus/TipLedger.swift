import Foundation

/// Память вопроса «сказать спасибо» — когда спрашивали, сколько раз человек
/// отказался и когда он всё-таки поблагодарил.
///
/// Отдельно от `ProOfferLedger` по той же причине, по которой `TipMoment`
/// отдельно от `ProContextOffer`: там считаются отказы от ПОКУПКИ, здесь — от
/// подарка, и складывать их в один счётчик значило бы закрыть человеку одно
/// из-за другого.
///
/// В `UserDefaults`, а не в CoreData: предмет тут не поездка, а поведение
/// приложения (тот же довод, что у `ProOfferLedger`). Личного — три значения.
///
/// Хранилище приходит параметром, чтобы тест не писал в контейнер симулятора:
/// правило, купленное `PrivacyZoneDisciplineTests`.
struct TipLedger {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let lastAskedAt = "tips.lastAskedAt.v1"
        static let declines = "tips.declines.v1"
        static let tippedAt = "tips.tippedAt.v1"
    }

    // MARK: - Чтение

    var lastAskedAt: Date? { date(Key.lastAskedAt) }
    var declines: Int { defaults.integer(forKey: Key.declines) }
    var tippedAt: Date? { date(Key.tippedAt) }

    // MARK: - Запись

    /// Карточка показана. Ставится в момент ПОКАЗА, а не нажатия: срок «раз в
    /// полгода» считается от того, когда человека потревожили, а не от того,
    /// ответил ли он.
    func noteAsked(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastAskedAt)
    }

    /// Человек закрыл карточку.
    func noteDeclined() {
        defaults.set(declines + 1, forKey: Key.declines)
    }

    /// Человек поблагодарил. Отказы при этом ОБНУЛЯЮТСЯ: «нет» год назад и
    /// «да» сегодня — это про разные моменты, и тащить прежний счёт дальше
    /// значило бы наказать его за прошлое.
    func noteTipped(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.tippedAt)
        defaults.set(0, forKey: Key.declines)
    }

    private func date(_ key: String) -> Date? {
        let raw = defaults.double(forKey: key)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }
}
