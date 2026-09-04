import Foundation

/// How a language string reaches the screen.
///
/// Russian and English stay written inline in `AppStrings`, next to the doc
/// comment that explains why the copy says what it says — they are the two
/// languages the product is designed in, and losing that context to a lookup
/// table would cost more than it saves. The five languages added in 0.6.1
/// (de/es/fr/it/pl) live in `Translations*.swift` tables keyed by the same
/// function name, so adding a language means adding one file rather than
/// touching 800 functions.
///
/// A key missing from a table falls back to **English**, never to the raw key:
/// a half-translated screen reads as a mixed-language app, which is survivable,
/// while `"profileRowAbout"` on a button is not.
extension AppStrings {
    @inline(__always)
    static func tr(
        _ lang: LanguageManager.Language,
        _ key: String,
        ru: String,
        en: String
    ) -> String {
        switch lang {
        case .ru: return ru
        case .en: return en
        case .de: return Translations.de[key] ?? en
        case .es: return Translations.es[key] ?? en
        case .fr: return Translations.fr[key] ?? en
        case .it: return Translations.it[key] ?? en
        case .pl: return Translations.pl[key] ?? en
        case .id: return Translations.id[key] ?? en
        case .tr: return Translations.tr[key] ?? en
        case .fil: return Translations.fil[key] ?? en
        case .uk: return Translations.uk[key] ?? en
        case .kk: return Translations.kk[key] ?? en
        case .pt: return Translations.pt[key] ?? en
        }
    }

    // MARK: - Plurals

    /// CLDR plural categories, cut down to the three shapes our seven
    /// languages actually need.
    enum PluralForm {
        case one, few, many
    }

