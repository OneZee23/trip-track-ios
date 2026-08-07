import SwiftUI

extension Badge {
    static let all: [Badge] = distance + exploration + special + streaks + exclusive

    // MARK: - Distance

    static let distance: [Badge] = [
        Badge(id: "first_trip", titleRu: "Первый путь", titleEn: "First Trip",
              descriptionRu: "Запишите первую поездку", descriptionEn: "Record your first trip",
              icon: "flag.fill", color: AppTheme.accent, category: .distance,
              rarity: .common,
              checkUnlocked: { $0.totalTrips >= 1 }),

        Badge(id: "road_regular", titleRu: "Завсегдатай", titleEn: "Road Regular",
              descriptionRu: "10 поездок", descriptionEn: "10 trips recorded",
              icon: "car.fill", color: AppTheme.blue, category: .distance,
              rarity: .common,
              checkUnlocked: { $0.totalTrips >= 10 }),

        Badge(id: "road_warrior", titleRu: "Дорожный воин", titleEn: "Road Warrior",
              descriptionRu: "50 поездок", descriptionEn: "50 trips recorded",
              icon: "shield.fill", color: AppTheme.purple, category: .distance,
              rarity: .rare,
              checkUnlocked: { $0.totalTrips >= 50 }),

        Badge(id: "trips_200", titleRu: "Бывалый", titleEn: "Seasoned",
              descriptionRu: "200 поездок", descriptionEn: "200 trips recorded",
              icon: "car.2.fill", color: AppTheme.blue, category: .distance,
              rarity: .rare,
              checkUnlocked: { $0.totalTrips >= 200 }),

        Badge(id: "trips_500", titleRu: "Заслуженный", titleEn: "Distinguished",
              descriptionRu: "500 поездок", descriptionEn: "500 trips recorded",
              icon: "rosette", color: AppTheme.accent, category: .distance,
              rarity: .epic,
              checkUnlocked: { $0.totalTrips >= 500 }),

        Badge(id: "legion", titleRu: "Легион", titleEn: "Legion",
              descriptionRu: "1 000 поездок записано", descriptionEn: "1,000 trips recorded",
              icon: "flag.2.crossed.fill", color: Color(red: 0.90, green: 0.65, blue: 0.10),
              category: .distance, rarity: .legendary,
              checkUnlocked: { $0.totalTrips >= 1000 }),

        Badge(id: "first_km", titleRu: "Первый километр", titleEn: "First Kilometer",
              descriptionRu: "1 км суммарно", descriptionEn: "1 km total distance",
              icon: "location.fill", color: AppTheme.green, category: .distance,
              rarity: .common,
              checkUnlocked: { $0.totalDistanceKm >= 1 }),

        Badge(id: "century", titleRu: "Сотня", titleEn: "Century",
              descriptionRu: "100 км суммарно", descriptionEn: "100 km total distance",
              icon: "speedometer", color: AppTheme.green, category: .distance,
              rarity: .common,
              checkUnlocked: { $0.totalDistanceKm >= 100 }),

        Badge(id: "thousand", titleRu: "Тысячник", titleEn: "Thousand",
              descriptionRu: "1 000 км суммарно", descriptionEn: "1,000 km total distance",
              icon: "bolt.fill", color: AppTheme.yellow, category: .distance,
              rarity: .uncommon,
              checkUnlocked: { $0.totalDistanceKm >= 1000 }),

        Badge(id: "ten_thousand", titleRu: "Десять тысяч", titleEn: "Ten Thousand",
              descriptionRu: "10 000 км суммарно", descriptionEn: "10,000 km total distance",
              icon: "bolt.circle.fill", color: AppTheme.accent, category: .distance,
              rarity: .rare,
              checkUnlocked: { $0.totalDistanceKm >= 10_000 }),

        Badge(id: "equator", titleRu: "Кругосветка", titleEn: "Around the World",
              descriptionRu: "40 075 км — длина экватора", descriptionEn: "40,075 km — the equator",
              icon: "globe.americas.fill", color: Color(red: 0.20, green: 0.55, blue: 0.90),
              category: .distance, rarity: .epic,
              checkUnlocked: { $0.totalDistanceKm >= 40_075 }),

        Badge(id: "km_100k", titleRu: "Сто тысяч", titleEn: "Hundred Thousand",
              descriptionRu: "100 000 км суммарно", descriptionEn: "100,000 km cumulative",
              icon: "gauge.high", color: AppTheme.accent, category: .distance,
              rarity: .epic,
              checkUnlocked: { $0.totalDistanceKm >= 100_000 }),

        Badge(id: "km_250k", titleRu: "Четверть миллиона", titleEn: "Quarter Million",
              descriptionRu: "250 000 км суммарно", descriptionEn: "250,000 km cumulative",
              icon: "speedometer", color: AppTheme.red, category: .distance,
              rarity: .legendary,
              checkUnlocked: { $0.totalDistanceKm >= 250_000 }),

        Badge(id: "half_million", titleRu: "Полмиллиона", titleEn: "Half a Million",
              descriptionRu: "500 000 км в сумме", descriptionEn: "500,000 km cumulative",
              icon: "infinity.circle.fill", color: Color(red: 0.60, green: 0.35, blue: 0.80),
              category: .distance, rarity: .legendary,
              checkUnlocked: { $0.totalDistanceKm >= 500_000 }),

        Badge(id: "million", titleRu: "Миллионник", titleEn: "Millionaire",
              descriptionRu: "1 000 000 км за всю жизнь", descriptionEn: "1,000,000 km in a lifetime",
              icon: "infinity", color: Color(red: 0.90, green: 0.65, blue: 0.10),
              category: .distance, rarity: .legendary,
              checkUnlocked: { $0.totalDistanceKm >= 1_000_000 }),

        Badge(id: "marathon_42", titleRu: "Марафонец", titleEn: "Marathon",
              descriptionRu: "42.2 км за одну поездку", descriptionEn: "42.2 km in a single trip",
              icon: "figure.run", color: AppTheme.teal, category: .distance,
              isRepeatable: true, rarity: .uncommon,
              checkUnlocked: { $0.hasSingleTripMarathon }),

        Badge(id: "marathon_100", titleRu: "Стоик", titleEn: "Stoic",
              descriptionRu: "Поездка длиннее 100 км", descriptionEn: "Single trip over 100 km",
              icon: "road.lanes", color: AppTheme.teal, category: .distance,
              isRepeatable: true, rarity: .uncommon,
              checkUnlocked: { $0.longestTripKm >= 100 }),

        Badge(id: "iron_butt", titleRu: "Железная задница", titleEn: "Iron Butt",
              descriptionRu: "500+ км за одну поездку", descriptionEn: "500+ km in a single trip",
              icon: "flame.fill", color: AppTheme.red, category: .distance,
              isHidden: true, isRepeatable: true, rarity: .epic,
              checkUnlocked: { $0.hasSingleTripIronButt }),

        Badge(id: "speed_demon", titleRu: "Спид-демон", titleEn: "Speed Demon",
              descriptionRu: "Макс. скорость > 120 км/ч", descriptionEn: "Max speed over 120 km/h",
              icon: "hare.fill", color: AppTheme.red, category: .distance,
              isRepeatable: true, rarity: .rare,
              checkUnlocked: { $0.maxSpeedKmh >= 120 }),

        Badge(id: "endurance", titleRu: "Выносливый", titleEn: "Endurance",
              descriptionRu: "10 часов за рулём", descriptionEn: "10 hours total driving",
              icon: "clock.fill", color: AppTheme.blue, category: .distance,
              rarity: .uncommon,
              checkUnlocked: { $0.totalDurationHours >= 10 }),

        Badge(id: "hours_50", titleRu: "Полста часов", titleEn: "Fifty Hours",
              descriptionRu: "50 часов за рулём", descriptionEn: "50 hours total driving",
              icon: "hourglass", color: AppTheme.teal, category: .distance,
              rarity: .rare,
              checkUnlocked: { $0.totalDurationHours >= 50 }),

        Badge(id: "veteran", titleRu: "Ветеран", titleEn: "Veteran",
              descriptionRu: "100 часов за рулём", descriptionEn: "100 hours total driving",
              icon: "star.fill", color: AppTheme.yellow, category: .distance,
              rarity: .rare,
              checkUnlocked: { $0.totalDurationHours >= 100 }),
    ]

