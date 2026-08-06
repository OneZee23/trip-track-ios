import Foundation

/// Region names are geocoded ONCE at record time with whatever locale the
/// geocoder answered in, and stored verbatim — so a RU app happily shows
/// «Krasnodar Krai». Per the 2026-08-06 decision the DISPLAY follows the app
/// language (RU → «Краснодар. край», EN → "Krasnodar Krai") while storage
/// stays raw. Covers the RF federal subjects; anything unrecognized (foreign
/// regions, free-form strings) passes through untouched.
enum RegionDisplay {
    static func localized(_ raw: String?, language: LanguageManager.Language) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        guard let entry = Self.index[normalize(raw)] else { return raw }
        return language == .ru ? entry.ruShort : entry.en
    }

    // MARK: - Table

    private struct Entry { let en: String; let ruShort: String }

    /// (EN Apple-geocoder name, extra recognition aliases, RU full form,
    /// RU short display form — «область» → «обл.», long adjectives trimmed
    /// the way the Figma canon does: «Моск. обл.», «Краснодар. край»).
    private static let subjects: [(en: String, aliases: [String], ruFull: String, ruShort: String)] = [
        // Federal cities
        ("Moscow", [], "Москва", "Москва"),
        ("Saint Petersburg", ["St Petersburg", "St. Petersburg"], "Санкт-Петербург", "Санкт-Петербург"),
        ("Sevastopol", [], "Севастополь", "Севастополь"),
        // Oblasts
        ("Amur Oblast", [], "Амурская область", "Амурская обл."),
        ("Arkhangelsk Oblast", [], "Архангельская область", "Архангельская обл."),
        ("Astrakhan Oblast", [], "Астраханская область", "Астраханская обл."),
        ("Belgorod Oblast", [], "Белгородская область", "Белгородская обл."),
        ("Bryansk Oblast", [], "Брянская область", "Брянская обл."),
        ("Chelyabinsk Oblast", [], "Челябинская область", "Челяб. обл."),
        ("Irkutsk Oblast", [], "Иркутская область", "Иркутская обл."),
        ("Ivanovo Oblast", [], "Ивановская область", "Ивановская обл."),
        ("Kaliningrad Oblast", [], "Калининградская область", "Калинингр. обл."),
        ("Kaluga Oblast", [], "Калужская область", "Калужская обл."),
        ("Kemerovo Oblast", ["Kuzbass"], "Кемеровская область", "Кемеровская обл."),
        ("Kirov Oblast", [], "Кировская область", "Кировская обл."),
        ("Kostroma Oblast", [], "Костромская область", "Костромская обл."),
        ("Kurgan Oblast", [], "Курганская область", "Курганская обл."),
        ("Kursk Oblast", [], "Курская область", "Курская обл."),
        ("Leningrad Oblast", [], "Ленинградская область", "Ленингр. обл."),
        ("Lipetsk Oblast", [], "Липецкая область", "Липецкая обл."),
        ("Magadan Oblast", [], "Магаданская область", "Магаданская обл."),
        ("Moscow Oblast", ["Moskovskaya Oblast"], "Московская область", "Моск. обл."),
        ("Murmansk Oblast", [], "Мурманская область", "Мурманская обл."),
        ("Nizhny Novgorod Oblast", [], "Нижегородская область", "Нижегор. обл."),
        ("Novgorod Oblast", [], "Новгородская область", "Новгородская обл."),
        ("Novosibirsk Oblast", [], "Новосибирская область", "Новосиб. обл."),
        ("Omsk Oblast", [], "Омская область", "Омская обл."),
        ("Orenburg Oblast", [], "Оренбургская область", "Оренбургская обл."),
        ("Oryol Oblast", ["Orel Oblast"], "Орловская область", "Орловская обл."),
        ("Penza Oblast", [], "Пензенская область", "Пензенская обл."),
        ("Pskov Oblast", [], "Псковская область", "Псковская обл."),
        ("Rostov Oblast", [], "Ростовская область", "Ростовская обл."),
        ("Ryazan Oblast", [], "Рязанская область", "Рязанская обл."),
        ("Sakhalin Oblast", [], "Сахалинская область", "Сахалинская обл."),
        ("Samara Oblast", [], "Самарская область", "Самарская обл."),
        ("Saratov Oblast", [], "Саратовская область", "Саратовская обл."),
        ("Smolensk Oblast", [], "Смоленская область", "Смоленская обл."),
        ("Sverdlovsk Oblast", [], "Свердловская область", "Свердл. обл."),
        ("Tambov Oblast", [], "Тамбовская область", "Тамбовская обл."),
        ("Tomsk Oblast", [], "Томская область", "Томская обл."),
        ("Tula Oblast", [], "Тульская область", "Тульская обл."),
        ("Tver Oblast", [], "Тверская область", "Тверская обл."),
        ("Tyumen Oblast", [], "Тюменская область", "Тюменская обл."),
        ("Ulyanovsk Oblast", [], "Ульяновская область", "Ульяновская обл."),
        ("Vladimir Oblast", [], "Владимирская область", "Владимирская обл."),
        ("Volgograd Oblast", [], "Волгоградская область", "Волгоградская обл."),
        ("Vologda Oblast", [], "Вологодская область", "Вологодская обл."),
        ("Voronezh Oblast", [], "Воронежская область", "Воронежская обл."),
        ("Yaroslavl Oblast", [], "Ярославская область", "Ярославская обл."),
        // Krais
        ("Altai Krai", [], "Алтайский край", "Алтайский край"),
        ("Kamchatka Krai", [], "Камчатский край", "Камчатский край"),
        ("Khabarovsk Krai", [], "Хабаровский край", "Хабаровский край"),
        ("Krasnodar Krai", ["Krasnodarskiy Kray"], "Краснодарский край", "Краснодар. край"),
        ("Krasnoyarsk Krai", [], "Красноярский край", "Краснояр. край"),
        ("Perm Krai", [], "Пермский край", "Пермский край"),
        ("Primorsky Krai", ["Primorye"], "Приморский край", "Приморский край"),
        ("Stavropol Krai", [], "Ставропольский край", "Ставроп. край"),
        ("Zabaykalsky Krai", ["Transbaikal Krai"], "Забайкальский край", "Забайкальский край"),
        // Republics
        ("Adygea", ["Republic of Adygea"], "Республика Адыгея", "Адыгея"),
        ("Altai Republic", [], "Республика Алтай", "Респ. Алтай"),
        ("Bashkortostan", ["Republic of Bashkortostan"], "Республика Башкортостан", "Башкортостан"),
        ("Buryatia", ["Republic of Buryatia"], "Республика Бурятия", "Бурятия"),
        ("Chechnya", ["Chechen Republic"], "Чеченская Республика", "Чечня"),
        ("Chuvashia", ["Chuvash Republic"], "Чувашская Республика", "Чувашия"),
        ("Crimea", ["Republic of Crimea"], "Республика Крым", "Крым"),
        ("Dagestan", ["Republic of Dagestan"], "Республика Дагестан", "Дагестан"),
        ("Ingushetia", ["Republic of Ingushetia"], "Республика Ингушетия", "Ингушетия"),
        ("Kabardino-Balkaria", ["Kabardino-Balkarian Republic"], "Кабардино-Балкарская Республика", "Кабардино-Балкария"),
        ("Kalmykia", ["Republic of Kalmykia"], "Республика Калмыкия", "Калмыкия"),
        ("Karachay-Cherkessia", ["Karachay-Cherkess Republic"], "Карачаево-Черкесская Республика", "Карачаево-Черкесия"),
        ("Karelia", ["Republic of Karelia"], "Республика Карелия", "Карелия"),
        ("Khakassia", ["Republic of Khakassia"], "Республика Хакасия", "Хакасия"),
        ("Komi", ["Komi Republic"], "Республика Коми", "Коми"),
        ("Mari El", ["Mari El Republic"], "Республика Марий Эл", "Марий Эл"),
        ("Mordovia", ["Republic of Mordovia"], "Республика Мордовия", "Мордовия"),
        ("North Ossetia", ["North Ossetia-Alania", "Republic of North Ossetia-Alania"], "Республика Северная Осетия — Алания", "Сев. Осетия"),
        ("Sakha", ["Sakha Republic", "Yakutia", "Sakha (Yakutia)"], "Республика Саха (Якутия)", "Якутия"),
        ("Tatarstan", ["Republic of Tatarstan"], "Республика Татарстан", "Татарстан"),
        ("Tuva", ["Tyva Republic", "Republic of Tuva"], "Республика Тыва", "Тыва"),
        ("Udmurtia", ["Udmurt Republic"], "Удмуртская Республика", "Удмуртия"),
        // Autonomous okrugs + oblast
        ("Chukotka", ["Chukotka Autonomous Okrug"], "Чукотский автономный округ", "Чукотка"),
        ("Khanty-Mansi Autonomous Okrug", ["Khanty-Mansiysk Autonomous Okrug", "Yugra"], "Ханты-Мансийский автономный округ — Югра", "ХМАО"),
        ("Nenets Autonomous Okrug", [], "Ненецкий автономный округ", "НАО"),
        ("Yamalo-Nenets Autonomous Okrug", ["Yamal-Nenets Autonomous Okrug"], "Ямало-Ненецкий автономный округ", "ЯНАО"),
        ("Jewish Autonomous Oblast", [], "Еврейская автономная область", "Еврейская АО"),
    ]

    /// normalize(recognition string) → entry. Built once; every EN name,
    /// alias, RU full and RU short form resolves to the same entry so a
    /// string stored in EITHER language re-renders in the current one.
    private static let index: [String: Entry] = {
        var map: [String: Entry] = [:]
        for s in subjects {
            let entry = Entry(en: s.en, ruShort: s.ruShort)
            for key in [s.en, s.ruFull, s.ruShort] + s.aliases {
                map[normalize(key)] = entry
            }
        }
        return map
    }()

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
    }
}
