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
    static func atlasTotalDistanceSuffix(_ lang: LanguageManager.Language) -> String {
        tr(lang, "atlasTotalDistanceSuffix", ru: "всего", en: "total")
    }
}