    // MARK: - Exploration

    static let exploration: [Badge] = [
        Badge(id: "explorer_5", titleRu: "Исследователь", titleEn: "Explorer",
              descriptionRu: "5 уникальных регионов", descriptionEn: "5 unique regions visited",
              icon: "map.fill", color: AppTheme.accent, category: .exploration,
              rarity: .common,
              checkUnlocked: { $0.uniqueRegions >= 5 }),

        Badge(id: "explorer_10", titleRu: "Путешественник", titleEn: "Traveler",
              descriptionRu: "10 уникальных регионов", descriptionEn: "10 unique regions visited",
              icon: "globe.americas.fill", color: AppTheme.green, category: .exploration,
              rarity: .uncommon,
              checkUnlocked: { $0.uniqueRegions >= 10 }),

        Badge(id: "explorer_25", titleRu: "Конкистадор", titleEn: "Conquistador",
              descriptionRu: "25 уникальных регионов", descriptionEn: "25 unique regions visited",
              icon: "globe.europe.africa.fill", color: AppTheme.purple, category: .exploration,
              rarity: .epic,
              checkUnlocked: { $0.uniqueRegions >= 25 }),

        Badge(id: "explorer_50", titleRu: "Полсотни регионов", titleEn: "Fifty Regions",
              descriptionRu: "50 уникальных регионов", descriptionEn: "50 unique regions visited",
              icon: "map.circle.fill", color: Color(red: 0.60, green: 0.35, blue: 0.80),
              category: .exploration, rarity: .epic,
              checkUnlocked: { $0.uniqueRegions >= 50 }),

        Badge(id: "explorer_100", titleRu: "Сотня регионов", titleEn: "Hundred Regions",
              descriptionRu: "100 уникальных регионов", descriptionEn: "100 unique regions visited",
              icon: "globe.americas.fill", color: Color(red: 0.90, green: 0.65, blue: 0.10),
              category: .exploration, rarity: .legendary,
              checkUnlocked: { $0.uniqueRegions >= 100 }),

        Badge(id: "ambassador", titleRu: "Посол", titleEn: "Ambassador",
              descriptionRu: "Поездки в 2+ странах", descriptionEn: "Trips in 2+ countries",
              icon: "airplane", color: AppTheme.blue, category: .exploration,
              isHidden: true, rarity: .rare,
              checkUnlocked: { $0.countriesCount >= 2 }),

        Badge(id: "globetrotter", titleRu: "Глобтроттер", titleEn: "Globetrotter",
              descriptionRu: "Поездки в 5+ странах", descriptionEn: "Trips in 5+ countries",
              icon: "globe", color: AppTheme.accent, category: .exploration,
              isHidden: true, rarity: .legendary,
              checkUnlocked: { $0.countriesCount >= 5 }),
    ]

