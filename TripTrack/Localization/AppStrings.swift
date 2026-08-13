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

    // MARK: - Groups (coming soon, Figma 117:2265)
    static func groupsComingTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Клубы — скоро" : "Clubs — coming soon"
    }
    static func groupsComingBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Сообщества по маркам и интересам: Miata, VAG, Dodge, дальнобой, оффроуд. Общие поездки и рейтинги."
            : "Communities by make and interest: Miata, VAG, Dodge, trucking, off-road. Group drives and leaderboards."
    }
    static func groupsNotifyMe(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Уведомить меня" : "Notify me"
    }
    /// The done state used to say «Вы в списке», which claims a server-side
    /// waitlist — the flag is a local @AppStorage bool with no endpoint
    /// behind it, so the copy now promises only what the app itself does.
    static func groupsNotifyDone(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Покажем, когда откроем" : "We'll show it when it opens"
    }
    static func groupsWaitlistCount(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Уже ждут 1 240 человек" : "1,240 people already waiting"
    }
    static func groupsChipTrucking(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "🛻 Дальнобой" : "🛻 Trucking"
    }
    static func groupsChipOffroad(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "🏔 Оффроуд" : "🏔 Off-road"
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

    /// Shown when a start is refused, so the slider never just springs back
    /// with nothing said.
    static func startRefusedRecovery(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Сначала закончите с прошлой поездкой"
            : "Finish with the previous trip first"
    }
    static func startRefusedNoGeo(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Нужен доступ к геолокации"
            : "Location access is required"
    }
    /// Deliberately vague, because the honest answer is that we do not know —
    /// and saying nothing is worse than saying that.
    static func startRefusedUnknown(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Не получилось начать запись — попробуйте ещё раз"
            : "Could not start recording — try again"
    }
    /// No fix yet. Starting here records a trip whose beginning is missing,
    /// so the control waits — and says what it is waiting for.
    static func startRefusedNoFix(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Ждём сигнал GPS — начало поездки не запишется"
            : "Waiting for GPS — the start of the trip would be lost"
    }
    /// The escape hatch: an underground car park may never give a fix, and
    /// refusing forever is worse than recording a trip that begins late.
    static func startAnyway(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Всё равно начать" : "Start anyway"
    }
    /// Label on the start control itself while there is no fix.
    static func slideWaitingForGPS(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ждём сигнал GPS" : "Waiting for GPS"
    }
    /// Before the first accepted fix. Distinct from «слабый» on purpose —
    /// waiting for satellites is normal and temporary, a weak signal is a
    /// problem, and showing the alarming one for the ordinary case made the
    /// whole screen look broken.
    static func gpsSearching(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ищем спутники" : "Finding GPS"
    }
    static func gpsLegendSearching(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Обычно пара секунд — под крышей дольше"
            : "Usually a couple of seconds — longer under cover"
    }
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
    static func pauseAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пауза" : "Pause"
    }
    static func resumeAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Продолжить" : "Resume"
    }
    /// Ending a recording cannot be undone — the trip closes and a later drive
    /// becomes a separate one. Worth one question.
    static func stopConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Завершить поездку?" : "Finish the trip?"
    }
    static func stopConfirmBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Продолжить эту же запись потом будет нельзя"
            : "You won't be able to continue this recording later"
    }
    static func stopConfirmAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Завершить и сохранить" : "Finish and save"
    }
    /// Offered inside the stop dialog — «стоп» at a petrol station usually
    /// means «wait», and that answer belongs next to the question.
    static func stopConfirmPause(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поставить на паузу" : "Pause instead"
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
    /// The canon's one-line toggle hint. It replaces the two-line
    /// subtitle-plus-footnote on the finish card: both said the same thing at
    /// different lengths, and neither said what the switch does in each
    /// position — which is the only thing you need at that moment.
    static func publishToggleHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Вкл — увидят все · выкл — только вы"
            : "On — everyone sees it · off — only you"
    }
    /// Placeholder on the finish card's inline description field.
    static func describeTripPlaceholder(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавить описание…" : "Add a description…"
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
    /// Feed-card metric label (Figma FeedCard 115:72 — «Ср. скор.», the
    /// full «Ср. скорость» overflows the third metric column at 11pt caps).
    static func avgSpeedShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ср. скор." : "Avg speed"
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
    /// Shown instead of «Разрешить» when the system permission is already
    /// granted — asking again would do nothing (iOS shows the prompt once),
    /// so the button has to say what it will actually do: move on.
    // Canon onboarding screens «Гео "Всегда"» and «Уведомления» — one ask
    // per screen, each explaining what breaks without it.
    static func onboardingBackgroundTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Запись в фоне" : "Recording in the background"
    }
    // This page's button also fires the Motion & Fitness prompt
    // (OnboardingView.requestAlwaysAndAdvance), and the copy named only
    // location — activity data was asked for with nothing disclosed about
    // it, so the sensor and its battery reason are spelled out here.
    static func onboardingBackgroundSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Чтобы поездки писались, когда телефон в кармане, нужен доступ к геолокации «Всегда» — с «При использовании» запись прервётся в фоне. Датчик движения («Движение и фитнес») помогает заметить начало поездки без постоянного GPS — так батарея расходуется меньше."
            : "For trips to keep recording with the phone in your pocket, location access must be «Always» — with «While Using» recording stops in the background. Motion & Fitness data lets the app spot a drive starting without keeping GPS on, so the battery lasts longer."
    }
    static func onboardingBackgroundAllow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разрешить «Всегда»" : "Allow «Always»"
    }
    static func onboardingNotificationsTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Будьте в курсе" : "Stay in the loop"
    }
    static func onboardingNotificationsSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Уведомления о реакциях, подписках и комментариях к вашим поездкам. Включите — и не пропустите отклик."
            : "Notifications about reactions, follows and comments on your trips. Turn them on so you don't miss the response."
    }
    static func onboardingNotificationsEnable(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Включить уведомления" : "Turn on notifications"
    }
    static func onboardingNotNow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не сейчас" : "Not now"
    }

    static func onboardingAlreadyGranted(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Доступ уже есть" : "Access already granted"
    }
    static func onboardingContinue(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Дальше" : "Continue"
    }
    static func onboardingSkipForNow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Позже" : "Not now"
    }

    static func onboardingAllow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разрешить" : "Allow"
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
    // citiesCount / regionsCountLabel deleted — zero callers, and their RU
    // plural forms were wrong («5 города»). Use proper plural helpers if a
    // caller ever appears.

    // MARK: - My Map (6.1.0)

    static func myMapTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Моя карта" : "My Map"
    }
    // The «Маршруты · Территория · Всё» segment is gone on purpose: the canon
    // note on the Карта page reads «Слоёв-переключателей нет» — territory and
    // trips share one layer, and depth comes from zoom instead.

    /// Collapsed sheet: «8 регионов · 12 890 км · 47 поездок».
    static func mapSummary(
        _ lang: LanguageManager.Language, regions: Int, km: Int, trips: Int
    ) -> String {
        let r = "\(groupedNumber(regions, lang)) \(regionsGenitive(lang, count: regions))"
        let k = "\(groupedNumber(km, lang)) \(lang == .ru ? "км" : "km")"
        let t = "\(groupedNumber(trips, lang)) \(tripsGenitive(lang, count: trips))"
        return "\(r) · \(k) · \(t)"
    }
    static func mapKmDriven(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км проехано" : "km driven"
    }
    /// «9 из 44» — the region's opened cities over its whole list.
    static func mapCitiesOfTotal(
        _ lang: LanguageManager.Language, opened: Int, total: Int
    ) -> String {
        "\(opened) \(lang == .ru ? "из" : "of") \(total)"
    }
    /// Progress bar over the region card — canon copy. The value beside it is
    /// real opened road in km; the bar itself is progress toward a stated
    /// per-region goal, since no road-network dataset exists to divide by.
    static func mapRoadsProgress(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Дороги края" : "Roads opened"
    }
    /// «84 км · 8%» — the kilometres first, because they are the honest part.
    static func mapRoadsValue(
        _ lang: LanguageManager.Language, km: Double, percent: String
    ) -> String {
        let value = km < 10
            ? String(format: "%.1f", km).replacingOccurrences(of: ".", with: lang == .ru ? "," : ".")
            : groupedNumber(Int(km.rounded()), lang)
        return "\(value) \(lang == .ru ? "км" : "km") · \(percent)"
    }
    static func mapPullHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Потяни вверх — города и поездки" : "Pull up — cities and trips"
    }
    static func mapCitiesSection(
        _ lang: LanguageManager.Language, opened: Int, total: Int
    ) -> String {
        let head = lang == .ru ? "ГОРОДА" : "CITIES"
        return "\(head) · \(mapCitiesOfTotal(lang, opened: opened, total: total))"
    }
    static func mapTripsSection(_ lang: LanguageManager.Language, count: Int) -> String {
        "\(lang == .ru ? "ПОЕЗДКИ ЗДЕСЬ" : "TRIPS HERE") · \(count)"
    }
    static func mapCityLocked(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "не открыт" : "not opened"
    }
    /// Section-header action. Short on purpose — it sits beside the heading,
    /// not on a line of its own at the bottom of the list.
    static func mapSeeAll(_ lang: LanguageManager.Language, count: Int) -> String {
        lang == .ru ? "Все \(count)" : "All \(count)"
    }
    static func mapOpenTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Открыть поездку" : "Open trip"
    }
    /// Tapping a road you have driven many times: every trip that used it.
    static func mapRoadTrips(_ lang: LanguageManager.Language, count: Int) -> String {
        lang == .ru
            ? "\(count) \(tripsGenitive(lang, count: count)) по этой дороге"
            : "\(count) trips on this road"
    }
    static func mapRoadPullHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Потяни вверх — все поездки" : "Pull up — all of them"
    }
    /// The map ships ahead of the rest — say so on the screen rather than
    /// leaving people to wonder whether what they see is a bug or the design.
    static func mapBetaBadge(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "БЕТА" : "BETA"
    }
    static func mapBetaTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Карта — бета" : "The map is in beta"
    }
    static func mapBetaBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Мы её ещё дорабатываем. Если что-то выглядит не так или работает странно — напишите нам, это правда помогает."
            : "We are still working on it. If something looks wrong or behaves oddly, tell us — it genuinely helps."
    }
    static func mapBetaReport(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Написать в Telegram" : "Message us on Telegram"
    }
    /// Endpoints of the selected route. Voice-over only — on screen they are
    /// the same green-start / white-finish dots the share poster uses.
    static func mapRouteStart(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Начало поездки" : "Trip start"
    }
    static func mapRouteFinish(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Конец поездки" : "Trip finish"
    }
    static func mapRegionLocked(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ещё не открыт" : "not opened yet"
    }
    /// «0 км · 0 поездок · 0 из 26 городов» — the zeroes are the point.
    static func mapLockedStats(_ lang: LanguageManager.Language, totalCities: Int) -> String {
        lang == .ru
            ? "0 км · 0 поездок · 0 из \(totalCities) городов"
            : "0 km · 0 trips · 0 of \(totalCities) cities"
    }
    /// «Ближайший твой след — 40 км западнее: Кропоткин, май 2026.
    /// Заедешь — регион загорится на карте.»
    static func mapLockedTeaser(
        _ lang: LanguageManager.Language, km: Int, bearing: String, city: String, when: String?
    ) -> String {
        let place = when.map { "\(city), \($0)" } ?? city
        return lang == .ru
            ? "Ближайший твой след — \(km) км \(bearing): \(place). Заедешь — регион загорится на карте."
            : "Your nearest trace — \(km) km \(bearing): \(place). Drive in and the region lights up."
    }
    static func mapBearing(
        _ lang: LanguageManager.Language, _ bearing: MyMapViewModel.NearestTrace.Bearing
    ) -> String {
        switch bearing {
        case .north: return lang == .ru ? "севернее" : "to the north"
        case .south: return lang == .ru ? "южнее" : "to the south"
        case .east:  return lang == .ru ? "восточнее" : "to the east"
        case .west:  return lang == .ru ? "западнее" : "to the west"
        }
    }
    /// «май 2026» / «May 2026».
    static func monthYear(_ lang: LanguageManager.Language, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == .ru ? "ru_RU" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date)
    }
    /// Locale-aware thousands grouping («12 890» in RU, «12,890» in EN).
    static func groupedNumber(_ value: Int, _ lang: LanguageManager.Language) -> String {
        let formatter = lang == .ru ? ruGrouping : enGrouping
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    private static let ruGrouping: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; return f
    }()
    private static let enGrouping: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","; return f
    }()
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
        lang == .ru ? "Движение" : "Movement"
    }
    static func movingDot(_ lang: LanguageManager.Language, _ value: String) -> String {
        lang == .ru ? "В движении · \(value)" : "Moving · \(value)"
    }
    /// «Стоянки» read as car parks. This is the time the trip was standing
    /// still — at lights, in traffic, waiting at a barrier — so it is named
    /// as the plain opposite of «В движении».
    static func stopsDot(_ lang: LanguageManager.Language, _ value: String) -> String {
        lang == .ru ? "Без движения · \(value)" : "Stopped · \(value)"
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
        lang == .ru ? "Без движения" : "Stopped"
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
    // levelShort deleted — the app-wide LVL convention is the hardcoded
    // "LVL n" pixel-font tag; the last caller migrated to it.

    // MARK: - Discussion (6.1.0)
    //
    // The product calls this ОБСУЖДЕНИЕ, not «комментарии» — a trip is a story
    // people talk about, and the word «комментарий» never appears in the UI.
    // The function names keep the old spelling so the diff stays readable.
    static func commentsTitleN(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "Обсуждение · \(n)" : "Discussion · \(n)"
    }
    static func commentPlaceholder(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Написать в обсуждение…" : "Write in the discussion…"
    }
    /// Centred pill under the teaser: «Всё обсуждение · 12 ›».
    static func discussionSeeAllPill(_ lang: LanguageManager.Language, _ n: Int) -> String {
        lang == .ru ? "Всё обсуждение · \(n)" : "Whole discussion · \(n)"
    }
    /// Zero state — the card stays, the invitation changes.
    static func writeFirstMessage(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Написать первое сообщение…" : "Write the first message…"
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
            : "What was the trip like? Roads, weather, stops…"
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
    /// Someone else's trip that has been taken out of the feed. Deliberately
    /// says what happened rather than «не удалось загрузить»: nothing failed,
    /// the author simply closed it, and offering «попробовать снова» for that
    /// is an invitation to retry something that will never change.
    /// The thread could not be read at all — as opposed to a thread that is
    /// simply empty. Saying «пока никто ничего не написал» over a heading that
    /// counts five messages is the app contradicting itself out loud.
    static func discussionUnavailable(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Не удалось загрузить обсуждение"
            : "Couldn't load the discussion"
    }
    /// A thread kept on the device after the trip left the server.
    /// Companions shown from the device's copy of a trip the server no longer
    /// holds. No «повторить» beside it — there is nothing to retry against.
    static func companionsSavedCopy(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Сохранено на устройстве — поездка не на сервере"
            : "Saved on this device — the trip is not on the server"
    }
    static func discussionArchived(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Сохранённая копия обсуждения — поездка больше не на сервере"
            : "A saved copy — this trip is no longer on the server"
    }
    static func tripPrivateTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка закрыта" : "This trip is private"
    }
    static func tripPrivateBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Автор сделал её приватной — теперь её видит только он."
            : "The author made it private — only they can see it now."
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
    /// Canon 510:119 — saving the share card needs somewhere to save it to.
    static func photoAccessAlertTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разрешите доступ к Фото" : "Allow access to Photos"
    }
    static func photoAccessAlertBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Чтобы сохранить карточку поездки в Фото, откройте доступ в Настройках."
            : "To save the trip card to Photos, allow access in Settings."
    }
    static func close(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Закрыть" : "Close"
    }
    /// «Получен 14 мая 2026 · Дача и обратно» (Figma 117:1582). The trip is
    /// what makes the date mean anything, so it joins the line when we know it.
    /// The tail of «Получено 15 раз · последний 9 августа 2026» — lowercase
    /// on purpose, it continues a sentence rather than starting one.
    static func badgeLastEarned(_ lang: LanguageManager.Language, date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang == .ru ? "ru_RU" : "en_US")
        f.dateFormat = "d MMMM yyyy"
        return lang == .ru
            ? "последний \(f.string(from: date))"
            : "last on \(f.string(from: date))"
    }
    static func badgeEarnedOn(
        _ lang: LanguageManager.Language,
        date: Date,
        tripTitle: String?
    ) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: lang == .ru ? "ru_RU" : "en_US")
        f.dateFormat = lang == .ru ? "d MMMM yyyy" : "d MMMM yyyy"
        let prefix = lang == .ru ? "Получен" : "Earned"
        var line = "\(prefix) \(f.string(from: date))"
        if let tripTitle, !tripTitle.isEmpty {
            line += " · \(tripTitle)"
        }
        return line
    }
    static func noCommentsYet(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пока никто ничего не написал." : "Nobody has written anything yet."
    }
    static func addReaction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поставить реакцию" : "Add a reaction"
    }

    // MARK: - Locked social sections on a private trip (Figma 545:499)

    static func publishForReactionsTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Опубликуйте, чтобы получить реакции" : "Publish to get reactions"
    }
    static func publishForReactionsBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Появятся, когда поездка станет публичной"
            : "They appear once the trip is public"
    }
    static func publishForCommentsTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Опубликуйте, чтобы открыть обсуждение" : "Publish to open the discussion"
    }
    static func publishForCommentsBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Обсуждение доступно на публичных поездках"
            : "The discussion lives on public trips"
    }

    // MARK: - Photo picker (Figma 117:587)

    static func choosePhotosTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Выберите фото" : "Choose photos"
    }
    static func managePhotoAccess(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Показать больше фото…" : "Show more photos…"
    }
    static func noPhotosInLibrary(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "В медиатеке нет фотографий" : "No photos in your library"
    }
    static func photoAccessDenied(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Нет доступа к фотографиям. Разрешите его в Настройках, чтобы добавить снимки к поездке."
            : "No access to photos. Allow it in Settings to attach photos to a trip."
    }

    /// Where along the route a chart sample sits: «212-й км» / «km 212».
    static func chartKmMark(_ lang: LanguageManager.Language, km: Double) -> String {
        let n = max(0, Int(km.rounded()))
        return lang == .ru ? "\(n)-й км" : "km \(n)"
    }

    // MARK: - Trip edit sheet (Figma 543:119)

    static func editTripTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Редактировать поездку" : "Edit trip"
    }
    static func tripTitleLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Название" : "Name"
    }
    static func vehicleSectionLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Машина" : "Car"
    }
    static func accessSectionLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Доступ" : "Access"
    }
    /// Under the access row: what the current state actually means, since
    /// «Видна всем» and «Только вы» each describe half of it.
    static func privacyPublicHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Публичная — в общей ленте" : "Public — in the shared feed"
    }
    static func privacyOnlyMeHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Приватная — видите только вы" : "Private — only you can see it"
    }

    /// A trip too short to be worth keeping was deleted on stop. Saying so is
    /// the whole point: the alternative is a recording that silently
    /// evaporates, which reads as data loss rather than as housekeeping.
    static func junkTripDiscarded(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Поездка не сохранена — слишком короткая"
            : "Trip not saved — too short"
    }
    static func notifAutoStartFailedTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Запись не началась" : "Recording didn't start"
    }
    /// Names the obstacle when we know it — «что-то пошло не так» is useless
    /// standing at the car, while «нет доступа к геолокации» can be acted on.
    static func notifAutoStartFailedBody(
        _ lang: LanguageManager.Language,
        reason: MapViewModel.StartRefusal?
    ) -> String {
        switch reason {
        case .locationDenied:
            return lang == .ru
                ? "Нет доступа к геолокации — включите его в Настройках"
                : "No location access — turn it on in Settings"
        case .recoveryPending:
            return lang == .ru
                ? "Сначала завершите прошлую поездку — откройте приложение"
                : "Finish the previous trip first — open the app"
        case .noFix, .unknown, .none:
            return lang == .ru
                ? "Откройте приложение и начните поездку вручную"
                : "Open the app and start the trip manually"
        }
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
    static func signInPromptCompanions(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войдите, чтобы звать попутчиков" : "Sign in to invite companions"
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
        lang == .ru ? "Войдите, чтобы подписываться и реагировать" : "Sign in to follow and react"
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
    /// Apple's official SIWA wording (App Review requires it on custom
    /// HIG-styled buttons — AppleSignInButton renders this).
    static func signInWithApple(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войти через Apple" : "Sign in with Apple"
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

    // MARK: - Home feed (6.1.0)
    static func feedSegmentFollowing(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Подписки" : "Following"
    }
    static func followingEmptyTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пока тихо" : "Quiet for now"
    }
    static func followingEmptyBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Подпишитесь на людей, и их поездки появятся здесь."
            : "Follow people and their trips will show up here."
    }
    static func followingGuestTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Лента подписок" : "Your following feed"
    }
    static func followingGuestBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Войдите, чтобы подписываться на людей и видеть их поездки здесь."
            : "Sign in to follow people and see their trips here."
    }
    static func feedEmptyTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Здесь появятся маршруты" : "Routes will show up here"
    }
    static func feedEmptyBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Опубликуйте первую поездку или найдите тех, за кем интересно следить."
            : "Publish your first trip or find people worth following."
    }
    static func findPeople(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Найти людей" : "Find people"
    }
    /// Short time units for the feed-card metric runs («4 ч 58 мин»).
    static func hoursUnitShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ч" : "h"
    }
    static func minutesUnitShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "мин" : "min"
    }
    /// Section title and accessibility label for the discussion.
    static func comments(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Обсуждение" : "Discussion"
    }

    // MARK: - Activity inbox (6.1.0)
    static func activityTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Активность" : "Activity"
    }
    static func chipReactions(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Реакции" : "Reactions"
    }
    static func chipFollows(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Подписки" : "Follows"
    }
    static func chipComments(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Комменты" : "Comments"
    }
    /// Chip filter label for `achievement` rows.
    static func chipAchievements(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Достижения" : "Achievements"
    }
    static func today(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сегодня" : "Today"
    }
    static func earlier(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ранее" : "Earlier"
    }
    static func noFilteredNotifications(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Таких уведомлений пока нет" : "No such notifications yet"
    }
    // MARK: - Activity rows (6.1.0)

    /// Second line of a reaction row: what happened, to what. The reaction
    /// itself is drawn as a badge on the avatar, so it is not repeated here.
    static func activityReactedTo(_ lang: LanguageManager.Language, _ trip: String) -> String {
        lang == .ru ? "отреагировал на «\(trip)»" : "reacted to “\(trip)”"
    }
    static func activityFollowedYou(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "подписался на Вас" : "started following you"
    }
    /// With the comment text when the server sent it, otherwise the trip.
    static func activityCommented(_ lang: LanguageManager.Language, text: String?, trip: String) -> String {
        if let text, !text.isEmpty {
            return lang == .ru ? "прокомментировал: «\(text)»" : "commented: “\(text)”"
        }
        return lang == .ru ? "прокомментировал «\(trip)»" : "commented on “\(trip)”"
    }
    /// Fallback object when a trip has no title of its own.
    static func activityYourTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Вашу поездку" : "your trip"
    }

    // MARK: - Achievement rows (6.1.0)

    /// Line one of a system-authored `achievement` row. Nobody did this TO
    /// the user, so the name slot is signed by the app rather than falling
    /// back to «Кто-то» the way an actor-less row otherwise would. A brand
    /// name, hence untranslated and language-free — it lives here anyway so
    /// the row keeps every string it draws in one place.
    static let activityAchievementActor = "TripTrack"
    /// Line two when the badge resolved to a known `Badge.all` entry.
    static func activityAchievementUnlocked(
        _ lang: LanguageManager.Language, badge: String
    ) -> String {
        lang == .ru ? "Открыто достижение «\(badge)»" : "Achievement unlocked: “\(badge)”"
    }
    /// Line two when the badge didn't resolve — an id this build doesn't
    /// know yet, or a server that names the badge some other way. Still a
    /// true, readable sentence instead of an empty row.
    static func activityAchievementUnlockedGeneric(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Открыто новое достижение" : "New achievement unlocked"
    }

    static func followBack(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "В ответ" : "Follow back"
    }

    // MARK: - Notification preferences — companions toggle (Fix 6)

    /// `NotificationPreferencesView`'s companions row — title/subtitle,
    /// same shape as its reactions/follows/comments/weekly-recap siblings.
    static func notifyCompanionsTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Попутчики" : "Companions"
    }
    static func notifyCompanionsSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Когда вас позовут в поездку или кто-то присоединится к вашей"
            : "When you're invited on a trip or someone joins yours"
    }

    // MARK: - Companion invite rows (6.1.0)

    /// Chip filter label for `companion_invite` / `companion_accepted` rows.
    static func chipCompanions(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Попутчики" : "Companions"
    }
    /// Decision-row header line — the invite verb, no trip specifics (those
    /// live in the trip-shape line below it, once the preview loads).
    static func companionInviteAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "пригласил вас в поездку" : "invited you on a trip"
    }
    /// `companion_accepted` action line — the OWNER's row: someone joined.
    static func companionAcceptedAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "присоединился к вашей поездке" : "joined your trip"
    }
    /// Post-response note replacing the decision controls once the
    /// invitee has accepted this session (or the server already has it
    /// on record).
    static func companionInviteAcceptedNote(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Вы приняли приглашение" : "You accepted the invite"
    }
    static func companionInviteDeclinedNote(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Вы отклонили приглашение" : "You declined the invite"
    }
    static func companionAccept(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Принять" : "Accept"
    }
    static func companionDecline(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Отклонить" : "Decline"
    }
    static func companionRespondFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось ответить на приглашение" : "Couldn't respond to the invite"
    }
    static func companionInvitePreviewFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось загрузить приглашение" : "Couldn't load the invite"
    }
    /// Shown when an accepted invite's trip can't be resolved yet from the
    /// companion trips cache (see `NotificationsInboxView.openAcceptedInviteTrip`).
    static func companionTripUnavailable(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка пока недоступна" : "Trip isn't available yet"
    }
    /// Fix 2: an invite whose `/companions/invite-preview` fetch confirms
    /// there is no longer a live PENDING row to answer — most commonly
    /// because it was already accepted or declined on ANOTHER device.
    /// Deliberately neutral about which way it went (the client has no
    /// local record of the actual outcome in this case), unlike
    /// `companionInviteAcceptedNote`/`companionInviteDeclinedNote` above.
    static func companionInviteUnavailableNote(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Приглашение больше не активно" : "This invite is no longer active"
    }

    // MARK: - Discover (6.1.0)
    static func suggestedByRegions(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Рекомендуем · по Вашим регионам" : "Suggested · based on your regions"
    }

    /// Rationale line of a suggested-person row (Figma 117:291). The server
    /// sends a machine key, these are its only renderings — an unknown key
    /// draws no line at all (see `SuggestionMatchReason`).
    static func suggestReasonSharedRegion(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ездит в Ваших краях" : "Drives in your regions"
    }
    static func suggestReasonNearby(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Рядом с Вами" : "Near you"
    }
    static func suggestReasonPopular(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Популярный водитель" : "Popular driver"
    }

    // MARK: - Share sheet / report (6.1.0)
    static func copyAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Копировать" : "Copy"
    }
    static func reportAnonymousNote(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Жалобы анонимны — автор не узнает, кто их отправил."
            : "Reports are anonymous — the author won't know who sent them."
    }

    // MARK: - Account & Sync page (6.1.0 Figma frames 1–3)
    // Category rows of the sync sheet reuse existing keys:
    // tripsTab («Поездки»), photos («Фото»), profile («Профиль»), garage («Гараж»).

    static func accountSyncTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Аккаунт и синхронизация" : "Account & Sync"
    }
    static func accountAppleIdLine(_ lang: LanguageManager.Language, email: String) -> String {
        "Apple ID · \(email)"
    }
    static func accountAppleIdOnly(_ lang: LanguageManager.Language) -> String {
        "Apple ID"
    }
    static func sectionSyncLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Синхронизация" : "Sync"
    }
    /// F6: deliberately NOT «iCloud-синхронизация» — sync is the TripTrack EU
    /// server + R2 (per the shipped GDPR consent copy), "iCloud" would be
    /// legally misleading.
    static func cloudSyncTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Облачная синхронизация" : "Cloud sync"
    }
    static func syncUpdatedAgo(_ lang: LanguageManager.Language, _ relative: String) -> String {
        lang == .ru ? "Обновлено \(relative)" : "Updated \(relative)"
    }
    /// F13 fallback subtitle when there is no lastSyncedAt for the account.
    static func syncStateOn(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Включена" : "On"
    }
    static func syncStateOff(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Выключена" : "Off"
    }
    static func syncPerItemStatus(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Статус по объектам" : "Per-item status"
    }
    static func syncAllDone(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Всё синхронизировано" : "All synced"
    }
    /// Status-row value: sync globally OFF but the queue still holds ops for
    /// explicitly-public trips — this state must remain reachable (edge #3).
    static func syncOffPublishing(_ lang: LanguageManager.Language, count: Int) -> String {
        lang == .ru ? "Выключено · публикация: \(count)" : "Off · publishing: \(count)"
    }
    static func syncOffState(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Выключено" : "Disabled"
    }
    static func syncingProgress(_ lang: LanguageManager.Language, done: Int, total: Int) -> String {
        lang == .ru ? "Синхронизация… \(done)/\(total)" : "Syncing… \(done)/\(total)"
    }
    static func syncingNow(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Синхронизация…" : "Syncing…"
    }
    static func syncQueuedCount(_ lang: LanguageManager.Language, count: Int) -> String {
        lang == .ru ? "В очереди: \(count)" : "Pending: \(count)"
    }
    static func sectionPrivacyLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Приватность" : "Privacy"
    }
    static func publicProfileTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Публичный профиль" : "Public profile"
    }
    static func publicProfileSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Новые поездки приватны по умолчанию" : "New trips are private by default"
    }
    static func blockedUsersShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Заблокированные" : "Blocked"
    }
    static func sectionAccountLabel(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Аккаунт" : "Account"
    }
    static func signOutSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездки останутся на устройстве" : "Trips stay on this device"
    }
    static func clearServerTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Очистить данные на сервере" : "Clear server data"
    }
    static func clearServerSubtitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Удалить поездки с сервера, оставить на устройстве"
            : "Remove trips from the server, keep them on device"
    }
    static func clearServerInProgress(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Очищаем…" : "Clearing…"
    }
    // Migrated verbatim from the pre-6.1.0 CloudSyncView inline strings —
    // the GDPR just-in-time consent alert (F12: confirmation flows survive).
    static func syncEnableConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Включить синхронизацию?" : "Turn on cloud sync?"
    }
    static func syncEnableConfirmBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Ваши поездки, фото (с удалёнными метаданными), автомобили и настройки будут загружены на наш сервер в ЕС и доступны на других Ваших устройствах. Вы можете отключить в любой момент. Подробнее — в Политике конфиденциальности."
            : "Your trips, photos (with metadata stripped), vehicles, and settings will be uploaded to our EU server so you can access them on your other devices. You can turn this off anytime. See our Privacy Policy for details."
    }
    static func syncEnableConfirmAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Включить" : "Turn on"
    }
    // Migrated verbatim: wipe-server confirmation.
    static func wipeServerConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Очистить данные с сервера?" : "Clear server data?"
    }
    static func wipeServerConfirmBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Все Ваши поездки и фото будут удалены с сервера. Локальные данные сохранятся, Вы останетесь в аккаунте.\n\nСинхронизация будет выключена — Вы сможете включить её снова, когда захотите."
            : "All your trips and photos will be removed from the server. Local data stays on this device, your account is preserved.\n\nCloud sync will be turned off — you can re-enable it anytime."
    }
    static func wipeServerConfirmAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Очистить" : "Clear"
    }
    // Migrated verbatim: 3-way public-trips sign-out dialog.
    static func signOutPublishedTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "У Вас есть публичные поездки" : "You have public trips"
    }
    static func signOutHidePublic(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Скрыть публичные и выйти" : "Hide public and sign out"
    }
    static func signOutKeepPublic(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Выйти, оставить публичные в ленте" : "Sign out, leave public in feed"
    }
    // Sync sheet (frame 2).
    static func syncSheetTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Синхронизация" : "Sync"
    }
    static func syncLastAt(_ lang: LanguageManager.Language, _ relative: String) -> String {
        lang == .ru ? "Последняя синхронизация: \(relative)" : "Last sync: \(relative)"
    }
    static func syncFailedCount(_ lang: LanguageManager.Language, count: Int) -> String {
        lang == .ru ? "Ошибки: \(count)" : "Failed: \(count)"
    }
    // Logs journal (frame 3).
    static func logsJournalTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Журнал" : "Log"
    }
    static func logsSendCTA(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Отправить логи разработчику" : "Send logs to developer"
    }
    static func logsShareFile(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поделиться файлом" : "Share file"
    }
    /// F7: truthful caption — the export header embeds account_id and log
    /// lines may contain trip metadata, so no "no personal data" claims.
    static func logsPrivacyCaption(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Логи помогают чинить баги. Перед отправкой файл можно просмотреть."
            : "Logs help us fix bugs. You can review the file before sending."
    }
    static func logsEmpty(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Записей пока нет" : "No entries yet"
    }
    static func logsLoadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось прочитать журнал" : "Couldn't read the log"
    }
    // Blocked list.
    static func blockedSince(_ lang: LanguageManager.Language, _ date: String) -> String {
        lang == .ru ? "Заблокирован \(date)" : "Blocked \(date)"
    }

    // MARK: - Me tab (6.1.0)

    static func meGuestName(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Вы" : "You"
    }
    static func wrappedKicker(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ИТОГИ ГОДА" : "YEAR IN REVIEW"
    }
    static func wrappedHeroTitle(_ lang: LanguageManager.Language, year: Int) -> String {
        lang == .ru ? "Ваш \(year)\nна дорогах" : "Your \(year)\non the road"
    }
    static func wrappedWatch(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Смотреть" : "Watch"
    }
    static func momentsSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Моменты" : "Moments"
    }
    static func historySection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "История" : "History"
    }
    static func momentYearAgo(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Год назад в этот день" : "A year ago today"
    }
    static func momentLongest(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Самая длинная поездка" : "Longest trip"
    }
    static func momentNewRegion(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Новый регион" : "New region"
    }
    /// Gender-neutral phrasing — region names are any gender («Пермский
    /// край», «Москва», «Приморье»), a participle can't agree with all.
    static func momentRegionOpened(_ lang: LanguageManager.Language, name: String) -> String {
        lang == .ru ? "Теперь на карте: \(name) 🗺" : "\(name) unlocked 🗺"
    }
    static func statsKmTotal(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км всего" : "km total"
    }
    static func statsRegions(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "регионов" : "regions"
    }
    static func statsHours(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ч в пути" : "h driving"
    }
    static func statsKmByMonth(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Километры по месяцам" : "Kilometers by month"
    }
    static func statsRecords(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "РЕКОРДЫ" : "RECORDS"
    }
    static func recordLongest(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Самая длинная" : "Longest"
    }
    static func recordLongestDay(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Дольше всего" : "Longest day"
    }
    static func recordPerDay(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "за один день" : "in one day"
    }
    static func recordStreak(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Лучшая серия" : "Best streak"
    }
    static func recordStreakSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "подряд" : "in a row"
    }
    /// «N дней» with proper RU plural agreement (день / дня / дней).
    static func daysCount(_ lang: LanguageManager.Language, n: Int) -> String {
        if lang == .ru {
            let mod10 = n % 10, mod100 = n % 100
            let word: String
            if mod100 >= 11 && mod100 <= 14 { word = "дней" }
            else if mod10 == 1 { word = "день" }
            else if (2...4).contains(mod10) { word = "дня" }
            else { word = "дней" }
            return "\(n) \(word)"
        }
        return n == 1 ? "1 day" : "\(n) days"
    }
    /// «N поездок» with proper RU plural agreement (поездка / поездки / поездок).
    static func tripsCount(_ lang: LanguageManager.Language, n: Int) -> String {
        if lang == .ru {
            let mod10 = n % 10, mod100 = n % 100
            let word: String
            if mod100 >= 11 && mod100 <= 14 { word = "поездок" }
            else if mod10 == 1 { word = "поездка" }
            else if (2...4).contains(mod10) { word = "поездки" }
            else { word = "поездок" }
            return "\(n) \(word)"
        }
        return n == 1 ? "1 trip" : "\(n) trips"
    }
    static func statsEmptyTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пока нет статистики" : "No stats yet"
    }
    static func statsEmptyBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Запишите первую поездку — и здесь появятся километры, рекорды и графики по месяцам."
            : "Record your first trip — kilometers, records and monthly charts will show up here."
    }
    static func recordTripCta(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Записать поездку" : "Record a trip"
    }
    static func settingsTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Настройки" : "Settings"
    }
    /// Globe opt-in row. Deliberately NOT «Публичный профиль» — that exact
    /// label already names the account-visibility toggle in CloudSyncView
    /// (auth.isPublic); two same-named toggles with different semantics
    /// would be a privacy-misleading collision.
    static func settingsPublicProfile(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездки на глобальной карте" : "Trips on the global map"
    }
    static func settingsNotifications(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Уведомления" : "Notifications"
    }
    static func settingsInbox(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Входящие" : "Inbox"
    }
    static func settingsUnits(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Единицы" : "Units"
    }
    static func themeSystem(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Системная" : "System"
    }
    static func settingsAvgSpeed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Средняя скорость" : "Average speed"
    }
    static func settingsAccountSync(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Аккаунт и синхронизация" : "Account & sync"
    }
    static func settingsShareProfile(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поделиться профилем" : "Share profile"
    }
    static func settingsSendLogs(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Отправить логи" : "Send debug logs"
    }
    static func settingsProfileBackground(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Фон профиля" : "Profile background"
    }
    static func rankProgressTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Уровень водителя" : "Driver level"
    }
    static func awards(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Награды" : "Awards"
    }
    static func nameEditorTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Имя" : "Name"
    }
    static func nameHelper(_ lang: LanguageManager.Language, max: Int) -> String {
        lang == .ru
            ? "Так Вас увидят в ленте и профиле. До \(max) символов."
            : "This is how you'll appear in the feed and profile. Up to \(max) characters."
    }
    /// «342 подписчика» with RU plural agreement (подписчик / подписчика / подписчиков).
    static func followersCount(_ lang: LanguageManager.Language, n: Int) -> String {
        if lang == .ru {
            let mod10 = n % 10, mod100 = n % 100
            let word: String
            if mod100 >= 11 && mod100 <= 14 { word = "подписчиков" }
            else if mod10 == 1 { word = "подписчик" }
            else if (2...4).contains(mod10) { word = "подписчика" }
            else { word = "подписчиков" }
            return "\(n) \(word)"
        }
        return n == 1 ? "1 follower" : "\(n) followers"
    }
    /// «128 подписок» with RU plural agreement (подписка / подписки / подписок).
    static func followingCountLabel(_ lang: LanguageManager.Language, n: Int) -> String {
        if lang == .ru {
            let mod10 = n % 10, mod100 = n % 100
            let word: String
            if mod100 >= 11 && mod100 <= 14 { word = "подписок" }
            else if mod10 == 1 { word = "подписка" }
            else if (2...4).contains(mod10) { word = "подписки" }
            else { word = "подписок" }
            return "\(n) \(word)"
        }
        return "\(n) following"
    }
    static func followDepthNote(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Глубина списка ограничена 3 уровнями связей"
            : "List depth is limited to 3 levels of connections"
    }
    static func wrappedKmYear(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км за год" : "km this year"
    }
    static func wrappedBestDay(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "лучший день" : "best day"
    }
    static func wrappedTopRegion(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "топ-регион" : "top region"
    }
    static func wrappedShareText(_ lang: LanguageManager.Language, year: Int, km: String, trips: Int) -> String {
        lang == .ru
            ? "Мой \(year) на дорогах: \(tripsCount(lang, n: trips)), \(km) км — TripTrack"
            : "My \(year) on the road: \(tripsCount(lang, n: trips)), \(km) km — TripTrack"
    }

    // MARK: - Audit-fix additions (6.1.0 post-release pass)

    /// «14 дней подряд» / "14 day streak" — trip-complete streak row.
    static func streakDaysInARow(_ lang: LanguageManager.Language, n: Int) -> String {
        lang == .ru ? "\(daysCount(lang, n: n)) подряд" : "\(n) day streak"
    }
    static func repeatRouteTimes(_ lang: LanguageManager.Language, n: Int) -> String {
        if lang == .ru {
            let m10 = n % 10, m100 = n % 100
            let word = (11...14).contains(m100) ? "раз" : ((2...4).contains(m10) ? "раза" : "раз")
            return "Вы проехали этот маршрут уже \(n) \(word)"
        }
        return n == 1 ? "You've driven this route once" : "You've driven this route \(n) times"
    }
    /// «Без авто» — shorter than noVehicle's «Без машины» (idle-HUD chip).
    static func noVehicleShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Без авто" : "No vehicle"
    }
    static func moreActions(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ещё" : "More"
    }
    static func openRouteMapA11y(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Открыть карту маршрута" : "Open route map"
    }
    /// VoiceOver HINT (verb phrase) for the poster title button.
    static func editTitleA11y(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Изменяет название поездки" : "Edits the trip title"
    }
    static func blockedListLoadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось загрузить список" : "Couldn't load the list"
    }
    /// Caption WITHOUT the number — the counter renders it separately.
    static func followersCaption(_ lang: LanguageManager.Language, n: Int) -> String {
        if lang == .ru {
            let m10 = n % 10, m100 = n % 100
            if (11...14).contains(m100) { return "подписчиков" }
            if m10 == 1 { return "подписчик" }
            if (2...4).contains(m10) { return "подписчика" }
            return "подписчиков"
        }
        return n == 1 ? "follower" : "followers"
    }
    static func followingCaption(_ lang: LanguageManager.Language, n: Int) -> String {
        if lang == .ru {
            let m10 = n % 10, m100 = n % 100
            if (11...14).contains(m100) { return "подписок" }
            if m10 == 1 { return "подписка" }
            if (2...4).contains(m10) { return "подписки" }
            return "подписок"
        }
        return "following"
    }
    // MARK: - Share sheet (6.1.0)

    // MARK: - Comment replies (6.1.0)

    /// Owner «…» entries on a feed card (canon).
    static func edit(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Редактировать" : "Edit"
    }
    static func makePrivateAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сделать приватной" : "Make private"
    }

    // Canon alert copy (Figma «Лента · Алерт · точно приватной? / точно
    // удалить?»): plain question, one line of consequence, «Нет» / «Да, …».
    // Undo toasts after the alert (canon «после "Да" в алерте»).
    static func tripHiddenToast(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка скрыта из ленты" : "Trip hidden from the feed"
    }
    static func tripDeletedToast(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поездка удалена" : "Trip deleted"
    }
    static func undoAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Отменить" : "Undo"
    }

    static func hideFromFeedAlertTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Точно скрыть из ленты?" : "Hide from the feed?"
    }
    static func hideFromFeedAlertBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Поездка останется только в вашем дневнике."
            : "The trip stays in your own diary only."
    }
    static func hideFromFeedAlertConfirm(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Да, скрыть" : "Yes, hide"
    }
    static func deleteTripAlertTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Точно удалить поездку?" : "Delete this trip?"
    }
    static func deleteTripAlertBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Маршрут, фото и статистика исчезнут из вашего дневника."
            : "Its route, photos and stats disappear from your diary."
    }
    static func deleteTripAlertConfirm(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Да, удалить" : "Yes, delete"
    }
    static func no(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Нет" : "No"
    }

    static func makePrivateConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Сделать поездку приватной?" : "Make this trip private?"
    }
    static func makePrivateConfirmBody(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Она исчезнет из общей ленты, а реакции и комментарии к ней больше никто не увидит. Вернуть публичной можно в любой момент."
            : "It leaves the public feed, and its reactions and comments go with it. You can publish it again any time."
    }

    /// Header link on the detail preview → full thread.
    static func commentsSeeAll(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Все" : "All"
    }
    static func commentReply(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ответить" : "Reply"
    }
    static func commentReplyingTo(_ lang: LanguageManager.Language, _ name: String) -> String {
        lang == .ru ? "В ответ \(name)" : "Replying to \(name)"
    }

    /// Short sign-in label for chrome (feed header pill, guest states).
    static func signInShort(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Войти" : "Sign in"
    }

    static func shareTripTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поделиться поездкой" : "Share trip"
    }
    /// Sits under the preview: says what the card is FOR, so the formats
    /// above it read as choices rather than settings.
    static func shareCardCaption(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Готовая карточка — в чат, пост или сторис"
            : "Ready-made card — for a chat, a post or a story"
    }
    static func shareCopyLink(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Копировать" : "Copy"
    }

    /// VoiceOver label for the circular close button on sheet headers.
    static func closeSheet(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Закрыть" : "Close"
    }
    static func reportProfileAction(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пожаловаться" : "Report"
    }
    /// «…» menu entry on a public profile — toggles with the block state.
    static func blockProfileAction(
        _ lang: LanguageManager.Language, isBlocked: Bool
    ) -> String {
        if isBlocked { return lang == .ru ? "Разблокировать" : "Unblock" }
        return lang == .ru ? "Заблокировать" : "Block"
    }
    /// «…» menu entry on a public profile — puts the profile URL on the
    /// pasteboard. The share row above it reuses `settingsShareProfile`.
    static func copyProfileLink(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Скопировать ссылку" : "Copy link"
    }
    /// Toast that answers the copy — the pasteboard itself says nothing.
    static func profileLinkCopied(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ссылка скопирована" : "Link copied"
    }
    /// Comment-create throttle (10/min server-side).
    static func commentRateLimited(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Слишком много комментариев — подождите минуту"
            : "Too many comments — wait a minute"
    }

    // MARK: - Companions

    static func companionsSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Попутчики" : "Companions"
    }
    static func companionsAddPrompt(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добавить попутчиков" : "Add companions"
    }
    static func companionsEmptyHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Кто ехал с вами?" : "Who rode with you?"
    }
    /// Fix 2: own trip, not yet on the server — the invite row is shown
    /// disabled (not a button) with this hint instead of the ordinary
    /// `companionsEmptyHint`, because inviting isn't possible yet either.
    static func companionsPublishFirstHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Чтобы звать попутчиков, сначала опубликуйте поездку"
            : "Publish the trip first to invite companions"
    }
    /// The OTHER reason the invite row can't act yet, and the one that used
    /// to be misreported as `companionsPublishFirstHint`: a signed-out
    /// viewer on their own trip — which may well be published already, so
    /// telling them to publish it is both wrong and a dead end. Unlike the
    /// publish hint, this row IS tappable: it opens the sign-in sheet.
    static func companionsSignInHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Войдите, чтобы звать попутчиков"
            : "Sign in to invite companions"
    }
    /// «Позвать» — opens the (Task 3) candidate picker. Same word for both
    /// the empty-state row and the smaller CTA appended after an existing
    /// roster.
    static func companionsInvite(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Позвать" : "Invite"
    }
    /// The note a roster row carries while the invite is unanswered.
    static func companionsWaiting(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "ждёт" : "Pending"
    }
    /// Declined rows reach the OWNER's roster only. They used to be told
    /// apart by dimming alone, which says "different" without saying how —
    /// on the roster screen, where the owner goes specifically to see who
    /// answered what, the row says it outright.
    static func companionsDeclinedNote(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "отказался" : "Declined"
    }
    /// A companion with no display name — an account that never set one.
    static func companionsNoName(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Без имени" : "No name"
    }

    // MARK: - Companions summary plaque (trip detail)

    /// The plaque's second line when at least one companion accepted, on
    /// the viewer's OWN trip.
    static func companionsRodeWithYou(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ездили вместе с вами" : "Rode along with you"
    }
    /// Same line on someone else's trip — the viewer isn't the driver, so
    /// "с вами" would be a lie for a stranger and only accidentally true
    /// for a companion.
    static func companionsRodeTogether(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ездили вместе" : "Rode along"
    }
    /// The plaque's second line when NOBODY has accepted yet and the
    /// invites are still out.
    static func companionsAwaitingReply(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        if lang == .ru { return count == 1 ? "Ждём ответа" : "Ждём ответов" }
        return count == 1 ? "Waiting for a reply" : "Waiting for replies"
    }
    /// Appended after `companionsRodeWithYou` when some accepted and others
    /// haven't answered — the accepted names are what the plaque shows, so
    /// without this the pending invites would be invisible until the roster
    /// screen is opened.
    static func companionsPendingSuffix(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        if lang == .ru { return count == 1 ? "ещё один ждёт" : "ещё \(count) ждут" }
        return count == 1 ? "1 more pending" : "\(count) more pending"
    }
    /// The plaque's second line when every invite was declined — owner-only
    /// by construction (declined rows never leave the server for anyone
    /// else).
    static func companionsAllDeclined(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        if lang == .ru { return count == 1 ? "Отказался" : "Отказались" }
        return count == 1 ? "Declined the invite" : "Declined the invite"
    }
    /// Tail of the names line when more people are on the trip than the
    /// plaque spells out: «Аня К., Дмитрий П. и ещё 2».
    static func companionsAndMore(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        lang == .ru ? "и ещё \(count)" : "and \(count) more"
    }
    static func companionsLoadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось загрузить попутчиков" : "Couldn't load companions"
    }
    /// Task 7: shown alongside a cached roster (`Trip.companions`) on the
    /// viewer's own trip when today's `/companions/list` refresh failed —
    /// real rows ARE on screen, so this is deliberately quieter than
    /// `companionsLoadFailed`'s error phrasing, just flagging that they
    /// might be out of date.
    static func companionsCachedNotice(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Нет сети — может быть неактуально" : "Offline — may be out of date"
    }
    /// Confirmation after picking photos. The system picker opens on a
    /// library that already holds everything you added before, so without a
    /// receipt afterwards there is nothing to tell "added" from "looked at
    /// the same photos again".
    static func photosAdded(_ count: Int, _ lang: LanguageManager.Language) -> String {
        if lang == .ru { return "Добавлено \(count) фото" }
        return count == 1 ? "1 photo added" : "\(count) photos added"
    }
    static func companionsRemoveFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось убрать попутчика" : "Couldn't remove companion"
    }
    /// Task 6: a companion's photo pick failed to reach the server at all
    /// (the required thumbnail part never landed). Shown as an error
    /// toast; the photo strip itself is left untouched (see
    /// `CompanionPhotoUploadController`'s doc comment).
    static func companionPhotoUploadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось загрузить фото" : "Couldn't upload photo"
    }
    /// Task 6: a companion's photo DID land (its thumbnail is on the
    /// server and it's visible on the trip) but the full-quality original
    /// didn't. Deliberately NOT phrased as a failure — the photo is there.
    static func companionPhotoUploadDegraded(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Фото добавлено, но в уменьшенном качестве"
            : "Photo added, but at reduced quality"
    }
    /// Task 6, review fix: a companion picked SEVERAL photos and only some
    /// landed — the rest were genuinely attempted and failed, not silently
    /// skipped. `succeeded`/`total` name exactly how many, so this can
    /// never be read as a flat failure when photos actually did get added.
    static func companionPhotoUploadPartial(_ succeeded: Int, _ total: Int, _ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Добавлено \(succeeded) из \(total) фото"
            : "\(succeeded) of \(total) photos added"
    }
    /// Task 6, review fix: the upload itself succeeded (at least one photo
    /// landed on the server), but the follow-up refresh of the trip's
    /// photo list failed — a distinct, separate network call. The strip
    /// keeps showing whatever it showed before this attempt (see
    /// `TripDetailView.uploadCompanionPhotos`); this says why the newly
    /// added photo isn't visible YET, not that the upload failed.
    static func companionPhotoReloadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Фото загружено, но список не обновился. Загляните на поездку позже"
            : "Photo uploaded, but the list didn't refresh. Check back on this trip later"
    }
    /// Fix 1: the trip owner tried to delete a companion's remote-only
    /// photo (no local row — `/photos/delete` failed). The optimistic
    /// removal from the strip is rolled back alongside this toast.
    static func companionPhotoDeleteFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось удалить фото" : "Couldn't delete photo"
    }
    static func companionsRemoveConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Убрать попутчика?" : "Remove companion?"
    }
    /// The confirmation dialog's destructive button AND the row's own
    /// remove control — deliberately NOT `delete`: a companion is being
    /// taken off the trip, not destroyed, and the dialog's own title
    /// already says «Убрать».
    static func companionsRemove(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Убрать" : "Remove"
    }
    /// Fix 3: a companion's own affordance for leaving someone else's
    /// trip — the «…» popover item, the confirmation dialog's title (used
    /// as a question, mirroring `deleteTrip`'s reuse pattern for its own
    /// confirmation) and its destructive button.
    static func companionsLeaveTrip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Покинуть поездку" : "Leave trip"
    }
    static func companionsLeaveConfirmTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Покинуть эту поездку?" : "Leave this trip?"
    }
    static func companionsLeaveFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось покинуть поездку" : "Couldn't leave the trip"
    }

    // MARK: - Companions picker (Task 3)

    /// `CompanionsPickerSheet`'s own header — deliberately not reusing
    /// `companionsInvite` ("Позвать"), which is the CTA that OPENS this
    /// sheet, not what the sheet itself is titled.
    static func companionsPickerTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Пригласить попутчика" : "Invite a companion"
    }
    static func companionsSearchPlaceholder(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поиск по подпискам" : "Search who you follow"
    }
    /// The picker's loaded-and-empty state — states the actual rule rather
    /// than implying the request is broken.
    static func companionsCandidatesEmptyTitle(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Некого позвать" : "No one to invite"
    }
    static func companionsCandidatesEmptyHint(_ lang: LanguageManager.Language) -> String {
        lang == .ru
            ? "Позвать можно только тех, на кого вы подписаны."
            : "You can only invite people you follow."
    }
    static func companionsCandidatesLoadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось загрузить список" : "Couldn't load the list"
    }
    static func companionsInviteFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось позвать" : "Couldn't invite"
    }
    /// The row state right after a successful (optimistic) tap — kept
    /// lowercase to match `companionsWaiting`'s «ждёт» styling.
    static func companionsInvited(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "приглашён" : "Invited"
    }

    // MARK: - «Со мной» profile section (Task 5)

    /// Section header. Reuses `ProfileTripRow` — same row `historySection`
    /// draws for the user's own trips — but each row names the driver, the
    /// one fact that tells this section apart from «История».
    static func withMeSection(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Со мной" : "With me"
    }
    static func withMeLoadFailed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Не удалось загрузить поездки" : "Couldn't load trips"
    }
    /// The driver-name fallback for a «Со мной» row. Same copy as the four
    /// pre-existing inline `displayName ?? (lang == .ru ? "Без имени" :
    /// "No name")` spots (`TripCompanionsSection.swift`,
    /// `CompanionsPickerSheet.swift`, `TripDetailView.swift` ×2) — this task
    /// only owns `WithMeSection`'s copy of that pattern (review finding),
    /// not a sweep of the pre-existing ones.
    static func withMeDriverNoName(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Без имени" : "No name"
    }
}
