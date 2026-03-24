import SwiftUI

extension Badge {
    static let all: [Badge] = distance + exploration + special + streaks

    // MARK: - Distance

    static let distance: [Badge] = [
        Badge(id: "first_trip", titleRu: "Первый путь", titleEn: "First Trip",
              descriptionRu: "Запишите первую поездку", descriptionEn: "Record your first trip",
              icon: "flag.fill", color: AppTheme.accent, category: .distance,
              checkUnlocked: { $0.totalTrips >= 1 }),

        Badge(id: "road_regular", titleRu: "Завсегдатай", titleEn: "Road Regular",
              descriptionRu: "10 поездок", descriptionEn: "10 trips recorded",
              icon: "car.fill", color: AppTheme.blue, category: .distance,
              checkUnlocked: { $0.totalTrips >= 10 }),

        Badge(id: "road_warrior", titleRu: "Дорожный воин", titleEn: "Road Warrior",
              descriptionRu: "50 поездок", descriptionEn: "50 trips recorded",
              icon: "shield.fill", color: AppTheme.purple, category: .distance,
              checkUnlocked: { $0.totalTrips >= 50 }),

        Badge(id: "first_km", titleRu: "Первый километр", titleEn: "First Kilometer",
              descriptionRu: "1 км суммарно", descriptionEn: "1 km total distance",
              icon: "location.fill", color: AppTheme.green, category: .distance,
              checkUnlocked: { $0.totalDistanceKm >= 1 }),

        Badge(id: "century", titleRu: "Сотня", titleEn: "Century",
              descriptionRu: "100 км суммарно", descriptionEn: "100 km total distance",
              icon: "speedometer", color: AppTheme.green, category: .distance,
              checkUnlocked: { $0.totalDistanceKm >= 100 }),

        Badge(id: "thousand", titleRu: "Тысячник", titleEn: "Thousand",
              descriptionRu: "1 000 км суммарно", descriptionEn: "1,000 km total distance",
              icon: "bolt.fill", color: AppTheme.yellow, category: .distance,
              checkUnlocked: { $0.totalDistanceKm >= 1000 }),

        Badge(id: "ten_thousand", titleRu: "Десять тысяч", titleEn: "Ten Thousand",
              descriptionRu: "10 000 км суммарно", descriptionEn: "10,000 km total distance",
              icon: "bolt.circle.fill", color: AppTheme.accent, category: .distance,
              checkUnlocked: { $0.totalDistanceKm >= 10_000 }),

        Badge(id: "marathon_42", titleRu: "Марафонец", titleEn: "Marathon",
              descriptionRu: "42.2 км за одну поездку", descriptionEn: "42.2 km in a single trip",
              icon: "figure.run", color: AppTheme.teal, category: .distance, isRepeatable: true,
              checkUnlocked: { $0.hasSingleTripMarathon }),

        Badge(id: "marathon_100", titleRu: "Стоик", titleEn: "Stoic",
              descriptionRu: "Поездка длиннее 100 км", descriptionEn: "Single trip over 100 km",
              icon: "road.lanes", color: AppTheme.teal, category: .distance, isRepeatable: true,
              checkUnlocked: { $0.longestTripKm >= 100 }),

        Badge(id: "iron_butt", titleRu: "Железная задница", titleEn: "Iron Butt",
              descriptionRu: "500+ км за одну поездку", descriptionEn: "500+ km in a single trip",
              icon: "flame.fill", color: AppTheme.red, category: .distance, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.hasSingleTripIronButt }),

        Badge(id: "speed_demon", titleRu: "Спид-демон", titleEn: "Speed Demon",
              descriptionRu: "Макс. скорость > 120 км/ч", descriptionEn: "Max speed over 120 km/h",
              icon: "hare.fill", color: AppTheme.red, category: .distance, isRepeatable: true,
              checkUnlocked: { $0.maxSpeedKmh >= 120 }),

        Badge(id: "endurance", titleRu: "Выносливый", titleEn: "Endurance",
              descriptionRu: "10 часов за рулём", descriptionEn: "10 hours total driving",
              icon: "clock.fill", color: AppTheme.blue, category: .distance,
              checkUnlocked: { $0.totalDurationHours >= 10 }),