    /// Which form a count takes. The two Slavic languages disagree in exactly
    /// one place worth remembering: 21 is «21 поездка» (one) in Russian but
    /// „21 tras" (many) in Polish, because Polish keys `one` off n == 1 alone.
    static func pluralForm(_ n: Int, _ lang: LanguageManager.Language) -> PluralForm {
        let mod10 = abs(n) % 10
        let mod100 = abs(n) % 100
        switch lang {
        case .ru, .uk:
            // East Slavic: 21 and 101 take the singular, 11 does not.
            if mod10 == 1 && mod100 != 11 { return .one }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) { return .few }
            return .many
        case .pl:
            // Polish keys `one` off n == 1 alone, so 21 is «21 tras», not
            // «21 trasa». This is the one place it parts with Russian.
            if abs(n) == 1 { return .one }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) { return .few }
            return .many
        case .fr, .fil, .pt:
            // These count zero with the singular: «0 trajet», not «0 trajets».
            return abs(n) <= 1 ? .one : .many
        case .id:
            // Indonesian has no plural inflection at all — one form covers
            // every count. Both arms of `plural` carry the same word, and
            // this branch keeps the caller from having to know that.
            return .many
        case .en, .de, .es, .it, .tr, .kk:
            return abs(n) == 1 ? .one : .many
        }
    }

    /// Picks a form. `few` is only ever read for ru/pl, so the two-form
    /// languages can leave it out.
    static func plural(
        _ lang: LanguageManager.Language,
        _ n: Int,
        one: String,
        few: String? = nil,
        many: String
    ) -> String {
        switch pluralForm(n, lang) {
        case .one:  return one
        case .few:  return few ?? many
        case .many: return many
        }
    }

    // MARK: - Counted nouns

    /// The nouns that get counted all over the app, in one place — a screen
    /// that says «3 поездки» and another that says «3 поездок» is the kind of
    /// thing nobody reports and everybody notices.
    static func nounTrips(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "поездка", few: "поездки", many: "поездок")
        case .en: return plural(lang, n, one: "trip", many: "trips")
        case .de: return plural(lang, n, one: "Fahrt", many: "Fahrten")
        case .es: return plural(lang, n, one: "viaje", many: "viajes")
        case .fr: return plural(lang, n, one: "trajet", many: "trajets")
        case .it: return plural(lang, n, one: "viaggio", many: "viaggi")
        case .pl: return plural(lang, n, one: "trasa", few: "trasy", many: "tras")
        case .id: return "perjalanan"
        case .tr: return "gezi"
        case .fil: return plural(lang, n, one: "biyahe", many: "biyahe")
        case .uk: return plural(lang, n, one: "поїздка", few: "поїздки", many: "поїздок")
        case .kk: return "сапар"
        case .pt: return plural(lang, n, one: "viagem", many: "viagens")
        }
    }

    static func nounPhotos(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "фото", few: "фото", many: "фото")
        case .en: return plural(lang, n, one: "photo", many: "photos")
        case .de: return plural(lang, n, one: "Foto", many: "Fotos")
        case .es: return plural(lang, n, one: "foto", many: "fotos")
        case .fr: return plural(lang, n, one: "photo", many: "photos")
        case .it: return plural(lang, n, one: "foto", many: "foto")
        case .pl: return plural(lang, n, one: "zdjęcie", few: "zdjęcia", many: "zdjęć")
        case .id: return "foto"
        case .tr: return "fotoğraf"
        case .fil: return "larawan"
        case .uk: return plural(lang, n, one: "фото", few: "фото", many: "фото")
        case .kk: return "фото"
        case .pt: return plural(lang, n, one: "foto", many: "fotos")
        }
    }

    static func nounDays(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "день", few: "дня", many: "дней")
        case .en: return plural(lang, n, one: "day", many: "days")
        case .de: return plural(lang, n, one: "Tag", many: "Tage")
        case .es: return plural(lang, n, one: "día", many: "días")
        case .fr: return plural(lang, n, one: "jour", many: "jours")
        case .it: return plural(lang, n, one: "giorno", many: "giorni")
        case .pl: return plural(lang, n, one: "dzień", few: "dni", many: "dni")
        case .id: return "hari"
        case .tr: return "gün"
        case .fil: return "araw"
        case .uk: return plural(lang, n, one: "день", few: "дні", many: "днів")
        case .kk: return "күн"
        case .pt: return plural(lang, n, one: "dia", many: "dias")
        }
    }

    /// «год / года / лет» — для стажа машины в гараже и для срока владения
    /// в архиве («2012–2023 · 11 лет»).
    ///
    /// Заведено в 0.6.4, потому что на макетах паспорта срок был написан
    /// СЛОВОМ («восемь лет»), а механизма для чисел словами в проекте нет
    /// вовсе — ни `spellOut`, ни таблицы. Цифра плюс это существительное —
    /// единственный способ, который переживает тринадцать языков.
    ///
    /// Русский тут особенно коварен: «лет» — это супплетивная форма от другого
    /// корня, и «5 годов» не сказал бы никто.
    static func nounYears(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "год", few: "года", many: "лет")
        case .en: return plural(lang, n, one: "year", many: "years")
        case .de: return plural(lang, n, one: "Jahr", many: "Jahre")
        case .es: return plural(lang, n, one: "año", many: "años")
        case .fr: return plural(lang, n, one: "an", many: "ans")
        case .it: return plural(lang, n, one: "anno", many: "anni")
        case .pl: return plural(lang, n, one: "rok", few: "lata", many: "lat")
        case .id: return "tahun"
        case .tr: return "yıl"
        case .fil: return "taon"
        case .uk: return plural(lang, n, one: "рік", few: "роки", many: "років")
        case .kk: return "жыл"
        case .pt: return plural(lang, n, one: "ano", many: "anos")
        }
    }

    static func nounHours(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "час", few: "часа", many: "часов")
        case .en: return plural(lang, n, one: "hour", many: "hours")
        case .de: return plural(lang, n, one: "Stunde", many: "Stunden")
        case .es: return plural(lang, n, one: "hora", many: "horas")
        case .fr: return plural(lang, n, one: "heure", many: "heures")
        case .it: return plural(lang, n, one: "ora", many: "ore")
        case .pl: return plural(lang, n, one: "godzina", few: "godziny", many: "godzin")
        case .id: return "jam"
        case .tr: return "saat"
        case .fil: return "oras"
        case .uk: return plural(lang, n, one: "година", few: "години", many: "годин")
        case .kk: return "сағат"
        case .pt: return plural(lang, n, one: "hora", many: "horas")
        }
    }

    static func nounMinutes(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "минута", few: "минуты", many: "минут")
        case .en: return plural(lang, n, one: "minute", many: "minutes")
        case .de: return plural(lang, n, one: "Minute", many: "Minuten")
        case .es: return plural(lang, n, one: "minuto", many: "minutos")
        case .fr: return plural(lang, n, one: "minute", many: "minutes")
        case .it: return plural(lang, n, one: "minuto", many: "minuti")
        case .pl: return plural(lang, n, one: "minuta", few: "minuty", many: "minut")
        case .id: return "menit"
        case .tr: return "dakika"
        case .fil: return "minuto"
        case .uk: return plural(lang, n, one: "хвилина", few: "хвилини", many: "хвилин")
        case .kk: return "минут"
        case .pt: return plural(lang, n, one: "minuto", many: "minutos")
        }
    }

    static func nounPeople(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "человек", few: "человека", many: "человек")
        case .en: return plural(lang, n, one: "person", many: "people")
        case .de: return plural(lang, n, one: "Person", many: "Personen")
        case .es: return plural(lang, n, one: "persona", many: "personas")
        case .fr: return plural(lang, n, one: "personne", many: "personnes")
        case .it: return plural(lang, n, one: "persona", many: "persone")
        case .pl: return plural(lang, n, one: "osoba", few: "osoby", many: "osób")
        case .id: return "orang"
        case .tr: return "kişi"
        case .fil: return "tao"
        case .uk: return plural(lang, n, one: "людина", few: "людини", many: "людей")
        case .kk: return "адам"
        case .pt: return plural(lang, n, one: "pessoa", many: "pessoas")
        }
    }

    static func nounCities(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "город", few: "города", many: "городов")
        case .en: return plural(lang, n, one: "city", many: "cities")
        case .de: return plural(lang, n, one: "Stadt", many: "Städte")
        case .es: return plural(lang, n, one: "ciudad", many: "ciudades")
        case .fr: return plural(lang, n, one: "ville", many: "villes")
        case .it: return plural(lang, n, one: "città", many: "città")
        case .pl: return plural(lang, n, one: "miasto", few: "miasta", many: "miast")
        case .id: return "kota"
        case .tr: return "şehir"
        case .fil: return "lungsod"
        case .uk: return plural(lang, n, one: "місто", few: "міста", many: "міст")
        case .kk: return "қала"
        case .pt: return plural(lang, n, one: "cidade", many: "cidades")
        }
    }

    static func nounRegions(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "регион", few: "региона", many: "регионов")
        case .en: return plural(lang, n, one: "region", many: "regions")
        case .de: return plural(lang, n, one: "Region", many: "Regionen")
        case .es: return plural(lang, n, one: "región", many: "regiones")
        case .fr: return plural(lang, n, one: "région", many: "régions")
        case .it: return plural(lang, n, one: "regione", many: "regioni")
        case .pl: return plural(lang, n, one: "region", few: "regiony", many: "regionów")
        case .id: return "wilayah"
        case .tr: return "bölge"
        case .fil: return "rehiyon"
        case .uk: return plural(lang, n, one: "регіон", few: "регіони", many: "регіонів")
        case .kk: return "аймақ"
        case .pt: return plural(lang, n, one: "região", many: "regiões")
        }
    }

    /// «раз» — how many times something happened.
    static func nounTimes(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "раз", few: "раза", many: "раз")
        case .en: return plural(lang, n, one: "time", many: "times")
        case .de: return plural(lang, n, one: "Mal", many: "Mal")
        case .es: return plural(lang, n, one: "vez", many: "veces")
        case .fr: return plural(lang, n, one: "fois", many: "fois")
        case .it: return plural(lang, n, one: "volta", many: "volte")
        case .pl: return plural(lang, n, one: "raz", few: "razy", many: "razy")
        case .id: return "kali"
        case .tr: return "kez"
        case .fil: return "beses"
        case .uk: return plural(lang, n, one: "раз", few: "рази", many: "разів")
        case .kk: return "рет"
        case .pt: return plural(lang, n, one: "vez", many: "vezes")
        }
    }
}

