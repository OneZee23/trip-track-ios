import Foundation

enum AppStrings {
    // MARK: - Tabs
    static func feed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Лента" : "Feed"
    }
    static func record(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Запись" : "Record"
    }
    static func regions(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Места" : "Places"
    }
    static func profile(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Профиль" : "Profile"
    }
    static func tabMap(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Карта" : "Map"
    }
    static func tabGroups(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Группы" : "Groups"
    }
    static func tabMe(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Я" : "Me"
    }

    // MARK: - Groups (coming soon)
    static func groupsComingTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Группы скоро" : "Groups are coming"
    }
    static func groupsComingBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Здесь появятся сообщества по интересам: клубы по маркам, региональные компании, совместные покатушки. Находите своих и следите за поездками всей группы."
            : "Interest-based communities are coming here: brand clubs, regional crews, group drives. Find your people and follow the whole group's trips."
    }

    // MARK: - Feed
    static func trips(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "поездок" : "trips"
    }
    static func km(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км" : "km"
    }
    static func time(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "в пути" : "drive time"
    }
    static func filters(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Фильтры" : "Filters"
    }
    static func noTrips(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пока нет поездок" : "No trips yet"
    }
    static func goRide(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Нажмите чтобы начать" : "Tap to start"
    }

    // MARK: - Stats labels
    static func stats(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Статистика" : "Stats"
    }
    static func avg(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ср. скор." : "avg speed"
    }
    static func fuel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "топливо" : "fuel"
    }
    static func cost(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "расход" : "fuel cost"
    }
    static func maxSpeed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Макс. скорость" : "Max speed"
    }
    static func elevation(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "набор высоты" : "elevation"
    }
    static func elevationGain(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Набор высоты" : "Elevation gain"
    }
    static func maxAltitude(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Макс. высота" : "Max altitude"
    }
    static func photos(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Фото" : "Photos"
    }

    // MARK: - Record
    static func startTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Начать поездку" : "Start trip"
    }
    static func slideToStart(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сдвиньте" : "Slide"
    }
    static func readyToRide(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "В путь?" : "Ready to roll?"
    }

    // MARK: - Recording states (6.1.0)

    static func gpsAccurate(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "GPS точный" : "GPS strong"
    }
    static func gpsMedium(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "GPS средний" : "GPS fair"
    }
    static func gpsWeak(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "GPS слабый" : "GPS weak"
    }
    static func gpsLost(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "GPS потерян" : "GPS lost"
    }
    static func gpsLegendAccurate(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "≤ 10 м · запись идеальна" : "≤ 10 m · perfect recording"
    }
    static func gpsLegendMedium(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "10–35 м · возможны неточности" : "10–35 m · minor inaccuracies"
    }
    static func gpsLegendWeak(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "> 35 м · трек прерывается" : "> 35 m · track breaks up"
    }
    static func weakSignalTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сигнал слабый" : "Weak signal"
    }
    static func weakSignalHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "На открытой местности точнее" : "More accurate in open areas"
    }
    static func signalLostTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сигнал GPS потерян" : "GPS signal lost"
    }
    static func signalLostHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Пишем по последней точке — восстановим, когда сигнал вернётся"
            : "Holding last point — we'll recover when the signal returns"
    }
    static func recordingPausedPill(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Запись на паузе" : "Recording paused"
    }
    static func pauseShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ПАУЗА" : "PAUSED"
    }
    static func stop(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Стоп" : "Stop"
    }
    static func noGeoTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Нет доступа к геолокации" : "No location access"
    }
    static func noGeoSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Включите доступ в Настройках" : "Enable access in Settings"
    }
    static func recoveryTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Запись была прервана" : "Recording was interrupted"
    }
    static func recoveryBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Приложение закрылось до того, как Вы завершили поездку. Мы сохранили Ваш маршрут."
            : "The app closed before you finished the trip. We saved your route."
    }
    static func recoveryChip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Восстановлено" : "Recovered"
    }
    static func recoveryContinue(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Продолжить запись" : "Continue recording"
    }
    static func recoveryFinish(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Завершить и сохранить" : "Finish and save"
    }
    static func vehiclePickerTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Машина для поездки" : "Vehicle for this trip"
    }
    static func manageInGarage(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Управлять в Гараже" : "Manage in Garage"
    }
    static func publishToFeed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Опубликовать в ленту" : "Publish to feed"
    }
    static func publishToFeedSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка появится в общей ленте" : "Your trip will appear in the shared feed"
    }
    static func publishFootnote(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Поездки приватны, пока Вы не опубликуете их сами."
            : "Trips stay private until you publish them yourself."
    }
    static func tripFinishedTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка завершена!" : "Trip finished!"
    }
    static func maxShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "МАКС" : "MAX"
    }
    static func photoShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Фото" : "Photo"
    }
    static func kmh(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км/ч" : "km/h"
    }
    static func unitLPer100(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "л/100" : "l/100"
    }
    static func unitMeters(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "м" : "m"
    }

    // MARK: - Regions
    static func regionsExplored(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "регионов" : "regions"
    }
    static func mapExplored(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "исследовано" : "explored"
    }
    static func unlocked(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "открыто" : "unlocked"
    }
    static func locked(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Заблокировано" : "Locked"
    }
    static func view(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Смотреть" : "View"
    }

    // MARK: - Filters
    static func apply(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Применить" : "Apply"
    }
    static func reset(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сбросить" : "Reset"
    }
    static func resetSecondary(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сбросить вторичные" : "Reset secondary"
    }
    static func all(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Все" : "All"
    }
    static func region(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Регион" : "Region"
    }

    // MARK: - Periods
    static func week(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Неделя" : "Week"
    }
    static func month(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Месяц" : "Month"
    }
    static func year(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Год" : "Year"
    }
    static func total(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Всё время" : "All time"
    }

    // MARK: - Profile / Settings
    static func back(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Назад" : "Back"
    }
    static func theme(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Тема" : "Theme"
    }
    static func lang(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Язык" : "Language"
    }
    static func dark(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Тёмная" : "Dark"
    }
    static func light(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Светлая" : "Light"
    }
    static func garage(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Гараж" : "Garage"
    }
    static func about(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "О приложении" : "About"
    }
    static func developer(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разработчик" : "Developer"
    }
    static func calendar(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Календарь" : "Calendar"
    }
    static func onlyCurrentWeek(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "только текущая неделя" : "only current week"
    }
    static func thisWeek(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Эта неделя" : "This Week"
    }
    static func quickStats(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Статистика" : "Quick stats"
    }
    static func consumption(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Расход л/100км" : "L/100km"
    }
    static func pricePerLiter(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "\(FuelCurrency.current) за литр" : "\(FuelCurrency.current)/L"
    }

    // MARK: - Trip detail
    static func distance(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Дистанция" : "Distance"
    }
    static func duration(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Время" : "Time"
    }
    static func avgSpeed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ср. скорость" : "Avg speed"
    }
    static func avgSpeedModeTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Расчёт средней скорости" : "Average speed basis"
    }
    static func avgSpeedOverall(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Общая" : "Overall"
    }
    static func avgSpeedMoving(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "В движении" : "Moving"
    }
    // Website-globe opt-in (per-user)
    static func publishOnGlobeTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Публикация поездок на глобальной карте" : "Publish trips on the global map"
    }
    static func publishOnGlobeSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Только публичные поездки, маршрут анонимизируется (концы обрезаются). Приватные не показываются."
            : "Public trips only, route is anonymized (endpoints trimmed). Private trips are never shown."
    }
    static func optYes(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Да" : "Yes"
    }
    static func optNo(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Нет" : "No"
    }
    static func noVehicle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Без машины" : "No vehicle"
    }
    static func tripVehicle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Машина поездки" : "Trip vehicle"
    }
    static func statsMoreKm(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "— больше км" : "— more km"
    }
    static func statsToday(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "сегодня" : "today"
    }
    static func tripTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка" : "Trip"
    }
    static func tripsHistory(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "История ваших путешествий" : "Your trip history"
    }
    static func tripsTab(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездки" : "Trips"
    }
    static func startFirstTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Начните первую поездку чтобы увидеть её здесь" : "Start your first trip to see it here"
    }
    static func totalKm(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км всего" : "total km"
    }
    static func regionsCount(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "регионов" : "regions"
    }
    static func m(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "м" : "m"
    }

    // MARK: - Onboarding
    // Two-tone welcome headline (6.1.0): the hook line in text color, the
    // punch line in accent.
    static func onboardingWelcomeTitle1(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Вы забудете почти каждую поездку." : "You'll forget almost every trip."
    }
    static func onboardingWelcomeTitle2(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "TripTrack — нет." : "TripTrack won't."
    }
    static func onboardingWelcomeSub(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "Дневник ваших дорог — маршруты, статистика, расход и гараж. Откройте через год — и вспомните всё."
        }
        return "A diary of your roads — routes, stats, fuel and garage. Open it a year from now — and remember everything."
    }
    static func onboardingPrivacyPill(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Приватно по умолчанию" : "Private by default"
    }
    static func onboardingValueTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Вот как выглядит ваша поездка" : "This is what your trip looks like"
    }
    static func onboardingValueCaption(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездки записываются сами — маршрут, скорость и расход." : "Trips record themselves — route, speed and fuel."
    }
    static func onboardingRecordedAuto(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Записано автоматически" : "Recorded automatically"
    }
    static func onboardingMockTripTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка · 16 мая" : "Trip · May 16"
    }
    // Short uppercase stat labels for the mock trip card's 2×3 metrics grid.
    static func onboardingStatAvg(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Средняя" : "Avg"
    }
    static func onboardingStatMax(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Макс" : "Max"
    }
    static func onboardingStatFuel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Расход" : "Fuel"
    }
    static func onboardingStatAltitude(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Высота" : "Elev"
    }
    static func onboardingLocation(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разрешите геолокацию" : "Allow location access"
    }
    static func onboardingLocationSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Для записи маршрутов нужен доступ к геолокации. Данные хранятся на устройстве." : "Location access is needed to record your routes. Your data stays on your device."
    }
    static func onboardingAllow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разрешить" : "Allow"
    }
    static func onboardingAutoRecord(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Автоматическая запись" : "Automatic recording"
    }
    static func onboardingAutoRecordSub(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "TripTrack сам определит, что Вы за рулём, и начнёт запись. Для этого нужен фоновый доступ к геолокации и датчику движения. Батарея почти не расходуется."
        }
        return "TripTrack detects when you're driving and starts recording automatically. This requires background location and motion sensor access. Minimal battery impact."
    }
    static func onboardingAutoRecordEnable(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Включить" : "Enable"
    }
    static func onboardingAutoRecordSkip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Настрою позже" : "Set up later"
    }
    /// Composes the full onboarding consent sentence with clickable Markdown links.
    /// Uses correct Russian declension (instrumental after «соглашаетесь с»).
    static func onboardingConsentMarkdown(
        _ lang: LanguageManager.Language,
        termsURL: String,
        privacyURL: String
    ) -> String {
        if lang == .ru {
            return "Продолжая, Вы соглашаетесь с [Условиями использования](\(termsURL)) и [Политикой конфиденциальности](\(privacyURL))"
        } else {
            return "By continuing, you accept our [Terms of Service](\(termsURL)) and [Privacy Policy](\(privacyURL))"
        }
    }

    /// Nominative / standalone title. Use wherever the text stands alone
    /// (button, row in settings, link in the profile).
    static func termsOfService(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Условия использования" : "Terms of Service"
    }

    /// Nominative / standalone title.
    static func privacyPolicy(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Политика конфиденциальности" : "Privacy Policy"
    }

    // MARK: - Badges
    static func badges(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Достижения" : "Badges"
    }
    static func newBadge(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Новое достижение" : "New badge"
    }
    static func achievementUnlocked(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Достижение!" : "Achievement Unlocked!"
    }
    static func earnedTimes(_ lang: LanguageManager.Language, count: Int) -> String {
        lang == .ru ? "Получено \(count) раз" : "Earned \(count) \(count == 1 ? "time" : "times")"
    }
    static func continueButton(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Продолжить" : "Continue"
    }

    // MARK: - Regions / Exploration
    static func map(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Карта" : "Map"
    }
    static func tilesDiscovered(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "УЧАСТКОВ ОТКРЫТО" : "TILES DISCOVERED"
    }
    static func citiesCount(_ lang: LanguageManager.Language, count: Int) -> String {
        if lang == .ru {
            return "\(count) \(count == 1 ? "город" : "города")"
        }
        return "\(count) \(count == 1 ? "City" : "Cities")"
    }
    static func regionsCountLabel(_ lang: LanguageManager.Language, count: Int) -> String {
        if lang == .ru {
            return "\(count) \(count == 1 ? "регион" : "региона")"
        }
        return "\(count) \(count == 1 ? "Region" : "Regions")"
    }

    // MARK: - My Map (6.1.0)

    static func myMapTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Моя карта" : "My Map"
    }
    static func mapModeRoutes(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Маршруты" : "Routes"
    }
    static func mapModeTerritory(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Территория" : "Territory"
    }
    static func mapModeAll(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Всё" : "All"
    }
    static func km2ExploredLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км² освоено" : "km² explored"
    }
    static func km2Short(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км²" : "km²"
    }
    /// Bare genitive plate labels («8 регионов», «24 города» etc.).
    static func regionsGenitive(_ lang: LanguageManager.Language, count: Int) -> String {
        guard lang == .ru else { return count == 1 ? "region" : "regions" }
        let m10 = count % 10, m100 = count % 100
        if m10 == 1 && m100 != 11 { return "регион" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "региона" }
        return "регионов"
    }
    static func citiesGenitive(_ lang: LanguageManager.Language, count: Int) -> String {
        guard lang == .ru else { return count == 1 ? "city" : "cities" }
        let m10 = count % 10, m100 = count % 100
        if m10 == 1 && m100 != 11 { return "город" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "города" }
        return "городов"
    }
    static func tripsGenitive(_ lang: LanguageManager.Language, count: Int) -> String {
        guard lang == .ru else { return count == 1 ? "trip" : "trips" }
        let m10 = count % 10, m100 = count % 100
        if m10 == 1 && m100 != 11 { return "поездка" }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return "поездки" }
        return "поездок"
    }
    static func emptyMapTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Карта пока пустая" : "The map is still empty"
    }
    static func emptyMapSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Запишите первую поездку — и здесь засветится ваш след"
            : "Record your first trip — your trail will light up here"
    }

    /// Sign-out warning copy when the user has public trips on the server.
    /// Russian needs full plural agreement: 1 → "публичная поездка", 2-4 →
    /// "публичные поездки", 5+ → "публичных поездок", with the verb form
    /// matching ("она" vs "они"). The "11-14" carve-out is the standard
    /// Slavic exception (11 takes the genitive plural). Copy avoids the word
    /// "удалить" — "Hide public" describes the user-visible effect; the
    /// implementation detail (server DELETE + local mark private) is
    /// invisible to them and doesn't touch private trips or local data.
    static func publishedTripsSignOutMessage(_ lang: LanguageManager.Language, count: Int) -> String {
        if lang == .ru {
            let lastDigit = count % 10
            let lastTwo = count % 100
            let noun: String
            let verb: String
            if lastTwo >= 11 && lastTwo <= 14 {
                noun = "публичных поездок"
                verb = "Они останутся в ленте"
            } else if lastDigit == 1 {
                noun = "публичная поездка"
                verb = "Она останется в ленте"
            } else if lastDigit >= 2 && lastDigit <= 4 {
                noun = "публичные поездки"
                verb = "Они останутся в ленте"
            } else {
                noun = "публичных поездок"
                verb = "Они останутся в ленте"
            }
            return "В общей ленте у Вас \(count) \(noun). \(verb) после выхода, если Вы их не скроете.\n\nПриватные поездки и локальные данные не затрагиваются — Вы сможете снова войти и продолжить."
        }
        let noun = count == 1 ? "public trip" : "public trips"
        let pron = count == 1 ? "It will stay in the feed" : "They will stay in the feed"
        return "You have \(count) \(noun) in the social feed. \(pron) after sign out unless you hide them.\n\nPrivate trips and local data are not affected — you can sign back in anytime."
    }
    static func exploredPercent(_ lang: LanguageManager.Language, percent: String, place: String) -> String {
        lang == .ru ? "\(percent)% от \(place) исследовано" : "\(percent)% of \(place) explored"
    }
    static func tiles(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "участков" : "tiles"
    }

    // MARK: - GPS
    static func gpsAccuracyTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Точность GPS" : "GPS Accuracy"
    }
    static func gpsAccuracyBody(_ lang: LanguageManager.Language, current: String) -> String {
        if lang == .ru {
            return "Текущая точность: \(current)\n\n🟢 ≤10м — отличная\n🟠 >10м — средняя\n\nВлияет на точность записи маршрута. На открытой местности точность выше."
        }
        return "Current accuracy: \(current)\n\n🟢 ≤10m — excellent\n🟠 >10m — moderate\n\nAffects route recording precision. Open areas provide better accuracy."
    }

    // MARK: - Trip Detail
    static func tripTitlePlaceholder(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Название поездки" : "Trip title"
    }

    // MARK: - Trip Detail poster (6.1.0)
    static func reliveTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Прожить заново" : "Relive"
    }
    static func watchTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Смотреть поездку" : "Watch trip"
    }
    static func detailsSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Детали" : "Details"
    }
    static func elevationProfile(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Профиль высоты" : "Elevation profile"
    }
    static func speedSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Скорость" : "Speed"
    }
    static func movingAndStops(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "В движении и стоянки" : "Moving & stops"
    }
    static func movingDot(_ lang: LanguageManager.Language, _ value: String) -> String {
        lang == .ru ? "В движении · \(value)" : "Moving · \(value)"
    }
    static func stopsDot(_ lang: LanguageManager.Language, _ value: String) -> String {
        lang == .ru ? "Стоянки · \(value)" : "Stops · \(value)"
    }
    /// Detail-context header for the trip notes ("Описание"). `notes` stays
    /// for legacy call sites.
    static func descriptionSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Описание" : "Description"
    }
    static func tripAchievements(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Достижения поездки" : "Trip achievements"
    }
    static func reactionsTitleN(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "Реакции · \(n)" : "Reactions · \(n)"
    }
    // Detail stat-grid short labels. Detail-scoped cases: the onboarding set
    // maps «Расход»→"Fuel" for the mock card, which would collide with the
    // fuel-volume vs fuel-cost split the detail grid needs.
    static func statMoving(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "В движении" : "Moving"
    }
    static func statStops(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Стоянки" : "Stops"
    }
    static func statAvg(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Средняя" : "Avg"
    }
    static func statMax(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Макс" : "Max"
    }
    static func statFuel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Топливо" : "Fuel"
    }
    static func statCost(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Расход" : "Cost"
    }
    static func chartAltitudeLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ВЫСОТА" : "ALTITUDE"
    }
    static func chartSpeedLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "КМ/Ч" : "KM/H"
    }
    static func chartMaxElev(_ lang: LanguageManager.Language, max: String, gain: String) -> String {
        lang == .ru ? "макс \(max) · ↑ \(gain)" : "max \(max) · ↑ \(gain)"
    }
    static func chartMaxAvg(_ lang: LanguageManager.Language, max: String, avg: String) -> String {
        lang == .ru ? "макс \(max) · ср \(avg)" : "max \(max) · avg \(avg)"
    }
    static func privacyOnlyMe(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Только для меня" : "Only me"
    }
    static func privacyPublic(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Видна всем" : "Public"
    }
    static func share(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поделиться" : "Share"
    }
    static func noReactionsYet(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пока никто не отреагировал" : "No reactions yet"
    }
    static func beFirstToReact(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Будьте первым, кто отреагирует" : "Be the first to react"
    }
    /// Author-pill level tag, pixel font — «ур. 18» / "lvl 18".
    static func levelShort(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "ур. \(n)" : "lvl \(n)"
    }

    // MARK: - Comments (6.1.0)
    static func commentsTitleN(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "Комментарии · \(n)" : "Comments · \(n)"
    }
    static func commentPlaceholder(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Оставьте комментарий…" : "Leave a comment…"
    }
    static func send(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Отправить" : "Send"
    }
    static func showMoreComments(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Показать ещё" : "Show more"
    }
    static func deleteCommentConfirm(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Удалить комментарий?" : "Delete comment?"
    }
    static func commentPostFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось отправить комментарий" : "Couldn't post the comment"
    }
    static func commentDeleteFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось удалить комментарий" : "Couldn't delete the comment"
    }
    static func signInPromptComment(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите, чтобы комментировать" : "Sign in to comment"
    }
    // Relative comment age — compact «2 ч» / "2 h" style (Figma «· 2 ч»).
    static func relTimeNow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "сейчас" : "now"
    }
    static func relTimeMinutes(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "\(n) мин" : "\(n) min"
    }
    static func relTimeHours(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "\(n) ч" : "\(n) h"
    }
    static func relTimeDays(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "\(n) д" : "\(n) d"
    }

    // MARK: - Publish flow (6.1.0)
    static func publishTripTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Опубликовать поездку?" : "Publish trip?"
    }
    static func publishAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Опубликовать" : "Publish"
    }
    static func publishOptionalDescLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ОПИСАНИЕ · НЕОБЯЗАТЕЛЬНО" : "DESCRIPTION · OPTIONAL"
    }
    static func publishDescPlaceholder(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Расскажите о поездке: дорога, погода, остановки…"
            : "Tell about the trip: road, weather, stops…"
    }
    static func publishing(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Публикуется…" : "Publishing…"
    }
    static func publishFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось опубликовать" : "Couldn't publish"
    }
    static func publishFailedBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Нет связи с сервером. Поездка пока видна только Вам — мы повторим автоматически."
            : "No connection. The trip is only visible to you for now — we'll retry automatically."
    }
    static func retry(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Повторить" : "Retry"
    }
    static func tripLoadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось загрузить поездку" : "Couldn't load the trip"
    }
    static func tripLoadFailedBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Проверьте подключение к интернету и попробуйте ещё раз"
            : "Check your internet connection and try again"
    }
    static func tryAgain(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Попробовать снова" : "Try again"
    }

    // MARK: - UX Actions
    static func undo(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Отменить" : "Undo"
    }
    static func tripDeleted(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка удалена" : "Trip deleted"
    }
    static func photoDeleted(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Фото удалено" : "Photo deleted"
    }
    static func deletePhoto(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Удалить фото?" : "Delete photo?"
    }
    static func delete(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Удалить" : "Delete"
    }
    static func deleteTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Удалить поездку?" : "Delete trip?"
    }
    static func cancel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Отмена" : "Cancel"
    }
    static func noResults(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ничего не найдено" : "No results"
    }
    static func tryOtherFilters(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Попробуйте другие фильтры" : "Try different filters"
    }
    static func timeToRide(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Время в путь!" : "Time to ride!"
    }
    static func recordAndBuild(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Записывайте поездки и создавайте свою историю дорог" : "Record trips and build your road story"
    }

    // MARK: - Links
    static func writeAuthor(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Написать автору" : "Contact author"
    }
    static func bugsAndIdeas(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Баги, идеи, предложения" : "Bugs, ideas, suggestions"
    }
    static func telegramChannel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Telegram-канал" : "Telegram channel"
    }
    static func telegramChannelSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разработка TripTrack в реальном времени" : "TripTrack development in real time"
    }
    static func githubSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Открытый исходный код" : "Open-source project"
    }
    static func youtubeSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Видео о разработке" : "Development videos"
    }

    // MARK: - Photos & Notes
    static func notes(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Заметки" : "Notes"
    }
    static func addNotes(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавить заметку..." : "Add a note..."
    }
    /// Discoverable empty-state CTA on the owner's own trip detail.
    static func addNotesCTA(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавьте описание поездки" : "Add a trip description"
    }
    static func addPhotos(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавить фото" : "Add photos"
    }

    // MARK: - Auto-record
    static func autoRecord(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Автозапись" : "Auto-record"
    }
    static func autoRecordMode(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Режим" : "Mode"
    }
    static func autoRecordOff(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Выкл" : "Off"
    }
    static func autoRecordRemind(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Напоминание" : "Remind"
    }
    static func autoRecordAuto(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Авто" : "Auto"
    }
    static func myDevices(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Мои устройства" : "My devices"
    }
    static func addDevice(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавить устройство" : "Add device"
    }
    static func linkStereo(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Привязать магнитолу" : "Link car stereo"
    }
    static func enterDeviceName(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Введите имя устройства" : "Enter device name"
    }
    static func enterDeviceNameHint(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "Откройте Настройки → Bluetooth на iPhone и скопируйте имя магнитолы"
        }
        return "Open Settings → Bluetooth on your iPhone and copy the stereo name"
    }
    static func save(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сохранить" : "Save"
    }
    static func nearbyDevices(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Устройства рядом" : "Nearby devices"
    }
    static func autoRecordDescription(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "Запись начнётся автоматически при подключении к магнитоле по Bluetooth"
        }
        return "Recording starts automatically when connected to the car stereo via Bluetooth"
    }
    static func remindModeDescription(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "Уведомление с кнопкой \"Начать запись\" при подключении"
        }
        return "Push notification with \"Start recording\" button on connection"
    }
    static func autoModeDescription(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "Запись начинается сразу, без касания телефона"
        }
        return "Recording starts immediately, no phone interaction needed"
    }
    static func autoStopDescription(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "Поездка автоматически завершится через это время после отключения от магнитолы"
        }
        return "Trip auto-stops this long after disconnecting from the stereo"
    }
    static func autoStopTimeout(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Автозавершение" : "Auto-stop"
    }
    static func autoStopMinutes(_ lang: LanguageManager.Language, minutes: Int) -> String {
        if lang == .ru {
            return "\(minutes) мин"
        }
        return "\(minutes) min"
    }
    static func scanningDevices(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поиск устройств..." : "Scanning for devices..."
    }
    static func scanHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Убедитесь, что Вы в машине и магнитола включена" : "Make sure you're in the car with the stereo on"
    }
    static func noDevicesFound(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Устройства не найдены" : "No devices found"
    }
    static func currentAudioOutput(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Текущий аудиовыход" : "Current audio output"
    }
    static func bluetoothRequired(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Для автозаписи нужен доступ к Bluetooth" : "Auto-record requires Bluetooth access"
    }
    static func notificationsRequired(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Для напоминаний нужны уведомления" : "Notifications are required for reminders"
    }
    static func openSettings(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Открыть настройки" : "Open Settings"
    }

    // MARK: - Auto-record Notifications
    static func notifTripStartTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Похоже, Вы в машине" : "Looks like you're in the car"
    }
    static func notifTripStartBody(_ lang: LanguageManager.Language, deviceName: String) -> String {
        if lang == .ru {
            return "Подключено к \(deviceName). Начать запись?"
        }
        return "Connected to \(deviceName). Start recording?"
    }
    static func notifTripStartAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Начать запись" : "Start Recording"
    }
    static func notifSkipAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пропустить" : "Skip"
    }
    static func notifTripStopTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка закончена?" : "Trip finished?"
    }
    enum TripStopReason {
        case bluetooth
        case inactivity
    }
    static func notifTripStopBody(_ lang: LanguageManager.Language, minutes: Int, reason: TripStopReason) -> String {
        switch reason {
        case .bluetooth:
            return lang == .ru
                ? "Bluetooth отключился. Автозавершение через \(minutes) мин"
                : "Bluetooth disconnected. Auto-stop in \(minutes) min"
        case .inactivity:
            return lang == .ru
                ? "Машина не движется. Автозавершение через \(minutes) мин"
                : "Vehicle isn't moving. Auto-stop in \(minutes) min"
        }
    }
    static func notifStopNowAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Завершить сейчас" : "Stop Now"
    }
    static func notifContinueAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Продолжить" : "Continue"
    }
    static func notifAutoStartTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Запись началась" : "Recording started"
    }
    static func notifAutoStartBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "TripTrack автоматически начал запись" : "TripTrack automatically started recording"
    }
    static func notifAutoStopTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка завершена" : "Trip completed"
    }
    static func notifAutoStopSummary(_ lang: LanguageManager.Language, km: String, time: String) -> String {
        lang == .ru ? "\(km) км · \(time)" : "\(km) km · \(time)"
    }
    static func notifAutoStopBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Автозавершение поездки" : "Auto-stopping trip"
    }
    static func bluetoothAudio(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Bluetooth-аудио" : "Bluetooth Audio"
    }
    static func strongSignal(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сильный сигнал" : "Strong signal"
    }
    static func mediumSignal(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Средний сигнал" : "Medium signal"
    }
    static func weakSignal(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Слабый сигнал" : "Weak signal"
    }
    static func done(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Готово" : "Done"
    }
    static func car(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Автомобиль" : "Car"
    }
    static func added(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавлено" : "Added"
    }
    static func linked(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Привязано" : "Linked"
    }

    // MARK: - Auth

    static func guest(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Гость" : "Guest"
    }
    static func signInToSync(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите для синхронизации" : "Sign in to sync trips"
    }
    static func signedIn(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Вы вошли" : "Signed in"
    }
    static func synced(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Синхронизировано" : "Synced"
    }
    static func syncComingSoon(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Синхронизация скоро" : "Sync coming soon"
    }
    static func signOut(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Выйти" : "Sign out"
    }
    static func signOutConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Выйти?" : "Sign out?"
    }
    static func signOutConfirmMessage(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ваши поездки останутся на устройстве" : "Your trips will remain on this device"
    }
    static func deleteAccount(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Удалить аккаунт" : "Delete account"
    }
    static func deleteAccountConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Удалить аккаунт?" : "Delete account?"
    }
    static func deleteAccountConfirmMessage(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Все данные на нашем сервере (поездки, фото, машины, настройки) будут удалены навсегда. Ваши локальные поездки на этом устройстве останутся — Вы сможете продолжать пользоваться приложением без облака. Это действие необратимо."
            : "All data on our server (trips, photos, vehicles, settings) will be permanently deleted. Your local trips on this device will remain — you can continue using the app offline. This action cannot be undone."
    }
    static func deleteAccountFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось удалить аккаунт. Попробуйте ещё раз." : "Couldn't delete account. Please try again."
    }
    static func dangerZone(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Опасная зона" : "Danger zone"
    }

    // MARK: - Sync status sheet

    static func syncStatusTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Очередь синхронизации" : "Sync queue"
    }
    static func syncStatusPendingHeader(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "В очереди" : "Pending"
    }
    static func syncStatusFailedHeader(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось" : "Failed"
    }
    static func syncStatusEmpty(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Всё синхронизировано." : "Everything is up to date."
    }
    static func syncStatusRetry(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Повторить сейчас" : "Retry now"
    }
    static func syncStatusNowLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сейчас" : "Now"
    }
    static func syncAttemptsLabel(_ count: Int, _ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            // Plural agreement for Russian: 1 → "1 попытка", 2-4 → "2 попытки",
            // 5-20 → "5 попыток", 21 → "21 попытка", etc.
            let mod10 = count % 10
            let mod100 = count % 100
            let word: String
            if mod100 >= 11 && mod100 <= 14 {
                word = "попыток"
            } else if mod10 == 1 {
                word = "попытка"
            } else if (2...4).contains(mod10) {
                word = "попытки"
            } else {
                word = "попыток"
            }
            return "\(count) \(word)"
        } else {
            return count == 1 ? "1 attempt" : "\(count) attempts"
        }
    }

    // MARK: - Sign-in prompt sheet

    static func signInPromptReact(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите, чтобы реагировать" : "Sign in to react"
    }
    static func signInPromptFollow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите, чтобы подписаться" : "Sign in to follow"
    }
    static func signInPromptShare(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите, чтобы поделиться" : "Sign in to share"
    }
    static func signInPromptSync(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите для синхронизации" : "Sign in to sync"
    }
    static func signInPromptPublish(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите, чтобы опубликовать" : "Sign in to publish"
    }
    static func signInPromptGeneric(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите в TripTrack" : "Sign in to TripTrack"
    }
    static func signInPromptSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Реакции, подписки и публикация — после входа. Ваши поездки остаются на устройстве."
            : "Reactions, follows and publishing — after you sign in. Your trips stay on your device."
    }
    static func signInLoading(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Входим…" : "Signing in…"
    }
    static func signInErrorRetry(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось войти. Попробуйте ещё раз." : "Couldn't sign in. Please try again."
    }
    /// Legal footnote with a tappable Markdown link on the last word.
    static func signInLegalMarkdown(_ lang: LanguageManager.Language, termsURL: String) -> String {
        lang == .ru
            ? "Продолжая, Вы соглашаетесь с [условиями](\(termsURL))"
            : "By continuing, you agree to the [terms](\(termsURL))"
    }
    static func signInPromptAppleFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Apple-вход не сработал. Проверьте, что Вы залогинены в iCloud в настройках устройства."
            : "Apple sign-in failed. Make sure you're signed into iCloud in device Settings."
    }
    static func signInFailedTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось войти" : "Sign in failed"
    }
    static func ok(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ОК" : "OK"
    }

    // MARK: - Guest mode banners / CTAs

    static func guestFeedBanner(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите чтобы подписываться и реагировать" : "Sign in to follow and react"
    }
    static func syncCardKicker(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "СИНХРОНИЗАЦИЯ" : "SYNC"
    }
    static func syncCardTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездки на всех устройствах" : "Your trips on every device"
    }
    static func syncCardBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Войдите, чтобы открыть свою историю на других устройствах. Все поездки уже здесь."
            : "Sign in to see your history on your other devices. All your trips are already here."
    }
    static func syncCardLater(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Можно позже — ничего не потеряется" : "You can do it later — nothing gets lost"
    }
    static func signInWithApple(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войти" : "Sign in"
    }

    // MARK: - Entity / action labels (used by sync status sheet)

    static func entityLabel(_ type: String, _ lang: LanguageManager.Language) -> String {
        switch type {
        case "trip":     return lang == .ru ? "Поездка" : "Trip"
        case "vehicle":  return lang == .ru ? "Машина" : "Vehicle"
        case "photo":    return lang == .ru ? "Фото" : "Photo"
        case "settings": return lang == .ru ? "Настройки" : "Settings"
        default:         return type.capitalized
        }
    }
    static func actionLabel(_ action: String, _ lang: LanguageManager.Language) -> String {
        switch action {
        case "upload": return lang == .ru ? "Загрузка" : "Upload"
        case "update": return lang == .ru ? "Обновление" : "Update"
        case "delete": return lang == .ru ? "Удаление" : "Delete"
        default:       return action.capitalized
        }
    }

    // MARK: - Garage (v6.1.0 redesign)

    static func vehicleMainLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Основная" : "Main"
    }
    static func myVehicle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Мой автомобиль" : "My Vehicle"
    }
    static func renameVehicle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Переименовать" : "Rename"
    }
    static func deleteVehicle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Удалить авто" : "Delete vehicle"
    }
    static func deleteVehicleConfirm(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Удалить это авто? Поездки сохранятся без привязки к нему."
            : "Delete this vehicle? Trips will keep their data without it."
    }
    static func makeMainVehicle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сделать основной" : "Make main"
    }
    static func odometerLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Одометр" : "Odometer"
    }
    static func avgConsumptionLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ср. расход" : "Avg. consumption"
    }
    static func stickersLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Стикеры" : "Stickers"
    }
    static func fuelSectionLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Расход топлива" : "Fuel consumption"
    }
    static func fuelCityRow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Расход в городе" : "City consumption"
    }
    static func fuelHighwayRow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Расход на трассе" : "Highway consumption"
    }
    static func fuelPriceRow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Цена топлива" : "Fuel price"
    }
    static func addVehicleTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавить автомобиль" : "Add vehicle"
    }
    static func vehicleNameSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Название" : "Name"
    }
    static func vehicleNamePlaceholder(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Например, Honda Civic" : "e.g. Honda Civic"
    }
    static func avatarSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Аватар" : "Avatar"
    }
    static func fuelCity(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Город" : "City"
    }
    static func fuelHighway(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Трасса" : "Highway"
    }
    static func mileageSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пробег" : "Mileage"
    }
    static func mileageAutoHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Начисляется автоматически по поездкам" : "Accrues automatically from your trips"
    }
    static func stereoSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Магнитола" : "Stereo"
    }
    static func btOffTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Bluetooth выключен" : "Bluetooth is off"
    }
    static func btOffChipBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Включите Bluetooth, чтобы запись стартовала по магнитоле."
            : "Turn on Bluetooth so recording can start from your stereo."
    }
    static func btOffSheetBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Включите Bluetooth в Настройках, чтобы найти магнитолу и привязать её к этому авто."
            : "Turn on Bluetooth in Settings to find your stereo and link it to this car."
    }
    static func settingsButton(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Настройки" : "Settings"
    }
    static func maxVehiclesHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Максимум 5 автомобилей" : "Maximum 5 vehicles"
    }
    static func unnamedVehicle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Без имени" : "Unnamed"
    }
    static func sinceYear(_ lang: LanguageManager.Language, year: Int) -> String {
        lang == .ru ? "с \(year)" : "since \(year)"
    }
}
