import Foundation

/// Строки путешествия — даты, длительность, имя плеча.
///
/// В одном месте, потому что их читают сразу трое: герой экрана, лента по дням
/// и лист подбора плеч. Формирователи собраны один раз (`static let`):
/// `LocalizedDateFormatter.templates` строит тринадцать `DateFormatter` за
/// вызов, а лента по дням спрашивает дату на каждой строке.
enum JourneyFormat {
    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")
    private static let dayMonthWeekday = LocalizedDateFormatter.templates("dMMMEEE")
    private static let hourMinute = LocalizedDateFormatter.templates("Hm")

    /// «12–17 сен», «30 сен – 2 окт», «12 сен».
    ///
    /// Месяц печатается один раз только там, где язык сам держит число с краю
    /// строки: по-русски «12 сент.» начинается числом, по-английски «Sep 12» —
    /// заканчивается им. Языку, который прячет число в середину, диапазон
    /// достаётся полным: это честнее, чем резать чужую грамматику по позиции
    /// подстроки.
    static func dateRange(from: Date, to: Date, language: LanguageManager.Language) -> String {
        guard let f = dayMonth[language] else { return "" }
        let calendar = Calendar.current
        let a = f.string(from: from)
        guard !calendar.isDate(from, inSameDayAs: to) else { return a }
        let b = f.string(from: to)
        if calendar.isDate(from, equalTo: to, toGranularity: .month) {
            let dayA = String(calendar.component(.day, from: from))
            let dayB = String(calendar.component(.day, from: to))
            if a.hasPrefix(dayA) { return "\(dayA)\u{2013}\(b)" }
            if a.hasSuffix(dayA) { return "\(a)\u{2013}\(dayB)" }
        }
        return "\(a) \u{2013} \(b)"
    }

    /// «12 сен, чт» — заголовок дня. Порядок полей выбирает язык.
    static func dayDate(_ date: Date, language: LanguageManager.Language) -> String {
        dayMonthWeekday[language]?.string(from: date) ?? ""
    }

    /// «15:00» — время старта местной поездки внутри раскрытой стоянки.
    /// Шаблон, а не жёсткий формат: половина языков пишет «3:00 PM», и решать
    /// это за них по флагу «ru или нет» мы уже пробовали.
    static func time(_ date: Date, language: LanguageManager.Language) -> String {
        hourMinute[language]?.string(from: date) ?? ""
    }

    /// «5 ч 20 мин» — те же куски, что на плитках «Детали» поездки, просто
    /// в строку. Своего форматирования времени у путешествия нет: разойтись
    /// с поездкой, из которой оно собрано, ему нечем.
    static func duration(_ seconds: TimeInterval, language: LanguageManager.Language) -> String {
        TripDetailFormat.durationSegments(seconds, lang: language)
            .map { $0.unit.isEmpty ? $0.value : "\($0.value) \($0.unit)" }
            .joined(separator: " ")
    }

    /// Имя поездки — тот же ответ, что дают карточки ленты: имя, иначе регион,
    /// иначе дата. Расходиться им нельзя: это одна и та же поездка на двух
    /// экранах.
    static func tripTitle(_ trip: Trip, language: LanguageManager.Language) -> String {
        if trip.hasDisplayableName,
           let t = TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: language),
           !t.isEmpty {
            return t
        }
        if let region = RegionDisplay.localized(trip.region, language: language), !region.isEmpty {
            return region
        }
        return ProfileDateFormat.dayMonth(trip.startDate, lang: language)
    }
}

/// Заголовок путешествия — ОДНА лестница из трёх ступеней на всё приложение.
///
/// Имя, данное рукой; иначе «Краснодар — Тбилиси», собранное из имён мест;
/// иначе даты окна, которые есть у путешествия всегда. Экран и карточка
/// считали её каждый по своей копии — а одна запись не может называться на
/// двух экранах по-разному, и первое же расхождение копий читалось бы как два
/// разных путешествия.
enum JourneyTitle {
    static func text(_ journey: Journey, aggregate: JourneyAggregate,
                     startName: String?, farthestName: String?,
                     dateRange: String) -> String {
        if let title = journey.title, !title.isEmpty { return title }
        if let auto = aggregate.defaultTitle(startName: startName, farthestName: farthestName),
           !auto.isEmpty {
            return auto
        }
        return dateRange
    }
}
