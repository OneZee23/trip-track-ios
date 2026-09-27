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

    /// CLDR plural categories, cut down to the shapes our thirteen languages
    /// actually need.
    enum PluralForm {
        case one, few, many
        /// CLDR `other` при ВИДИМОЙ дробной части: «1,5 мили», «2,0 фута».
        ///
        /// Отдельным случаем, а не «сойдёт за `few`», потому что совпадение
        /// форм языко-зависимо. В русском при дробном числительном стоит
        /// родительный падеж единственного числа, и он у наших слов совпал с
        /// формой для двух-четырёх («2 фута» / «1,5 фута»). В украинском не
        /// совпал: два-чотири берут називний множини («2 фути»), а дробное —
        /// той же родительный однини («1,5 фута»). Категория — про число,
        /// слово — про язык, и решает его тот, кто пишет слова.
        case fraction
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

    /// Какую форму берёт УЖЕ ПОКАЗАННОЕ число — то есть число вместе с теми
    /// десятыми, которые человек видит на экране.
    ///
    /// CLDR смотрит не на значение, а на ЗАПИСЬ: у «2,0» есть видимая дробная
    /// часть, и правило `one` (`v = 0 and i % 10 = 1`) до неё не достаёт —
    /// категория выходит `other`, и по-русски это «2,0 мили», а не «2,0
    /// миля». Поэтому решает `fractionDigits`, а не остаток от деления: у
    /// стиля «всегда одна десятая» дробная часть видна даже когда она ноль.
    ///
    /// Дробную часть язык не спрашивается: она даёт `other` во всех тринадцати.
    /// А какое слово этой категории отвечает, знает тот, кто пишет слова
    /// (см. `plural(form:…)`). Целое число, наоборот, без языка не разобрать:
    /// 21 — это «21 миля» по-русски и «21 mil» по-польски.
    static func pluralForm(
        shown value: Double,
        fractionDigits: Int,
        _ lang: LanguageManager.Language
    ) -> PluralForm {
        fractionDigits > 0 ? .fraction : pluralForm(Int(value.rounded()), lang)
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
        plural(form: pluralForm(n, lang), one: one, few: few, many: many)
    }

    /// Тот же выбор, когда форма уже посчитана — например по показанному
    /// числу с десятыми (`pluralForm(shown:fractionDigits:)`).
    ///
    /// `fraction` не назван — берётся `few`: в русском формы совпали, а языки,
    /// у которых не совпали, обязаны назвать её сами.
    static func plural(
        form: PluralForm,
        one: String,
        few: String? = nil,
        many: String,
        fraction: String? = nil
    ) -> String {
        switch form {
        case .one:      return one
        case .few:      return few ?? many
        case .many:     return many
        case .fraction: return fraction ?? few ?? many
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

    /// «3 черновика» — в заголовке диалога удаления нескольких.
    ///
    /// Счётным существительным, а не stringsdict: у приложения своя таблица
    /// форм CLDR (`plural`), и у русского с украинским три формы, у польского
    /// свои, а у индонезийского множественного нет вовсе. Спека называет
    /// stringsdict, но его в проекте не существует; смысл — один и тот же.
    static func nounDrafts(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "черновик", few: "черновика", many: "черновиков")
        case .en: return plural(lang, n, one: "draft", many: "drafts")
        case .de: return plural(lang, n, one: "Entwurf", many: "Entwürfe")
        case .es: return plural(lang, n, one: "borrador", many: "borradores")
        case .fr: return plural(lang, n, one: "brouillon", many: "brouillons")
        case .it: return plural(lang, n, one: "bozza", many: "bozze")
        case .pl: return plural(lang, n, one: "szkic", few: "szkice", many: "szkiców")
        case .id: return "draf"
        case .tr: return "taslak"
        case .fil: return plural(lang, n, one: "draft", many: "draft")
        case .uk: return plural(lang, n, one: "чернетка", few: "чернетки", many: "чернеток")
        case .kk: return "жоба"
        case .pt: return plural(lang, n, one: "rascunho", many: "rascunhos")
        }
    }

    /// «3 машины» — счётчик под превью гаража.
    ///
    /// Слово родовое, а не «автомобиль»: в гараже бывают мотоцикл, скутер и
    /// велосипед, и «3 автомобиля» под ними было бы неправдой.
    static func nounVehicles(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "машина", few: "машины", many: "машин")
        case .en: return plural(lang, n, one: "vehicle", many: "vehicles")
        case .de: return plural(lang, n, one: "Fahrzeug", many: "Fahrzeuge")
        case .es: return plural(lang, n, one: "vehículo", many: "vehículos")
        case .fr: return plural(lang, n, one: "véhicule", many: "véhicules")
        case .it: return plural(lang, n, one: "veicolo", many: "veicoli")
        case .pl: return plural(lang, n, one: "pojazd", few: "pojazdy", many: "pojazdów")
        case .id: return "kendaraan"
        case .tr: return "araç"
        case .fil: return plural(lang, n, one: "sasakyan", many: "sasakyan")
        case .uk: return plural(lang, n, one: "машина", few: "машини", many: "машин")
        case .kk: return "көлік"
        case .pt: return plural(lang, n, one: "veículo", many: "veículos")
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

    /// «2 отметки» — счётчик отметок в строке плеча путешествия.
    ///
    /// Слово берётся то же, что у `checkpointsTitle` на экране поездки: одна и
    /// та же вещь, названная на двух экранах по-разному, читается как две.
    static func nounCheckpoints(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "отметка", few: "отметки", many: "отметок")
        case .en: return plural(lang, n, one: "checkpoint", many: "checkpoints")
        case .de: return plural(lang, n, one: "Markierung", many: "Markierungen")
        case .es: return plural(lang, n, one: "marca", many: "marcas")
        case .fr: return plural(lang, n, one: "repère", many: "repères")
        case .it: return plural(lang, n, one: "segnalibro", many: "segnalibri")
        case .pl: return plural(lang, n, one: "znacznik", few: "znaczniki", many: "znaczników")
        case .id: return "penanda"
        case .tr: return "işaret"
        case .fil: return "marka"
        case .uk: return plural(lang, n, one: "позначка", few: "позначки", many: "позначок")
        case .kk: return "белгі"
        case .pt: return plural(lang, n, one: "marcação", many: "marcações")
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

    /// «3 путешествия» — счётчик под хаб-карточкой «Путешествия» в чужом
    /// профиле (S7, 0.6.8). Тот же корень, что у `journeyWord` (путешествие /
    /// journey / Reise / …), но здесь — родовое склоняемое слово после числа,
    /// как у `nounTrips`/`nounDays`, а не заголовок с большой буквы.
    static func nounJourneys(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "путешествие", few: "путешествия", many: "путешествий")
        case .en: return plural(lang, n, one: "journey", many: "journeys")
        case .de: return plural(lang, n, one: "Reise", many: "Reisen")
        case .es: return plural(lang, n, one: "viaje", many: "viajes")
        case .fr: return plural(lang, n, one: "voyage", many: "voyages")
        case .it: return plural(lang, n, one: "viaggio", many: "viaggi")
        case .pl: return plural(lang, n, one: "podróż", few: "podróże", many: "podróży")
        case .id: return "perjalanan"
        case .tr: return "yolculuk"
        case .fil: return plural(lang, n, one: "paglalakbay", many: "paglalakbay")
        case .uk: return plural(lang, n, one: "подорож", few: "подорожі", many: "подорожей")
        case .kk: return "саяхат"
        case .pt: return plural(lang, n, one: "viagem", many: "viagens")
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

    /// «знак» — печать находки на «Атласе» (0.7.0).
    ///
    /// Слово одно на все три вида: на карте они и правда одно — тёмный
    /// медальон, — а чем именно он оказался, человек узнаёт, нажав.
    static func nounSeals(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "знак", few: "знака", many: "знаков")
        case .en: return plural(lang, n, one: "seal", many: "seals")
        case .de: return plural(lang, n, one: "Siegel", many: "Siegel")
        case .es: return plural(lang, n, one: "sello", many: "sellos")
        case .fr: return plural(lang, n, one: "sceau", many: "sceaux")
        case .it: return plural(lang, n, one: "sigillo", many: "sigilli")
        case .pl: return plural(lang, n, one: "pieczęć", few: "pieczęcie", many: "pieczęci")
        case .id: return "segel"
        case .tr: return "mühür"
        case .fil: return "selyo"
        case .uk: return plural(lang, n, one: "знак", few: "знаки", many: "знаків")
        case .kk: return "мөр"
        case .pt: return plural(lang, n, one: "selo", many: "selos")
        }
    }

    /// «загадка» — нерешённая подсказка на тумане (0.7.0).
    static func nounRiddles(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "загадка", few: "загадки", many: "загадок")
        case .en: return plural(lang, n, one: "riddle", many: "riddles")
        case .de: return plural(lang, n, one: "Rätsel", many: "Rätsel")
        case .es: return plural(lang, n, one: "enigma", many: "enigmas")
        case .fr: return plural(lang, n, one: "énigme", many: "énigmes")
        case .it: return plural(lang, n, one: "enigma", many: "enigmi")
        case .pl: return plural(lang, n, one: "zagadka", few: "zagadki", many: "zagadek")
        case .id: return "teka-teki"
        case .tr: return "bilmece"
        case .fil: return "palaisipan"
        case .uk: return plural(lang, n, one: "загадка", few: "загадки", many: "загадок")
        case .kk: return "жұмбақ"
        case .pt: return plural(lang, n, one: "enigma", many: "enigmas")
        }
    }

    /// «секрет» — авторская находка на треке (0.7.0).
    ///
    /// Отдельно от `nounSeals`: на карте все три вида — один медальон и одно
    /// слово «знак», а в строке «Открыто» человек читает, ЧТО именно нашлось,
    /// и «1 знак · 1 знак» не ответило бы ни на что.
    static func nounSecrets(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "секрет", few: "секрета", many: "секретов")
        case .en: return plural(lang, n, one: "secret", many: "secrets")
        case .de: return plural(lang, n, one: "Geheimnis", many: "Geheimnisse")
        case .es: return plural(lang, n, one: "secreto", many: "secretos")
        case .fr: return plural(lang, n, one: "secret", many: "secrets")
        case .it: return plural(lang, n, one: "segreto", many: "segreti")
        case .pl: return plural(lang, n, one: "sekret", few: "sekrety", many: "sekretów")
        case .id: return "rahasia"
        case .tr: return "sır"
        case .fil: return "lihim"
        case .uk: return plural(lang, n, one: "секрет", few: "секрети", many: "секретів")
        case .kk: return "құпия"
        case .pt: return plural(lang, n, one: "segredo", many: "segredos")
        }
    }

    /// «веха» — отметка собственной географии (0.7.0).
    static func nounMilestones(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "веха", few: "вехи", many: "вех")
        case .en: return plural(lang, n, one: "milestone", many: "milestones")
        case .de: return plural(lang, n, one: "Meilenstein", many: "Meilensteine")
        case .es: return plural(lang, n, one: "hito", many: "hitos")
        case .fr: return plural(lang, n, one: "jalon", many: "jalons")
        case .it: return plural(lang, n, one: "traguardo", many: "traguardi")
        case .pl: return plural(lang, n, one: "kamień milowy", few: "kamienie milowe",
                                many: "kamieni milowych")
        case .id: return "tonggak"
        case .tr: return "dönüm noktası"
        case .fil: return "milyahe"
        case .uk: return plural(lang, n, one: "віха", few: "віхи", many: "віх")
        case .kk: return "белес"
        case .pt: return plural(lang, n, one: "marco", many: "marcos")
        }
    }

    /// «проезд» — how many times a trip has gone past a place (0.6.8).
    static func nounPasses(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "проезд", few: "проезда", many: "проездов")
        case .en: return plural(lang, n, one: "pass", many: "passes")
        case .de: return plural(lang, n, one: "Durchfahrt", many: "Durchfahrten")
        case .es: return plural(lang, n, one: "paso", many: "pasos")
        case .fr: return plural(lang, n, one: "passage", many: "passages")
        case .it: return plural(lang, n, one: "passaggio", many: "passaggi")
        case .pl: return plural(lang, n, one: "przejazd", few: "przejazdy", many: "przejazdów")
        case .id: return "lintasan"
        case .tr: return "geçiş"
        case .fil: return "pagdaan"
        case .uk: return plural(lang, n, one: "проїзд", few: "проїзди", many: "проїздів")
        case .kk: return "өту"
        case .pt: return plural(lang, n, one: "passagem", many: "passagens")
        }
    }

    /// «место» — счётное, для шапки «24 места» (0.8.1).
    static func nounPlaces(_ lang: LanguageManager.Language, _ n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "место", few: "места", many: "мест")
        case .en: return plural(lang, n, one: "place", many: "places")
        case .de: return plural(lang, n, one: "Ort", many: "Orte")
        case .es: return plural(lang, n, one: "lugar", many: "lugares")
        case .fr: return plural(lang, n, one: "lieu", many: "lieux")
        case .it: return plural(lang, n, one: "luogo", many: "luoghi")
        case .pl: return plural(lang, n, one: "miejsce", few: "miejsca", many: "miejsc")
        case .id: return "tempat"
        case .tr: return "yer"
        case .fil: return "lugar"
        case .uk: return plural(lang, n, one: "місце", few: "місця", many: "місць")
        case .kk: return "орын"
        case .pt: return plural(lang, n, one: "lugar", many: "lugares")
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