        Badge(id: "veteran", titleRu: "Ветеран", titleEn: "Veteran",
              descriptionRu: "100 часов за рулём", descriptionEn: "100 hours total driving",
              icon: "star.fill", color: AppTheme.yellow, category: .distance,
              checkUnlocked: { $0.totalDurationHours >= 100 }),
    ]

    // MARK: - Exploration

    static let exploration: [Badge] = [
        Badge(id: "explorer_5", titleRu: "Исследователь", titleEn: "Explorer",
              descriptionRu: "5 уникальных регионов", descriptionEn: "5 unique regions visited",
              icon: "map.fill", color: AppTheme.accent, category: .exploration,
              checkUnlocked: { $0.uniqueRegions >= 5 }),

        Badge(id: "explorer_10", titleRu: "Путешественник", titleEn: "Traveler",
              descriptionRu: "10 уникальных регионов", descriptionEn: "10 unique regions visited",
              icon: "globe.americas.fill", color: AppTheme.green, category: .exploration,
              checkUnlocked: { $0.uniqueRegions >= 10 }),

        Badge(id: "explorer_25", titleRu: "Конкистадор", titleEn: "Conquistador",
              descriptionRu: "25 уникальных регионов", descriptionEn: "25 unique regions visited",
              icon: "globe.europe.africa.fill", color: AppTheme.purple, category: .exploration,
              checkUnlocked: { $0.uniqueRegions >= 25 }),

        Badge(id: "ambassador", titleRu: "Посол", titleEn: "Ambassador",
              descriptionRu: "Поездки в 2+ странах", descriptionEn: "Trips in 2+ countries",
              icon: "airplane", color: AppTheme.blue, category: .exploration, isHidden: true,
              checkUnlocked: { $0.countriesCount >= 2 }),

        Badge(id: "globetrotter", titleRu: "Глобтроттер", titleEn: "Globetrotter",
              descriptionRu: "Поездки в 5+ странах", descriptionEn: "Trips in 5+ countries",
              icon: "globe", color: AppTheme.accent, category: .exploration, isHidden: true,
              checkUnlocked: { $0.countriesCount >= 5 }),
    ]

    // MARK: - Special (Hidden)

    static let special: [Badge] = [
        Badge(id: "night_rider", titleRu: "Ночной гонщик", titleEn: "Night Rider",
              descriptionRu: "Поездка ночью (22:00–05:00)", descriptionEn: "Trip at night (10 PM–5 AM)",
              icon: "moon.fill", color: Color(red: 80/255, green: 80/255, blue: 160/255),
              category: .special, isRepeatable: true,
              checkUnlocked: { $0.hasNightTrip }),

        Badge(id: "night_wolf", titleRu: "Ночной волк", titleEn: "Night Wolf",
              descriptionRu: "Поездка после 23:00", descriptionEn: "Trip started after 11 PM",
              icon: "moon.stars.fill", color: Color(red: 60/255, green: 60/255, blue: 140/255),
              category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.hasLateNightTrip }),

        Badge(id: "early_bird", titleRu: "Ранняя птица", titleEn: "Early Bird",
              descriptionRu: "Поездка до 6:00", descriptionEn: "Trip started before 6 AM",
              icon: "sunrise.fill", color: AppTheme.yellow, category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.hasEarlyMorningTrip }),

        Badge(id: "mountain_goat", titleRu: "Горный козёл", titleEn: "Mountain Goat",
              descriptionRu: "Набор высоты 1000м за поездку", descriptionEn: "1000m elevation gain in one trip",
              icon: "mountain.2.fill", color: AppTheme.teal, category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.maxElevationGainSingleTrip >= 1000 }),

        Badge(id: "above_clouds", titleRu: "Выше облаков", titleEn: "Above Clouds",
              descriptionRu: "Высота 2000+м", descriptionEn: "Altitude 2000+m reached",
              icon: "cloud.fill", color: AppTheme.blue, category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.maxAltitude >= 2000 }),

        Badge(id: "polar", titleRu: "Полярник", titleEn: "Polar",
              descriptionRu: "Широта > 66°", descriptionEn: "Latitude above 66°",
              icon: "snowflake", color: Color(red: 180/255, green: 220/255, blue: 255/255),
              category: .special, isHidden: true,
              checkUnlocked: { $0.maxLatitude >= 66.0 }),

        Badge(id: "sea_level", titleRu: "На уровне моря", titleEn: "Sea Level",
              descriptionRu: "Вдоль побережья (высота <10м, >20км)",
              descriptionEn: "Along coastline (altitude <10m, >20km)",
              icon: "water.waves", color: AppTheme.blue, category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.hasSeaLevelTrip }),

        Badge(id: "long_shift", titleRu: "Длинная смена", titleEn: "Long Shift",
              descriptionRu: "4+ часа без остановки", descriptionEn: "4+ hours non-stop",
              icon: "clock.arrow.circlepath", color: AppTheme.purple, category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.longestSingleTripDuration >= 4 * 3600 }),

        Badge(id: "sunday_driver", titleRu: "Воскресный водитель", titleEn: "Sunday Driver",
              descriptionRu: "Поездка в воскресенье", descriptionEn: "Trip on Sunday",
              icon: "sun.max.fill", color: AppTheme.yellow, category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.hasSundayTrip }),

        Badge(id: "weekend_warrior", titleRu: "Weekend warrior", titleEn: "Weekend Warrior",
              descriptionRu: "Поездки 4 выходных подряд", descriptionEn: "Trips 4 weekends in a row",
              icon: "calendar.badge.checkmark", color: AppTheme.accent, category: .special, isHidden: true,
              checkUnlocked: { $0.hasWeekendWarrior }),

        Badge(id: "snow_leopard", titleRu: "Снежный барс", titleEn: "Snow Leopard",
              descriptionRu: "Зимняя горная поездка (дек-фев)",
              descriptionEn: "Winter mountain trip (Dec-Feb)",
              icon: "snowflake.circle.fill", color: Color(red: 180/255, green: 220/255, blue: 255/255),
              category: .special, isHidden: true, isRepeatable: true,
              checkUnlocked: { $0.hasWinterMountainTrip }),
    ]

    // MARK: - Streaks

    static let streaks: [Badge] = [
        Badge(id: "streak_3", titleRu: "Тройка", titleEn: "Three-peat",
              descriptionRu: "3 дня подряд с поездкой", descriptionEn: "3-day trip streak",
              icon: "flame.fill", color: AppTheme.accent, category: .streaks,
              checkUnlocked: { $0.bestStreak >= 3 }),

        Badge(id: "streak_7", titleRu: "Неделя на колёсах", titleEn: "Week on Wheels",
              descriptionRu: "7 дней подряд", descriptionEn: "7-day trip streak",
              icon: "flame.circle.fill", color: AppTheme.accent, category: .streaks,
              checkUnlocked: { $0.bestStreak >= 7 }),

        Badge(id: "streak_30", titleRu: "Месяц без остановки", titleEn: "Month Non-stop",
              descriptionRu: "30 дней подряд", descriptionEn: "30-day trip streak",
              icon: "flame.circle.fill", color: AppTheme.red, category: .streaks, isHidden: true,
              checkUnlocked: { $0.bestStreak >= 30 }),
    ]
}