    // MARK: - Special (Hidden)

    static let special: [Badge] = [
        Badge(id: "night_rider", titleRu: "Ночной гонщик", titleEn: "Night Rider",
              descriptionRu: "Поездка ночью (22:00–05:00)", descriptionEn: "Trip at night (10 PM–5 AM)",
              icon: "moon.fill", color: Color(red: 80/255, green: 80/255, blue: 160/255),
              category: .special, isRepeatable: true, rarity: .common,
              checkUnlocked: { $0.hasNightTrip }),

        Badge(id: "night_wolf", titleRu: "Ночной волк", titleEn: "Night Wolf",
              descriptionRu: "Поездка в окно 23:00–04:00", descriptionEn: "Drive during the 11 PM–4 AM window",
              icon: "moon.stars.fill", color: Color(red: 60/255, green: 60/255, blue: 140/255),
              category: .special, isHidden: true, isRepeatable: true, rarity: .uncommon,
              checkUnlocked: { $0.hasLateNightTrip }),

        Badge(id: "early_bird", titleRu: "Ранняя птица", titleEn: "Early Bird",
              descriptionRu: "Поездка в окно 00:00–06:00", descriptionEn: "Drive during the midnight–6 AM window",
              icon: "sunrise.fill", color: AppTheme.yellow, category: .special,
              isHidden: true, isRepeatable: true, rarity: .uncommon,
              checkUnlocked: { $0.hasEarlyMorningTrip }),

        Badge(id: "mountain_goat", titleRu: "Горный козёл", titleEn: "Mountain Goat",
              descriptionRu: "Набор высоты 1000м за поездку", descriptionEn: "1000m elevation gain in one trip",
              icon: "mountain.2.fill", color: AppTheme.teal, category: .special,
              isHidden: true, isRepeatable: true, rarity: .rare,
              checkUnlocked: { $0.maxElevationGainSingleTrip >= 1000 }),

        Badge(id: "above_clouds", titleRu: "Выше облаков", titleEn: "Above Clouds",
              descriptionRu: "Высота 2000+м", descriptionEn: "Altitude 2000+m reached",
              icon: "cloud.fill", color: AppTheme.blue, category: .special,
              isHidden: true, isRepeatable: true, rarity: .epic,
              checkUnlocked: { $0.maxAltitude >= 2000 }),

        Badge(id: "polar", titleRu: "Полярник", titleEn: "Polar",
              descriptionRu: "Широта > 66°", descriptionEn: "Latitude above 66°",
              icon: "snowflake", color: Color(red: 180/255, green: 220/255, blue: 255/255),
              category: .special, isHidden: true, rarity: .legendary,
              checkUnlocked: { $0.maxLatitude >= 66.0 }),

        Badge(id: "sea_level", titleRu: "На уровне моря", titleEn: "Sea Level",
              descriptionRu: "Вдоль побережья (высота <10м, >20км)",
              descriptionEn: "Along coastline (altitude <10m, >20km)",
              icon: "water.waves", color: AppTheme.blue, category: .special,
              isHidden: true, isRepeatable: true, rarity: .rare,
              checkUnlocked: { $0.hasSeaLevelTrip }),

        Badge(id: "long_shift", titleRu: "Длинная смена", titleEn: "Long Shift",
              descriptionRu: "4+ часа без остановки", descriptionEn: "4+ hours non-stop",
              icon: "clock.arrow.circlepath", color: AppTheme.purple, category: .special,
              isHidden: true, isRepeatable: true, rarity: .rare,
              checkUnlocked: { $0.longestSingleTripDuration >= 4 * 3600 }),

        Badge(id: "sunday_driver", titleRu: "Воскресный водитель", titleEn: "Sunday Driver",
              descriptionRu: "Поездка в воскресенье", descriptionEn: "Trip on Sunday",
              icon: "sun.max.fill", color: AppTheme.yellow, category: .special,
              isHidden: true, isRepeatable: true, rarity: .common,
              checkUnlocked: { $0.hasSundayTrip }),

        Badge(id: "weekend_warrior", titleRu: "Weekend warrior", titleEn: "Weekend Warrior",
              descriptionRu: "Поездки 4 выходных подряд", descriptionEn: "Trips 4 weekends in a row",
              icon: "calendar.badge.checkmark", color: AppTheme.accent, category: .special,
              isHidden: true, rarity: .rare,
              checkUnlocked: { $0.hasWeekendWarrior }),

        Badge(id: "snow_leopard", titleRu: "Снежный барс", titleEn: "Snow Leopard",
              descriptionRu: "Зимняя горная поездка (дек-фев)",
              descriptionEn: "Winter mountain trip (Dec-Feb)",
              icon: "snowflake.circle.fill", color: Color(red: 180/255, green: 220/255, blue: 255/255),
              category: .special, isHidden: true, isRepeatable: true, rarity: .epic,
              checkUnlocked: { $0.hasWinterMountainTrip }),

        // MARK: - Secret badges (0.5.5 pack)
        // Surprise rewards — no in-app hint about how to earn them.
        Badge(id: "midnight_rider", titleRu: "Полуночник", titleEn: "Midnight Rider",
              descriptionRu: "Поездка между 00:00 и 04:00",
              descriptionEn: "Trip between midnight and 4 AM",
              icon: "moon.stars.fill", color: Color(red: 0.55, green: 0.40, blue: 0.85),
              category: .special, isHidden: true, rarity: .uncommon,
              checkUnlocked: { $0.hasAfterMidnightTrip }),

        Badge(id: "highway_wolf", titleRu: "Хайвейный волк", titleEn: "Highway Wolf",
              descriptionRu: "Одна поездка длиной 300+ км",
              descriptionEn: "Single trip ≥300 km",
              icon: "road.lanes", color: AppTheme.accent,
              category: .special, isHidden: true, rarity: .rare,
              checkUnlocked: { $0.longestTripKm >= 300 }),

        Badge(id: "wrapped_year", titleRu: "Завёрнутый год", titleEn: "Wrapped",
              descriptionRu: "Поездки во все 12 месяцев года",
              descriptionEn: "Drove during all 12 months of the year",
              icon: "calendar.circle.fill", color: AppTheme.green,
              category: .special, isHidden: true, rarity: .epic,
              checkUnlocked: { $0.distinctMonthsWithTrips >= 12 }),

        Badge(id: "centurion", titleRu: "Центурион", titleEn: "Centurion",
              descriptionRu: "100 поездок записано",
              descriptionEn: "100 trips recorded",
              icon: "100.circle.fill", color: Color(red: 1.0, green: 0.85, blue: 0.30),
              category: .special, isHidden: true, rarity: .rare,
              checkUnlocked: { $0.totalTrips >= 100 }),

        Badge(id: "carpool_karaoke", titleRu: "Любимая машина", titleEn: "Carpool Karaoke",
              descriptionRu: "30+ поездок на одной машине",
              descriptionEn: "30+ trips on the same vehicle",
              icon: "music.mic", color: Color(red: 0.95, green: 0.40, blue: 0.55),
              category: .special, isHidden: true, rarity: .rare,
              checkUnlocked: { $0.maxTripsOnSingleVehicle >= 30 }),

        Badge(id: "vault_keeper", titleRu: "Хранитель тайн", titleEn: "Vault Keeper",
              descriptionRu: "50 приватных поездок",
              descriptionEn: "50 private trips",
              icon: "lock.shield.fill", color: Color(red: 0.65, green: 0.70, blue: 0.80),
              category: .special, isHidden: true, rarity: .epic,
              checkUnlocked: { $0.privateTripCount >= 50 }),

        Badge(id: "expedition", titleRu: "Экспедиция", titleEn: "Expedition",
              descriptionRu: "50 000 км в сумме",
              descriptionEn: "50,000 km cumulative",
              icon: "mountain.2.fill", color: Color(red: 0.65, green: 0.50, blue: 0.35),
              category: .special, isHidden: true, rarity: .legendary,
              checkUnlocked: { $0.totalDistanceKm >= 50000 }),
    ]

