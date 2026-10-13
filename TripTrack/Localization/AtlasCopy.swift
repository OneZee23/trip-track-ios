import Foundation

/// Copy for the 0.8.1 Atlas. Distances and counted nouns remain with Measure
/// and the shared CLDR helpers; these labels contain no measurement units.
extension AppStrings {
    static func atlasExplored(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasExplored", ru: "Исследовано", en: "Explored")
    }

    static func atlasNewRoads(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasNewRoads", ru: "новых дорог", en: "new roads")
    }

    static func atlasTotalTravelled(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTotalTravelled", ru: "проехано всего", en: "total travelled")
    }

    static func atlasCityOrRegion(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasCityOrRegion", ru: "Город или регион", en: "City or region")
    }

    static func atlasMapStyle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasMapStyle", ru: "Вид карты", en: "Map appearance")
    }

    static func atlasHowWeCount(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasHowWeCount", ru: "Как считаем", en: "How we count")
    }

    static func atlasNoTripsInPeriod(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasNoTripsInPeriod", ru: "В этом периоде поездок нет", en: "No trips in this period")
    }

    static func atlasResetPeriod(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasResetPeriod", ru: "Всё время", en: "All time")
    }

    static func atlasSettings(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasSettings", ru: "Настройки атласа", en: "Atlas settings")
    }

    static func atlasCities(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasCities", ru: "Города", en: "Cities")
    }

    static func atlasCountries(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasCountries", ru: "Страны", en: "Countries")
    }

    static func atlasSearchEmpty(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasSearchEmpty", ru: "Ничего не нашли", en: "No results")
    }

    static func atlasSearchHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasSearchHint", ru: "Город или регион", en: "City or region")
    }

    static func atlasAllTrips(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasAllTrips", ru: "Все поездки", en: "All trips")
    }

    static func atlasMyLocation(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasMyLocation", ru: "Моё местоположение", en: "My location")
    }

    static func atlasLocationUnavailable(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasLocationUnavailable", ru: "Местоположение пока недоступно", en: "Location is not available yet")
    }

    static func atlasShowFog(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasShowFog", ru: "Туман", en: "Fog")
    }

    static func atlasShowPhotos(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasShowPhotos", ru: "Фото из поездок", en: "Trip photos")
    }

    static func atlasStandardMap(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasStandardMap", ru: "Карта", en: "Map")
    }

    static func atlasSatelliteMap(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasSatelliteMap", ru: "Спутник", en: "Satellite")
    }

    static func atlasPeriod(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasPeriod", ru: "Период", en: "Period")
    }

    static func atlasAllTime(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasAllTime", ru: "Всё время", en: "All time")
    }

    static func atlasThisYear(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasThisYear", ru: "Этот год", en: "This year")
    }

    static func atlasThisMonth(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasThisMonth", ru: "Этот месяц", en: "This month")
    }

    static func atlasLast30Days(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasLast30Days", ru: "Последние 30 дней", en: "Last 30 days")
    }

    static func atlasCustomPeriod(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasCustomPeriod", ru: "Свой период", en: "Custom period")
    }

    static func atlasFrom(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasFrom", ru: "С", en: "From")
    }

    static func atlasTo(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTo", ru: "По", en: "To")
    }

    static func atlasShow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasShow", ru: "Показать", en: "Show")
    }

    static func atlasCityLabels(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasCityLabels", ru: "Подписи городов", en: "City labels")
    }

    static func atlasNight(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasNight", ru: "Ночь", en: "Night")
    }

    static func atlasSearchEmptyBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasSearchEmptyBody", ru: "Проверь написание. Ищем по городам и регионам атласа.", en: "Check the spelling. Search covers cities and regions in the atlas.")
    }

    static func atlasPeriodEmptyBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasPeriodEmptyBody", ru: "Выбери другой период или вернись ко всему времени.", en: "Choose another period or return to all time.")
    }

    static func atlasRoadsExplanation(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasRoadsExplanation", ru: "Дорога засчитывается один раз, в первую поездку по ней. Повторы идут в «проехано всего».", en: "A road counts once, on your first trip along it. Repeat trips add to the total travelled.")
    }

    static func atlasTripsExplanation(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTripsExplanation", ru: "Сумма расстояний всех поездок, которые участвуют в атласе. Повторные проезды тоже учитываются.", en: "The total distance of all trips included in your atlas. Repeat journeys count too.")
    }

    static func atlasPeriodHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasPeriodHint", ru: "Показываем дороги, города и поездки за выбранный период.", en: "Showing roads, cities and trips from the selected period.")
    }

    static func atlasUniqueRoads(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasUniqueRoads", ru: "уникальных дорог", en: "unique roads")
    }

    static func atlasFogStyle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasFogStyle", ru: "Туман", en: "Fog")
    }

    static func atlasNightStyle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasNightStyle", ru: "Ночь", en: "Night")
    }
    /// Третий стиль карты (0.8.2): открытое квантовано клетками.
    static func atlasCellsStyle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasCellsStyle", ru: "Клетки", en: "Cells")
    }

    static func atlasShowCityLabels(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasShowCityLabels", ru: "Подписи городов", en: "City labels")
    }

    static func atlasPeriodRoadsExplanation(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasPeriodRoadsExplanation", ru: "В выбранном периоде считаем уникальные дороги его поездок. Они могли встречаться в более ранних поездках — это не обязательно новые открытия за всю историю.", en: "For a selected period, we count the unique roads in its trips. You may have driven them before, so they are not necessarily first-ever discoveries.")
    }
    static func atlasNotVisited(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasNotVisited", ru: "Ещё не открыто", en: "Not explored yet")
    }
    /// Единственное действие карточки места — словами, а не стрелкой.
    static func atlasOpenPlace(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasOpenPlace", ru: "Открыть место", en: "Open place")
    }

    /// Подпись второй колонки тройки: одно слово.
    ///
    /// Своя, а не `atlasTotalTravelled` («проехано всего»): в колонке шириной
    /// в треть карточки та переносится на две строки и ломает ряд —
    /// в макете там ровно «ВСЕГО».
    static func atlasTotalShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTotalShort", ru: "всего", en: "total")
    }

    /// Заголовок секции регионов в списке «Атласа» (спека §3.5).
    static func atlasRegions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasRegions", ru: "Регионы", en: "Regions")
    }

    /// «4 из 28 городов» — сколько городов региона открыто из всех его.
    ///
    /// Подстановки токенами, а не интерполяцией в литерал: `tr` для
    /// остальных одиннадцати языков читает ГОТОВУЮ строку из таблиц и числа
    /// в момент вызова получить не может (CLAUDE.md).
    static func atlasCitiesOutOf(_ lang: LanguageManager.Language,
                                 visited: Int, total: Int) -> String {
        tr(lang, "atlasCitiesOutOf",
           ru: "{visited} из {total} {cities}", en: "{visited} of {total} {cities}")
            .replacingOccurrences(of: "{visited}", with: formattedCount(visited, lang: lang))
            .replacingOccurrences(of: "{total}", with: formattedCount(total, lang: lang))
            .replacingOccurrences(of: "{cities}", with: nounCities(lang, total))
    }

    /// Пунктирный чип закрытых городов: «ещё 26 в тумане».
    static func atlasMoreInFog(_ lang: LanguageManager.Language, count: Int) -> String {
        tr(lang, "atlasMoreInFog", ru: "ещё {count} в тумане", en: "{count} more in the fog")
            .replacingOccurrences(of: "{count}", with: formattedCount(count, lang: lang))
    }

    /// Заголовок секции поездок в подсостоянии региона (состояние 16).
    ///
    /// Своя, а не `AppStrings.mapTripsSection`: та с 0.7.0 напечатана
    /// ПРОПИСНЫМИ прямо в таблицах — наследство HTML-макета, от которого
    /// «Атлас» и «Места» отучили 26 сентября («мелкие серые прописные и были
    /// тем, чем эти вкладки отличались от соседних»). Чинить регистр в
    /// тринадцати таблицах ради одного места показа значит трогать строку,
    /// которую читает ещё и прежняя панель; проще завести свою в нужном
    /// регистре, чем разойтись с соседней «Города» на одном экране.
    static func atlasTripsHere(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTripsHere", ru: "Поездки здесь", en: "Trips here")
    }

    /// Строка внизу списка: сколько поездок участвует в атласе.
    static func atlasTripsInAtlas(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTripsInAtlas", ru: "Поездки в атласе", en: "Trips in the atlas")
    }

    static func atlasTotalDistanceSuffix(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTotalDistanceSuffix", ru: "всего", en: "total")
    }

    // MARK: - Дом на карте, нет сети, геопозиция (0.8.2)

    /// Имя карточки дома на «Атласе» (состояние 26).
    static func atlasHome(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasHome", ru: "Дом", en: "Home")
    }

    /// «61 поездка отсюда» — строка смысла в карточке дома.
    ///
    /// Число со склонённым существительным собирается ОТДЕЛЬНО и приходит
    /// сюда готовым: порядок слов у «отсюда» в тринадцати языках свой, а
    /// склонение — общее (`nounTrips`).
    static func atlasTripsFromHome(_ lang: LanguageManager.Language, trips: String) -> String {
        tr(lang, "atlasTripsFromHome", ru: "{trips} отсюда", en: "{trips} from here")
            .replacingOccurrences(of: "{trips}", with: trips)
    }

    /// Действие в карточке дома: ведёт в настройку дома (S16).
    static func atlasHomeConfigure(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasHomeConfigure", ru: "Настроить", en: "Set up")
    }

    /// Строка над сводкой, когда сети нет (состояние 24).
    static func atlasOffline(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasOffline", ru: "Нет сети", en: "No network")
    }

    /// Заголовок диалога у перечёркнутой кнопки «где я» (состояние 13).
    static func atlasLocationDeniedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasLocationDeniedTitle",
           ru: "Геопозиция недоступна", en: "Location unavailable")
    }

    /// Одна фраза под ним — и она про то, ЧТО изменится, а не про запрет.
    static func atlasLocationDeniedBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasLocationDeniedBody",
           ru: "Разрешите доступ в Настройках, чтобы атлас следовал за вами",
           en: "Allow access in Settings so the atlas can follow you")
    }
}