/// Date formatters that exist once per language.
///
/// Before 0.6.1 every screen kept its own `(ru:, en:)` tuple of hand-built
/// `DateFormatter`s and picked between them with a ternary — which is why
/// adding five languages meant touching a dozen files. Ask for a table here
/// instead: a new language needs no code at the call site at all.
///
/// `DateFormatter` is expensive to construct and these are hit once per feed
/// card, so callers keep the table in a `static let`, never build one in `body`.
enum LocalizedDateFormatter {
    /// A FIXED field order in every language — use when the design pins the
    /// layout («14 апр 2026, 10:40» must line up across a column).
    static func patterns(_ pattern: String) -> [LanguageManager.Language: DateFormatter] {
        table { $0.dateFormat = pattern }
    }

    /// Each language's OWN field order, from a template like `"dMMMM"` —
    /// «14 апреля», "April 14", „14. April". Use when the line is prose.
    static func templates(_ template: String) -> [LanguageManager.Language: DateFormatter] {
        table { $0.setLocalizedDateFormatFromTemplate(template) }
    }

    private static func table(
        _ configure: (DateFormatter) -> Void
    ) -> [LanguageManager.Language: DateFormatter] {
        var map: [LanguageManager.Language: DateFormatter] = [:]
        for lang in LanguageManager.Language.allCases {
            let f = DateFormatter()
            f.locale = lang.locale
            configure(f)
            map[lang] = f
        }
        return map
    }
}

/// Case conversion that asks the language.
///
/// Turkish is why this exists. `"i".uppercased()` gives `I`, but Turkish
/// wants `İ` — and `"I".lowercased()` gives `i` where Turkish wants `ı`. Every
/// section header in this app is upper-cased in code, so without a locale
/// «BURADAKİ GEZİLER» ships as «BURADAKI GEZILER», which reads to a Turkish
/// speaker roughly the way «пОездка» reads to us.
///
/// SwiftUI's own `.textCase(.uppercase)` takes its locale from the
/// environment, which `TripTrackApp` sets from the chosen language — so those
/// call sites need nothing. These two are for the explicit ones.
extension String {
    func uppercased(_ lang: LanguageManager.Language) -> String {
        uppercased(with: lang.locale)
    }

    func lowercased(_ lang: LanguageManager.Language) -> String {
        lowercased(with: lang.locale)
    }
}