    // MARK: - Streaks

    static let streaks: [Badge] = [
        Badge(id: "streak_3", titleRu: "Тройка", titleEn: "Three-peat",
              descriptionRu: "3 дня подряд с поездкой", descriptionEn: "3-day trip streak",
              icon: "flame.fill", color: AppTheme.accent, category: .streaks,
              rarity: .common,
              checkUnlocked: { $0.bestStreak >= 3 }),

        Badge(id: "streak_7", titleRu: "Неделя на колёсах", titleEn: "Week on Wheels",
              descriptionRu: "7 дней подряд", descriptionEn: "7-day trip streak",
              icon: "flame.circle.fill", color: AppTheme.accent, category: .streaks,
              rarity: .uncommon,
              checkUnlocked: { $0.bestStreak >= 7 }),

        Badge(id: "streak_14", titleRu: "Две недели", titleEn: "Two Weeks",
              descriptionRu: "14 дней подряд", descriptionEn: "14-day trip streak",
              icon: "flame.circle.fill", color: AppTheme.red, category: .streaks,
              rarity: .rare,
              checkUnlocked: { $0.bestStreak >= 14 }),

        Badge(id: "streak_30", titleRu: "Месяц без остановки", titleEn: "Month Non-stop",
              descriptionRu: "30 дней подряд", descriptionEn: "30-day trip streak",
              icon: "flame.circle.fill", color: AppTheme.red, category: .streaks,
              isHidden: true, rarity: .epic,
              checkUnlocked: { $0.bestStreak >= 30 }),
    ]

