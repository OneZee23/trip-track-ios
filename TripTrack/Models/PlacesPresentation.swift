import Foundation

/// Порядок списка мест. Живёт на телефоне: это выбор показа, а не данные.
///
/// `rawValue` — ключ `UserDefaults`, менять нельзя.
enum PlacesSort: String, CaseIterable, Codable {
    /// Свежие сверху. То, что было до 0.8.1, и умолчание.
    case recent
    /// По числу проездов: «где я бываю чаще всего».
    case frequent
    /// По имени — единственный порядок, который не меняется от поездок.
    case name

    private static let defaultsKey = "places.sort"

    static func load(defaults: UserDefaults = .standard) -> PlacesSort {
        guard let raw = defaults.string(forKey: defaultsKey),
              let value = PlacesSort(rawValue: raw) else { return .recent }
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Список мест, приведённый к тому, что рисует экран: поиск, порядок и
/// группы. Чистой функцией — у экрана «Места» это единственное место, где
/// решается, что человек увидит, и проверять его открытым экраном дорого.
enum PlacesPresentation {

    /// Группа списка. `title == nil` — единственная группа, и заголовок ей
    /// не нужен: «Мои места» уже стоит выше.
    struct Group: Identifiable, Equatable {
        enum Kind: String { case all, frequent, others, today, thisWeek, earlier }
        let kind: Kind
        let items: [PlaceListItem]
        var id: String { kind.rawValue }
    }

    /// Порог, с которого список перестаёт быть списком: появляются поиск,
    /// сортировка и группы. Ниже него они только мешают — искать среди
    /// четырёх строк нечего.
    static let manyPlaces = 8

    /// Поиск по имени. Регистр и диакритика не важны, пустой запрос
    /// ничего не фильтрует.
    static func filter(_ items: [PlaceListItem], query: String,
                       language: LanguageManager.Language) -> [PlaceListItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return items }
        return items.filter { item in
            guard let name = item.place.name, !name.isEmpty else { return false }
            return name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive],
                              locale: language.locale) != nil
        }
    }

    /// Порядок. «Недавно» — прежняя сортировка целиком (`PlaceListItem
    /// .sorted`), чтобы умолчание не поехало; остальные два падают на неё же
    /// при равенстве, иначе порядок прыгал бы между перерисовками.
    static func sort(_ items: [PlaceListItem], by order: PlacesSort) -> [PlaceListItem] {
        let recent: [PlaceListItem] = PlaceListItem.sorted(items)
        guard order != .recent else { return recent }
        // Индекс несётся рядом и решает ничьи: без него равные элементы
        // меняются местами между перерисовками, и список «дышит».
        let ranked: [(index: Int, item: PlaceListItem)] = recent.enumerated()
            .map { (index: $0.offset, item: $0.element) }
        let sorted: [(index: Int, item: PlaceListItem)]
        switch order {
        case .recent:
            sorted = ranked
        case .frequent:
            sorted = ranked.sorted { lhs, rhs in
                let a = lhs.item.stats.passCount, b = rhs.item.stats.passCount
                return a == b ? lhs.index < rhs.index : a > b
            }
        case .name:
            sorted = ranked.sorted { lhs, rhs in
                let a: String = lhs.item.place.name ?? ""
                let b: String = rhs.item.place.name ?? ""
                if a.isEmpty != b.isEmpty { return !a.isEmpty }
                if a == b { return lhs.index < rhs.index }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        }
        return sorted.map(\.item)
    }

    /// Группы. Отделять «частых гостей» есть смысл только когда их меньше,
    /// чем всех: группа, в которую попало ВСЁ, не группирует ничего, а
    /// заголовок над ней врёт, что где-то есть остальные.
    static func group(_ items: [PlaceListItem], grouped: Bool,
                      by order: PlacesSort = .frequent,
                      now: Date = Date(),
                      calendar: Calendar = .current) -> [Group] {
        guard grouped else { return single(items) }
        switch order {
        case .name:
            // «По имени» групп не имеет вовсе (спека §3.4): алфавит сам и
            // есть группировка, а вторая поверх него ничего не добавляет.
            return single(items)
        case .frequent:
            let frequent = items.filter(\.isFrequentGuest)
            let others = items.filter { !$0.isFrequentGuest }
            return pack([(.frequent, frequent), (.others, others)], all: items)
        case .recent:
            let startOfToday = calendar.startOfDay(for: now)
            // Неделя считается ОТ СЕГОДНЯ назад, а не от понедельника:
            // вопрос у человека «когда я там был последний раз», и в
            // воскресенье «на этой неделе» из одного дня было бы обманом.
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
            var today: [PlaceListItem] = []
            var week: [PlaceListItem] = []
            var earlier: [PlaceListItem] = []
            for item in items {
                guard let last = item.lastAt else { earlier.append(item); continue }
                if last >= startOfToday { today.append(item) }
                else if last >= weekAgo { week.append(item) }
                else { earlier.append(item) }
            }
            return pack([(.today, today), (.thisWeek, week), (.earlier, earlier)], all: items)
        }
    }

    private static func single(_ items: [PlaceListItem]) -> [Group] {
        items.isEmpty ? [] : [Group(kind: .all, items: items)]
    }

    /// Группа, в которую попало ВСЁ, не группирует ничего, а заголовок над
    /// ней врёт, что где-то есть остальные. Поэтому пустые выбрасываются, и
    /// единственная выжившая превращается обратно в «Мои места».
    private static func pack(_ candidates: [(Group.Kind, [PlaceListItem])],
                             all items: [PlaceListItem]) -> [Group] {
        let filled = candidates.filter { !$0.1.isEmpty }
        guard filled.count > 1 else { return single(items) }
        return filled.map { Group(kind: $0.0, items: $0.1) }
    }

    /// Весь путь разом — то, что зовёт экран.
    static func build(_ items: [PlaceListItem], query: String, sort order: PlacesSort,
                      language: LanguageManager.Language, now: Date = Date()) -> [Group] {
        let found = filter(items, query: query, language: language)
        // Группы включает РАЗМЕР БИБЛИОТЕКИ, а не размер выдачи: иначе
        // поиск, сузивший список до трёх строк, менял бы ещё и его форму.
        return group(sort(found, by: order),
                     grouped: items.count >= manyPlaces && query.isEmpty,
                     by: order, now: now)
    }
}