    // MARK: - Exclusive (time-limited / gifted — not earned by a plain stat)

    static let exclusive: [Badge] = [
        // Everyone who records a trip on a pre-1.0.0 build earns this. Once 1.0.0
        // ships, drop `early_tester` from this list so newcomers can't get it —
        // that's what keeps it a genuine badge of honour.
        Badge(id: "early_tester", titleRu: "Ранний тестер", titleEn: "Early Tester",
              descriptionRu: "Ты был с нами до релиза 1.0.0. Спасибо!",
              descriptionEn: "You were here before 1.0.0. Thank you!",
              icon: "hammer.fill", color: Color(red: 0.86, green: 0.20, blue: 0.58),
              category: .exclusive, rarity: .exclusive,
              checkUnlocked: { $0.totalTrips >= 1 }),

        // Yearly "thank you" — gifted server-side on Dec 31 to accounts that were
        // active that year. `checkUnlocked` stays false so it never auto-unlocks
        // locally; the backend grants it (adds the id to the account's badges).
        // Clone this per year (veteran_2027, …) each December.
        Badge(id: "veteran_2026", titleRu: "Ветеран 2026", titleEn: "2026 Veteran",
              descriptionRu: "Спасибо, что были с нами весь 2026 год",
              descriptionEn: "Thank you for riding with us through 2026",
              icon: "laurel.leading", color: Color(red: 0.86, green: 0.20, blue: 0.58),
              category: .exclusive, rarity: .exclusive,
              checkUnlocked: { _ in false }),
    ]
}
