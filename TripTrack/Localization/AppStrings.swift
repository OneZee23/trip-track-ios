import Foundation

enum AppStrings {
    // MARK: - Tabs
    static func feed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feed", ru: "Лента", en: "Feed")
    }
    static func record(_ lang: LanguageManager.Language) -> String {
        tr(lang, "record", ru: "Запись", en: "Record")
    }
    static func regions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "regions", ru: "Места", en: "Places")
    }
    static func profile(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profile", ru: "Профиль", en: "Profile")
    }
    static func tabMap(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tabMap", ru: "Карта", en: "Map")
    }
    static func tabGroups(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tabGroups", ru: "Группы", en: "Groups")
    }
    static func tabMe(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tabMe", ru: "Я", en: "Me")
    }

    // MARK: - Groups (coming soon, Figma 117:2265)
    static func groupsComingTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsComingTitle", ru: "Клубы — скоро", en: "Clubs — coming soon")
    }
    static func groupsComingBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsComingBody",
           ru: "Сообщества по маркам и интересам: Miata, VAG, Dodge, дальнобой, оффроуд. Общие поездки и рейтинги.",
           en: "Communities by make and interest: Miata, VAG, Dodge, trucking, off-road. Group drives and leaderboards.")
    }
    static func groupsNotifyMe(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsNotifyMe", ru: "Уведомить меня", en: "Notify me")
    }
    /// The done state used to say «Вы в списке», which claims a server-side
    /// waitlist — the flag is a local @AppStorage bool with no endpoint
    /// behind it, so the copy now promises only what the app itself does.
    static func groupsNotifyDone(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsNotifyDone",
           ru: "Покажем, когда откроем",
           en: "We'll show it when it opens")
    }
    /// The real count, from `/groups/waitlist`. It used to be the literal
    /// «Уже ждут 1 240 человек» printed into the layout — a made-up number
    /// under a button that only set a local flag.
    static func groupsWaitlistCount(_ lang: LanguageManager.Language, count: Int) -> String {
        let n = formattedCount(count, lang: lang)
        let people = nounPeople(lang, count)
        switch lang {
        case .ru: return "Уже ждут \(n) \(people)"
        case .en: return "\(n) \(people) already waiting"
        case .de: return "\(n) \(people) warten bereits"
        case .es: return "Ya esperan \(n) \(people)"
        case .fr: return "\(n) \(people) attendent déjà"
        case .it: return "\(n) \(people) sono già in attesa"
        case .pl: return "Czeka już \(n) \(people)"
        case .id: return "\(n) \(people) sudah menunggu"
        case .tr: return "\(n) \(people) şimdiden bekliyor"
        case .fil: return "\(n) \(people) ang naghihintay"
        case .uk: return "Уже чекають \(n) \(people)"
        case .kk: return "\(n) \(people) күтіп отыр"
        case .pt: return "\(n) \(people) já esperando"
        }
    }

    /// «1 240» / «1,240» — the grouping the rest of the app uses.
    static func formattedCount(_ count: Int, lang: LanguageManager.Language) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = lang.locale
        return f.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// Nobody has tapped it yet — an honest invitation instead of «ждут 0».
    static func groupsWaitlistFirst(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsWaitlistFirst", ru: "Вы можете быть первым", en: "You could be the first")
    }

    static func groupsPreviewCTA(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsPreviewCTA", ru: "Посмотреть что будет", en: "See what's coming")
    }
    static func clubsTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubsTitle", ru: "Клубы", en: "Clubs")
    }
    static func clubsSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubsSubtitle",
           ru: "Клубы по маркам и интересам",
           en: "Clubs by make and interest")
    }
    static func clubsSoonBadge(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubsSoonBadge", ru: "СКОРО", en: "SOON")
    }
    /// Section label on a club page.
    static func clubPerksTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubPerksTitle", ru: "Что будет в клубе", en: "What the club will have")
    }
    static func clubJoin(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubJoin", ru: "Вступить", en: "Join")
    }
    /// State after tapping «Вступить» on a club that does not exist yet: we
    /// remember it and will say when it opens. Not «Вы участник» — nobody is
    /// a member of anything yet.
    static func clubJoinWaiting(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubJoinWaiting", ru: "Ждёте", en: "Waiting")
    }
    static func clubWaitingCount(_ lang: LanguageManager.Language, count: Int) -> String {
        let n = formattedCount(count, lang: lang)
        switch lang {
        case .ru: return "\(n) ждут"
        case .en: return "\(n) waiting"
        case .de: return "\(n) warten"
        case .es: return "\(n) esperando"
        case .fr: return "\(n) en attente"
        case .it: return "\(n) in attesa"
        case .pl: return "\(n) czeka"
        case .id: return "\(n) menunggu"
        case .tr: return "\(n) bekliyor"
        case .fil: return "\(n) naghihintay"
        case .uk: return "\(n) чекають"
        case .kk: return "\(n) күтуде"
        case .pt: return "\(n) esperando"
        }
    }
    static func clubBeFirst(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubBeFirst", ru: "Пока никто не ждёт", en: "Nobody waiting yet")
    }
    static func clubComingFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubComingFootnote",
           ru: "Функция появится в одном из следующих обновлений",
           en: "This will arrive in one of the next updates")
    }
    /// Shown under the CTA to a signed-out visitor: their place in the queue
    /// is recorded, but a push needs an account to land on.
    static func groupsNotifySignInHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsNotifySignInHint",
           ru: "Войдите, чтобы мы точно смогли прислать уведомление",
           en: "Sign in so we can actually send you that notification")
    }
    static func groupsChipTrucking(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsChipTrucking", ru: "🛻 Дальнобой", en: "🛻 Trucking")
    }
    static func groupsChipOffroad(_ lang: LanguageManager.Language) -> String {
        tr(lang, "groupsChipOffroad", ru: "🏔 Оффроуд", en: "🏔 Off-road")
    }

    // MARK: - Feed
    static func trips(_ lang: LanguageManager.Language) -> String {
        tr(lang, "trips", ru: "поездок", en: "trips")
    }
    static func km(_ lang: LanguageManager.Language) -> String {
        tr(lang, "km", ru: "км", en: "km")
    }
    static func time(_ lang: LanguageManager.Language) -> String {
        tr(lang, "time", ru: "в пути", en: "drive time")
    }
    static func filters(_ lang: LanguageManager.Language) -> String {
        tr(lang, "filters", ru: "Фильтры", en: "Filters")
    }
    static func noTrips(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noTrips", ru: "Пока нет поездок", en: "No trips yet")
    }
    static func goRide(_ lang: LanguageManager.Language) -> String {
        tr(lang, "goRide", ru: "Нажмите чтобы начать", en: "Tap to start")
    }

    // MARK: - Stats labels
    static func stats(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stats", ru: "Статистика", en: "Stats")
    }
    static func avg(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avg", ru: "ср. скор.", en: "avg speed")
    }
    static func fuel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuel", ru: "топливо", en: "fuel")
    }
    static func cost(_ lang: LanguageManager.Language) -> String {
        tr(lang, "cost", ru: "расход", en: "fuel cost")
    }
    static func maxSpeed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "maxSpeed", ru: "Макс. скорость", en: "Max speed")
    }
    static func elevation(_ lang: LanguageManager.Language) -> String {
        tr(lang, "elevation", ru: "набор высоты", en: "elevation")
    }
    static func elevationGain(_ lang: LanguageManager.Language) -> String {
        tr(lang, "elevationGain", ru: "Набор высоты", en: "Elevation gain")
    }
    static func maxAltitude(_ lang: LanguageManager.Language) -> String {
        tr(lang, "maxAltitude", ru: "Макс. высота", en: "Max altitude")
    }
    static func photos(_ lang: LanguageManager.Language) -> String {
        tr(lang, "photos", ru: "Фото", en: "Photos")
    }

    // MARK: - Record
    static func startTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "startTrip", ru: "Начать поездку", en: "Start trip")
    }
    static func slideToStart(_ lang: LanguageManager.Language) -> String {
        tr(lang, "slideToStart", ru: "Сдвиньте", en: "Slide")
    }
    static func readyToRide(_ lang: LanguageManager.Language) -> String {
        tr(lang, "readyToRide", ru: "В путь?", en: "Ready to roll?")
    }

    // MARK: - Recording states (0.6.0)

    /// Shown when a start is refused, so the slider never just springs back
    /// with nothing said.
    static func startRefusedRecovery(_ lang: LanguageManager.Language) -> String {
        tr(lang, "startRefusedRecovery",
           ru: "Сначала закончите с прошлой поездкой",
           en: "Finish with the previous trip first")
    }
    static func startRefusedNoGeo(_ lang: LanguageManager.Language) -> String {
        tr(lang, "startRefusedNoGeo",
           ru: "Нужен доступ к геолокации",
           en: "Location access is required")
    }
    /// Deliberately vague, because the honest answer is that we do not know —
    /// and saying nothing is worse than saying that.
    static func startRefusedUnknown(_ lang: LanguageManager.Language) -> String {
        tr(lang, "startRefusedUnknown",
           ru: "Не получилось начать запись — попробуйте ещё раз",
           en: "Could not start recording — try again")
    }
    /// No fix yet. Starting here records a trip whose beginning is missing,
    /// so the control waits — and says what it is waiting for.
    static func startRefusedNoFix(_ lang: LanguageManager.Language) -> String {
        tr(lang, "startRefusedNoFix",
           ru: "Ждём сигнал GPS — начало поездки не запишется",
           en: "Waiting for GPS — the start of the trip would be lost")
    }
    /// The escape hatch: an underground car park may never give a fix, and
    /// refusing forever is worse than recording a trip that begins late.
    static func startAnyway(_ lang: LanguageManager.Language) -> String {
        tr(lang, "startAnyway", ru: "Всё равно начать", en: "Start anyway")
    }
    /// Label on the start control itself while there is no fix.
    static func slideWaitingForGPS(_ lang: LanguageManager.Language) -> String {
        tr(lang, "slideWaitingForGPS", ru: "Ждём сигнал GPS", en: "Waiting for GPS")
    }
    /// Before the first accepted fix. Distinct from «слабый» on purpose —
    /// waiting for satellites is normal and temporary, a weak signal is a
    /// problem, and showing the alarming one for the ordinary case made the
    /// whole screen look broken.
    static func gpsSearching(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsSearching", ru: "Ищем спутники", en: "Finding GPS")
    }
    static func gpsLegendSearching(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsLegendSearching",
           ru: "Обычно пара секунд — под крышей дольше",
           en: "Usually a couple of seconds — longer under cover")
    }
    static func gpsAccurate(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsAccurate", ru: "GPS точный", en: "GPS strong")
    }
    static func gpsMedium(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsMedium", ru: "GPS средний", en: "GPS fair")
    }
    static func gpsWeak(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsWeak", ru: "GPS слабый", en: "GPS weak")
    }
    static func gpsLost(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsLost", ru: "GPS потерян", en: "GPS lost")
    }
    static func gpsLegendAccurate(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsLegendAccurate",
           ru: "≤ 10 м · запись идеальна",
           en: "≤ 10 m · perfect recording")
    }
    static func gpsLegendMedium(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsLegendMedium",
           ru: "10–35 м · возможны неточности",
           en: "10–35 m · minor inaccuracies")
    }
    static func gpsLegendWeak(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsLegendWeak", ru: "> 35 м · трек прерывается", en: "> 35 m · track breaks up")
    }
    static func weakSignalTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "weakSignalTitle", ru: "Сигнал слабый", en: "Weak signal")
    }
    static func weakSignalHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "weakSignalHint",
           ru: "На открытой местности точнее",
           en: "More accurate in open areas")
    }
    static func signalLostTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signalLostTitle", ru: "Сигнал GPS потерян", en: "GPS signal lost")
    }
    static func signalLostHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signalLostHint",
           ru: "Пишем по последней точке — восстановим, когда сигнал вернётся",
           en: "Holding last point — we'll recover when the signal returns")
    }
    static func recordingPausedPill(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordingPausedPill", ru: "Запись на паузе", en: "Recording paused")
    }
    static func pauseShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "pauseShort", ru: "ПАУЗА", en: "PAUSED")
    }
    static func pauseAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "pauseAction", ru: "Пауза", en: "Pause")
    }
    static func resumeAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "resumeAction", ru: "Продолжить", en: "Resume")
    }
    /// Ending a recording cannot be undone — the trip closes and a later drive
    /// becomes a separate one. Worth one question.
    static func stopConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stopConfirmTitle", ru: "Завершить поездку?", en: "Finish the trip?")
    }
    static func stopConfirmBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stopConfirmBody",
           ru: "Продолжить эту же запись потом будет нельзя",
           en: "You won't be able to continue this recording later")
    }
    static func stopConfirmAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stopConfirmAction", ru: "Завершить и сохранить", en: "Finish and save")
    }
    /// Offered inside the stop dialog — «стоп» at a petrol station usually
    /// means «wait», and that answer belongs next to the question.
    static func stopConfirmPause(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stopConfirmPause", ru: "Поставить на паузу", en: "Pause instead")
    }
    static func stop(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stop", ru: "Стоп", en: "Stop")
    }
    static func noGeoTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noGeoTitle", ru: "Нет доступа к геолокации", en: "No location access")
    }
    static func noGeoSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noGeoSubtitle",
           ru: "Включите доступ в Настройках",
           en: "Enable access in Settings")
    }
    static func recoveryTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recoveryTitle", ru: "Запись была прервана", en: "Recording was interrupted")
    }
    static func recoveryBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recoveryBody",
           ru: "Приложение закрылось до того, как Вы завершили поездку. Мы сохранили Ваш маршрут.",
           en: "The app closed before you finished the trip. We saved your route.")
    }
    static func recoveryChip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recoveryChip", ru: "Восстановлено", en: "Recovered")
    }
    static func recoveryContinue(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recoveryContinue", ru: "Продолжить запись", en: "Continue recording")
    }
    static func recoveryFinish(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recoveryFinish", ru: "Завершить и сохранить", en: "Finish and save")
    }
    static func vehiclePickerTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehiclePickerTitle", ru: "Транспорт для поездки", en: "Transport for this trip")
    }
    static func manageInGarage(_ lang: LanguageManager.Language) -> String {
        tr(lang, "manageInGarage", ru: "Управлять в Гараже", en: "Manage in Garage")
    }
    static func publishToFeed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishToFeed", ru: "Опубликовать в ленту", en: "Publish to feed")
    }
    static func publishToFeedSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishToFeedSubtitle",
           ru: "Поездка появится в общей ленте",
           en: "Your trip will appear in the shared feed")
    }
    static func publishFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishFootnote",
           ru: "Поездки приватны, пока Вы не опубликуете их сами.",
           en: "Trips stay private until you publish them yourself.")
    }
    /// The canon's one-line toggle hint. It replaces the two-line
    /// subtitle-plus-footnote on the finish card: both said the same thing at
    /// different lengths, and neither said what the switch does in each
    /// position — which is the only thing you need at that moment.
    static func publishToggleHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishToggleHint",
           ru: "Вкл — увидят все · выкл — только вы",
           en: "On — everyone sees it · off — only you")
    }
    /// Placeholder on the finish card's inline description field.
    static func describeTripPlaceholder(_ lang: LanguageManager.Language) -> String {
        tr(lang, "describeTripPlaceholder", ru: "Добавить описание…", en: "Add a description…")
    }
    static func tripFinishedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripFinishedTitle", ru: "Поездка завершена!", en: "Trip finished!")
    }
    static func maxShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "maxShort", ru: "МАКС", en: "MAX")
    }
    static func photoShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "photoShort", ru: "Фото", en: "Photo")
    }
    static func kmh(_ lang: LanguageManager.Language) -> String {
        tr(lang, "kmh", ru: "км/ч", en: "km/h")
    }
    static func unitLPer100(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unitLPer100", ru: "л/100", en: "l/100")
    }
    static func unitMeters(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unitMeters", ru: "м", en: "m")
    }

    // MARK: - Regions
    static func regionsExplored(_ lang: LanguageManager.Language) -> String {
        tr(lang, "regionsExplored", ru: "регионов", en: "regions")
    }
    static func mapExplored(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapExplored", ru: "исследовано", en: "explored")
    }
    static func unlocked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unlocked", ru: "открыто", en: "unlocked")
    }
    static func locked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "locked", ru: "Заблокировано", en: "Locked")
    }
    static func view(_ lang: LanguageManager.Language) -> String {
        tr(lang, "view", ru: "Смотреть", en: "View")
    }

    // MARK: - Filters
    static func apply(_ lang: LanguageManager.Language) -> String {
        tr(lang, "apply", ru: "Применить", en: "Apply")
    }
    static func reset(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reset", ru: "Сбросить", en: "Reset")
    }
    static func resetSecondary(_ lang: LanguageManager.Language) -> String {
        tr(lang, "resetSecondary", ru: "Сбросить вторичные", en: "Reset secondary")
    }
    static func all(_ lang: LanguageManager.Language) -> String {
        tr(lang, "all", ru: "Все", en: "All")
    }
    static func region(_ lang: LanguageManager.Language) -> String {
        tr(lang, "region", ru: "Регион", en: "Region")
    }

    // MARK: - Periods
    static func week(_ lang: LanguageManager.Language) -> String {
        tr(lang, "week", ru: "Неделя", en: "Week")
    }
    static func month(_ lang: LanguageManager.Language) -> String {
        tr(lang, "month", ru: "Месяц", en: "Month")
    }
    static func year(_ lang: LanguageManager.Language) -> String {
        tr(lang, "year", ru: "Год", en: "Year")
    }
    static func total(_ lang: LanguageManager.Language) -> String {
        tr(lang, "total", ru: "Всё время", en: "All time")
    }

    // MARK: - Profile / Settings
    static func back(_ lang: LanguageManager.Language) -> String {
        tr(lang, "back", ru: "Назад", en: "Back")
    }
    static func theme(_ lang: LanguageManager.Language) -> String {
        tr(lang, "theme", ru: "Тема", en: "Theme")
    }
    static func lang(_ lang: LanguageManager.Language) -> String {
        tr(lang, "lang", ru: "Язык", en: "Language")
    }
    static func dark(_ lang: LanguageManager.Language) -> String {
        tr(lang, "dark", ru: "Тёмная", en: "Dark")
    }
    static func light(_ lang: LanguageManager.Language) -> String {
        tr(lang, "light", ru: "Светлая", en: "Light")
    }
    static func garage(_ lang: LanguageManager.Language) -> String {
        tr(lang, "garage", ru: "Гараж", en: "Garage")
    }
    static func about(_ lang: LanguageManager.Language) -> String {
        tr(lang, "about", ru: "О приложении", en: "About")
    }
    static func developer(_ lang: LanguageManager.Language) -> String {
        tr(lang, "developer", ru: "Разработчик", en: "Developer")
    }
    static func calendar(_ lang: LanguageManager.Language) -> String {
        tr(lang, "calendar", ru: "Календарь", en: "Calendar")
    }
    static func onlyCurrentWeek(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onlyCurrentWeek", ru: "только текущая неделя", en: "only current week")
    }
    static func thisWeek(_ lang: LanguageManager.Language) -> String {
        tr(lang, "thisWeek", ru: "Эта неделя", en: "This Week")
    }
    static func quickStats(_ lang: LanguageManager.Language) -> String {
        tr(lang, "quickStats", ru: "Статистика", en: "Quick stats")
    }
    static func consumption(_ lang: LanguageManager.Language) -> String {
        tr(lang, "consumption", ru: "Расход л/100км", en: "L/100km")
    }
    static func pricePerLiter(_ lang: LanguageManager.Language) -> String {
        let c = FuelCurrency.current
        switch lang {
        case .ru: return "\(c) за литр"
        case .en: return "\(c)/L"
        case .de: return "\(c)/l"
        case .es: return "\(c)/l"
        case .fr: return "\(c)/l"
        case .it: return "\(c)/l"
        case .pl: return "\(c)/l"
        case .id: return "\(c)/l"
        case .tr: return "\(c)/l"
        case .fil: return "\(c)/L"
        case .uk: return "\(c) за літр"
        case .kk: return "\(c)/л"
        case .pt: return "\(c)/l"
        }
    }

    // MARK: - Trip detail
    static func distance(_ lang: LanguageManager.Language) -> String {
        tr(lang, "distance", ru: "Дистанция", en: "Distance")
    }
    static func duration(_ lang: LanguageManager.Language) -> String {
        tr(lang, "duration", ru: "Время", en: "Time")
    }
    static func avgSpeed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avgSpeed", ru: "Ср. скорость", en: "Avg speed")
    }
    /// Feed-card metric label (Figma FeedCard 115:72 — «Ср. скор.», the
    /// full «Ср. скорость» overflows the third metric column at 11pt caps).
    static func avgSpeedShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avgSpeedShort", ru: "Ср. скор.", en: "Avg speed")
    }
    static func avgSpeedModeTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avgSpeedModeTitle", ru: "Расчёт средней скорости", en: "Average speed basis")
    }
    static func avgSpeedOverall(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avgSpeedOverall", ru: "Общая", en: "Overall")
    }
    static func avgSpeedMoving(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avgSpeedMoving", ru: "В движении", en: "Moving")
    }
    // Website-globe opt-in (per-user)
    static func publishOnGlobeTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishOnGlobeTitle",
           ru: "Публикация поездок на глобальной карте",
           en: "Publish trips on the global map")
    }
    static func publishOnGlobeSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishOnGlobeSubtitle",
           ru: "Только публичные поездки, маршрут анонимизируется (концы обрезаются). Приватные не показываются.",
           en: "Public trips only, route is anonymized (endpoints trimmed). Private trips are never shown.")
    }
    static func optYes(_ lang: LanguageManager.Language) -> String {
        tr(lang, "optYes", ru: "Да", en: "Yes")
    }
    static func optNo(_ lang: LanguageManager.Language) -> String {
        tr(lang, "optNo", ru: "Нет", en: "No")
    }
    static func noVehicle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noVehicle", ru: "Без транспорта", en: "No transport")
    }
    static func tripVehicle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripVehicle", ru: "Машина поездки", en: "Trip vehicle")
    }
    static func statsMoreKm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsMoreKm", ru: "— больше км", en: "— more km")
    }
    static func statsToday(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsToday", ru: "сегодня", en: "today")
    }
    static func tripTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripTitle", ru: "Поездка", en: "Trip")
    }
    static func tripsHistory(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripsHistory", ru: "История ваших путешествий", en: "Your trip history")
    }
    static func tripsTab(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripsTab", ru: "Поездки", en: "Trips")
    }
    static func startFirstTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "startFirstTrip",
           ru: "Начните первую поездку чтобы увидеть её здесь",
           en: "Start your first trip to see it here")
    }
    static func totalKm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "totalKm", ru: "км всего", en: "total km")
    }
    static func regionsCount(_ lang: LanguageManager.Language) -> String {
        tr(lang, "regionsCount", ru: "регионов", en: "regions")
    }
    static func m(_ lang: LanguageManager.Language) -> String {
        tr(lang, "m", ru: "м", en: "m")
    }

    // MARK: - Onboarding
    // Two-tone welcome headline (0.6.0): the hook line in text color, the
    // punch line in accent.
    static func onboardingWelcomeTitle1(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingWelcomeTitle1",
           ru: "Вы забудете почти каждую поездку.",
           en: "You'll forget almost every trip.")
    }
    static func onboardingWelcomeTitle2(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingWelcomeTitle2", ru: "TripTrack — нет.", en: "TripTrack won't.")
    }
    static func onboardingWelcomeSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingWelcomeSub",
           ru: "Дневник ваших дорог — маршруты, статистика, расход и гараж. Откройте через год — и вспомните всё.",
           en: "A diary of your roads — routes, stats, fuel and garage. Open it a year from now — and remember everything.")
    }
    static func onboardingPrivacyPill(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingPrivacyPill", ru: "Приватно по умолчанию", en: "Private by default")
    }
    static func onboardingValueTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingValueTitle",
           ru: "Вот как выглядит ваша поездка",
           en: "This is what your trip looks like")
    }
    static func onboardingValueCaption(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingValueCaption",
           ru: "Поездки записываются сами — маршрут, скорость и расход.",
           en: "Trips record themselves — route, speed and fuel.")
    }
    static func onboardingRecordedAuto(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingRecordedAuto",
           ru: "Записано автоматически",
           en: "Recorded automatically")
    }
    static func onboardingMockTripTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingMockTripTitle", ru: "Поездка · 16 мая", en: "Trip · May 16")
    }
    // Short uppercase stat labels for the mock trip card's 2×3 metrics grid.
    static func onboardingStatAvg(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingStatAvg", ru: "Средняя", en: "Avg")
    }
    static func onboardingStatMax(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingStatMax", ru: "Макс", en: "Max")
    }
    static func onboardingStatFuel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingStatFuel", ru: "Расход", en: "Fuel")
    }
    static func onboardingStatAltitude(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingStatAltitude", ru: "Высота", en: "Elev")
    }
    static func onboardingLocation(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingLocation", ru: "Разрешите геолокацию", en: "Allow location access")
    }
    static func onboardingLocationSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingLocationSub",
           ru: "Для записи маршрутов нужен доступ к геолокации. Данные хранятся на устройстве.",
           en: "Location access is needed to record your routes. Your data stays on your device.")
    }
    /// Shown instead of «Разрешить» when the system permission is already
    /// granted — asking again would do nothing (iOS shows the prompt once),
    /// so the button has to say what it will actually do: move on.
    // Canon onboarding screens «Гео "Всегда"» and «Уведомления» — one ask
    // per screen, each explaining what breaks without it.
    static func onboardingBackgroundTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingBackgroundTitle",
           ru: "Запись в фоне",
           en: "Recording in the background")
    }
    // This page's button also fires the Motion & Fitness prompt
    // (OnboardingView.requestAlwaysAndAdvance), and the copy named only
    // location — activity data was asked for with nothing disclosed about
    // it, so the sensor and its battery reason are spelled out here.
    static func onboardingBackgroundSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingBackgroundSub",
           ru: "Чтобы поездки писались, когда телефон в кармане, нужен доступ к геолокации «Всегда» — с «При использовании» запись прервётся в фоне. Датчик движения («Движение и фитнес») помогает заметить начало поездки без постоянного GPS — так батарея расходуется меньше.",
           en: "For trips to keep recording with the phone in your pocket, location access must be «Always» — with «While Using» recording stops in the background. Motion & Fitness data lets the app spot a drive starting without keeping GPS on, so the battery lasts longer.")
    }
    static func onboardingBackgroundAllow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingBackgroundAllow", ru: "Разрешить «Всегда»", en: "Allow «Always»")
    }
    static func onboardingNotificationsTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingNotificationsTitle", ru: "Будьте в курсе", en: "Stay in the loop")
    }
    static func onboardingNotificationsSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingNotificationsSub",
           ru: "Уведомления о реакциях, подписках и комментариях к вашим поездкам. Включите — и не пропустите отклик.",
           en: "Notifications about reactions, follows and comments on your trips. Turn them on so you don't miss the response.")
    }
    static func onboardingNotificationsEnable(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingNotificationsEnable",
           ru: "Включить уведомления",
           en: "Turn on notifications")
    }
    static func onboardingNotNow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingNotNow", ru: "Не сейчас", en: "Not now")
    }

    static func onboardingAlreadyGranted(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingAlreadyGranted", ru: "Доступ уже есть", en: "Access already granted")
    }
    static func onboardingContinue(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingContinue", ru: "Дальше", en: "Continue")
    }
    static func onboardingSkipForNow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingSkipForNow", ru: "Позже", en: "Not now")
    }

    static func onboardingAllow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "onboardingAllow", ru: "Разрешить", en: "Allow")
    }
    /// Composes the full onboarding consent sentence with clickable Markdown links.
    /// Uses correct Russian declension (instrumental after «соглашаетесь с»).
    static func onboardingConsentMarkdown(
        _ lang: LanguageManager.Language,
        termsURL: String,
        privacyURL: String
    ) -> String {
        let terms = "[\(termsOfService(lang))](\(termsURL))"
        let privacy = "[\(privacyPolicy(lang))](\(privacyURL))"
        switch lang {
        case .ru: return "Продолжая, Вы соглашаетесь с \(terms) и \(privacy)"
        case .en: return "By continuing, you accept our \(terms) and \(privacy)"
        case .de: return "Wenn du fortfährst, akzeptierst du \(terms) und \(privacy)"
        case .es: return "Si continúas, aceptas los \(terms) y la \(privacy)"
        case .fr: return "En continuant, vous acceptez les \(terms) et la \(privacy)"
        case .it: return "Continuando, accetti i \(terms) e l'\(privacy)"
        case .pl: return "Kontynuując, akceptujesz \(terms) i \(privacy)"
        case .id: return "Dengan melanjutkan, Anda menyetujui \(terms) dan \(privacy)"
        case .tr: return "Devam ederek \(terms) ve \(privacy) belgelerini kabul edersiniz"
        case .fil: return "Sa pagpapatuloy, tinatanggap mo ang \(terms) at \(privacy)"
        case .uk: return "Продовжуючи, Ви погоджуєтесь з \(terms) і \(privacy)"
        case .kk: return "Жалғастыра отырып, сіз \(terms) және \(privacy) қабылдайсыз"
        case .pt: return "Ao continuar, você aceita os \(terms) e a \(privacy)"
        }
    }

    /// Nominative / standalone title. Use wherever the text stands alone
    /// (button, row in settings, link in the profile).
    static func termsOfService(_ lang: LanguageManager.Language) -> String {
        tr(lang, "termsOfService", ru: "Условия использования", en: "Terms of Service")
    }

    /// Nominative / standalone title.
    static func privacyPolicy(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyPolicy", ru: "Политика конфиденциальности", en: "Privacy Policy")
    }

    // MARK: - Badges
    static func badges(_ lang: LanguageManager.Language) -> String {
        tr(lang, "badges", ru: "Достижения", en: "Badges")
    }
    static func newBadge(_ lang: LanguageManager.Language) -> String {
        tr(lang, "newBadge", ru: "Новое достижение", en: "New badge")
    }
    static func achievementUnlocked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementUnlocked", ru: "Достижение!", en: "Achievement Unlocked!")
    }
    static func earnedTimes(_ lang: LanguageManager.Language, count: Int) -> String {
        let t = nounTimes(lang, count)
        switch lang {
        case .ru: return "Получено \(count) \(t)"
        case .en: return "Earned \(count) \(t)"
        case .de: return "\(count)-mal erhalten"
        case .es: return "Conseguido \(count) \(t)"
        case .fr: return "Obtenu \(count) \(t)"
        case .it: return "Ottenuto \(count) \(t)"
        case .pl: return "Zdobyte \(count) \(t)"
        case .id: return "Diperoleh \(count) \(t)"
        case .tr: return "\(count) \(t) kazanıldı"
        case .fil: return "Nakuha nang \(count) \(t)"
        case .uk: return "Отримано \(count) \(t)"
        case .kk: return "\(count) \(t) алынды"
        case .pt: return "Conquistado \(count) \(t)"
        }
    }
    static func continueButton(_ lang: LanguageManager.Language) -> String {
        tr(lang, "continueButton", ru: "Продолжить", en: "Continue")
    }

    // MARK: - Regions / Exploration
    static func map(_ lang: LanguageManager.Language) -> String {
        tr(lang, "map", ru: "Карта", en: "Map")
    }
    static func tilesDiscovered(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tilesDiscovered", ru: "УЧАСТКОВ ОТКРЫТО", en: "TILES DISCOVERED")
    }
    // citiesCount / regionsCountLabel deleted — zero callers, and their RU
    // plural forms were wrong («5 города»). Use proper plural helpers if a
    // caller ever appears.

    // MARK: - My Map (0.6.0)

    static func myMapTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myMapTitle", ru: "Моя карта", en: "My Map")
    }
    // The «Маршруты · Территория · Всё» segment is gone on purpose: the canon
    // note on the Карта page reads «Слоёв-переключателей нет» — territory and
    // trips share one layer, and depth comes from zoom instead.

    /// Collapsed sheet: «8 регионов · 12 890 км · 47 поездок».
    static func mapSummary(
        _ lang: LanguageManager.Language, regions: Int, km: Int, trips: Int
    ) -> String {
        let r = "\(groupedNumber(regions, lang)) \(nounRegions(lang, regions))"
        let k = "\(groupedNumber(km, lang)) \(AppStrings.km(lang))"
        let t = "\(groupedNumber(trips, lang)) \(nounTrips(lang, trips))"
        return "\(r) · \(k) · \(t)"
    }
    static func mapKmDriven(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapKmDriven", ru: "км проехано", en: "km driven")
    }
    /// «9 из 44» — the region's opened cities over its whole list.
    static func mapCitiesOfTotal(
        _ lang: LanguageManager.Language, opened: Int, total: Int
    ) -> String {
        "\(opened) \(ofWord(lang)) \(total)"
    }

    /// The «N ИЗ M» joiner, shared by every «x of y» line.
    static func ofWord(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "из"
        case .en: return "of"
        case .de: return "von"
        case .es: return "de"
        case .fr: return "sur"
        case .it: return "di"
        case .pl: return "z"
        case .id: return "dari"
        case .tr: return "/"
        case .fil: return "sa"
        case .uk: return "з"
        case .kk: return "/"
        case .pt: return "de"
        }
    }
    /// Progress bar over the region card — canon copy. The value beside it is
    /// real opened road in km; the bar itself is progress toward a stated
    /// per-region goal, since no road-network dataset exists to divide by.
    static func mapRoadsProgress(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapRoadsProgress", ru: "Дороги края", en: "Roads opened")
    }
    /// «84 км · 8%» — the kilometres first, because they are the honest part.
    static func mapRoadsValue(
        _ lang: LanguageManager.Language, km: Double, percent: String
    ) -> String {
        let value = km < 10
            ? String(format: "%.1f", km)
                .replacingOccurrences(of: ".", with: decimalSeparator(lang))
            : groupedNumber(Int(km.rounded()), lang)
        return "\(value) \(AppStrings.km(lang)) · \(percent)"
    }

    /// English is the only one of the seven that puts a dot before the tenths.
    static func decimalSeparator(_ lang: LanguageManager.Language) -> String {
        // Asked of the locale, not written out: English, Filipino and Chinese
        // use a dot where most of Europe uses a comma, and the list only grows.
        lang.locale.decimalSeparator ?? "."
    }
    static func mapPullHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapPullHint",
           ru: "Потяни вверх — города и поездки",
           en: "Pull up — cities and trips")
    }
    static func mapCitiesSection(
        _ lang: LanguageManager.Language, opened: Int, total: Int
    ) -> String {
        let head = tr(lang, "mapCitiesSectionHead", ru: "ГОРОДА", en: "CITIES")
        return "\(head) · \(mapCitiesOfTotal(lang, opened: opened, total: total))"
    }
    static func mapTripsSection(_ lang: LanguageManager.Language, count: Int) -> String {
        "\(tr(lang, "mapTripsSectionHead", ru: "ПОЕЗДКИ ЗДЕСЬ", en: "TRIPS HERE")) · \(count)"
    }
    static func mapCityLocked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapCityLocked", ru: "не открыт", en: "not opened")
    }
    /// Section-header action. Short on purpose — it sits beside the heading,
    /// not on a line of its own at the bottom of the list.
    static func mapSeeAll(_ lang: LanguageManager.Language, count: Int) -> String {
        switch lang {
        case .ru: return "Все \(count)"
        case .en: return "All \(count)"
        case .de: return "Alle \(count)"
        case .es: return "Ver los \(count)"
        case .fr: return "Les \(count)"
        case .it: return "Tutti e \(count)"
        case .pl: return "Wszystkie \(count)"
        case .id: return "Semua \(count)"
        case .tr: return "Tümü \(count)"
        case .fil: return "Lahat ng \(count)"
        case .uk: return "Усі \(count)"
        case .kk: return "Барлығы \(count)"
        case .pt: return "Todas as \(count)"
        }
    }
    static func mapOpenTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapOpenTrip", ru: "Открыть поездку", en: "Open trip")
    }
    /// Tapping a road you have driven many times: every trip that used it.
    static func mapRoadTrips(_ lang: LanguageManager.Language, count: Int) -> String {
        let t = "\(count) \(nounTrips(lang, count))"
        switch lang {
        case .ru: return "\(t) по этой дороге"
        case .en: return "\(t) on this road"
        case .de: return "\(t) auf dieser Straße"
        case .es: return "\(t) por esta carretera"
        case .fr: return "\(t) sur cette route"
        case .it: return "\(t) su questa strada"
        case .pl: return "\(t) na tej drodze"
        case .id: return "\(t) di jalan ini"
        case .tr: return "bu yolda \(t)"
        case .fil: return "\(t) sa kalsadang ito"
        case .uk: return "\(t) цією дорогою"
        case .kk: return "осы жолда \(t)"
        case .pt: return "\(t) nesta estrada"
        }
    }
    static func mapRoadPullHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapRoadPullHint", ru: "Потяни вверх — все поездки", en: "Pull up — all of them")
    }
    /// The map ships ahead of the rest — say so on the screen rather than
    /// leaving people to wonder whether what they see is a bug or the design.
    static func mapBetaBadge(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapBetaBadge", ru: "БЕТА", en: "BETA")
    }
    static func mapBetaTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapBetaTitle", ru: "Карта — бета", en: "The map is in beta")
    }
    static func mapBetaBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapBetaBody",
           ru: "Мы её ещё дорабатываем. Если что-то выглядит не так или работает странно — напишите нам, это правда помогает.",
           en: "We are still working on it. If something looks wrong or behaves oddly, tell us — it genuinely helps.")
    }
    static func mapBetaReport(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapBetaReport", ru: "Написать в Telegram", en: "Message us on Telegram")
    }
    /// Endpoints of the selected route. Voice-over only — on screen they are
    /// the same green-start / white-finish dots the share poster uses.
    static func mapRouteStart(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapRouteStart", ru: "Начало поездки", en: "Trip start")
    }
    static func mapRouteFinish(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapRouteFinish", ru: "Конец поездки", en: "Trip finish")
    }
    static func mapRegionLocked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mapRegionLocked", ru: "ещё не открыт", en: "not opened yet")
    }
    /// «0 км · 0 поездок · 0 из 26 городов» — the zeroes are the point.
    static func mapLockedStats(_ lang: LanguageManager.Language, totalCities: Int) -> String {
        let zeroTrips = "0 \(nounTrips(lang, 0))"
        let cities = "0 \(ofWord(lang)) \(totalCities) \(nounCities(lang, totalCities))"
        return "0 \(AppStrings.km(lang)) · \(zeroTrips) · \(cities)"
    }
    /// «Ближайший твой след — 40 км западнее: Кропоткин, май 2026.
    /// Заедешь — регион загорится на карте.»
    static func mapLockedTeaser(
        _ lang: LanguageManager.Language, km: Int, bearing: String, city: String, when: String?
    ) -> String {
        let place = when.map { "\(city), \($0)" } ?? city
        let head = "\(km) \(AppStrings.km(lang)) \(bearing): \(place)"
        switch lang {
        case .ru: return "Ближайший твой след — \(head). Заедешь — регион загорится на карте."
        case .en: return "Your nearest trace — \(head). Drive in and the region lights up."
        case .de: return "Deine nächste Spur — \(head). Fahr hin, und die Region leuchtet auf."
        case .es: return "Tu rastro más cercano — \(head). Pasa por allí y la región se enciende."
        case .fr: return "Votre trace la plus proche — \(head). Passez-y et la région s'allume."
        case .it: return "La tua traccia più vicina — \(head). Passaci e la regione si accende."
        case .pl: return "Twój najbliższy ślad — \(head). Zajedź tam, a region się zapali."
        case .id: return "Jejak terdekatmu — \(head). Lewati, dan wilayahnya menyala."
        case .tr: return "Sana en yakın iz — \(head). Oradan geç, bölge yansın."
        case .fil: return "Ang pinakamalapit mong bakas — \(head). Daanan mo, at magliliwanag ang rehiyon."
        case .uk: return "Найближчий твій слід — \(head). Заїдеш — регіон засвітиться на карті."
        case .kk: return "Ең жақын ізің — \(head). Барсаң, аймақ картада жанады."
        case .pt: return "Seu rastro mais próximo — \(head). Passe por lá e a região acende."
        }
    }
    static func mapBearing(
        _ lang: LanguageManager.Language, _ bearing: MyMapViewModel.NearestTrace.Bearing
    ) -> String {
        switch bearing {
        case .north:
            return tr(lang, "bearingNorth", ru: "севернее", en: "to the north")
        case .south:
            return tr(lang, "bearingSouth", ru: "южнее", en: "to the south")
        case .east:
            return tr(lang, "bearingEast", ru: "восточнее", en: "to the east")
        case .west:
            return tr(lang, "bearingWest", ru: "западнее", en: "to the west")
        }
    }
    /// «май 2026» / «May 2026».
    static func monthYear(_ lang: LanguageManager.Language, _ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = lang.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date)
    }
    /// Locale-aware thousands grouping («12 890» in RU, «12,890» in EN).
    static func groupedNumber(_ value: Int, _ lang: LanguageManager.Language) -> String {
        let formatter = groupingFormatters[lang] ?? enGrouping
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// One formatter per language, built once. Russian keeps its explicit
    /// space and English its comma — the two the design was drawn against;
    /// the rest take whatever their locale groups with (a dot in German,
    /// Italian and Spanish, a thin space in French and Polish).
    private static let groupingFormatters: [LanguageManager.Language: NumberFormatter] = {
        var map: [LanguageManager.Language: NumberFormatter] = [:]
        for lang in LanguageManager.Language.allCases {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = lang.locale
            if lang == .ru { f.groupingSeparator = " " }
            if lang == .en { f.groupingSeparator = "," }
            map[lang] = f
        }
        return map
    }()
    private static let ruGrouping: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; return f
    }()
    private static let enGrouping: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","; return f
    }()
    static func km2ExploredLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "km2ExploredLabel", ru: "км² освоено", en: "km² explored")
    }
    static func km2Short(_ lang: LanguageManager.Language) -> String {
        tr(lang, "km2Short", ru: "км²", en: "km²")
    }
    /// Bare genitive plate labels («8 регионов», «24 города» etc.).
    static func regionsGenitive(_ lang: LanguageManager.Language, count: Int) -> String {
        nounRegions(lang, count)
    }
    static func citiesGenitive(_ lang: LanguageManager.Language, count: Int) -> String {
        nounCities(lang, count)
    }
    static func tripsGenitive(_ lang: LanguageManager.Language, count: Int) -> String {
        nounTrips(lang, count)
    }
    static func emptyMapTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "emptyMapTitle", ru: "Карта пока пустая", en: "The map is still empty")
    }
    static func emptyMapSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "emptyMapSubtitle",
           ru: "Запишите первую поездку — и здесь засветится ваш след",
           en: "Record your first trip — your trail will light up here")
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
        let tail: String
        let head: String
        switch lang {
        case .ru:
            let noun = plural(lang, count,
                              one: "публичная поездка",
                              few: "публичные поездки",
                              many: "публичных поездок")
            let verb = plural(lang, count,
                              one: "Она останется в ленте",
                              many: "Они останутся в ленте")
            head = "В общей ленте у Вас \(count) \(noun). \(verb) после выхода, если Вы их не скроете."
            tail = "Приватные поездки и локальные данные не затрагиваются — Вы сможете снова войти и продолжить."
        case .en:
            let noun = plural(lang, count, one: "public trip", many: "public trips")
            let pron = plural(lang, count,
                              one: "It will stay in the feed",
                              many: "They will stay in the feed")
            head = "You have \(count) \(noun) in the social feed. \(pron) after sign out unless you hide them."
            tail = "Private trips and local data are not affected — you can sign back in anytime."
        case .de:
            let noun = plural(lang, count, one: "öffentliche Fahrt", many: "öffentliche Fahrten")
            let pron = plural(lang, count,
                              one: "Sie bleibt im Feed",
                              many: "Sie bleiben im Feed")
            head = "Du hast \(count) \(noun) im gemeinsamen Feed. \(pron) auch nach dem Abmelden, wenn du sie nicht verbirgst."
            tail = "Private Fahrten und lokale Daten sind nicht betroffen — du kannst dich jederzeit wieder anmelden."
        case .es:
            let noun = plural(lang, count, one: "viaje público", many: "viajes públicos")
            let pron = plural(lang, count,
                              one: "Seguirá en el feed",
                              many: "Seguirán en el feed")
            head = "Tienes \(count) \(noun) en el feed común. \(pron) tras cerrar sesión, salvo que los ocultes."
            tail = "Los viajes privados y los datos locales no se ven afectados: puedes volver a entrar cuando quieras."
        case .fr:
            let noun = plural(lang, count, one: "trajet public", many: "trajets publics")
            let pron = plural(lang, count,
                              one: "Il restera dans le fil",
                              many: "Ils resteront dans le fil")
            head = "Vous avez \(count) \(noun) dans le fil commun. \(pron) après la déconnexion, sauf si vous les masquez."
            tail = "Les trajets privés et les données locales ne sont pas touchés — vous pourrez vous reconnecter quand vous voudrez."
        case .it:
            let noun = plural(lang, count, one: "viaggio pubblico", many: "viaggi pubblici")
            let pron = plural(lang, count,
                              one: "Resterà nel feed",
                              many: "Resteranno nel feed")
            head = "Hai \(count) \(noun) nel feed comune. \(pron) anche dopo l'uscita, se non li nascondi."
            tail = "I viaggi privati e i dati locali non vengono toccati — puoi rientrare quando vuoi."
        case .pl:
            let noun = plural(lang, count,
                              one: "publiczną trasę",
                              few: "publiczne trasy",
                              many: "publicznych tras")
            let pron = plural(lang, count,
                              one: "Zostanie na tablicy",
                              many: "Zostaną na tablicy")
            head = "Masz \(count) \(noun) na wspólnej tablicy. \(pron) po wylogowaniu, jeśli ich nie ukryjesz."
            tail = "Prywatne trasy i dane lokalne pozostają nietknięte — możesz zalogować się ponownie w każdej chwili."
        case .id:
            let noun = plural(lang, count, one: "perjalanan publik", many: "perjalanan publik")
            let pron = "Perjalanan itu akan tetap di feed"
            head = "Kamu punya \(count) \(noun) di feed bersama. \(pron) setelah keluar, kecuali kamu sembunyikan."
            tail = "Perjalanan privat dan data di perangkat tidak terpengaruh — kamu bisa masuk lagi kapan saja."
        case .tr:
            let noun = "herkese açık gezi"
            let pron = plural(lang, count, one: "Çıkış yaptıktan sonra akışta kalır",
                              many: "Çıkış yaptıktan sonra akışta kalırlar")
            head = "Ortak akışta \(count) \(noun) var. \(pron), gizlemezsen."
            tail = "Özel geziler ve cihazdaki veriler etkilenmez — istediğin zaman tekrar giriş yapabilirsin."
        case .fil:
            let noun = plural(lang, count, one: "pampublikong biyahe", many: "pampublikong biyahe")
            let pron = plural(lang, count, one: "Mananatili ito sa feed", many: "Mananatili sila sa feed")
            head = "May \(count) \(noun) ka sa panlahatang feed. \(pron) pagkatapos mag-sign out, maliban kung itatago mo."
            tail = "Hindi apektado ang mga pribadong biyahe at ang datos sa device — puwede kang mag-sign in ulit anumang oras."
        case .uk:
            let noun = plural(lang, count,
                              one: "публічна поїздка",
                              few: "публічні поїздки",
                              many: "публічних поїздок")
            let verb = plural(lang, count,
                              one: "Вона залишиться у стрічці",
                              many: "Вони залишаться у стрічці")
            head = "У спільній стрічці у Вас \(count) \(noun). \(verb) після виходу, якщо Ви їх не сховаєте."
            tail = "Приватні поїздки та локальні дані не зачіпаються — Ви зможете знову увійти й продовжити."
        case .kk:
            let noun = "ашық сапар"
            let pron = "Олар шыққаннан кейін де таспада қалады"
            head = "Ортақ таспада сізде \(count) \(noun) бар. \(pron), егер жасырмасаңыз."
            tail = "Жеке сапарлар мен құрылғыдағы деректер өзгермейді — қалаған кезде қайта кіре аласыз."
        case .pt:
            let noun = plural(lang, count, one: "viagem pública", many: "viagens públicas")
            let pron = plural(lang, count, one: "Ela continuará no feed", many: "Elas continuarão no feed")
            head = "Você tem \(count) \(noun) no feed comum. \(pron) depois de sair, a menos que você as esconda."
            tail = "Viagens privadas e dados locais não são afetados — você pode entrar de novo quando quiser."
        }
        return "\(head)\n\n\(tail)"
    }
    static func exploredPercent(_ lang: LanguageManager.Language, percent: String, place: String) -> String {
        switch lang {
        case .ru: return "\(percent)% от \(place) исследовано"
        case .en: return "\(percent)% of \(place) explored"
        case .de: return "\(percent) % von \(place) erkundet"
        case .es: return "\(percent) % de \(place) explorado"
        case .fr: return "\(percent) % de \(place) exploré"
        case .it: return "\(percent)% di \(place) esplorato"
        case .pl: return "\(percent)% \(place) odkryte"
        case .id: return "\(percent)% dari \(place) dijelajahi"
        case .tr: return "\(place) bölgesinin %\(percent) kadarı keşfedildi"
        case .fil: return "\(percent)% ng \(place) ang natuklasan"
        case .uk: return "\(percent)% від \(place) досліджено"
        case .kk: return "\(place) аймағының \(percent)%-ы игерілді"
        case .pt: return "\(percent)% de \(place) explorado"
        }
    }
    static func tiles(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tiles", ru: "участков", en: "tiles")
    }

    // MARK: - GPS
    static func gpsAccuracyTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "gpsAccuracyTitle", ru: "Точность GPS", en: "GPS Accuracy")
    }
    static func gpsAccuracyBody(_ lang: LanguageManager.Language, current: String) -> String {
        let head = tr(lang, "gpsAccuracyCurrent", ru: "Текущая точность", en: "Current accuracy")
        let good = tr(lang, "gpsAccuracyGood", ru: "отличная", en: "excellent")
        let fair = tr(lang, "gpsAccuracyFair", ru: "средняя", en: "moderate")
        let note = tr(lang, "gpsAccuracyNote",
                      ru: "Влияет на точность записи маршрута. На открытой местности точность выше.",
                      en: "Affects route recording precision. Open areas provide better accuracy.")
        let unit = lang == .ru ? "м" : "m"
        return "\(head): \(current)\n\n🟢 ≤10\(unit) — \(good)\n🟠 >10\(unit) — \(fair)\n\n\(note)"
    }

    // MARK: - Trip Detail
    static func tripTitlePlaceholder(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripTitlePlaceholder", ru: "Название поездки", en: "Trip title")
    }

    // MARK: - Trip Detail poster (0.6.0)
    static func reliveTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reliveTrip", ru: "Прожить заново", en: "Relive")
    }
    static func watchTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "watchTrip", ru: "Смотреть поездку", en: "Watch trip")
    }
    static func detailsSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "detailsSection", ru: "Детали", en: "Details")
    }
    static func elevationProfile(_ lang: LanguageManager.Language) -> String {
        tr(lang, "elevationProfile", ru: "Профиль высоты", en: "Elevation profile")
    }
    static func speedSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "speedSection", ru: "Скорость", en: "Speed")
    }
    static func movingAndStops(_ lang: LanguageManager.Language) -> String {
        tr(lang, "movingAndStops", ru: "Движение", en: "Movement")
    }
    static func movingDot(_ lang: LanguageManager.Language, _ value: String) -> String {
        "\(statMoving(lang)) · \(value)"
    }
    /// «Стоянки» read as car parks. This is the time the trip was standing
    /// still — at lights, in traffic, waiting at a barrier — so it is named
    /// as the plain opposite of «В движении».
    static func stopsDot(_ lang: LanguageManager.Language, _ value: String) -> String {
        "\(statStops(lang)) · \(value)"
    }
    /// Detail-context header for the trip notes ("Описание"). `notes` stays
    /// for legacy call sites.
    static func descriptionSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "descriptionSection", ru: "Описание", en: "Description")
    }
    static func tripAchievements(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripAchievements", ru: "Достижения поездки", en: "Trip achievements")
    }
    static func reactionsTitleN(_ lang: LanguageManager.Language, _ n: Int) -> String {
        "\(chipReactions(lang)) · \(n)"
    }
    // Detail stat-grid short labels. Detail-scoped cases: the onboarding set
    // maps «Расход»→"Fuel" for the mock card, which would collide with the
    // fuel-volume vs fuel-cost split the detail grid needs.
    static func statMoving(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statMoving", ru: "В движении", en: "Moving")
    }
    static func statStops(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statStops", ru: "Без движения", en: "Stopped")
    }
    static func statAvg(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statAvg", ru: "Средняя", en: "Avg")
    }
    static func statMax(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statMax", ru: "Макс", en: "Max")
    }
    static func statFuel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statFuel", ru: "Топливо", en: "Fuel")
    }
    static func statCost(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statCost", ru: "Расход", en: "Cost")
    }
    static func chartAltitudeLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "chartAltitudeLabel", ru: "ВЫСОТА", en: "ALTITUDE")
    }
    static func chartSpeedLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "chartSpeedLabel", ru: "КМ/Ч", en: "KM/H")
    }
    static func chartMaxElev(_ lang: LanguageManager.Language, max: String, gain: String) -> String {
        "\(shortMax(lang)) \(max) · ↑ \(gain)"
    }

    /// Lowercase «макс» / «max» for chart captions — the all-caps `maxShort`
    /// belongs to stat tiles and shouts inside a caption.
    static func shortMax(_ lang: LanguageManager.Language) -> String {
        tr(lang, "shortMax", ru: "макс", en: "max")
    }

    /// Lowercase «ср» / «avg», same reason.
    static func shortAvg(_ lang: LanguageManager.Language) -> String {
        tr(lang, "shortAvg", ru: "ср", en: "avg")
    }
    static func chartMaxAvg(_ lang: LanguageManager.Language, max: String, avg: String) -> String {
        "\(shortMax(lang)) \(max) · \(shortAvg(lang)) \(avg)"
    }
    static func privacyOnlyMe(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyOnlyMe", ru: "Только для меня", en: "Only me")
    }
    static func privacyPublic(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyPublic", ru: "Видна всем", en: "Public")
    }
    static func share(_ lang: LanguageManager.Language) -> String {
        tr(lang, "share", ru: "Поделиться", en: "Share")
    }
    static func noReactionsYet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noReactionsYet", ru: "Пока никто не отреагировал", en: "No reactions yet")
    }
    static func beFirstToReact(_ lang: LanguageManager.Language) -> String {
        tr(lang, "beFirstToReact",
           ru: "Будьте первым, кто отреагирует",
           en: "Be the first to react")
    }
    // levelShort deleted — the app-wide LVL convention is the hardcoded
    // "LVL n" pixel-font tag; the last caller migrated to it.

    // MARK: - Discussion (0.6.0)
    //
    // The product calls this ОБСУЖДЕНИЕ, not «комментарии» — a trip is a story
    // people talk about, and the word «комментарий» never appears in the UI.
    // The function names keep the old spelling so the diff stays readable.
    static func commentsTitleN(_ lang: LanguageManager.Language, _ n: Int) -> String {
        "\(comments(lang)) · \(n)"
    }
    static func commentPlaceholder(_ lang: LanguageManager.Language) -> String {
        tr(lang, "commentPlaceholder", ru: "Написать в обсуждение…", en: "Write in the discussion…")
    }
    /// Centred pill under the teaser: «Всё обсуждение · 12 ›».
    static func discussionSeeAllPill(_ lang: LanguageManager.Language, _ n: Int) -> String {
        "\(tr(lang, "discussionSeeAllPillHead", ru: "Всё обсуждение", en: "Whole discussion")) · \(n)"
    }
    /// Zero state — the card stays, the invitation changes.
    static func writeFirstMessage(_ lang: LanguageManager.Language) -> String {
        tr(lang, "writeFirstMessage",
           ru: "Написать первое сообщение…",
           en: "Write the first message…")
    }
    static func send(_ lang: LanguageManager.Language) -> String {
        tr(lang, "send", ru: "Отправить", en: "Send")
    }
    static func showMoreComments(_ lang: LanguageManager.Language) -> String {
        tr(lang, "showMoreComments", ru: "Показать ещё", en: "Show more")
    }
    static func deleteCommentConfirm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteCommentConfirm", ru: "Удалить комментарий?", en: "Delete comment?")
    }
    static func commentPostFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "commentPostFailed",
           ru: "Не удалось отправить комментарий",
           en: "Couldn't post the comment")
    }
    static func commentDeleteFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "commentDeleteFailed",
           ru: "Не удалось удалить комментарий",
           en: "Couldn't delete the comment")
    }
    static func signInPromptComment(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptComment",
           ru: "Войдите, чтобы комментировать",
           en: "Sign in to comment")
    }
    // Relative comment age — compact «2 ч» / "2 h" style (Figma «· 2 ч»).
    static func relTimeNow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "relTimeNow", ru: "сейчас", en: "now")
    }
    static func relTimeMinutes(_ lang: LanguageManager.Language, _ n: Int) -> String {
        "\(n) \(minutesUnitShort(lang))"
    }
    static func relTimeHours(_ lang: LanguageManager.Language, _ n: Int) -> String {
        "\(n) \(hoursUnitShort(lang))"
    }
    static func relTimeDays(_ lang: LanguageManager.Language, _ n: Int) -> String {
        "\(n) \(tr(lang, "daysUnitShort", ru: "д", en: "d"))"
    }

    // MARK: - Publish flow (0.6.0)
    static func publishTripTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishTripTitle", ru: "Опубликовать поездку?", en: "Publish trip?")
    }
    static func publishAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishAction", ru: "Опубликовать", en: "Publish")
    }
    static func publishOptionalDescLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishOptionalDescLabel",
           ru: "ОПИСАНИЕ · НЕОБЯЗАТЕЛЬНО",
           en: "DESCRIPTION · OPTIONAL")
    }
    static func publishDescPlaceholder(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishDescPlaceholder",
           ru: "Расскажите о поездке: дорога, погода, остановки…",
           en: "What was the trip like? Roads, weather, stops…")
    }
    static func publishing(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishing", ru: "Публикуется…", en: "Publishing…")
    }
    static func publishFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishFailed", ru: "Не удалось опубликовать", en: "Couldn't publish")
    }
    static func publishFailedBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishFailedBody",
           ru: "Нет связи с сервером. Поездка пока видна только Вам — мы повторим автоматически.",
           en: "No connection. The trip is only visible to you for now — we'll retry automatically.")
    }
    static func retry(_ lang: LanguageManager.Language) -> String {
        tr(lang, "retry", ru: "Повторить", en: "Retry")
    }
    static func tripLoadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripLoadFailed", ru: "Не удалось загрузить поездку", en: "Couldn't load the trip")
    }
    static func tripLoadFailedBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripLoadFailedBody",
           ru: "Проверьте подключение к интернету и попробуйте ещё раз",
           en: "Check your internet connection and try again")
    }
    /// Someone else's trip that has been taken out of the feed. Deliberately
    /// says what happened rather than «не удалось загрузить»: nothing failed,
    /// the author simply closed it, and offering «попробовать снова» for that
    /// is an invitation to retry something that will never change.
    /// The thread could not be read at all — as opposed to a thread that is
    /// simply empty. Saying «пока никто ничего не написал» over a heading that
    /// counts five messages is the app contradicting itself out loud.
    static func discussionUnavailable(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discussionUnavailable",
           ru: "Не удалось загрузить обсуждение",
           en: "Couldn't load the discussion")
    }
    /// A thread kept on the device after the trip left the server.
    /// Companions shown from the device's copy of a trip the server no longer
    /// holds. No «повторить» beside it — there is nothing to retry against.
    static func companionsSavedCopy(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsSavedCopy",
           ru: "Сохранено на устройстве — поездка не на сервере",
           en: "Saved on this device — the trip is not on the server")
    }
    static func discussionArchived(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discussionArchived",
           ru: "Сохранённая копия обсуждения — поездка больше не на сервере",
           en: "A saved copy — this trip is no longer on the server")
    }
    static func tripPrivateTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripPrivateTitle", ru: "Поездка закрыта", en: "This trip is private")
    }
    static func tripPrivateBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripPrivateBody",
           ru: "Автор сделал её приватной — теперь её видит только он.",
           en: "The author made it private — only they can see it now.")
    }
    static func tryAgain(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tryAgain", ru: "Попробовать снова", en: "Try again")
    }

    // MARK: - UX Actions
    static func undo(_ lang: LanguageManager.Language) -> String {
        tr(lang, "undo", ru: "Отменить", en: "Undo")
    }
    static func tripDeleted(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripDeleted", ru: "Поездка удалена", en: "Trip deleted")
    }
    static func photoDeleted(_ lang: LanguageManager.Language) -> String {
        tr(lang, "photoDeleted", ru: "Фото удалено", en: "Photo deleted")
    }
    static func deletePhoto(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deletePhoto", ru: "Удалить фото?", en: "Delete photo?")
    }
    static func delete(_ lang: LanguageManager.Language) -> String {
        tr(lang, "delete", ru: "Удалить", en: "Delete")
    }
    static func deleteTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteTrip", ru: "Удалить поездку?", en: "Delete trip?")
    }
    static func cancel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "cancel", ru: "Отмена", en: "Cancel")
    }
    static func noResults(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noResults", ru: "Ничего не найдено", en: "No results")
    }
    static func tryOtherFilters(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tryOtherFilters", ru: "Попробуйте другие фильтры", en: "Try different filters")
    }
    static func timeToRide(_ lang: LanguageManager.Language) -> String {
        tr(lang, "timeToRide", ru: "Время в путь!", en: "Time to ride!")
    }
    static func recordAndBuild(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordAndBuild",
           ru: "Записывайте поездки и создавайте свою историю дорог",
           en: "Record trips and build your road story")
    }

    // MARK: - Links
    static func writeAuthor(_ lang: LanguageManager.Language) -> String {
        tr(lang, "writeAuthor", ru: "Написать автору", en: "Contact author")
    }
    static func bugsAndIdeas(_ lang: LanguageManager.Language) -> String {
        tr(lang, "bugsAndIdeas", ru: "Баги, идеи, предложения", en: "Bugs, ideas, suggestions")
    }
    static func telegramChannel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "telegramChannel", ru: "Telegram-канал", en: "Telegram channel")
    }
    static func telegramChannelSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "telegramChannelSub",
           ru: "Разработка TripTrack в реальном времени",
           en: "TripTrack development in real time")
    }
    static func githubSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "githubSub", ru: "Открытый исходный код", en: "Open-source project")
    }
    static func youtubeSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "youtubeSub", ru: "Видео о разработке", en: "Development videos")
    }

    // MARK: - Photos & Notes
    static func notes(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notes", ru: "Заметки", en: "Notes")
    }
    static func addNotes(_ lang: LanguageManager.Language) -> String {
        tr(lang, "addNotes", ru: "Добавить заметку...", en: "Add a note...")
    }
    /// Discoverable empty-state CTA on the owner's own trip detail.
    static func addNotesCTA(_ lang: LanguageManager.Language) -> String {
        tr(lang, "addNotesCTA", ru: "Добавьте описание поездки", en: "Add a trip description")
    }
    static func addPhotos(_ lang: LanguageManager.Language) -> String {
        tr(lang, "addPhotos", ru: "Добавить фото", en: "Add photos")
    }

    // MARK: - Auto-record
    static func autoRecord(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoRecord", ru: "Автозапись", en: "Auto-record")
    }
    static func autoRecordMode(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoRecordMode", ru: "Режим", en: "Mode")
    }
    static func autoRecordOff(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoRecordOff", ru: "Выкл", en: "Off")
    }
    static func autoRecordOn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoRecordOn", ru: "Вкл", en: "On")
    }
    static func autoRecordRemind(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoRecordRemind", ru: "Напоминание", en: "Remind")
    }
    static func autoRecordAuto(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoRecordAuto", ru: "Авто", en: "Auto")
    }
    static func myDevices(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myDevices", ru: "Мои устройства", en: "My devices")
    }
    static func addDevice(_ lang: LanguageManager.Language) -> String {
        tr(lang, "addDevice", ru: "Добавить устройство", en: "Add device")
    }
    static func linkStereo(_ lang: LanguageManager.Language) -> String {
        tr(lang, "linkStereo", ru: "Привязать магнитолу", en: "Link car stereo")
    }
    static func enterDeviceName(_ lang: LanguageManager.Language) -> String {
        tr(lang, "enterDeviceName", ru: "Введите имя устройства", en: "Enter device name")
    }
    static func enterDeviceNameHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "enterDeviceNameHint",
           ru: "Откройте Настройки → Bluetooth на iPhone и скопируйте имя магнитолы",
           en: "Open Settings → Bluetooth on your iPhone and copy the stereo name")
    }
    static func save(_ lang: LanguageManager.Language) -> String {
        tr(lang, "save", ru: "Сохранить", en: "Save")
    }
    static func nearbyDevices(_ lang: LanguageManager.Language) -> String {
        tr(lang, "nearbyDevices", ru: "Устройства рядом", en: "Nearby devices")
    }
    static func autoRecordDescription(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoRecordDescription",
           ru: "Запись начнётся автоматически при подключении к магнитоле по Bluetooth",
           en: "Recording starts automatically when connected to the car stereo via Bluetooth")
    }
    static func remindModeDescription(_ lang: LanguageManager.Language) -> String {
        tr(lang, "remindModeDescription",
           ru: "Уведомление с кнопкой \"Начать запись\" при подключении",
           en: "Push notification with \"Start recording\" button on connection")
    }
    static func autoModeDescription(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoModeDescription",
           ru: "Запись начинается сразу, без касания телефона",
           en: "Recording starts immediately, no phone interaction needed")
    }
    static func autoStopDescription(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoStopDescription",
           ru: "Поездка автоматически завершится через это время после отключения от магнитолы",
           en: "Trip auto-stops this long after disconnecting from the stereo")
    }
    static func autoStopTimeout(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoStopTimeout", ru: "Автозавершение", en: "Auto-stop")
    }
    static func autoStopMinutes(_ lang: LanguageManager.Language, minutes: Int) -> String {
        "\(minutes) \(minutesUnitShort(lang))"
    }
    static func scanningDevices(_ lang: LanguageManager.Language) -> String {
        tr(lang, "scanningDevices", ru: "Поиск устройств...", en: "Scanning for devices...")
    }
    static func scanHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "scanHint",
           ru: "Убедитесь, что Вы в машине и магнитола включена",
           en: "Make sure you're in the car with the stereo on")
    }
    static func noDevicesFound(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noDevicesFound", ru: "Устройства не найдены", en: "No devices found")
    }
    static func currentAudioOutput(_ lang: LanguageManager.Language) -> String {
        tr(lang, "currentAudioOutput", ru: "Текущий аудиовыход", en: "Current audio output")
    }
    static func bluetoothRequired(_ lang: LanguageManager.Language) -> String {
        tr(lang, "bluetoothRequired",
           ru: "Для автозаписи нужен доступ к Bluetooth",
           en: "Auto-record requires Bluetooth access")
    }
    static func notificationsRequired(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationsRequired",
           ru: "Для напоминаний нужны уведомления",
           en: "Notifications are required for reminders")
    }
    static func openSettings(_ lang: LanguageManager.Language) -> String {
        tr(lang, "openSettings", ru: "Открыть настройки", en: "Open Settings")
    }

    // MARK: - Auto-record Notifications
    static func notifTripStartTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifTripStartTitle",
           ru: "Похоже, Вы в машине",
           en: "Looks like you're in the car")
    }
    static func notifTripStartBody(_ lang: LanguageManager.Language, deviceName: String) -> String {
        switch lang {
        case .ru: return "Подключено к \(deviceName). Начать запись?"
        case .en: return "Connected to \(deviceName). Start recording?"
        case .de: return "Mit \(deviceName) verbunden. Aufnahme starten?"
        case .es: return "Conectado a \(deviceName). ¿Empezar a grabar?"
        case .fr: return "Connecté à \(deviceName). Démarrer l'enregistrement ?"
        case .it: return "Connesso a \(deviceName). Avviare la registrazione?"
        case .pl: return "Połączono z \(deviceName). Zacząć nagrywanie?"
        case .id: return "Terhubung ke \(deviceName). Mulai merekam?"
        case .tr: return "\(deviceName) bağlandı. Kayıt başlasın mı?"
        case .fil: return "Nakakonekta sa \(deviceName). Simulan ang pag-record?"
        case .uk: return "Підключено до \(deviceName). Почати запис?"
        case .kk: return "\(deviceName) құрылғысына қосылды. Жазуды бастау керек пе?"
        case .pt: return "Conectado a \(deviceName). Começar a gravar?"
        }
    }
    static func notifTripStartAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifTripStartAction", ru: "Начать запись", en: "Start Recording")
    }
    static func notifSkipAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifSkipAction", ru: "Пропустить", en: "Skip")
    }
    static func notifTripStopTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifTripStopTitle", ru: "Поездка закончена?", en: "Trip finished?")
    }
    enum TripStopReason {
        case bluetooth
        case inactivity
    }
    static func notifTripStopBody(_ lang: LanguageManager.Language, minutes: Int, reason: TripStopReason) -> String {
        let cause: String
        switch reason {
        case .bluetooth:
            cause = tr(lang, "notifStopCauseBluetooth",
                       ru: "Bluetooth отключился.", en: "Bluetooth disconnected.")
        case .inactivity:
            cause = tr(lang, "notifStopCauseInactivity",
                       ru: "Машина не движется.", en: "Vehicle isn't moving.")
        }
        let mins = "\(minutes) \(minutesUnitShort(lang))"
        let tail: String
        switch lang {
        case .ru: tail = "Автозавершение через \(mins)"
        case .en: tail = "Auto-stop in \(mins)"
        case .de: tail = "Automatisches Ende in \(mins)"
        case .es: tail = "Fin automático en \(mins)"
        case .fr: tail = "Arrêt automatique dans \(mins)"
        case .it: tail = "Chiusura automatica tra \(mins)"
        case .pl: tail = "Automatyczne zakończenie za \(mins)"
        case .id: tail = "Berhenti otomatis dalam \(mins)"
        case .tr: tail = "\(mins) içinde otomatik olarak bitecek"
        case .fil: tail = "Awtomatikong titigil sa loob ng \(mins)"
        case .uk: tail = "Автозавершення через \(mins)"
        case .kk: tail = "\(mins) кейін автоматты аяқталады"
        case .pt: tail = "Encerramento automático em \(mins)"
        }
        return "\(cause) \(tail)"
    }
    static func notifStopNowAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifStopNowAction", ru: "Завершить сейчас", en: "Stop Now")
    }
    static func notifContinueAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifContinueAction", ru: "Продолжить", en: "Continue")
    }
    static func notifAutoStartTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifAutoStartTitle", ru: "Запись началась", en: "Recording started")
    }
    static func notifAutoStartBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifAutoStartBody",
           ru: "TripTrack автоматически начал запись",
           en: "TripTrack automatically started recording")
    }
    /// Canon 510:119 — saving the share card needs somewhere to save it to.
    static func photoAccessAlertTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "photoAccessAlertTitle",
           ru: "Разрешите доступ к Фото",
           en: "Allow access to Photos")
    }
    static func photoAccessAlertBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "photoAccessAlertBody",
           ru: "Чтобы сохранить карточку поездки в Фото, откройте доступ в Настройках.",
           en: "To save the trip card to Photos, allow access in Settings.")
    }
    static func close(_ lang: LanguageManager.Language) -> String {
        tr(lang, "close", ru: "Закрыть", en: "Close")
    }
    /// «Получен 14 мая 2026 · Дача и обратно» (Figma 117:1582). The trip is
    /// what makes the date mean anything, so it joins the line when we know it.
    /// The tail of «Получено 15 раз · последний 9 августа 2026» — lowercase
    /// on purpose, it continues a sentence rather than starting one.
    static func badgeLastEarned(_ lang: LanguageManager.Language, date: Date) -> String {
        let day = longDate(date, lang)
        switch lang {
        case .ru: return "последний \(day)"
        case .en: return "last on \(day)"
        case .de: return "zuletzt am \(day)"
        case .es: return "el último el \(day)"
        case .fr: return "le dernier le \(day)"
        case .it: return "l'ultimo il \(day)"
        case .pl: return "ostatni \(day)"
        case .id: return "terakhir \(day)"
        case .tr: return "son olarak \(day)"
        case .fil: return "huling \(day)"
        case .uk: return "останній \(day)"
        case .kk: return "соңғысы \(day)"
        case .pt: return "o último em \(day)"
        }
    }

    /// «14 мая 2026» in whatever the language writes a long date as — the
    /// template, not a hand-written `dateFormat`, so German gets «14. Mai
    /// 2026» and English «May 14, 2026» instead of a Russian day-first order.
    static func longDate(_ date: Date, _ lang: LanguageManager.Language) -> String {
        let f = DateFormatter()
        f.locale = lang.locale
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return f.string(from: date)
    }
    static func badgeEarnedOn(
        _ lang: LanguageManager.Language,
        date: Date,
        tripTitle: String?
    ) -> String {
        let prefix = tr(lang, "badgeEarnedOnPrefix", ru: "Получен", en: "Earned")
        var line = "\(prefix) \(longDate(date, lang))"
        if let tripTitle, !tripTitle.isEmpty {
            line += " · \(tripTitle)"
        }
        return line
    }
    static func noCommentsYet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noCommentsYet",
           ru: "Пока никто ничего не написал.",
           en: "Nobody has written anything yet.")
    }
    static func addReaction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "addReaction", ru: "Поставить реакцию", en: "Add a reaction")
    }

    // MARK: - Locked social sections on a private trip (Figma 545:499)

    static func publishForReactionsTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishForReactionsTitle",
           ru: "Опубликуйте, чтобы получить реакции",
           en: "Publish to get reactions")
    }
    static func publishForReactionsBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishForReactionsBody",
           ru: "Появятся, когда поездка станет публичной",
           en: "They appear once the trip is public")
    }
    static func publishForCommentsTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishForCommentsTitle",
           ru: "Опубликуйте, чтобы открыть обсуждение",
           en: "Publish to open the discussion")
    }
    static func publishForCommentsBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishForCommentsBody",
           ru: "Обсуждение доступно на публичных поездках",
           en: "The discussion lives on public trips")
    }

    // MARK: - Photo picker (Figma 117:587)

    static func choosePhotosTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "choosePhotosTitle", ru: "Выберите фото", en: "Choose photos")
    }
    static func managePhotoAccess(_ lang: LanguageManager.Language) -> String {
        tr(lang, "managePhotoAccess", ru: "Показать больше фото…", en: "Show more photos…")
    }
    static func noPhotosInLibrary(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noPhotosInLibrary",
           ru: "В медиатеке нет фотографий",
           en: "No photos in your library")
    }
    static func photoAccessDenied(_ lang: LanguageManager.Language) -> String {
        tr(lang, "photoAccessDenied",
           ru: "Нет доступа к фотографиям. Разрешите его в Настройках, чтобы добавить снимки к поездке.",
           en: "No access to photos. Allow it in Settings to attach photos to a trip.")
    }

    /// Where along the route a chart sample sits: «212-й км» / «km 212».
    static func chartKmMark(_ lang: LanguageManager.Language, km: Double) -> String {
        let n = max(0, Int(km.rounded()))
        switch lang {
        case .ru: return "\(n)-й км"
        case .en: return "km \(n)"
        case .de: return "km \(n)"
        case .es: return "km \(n)"
        case .fr: return "km \(n)"
        case .it: return "km \(n)"
        case .pl: return "\(n). km"
        case .id: return "km \(n)"
        case .tr: return "\(n). km"
        case .fil: return "km \(n)"
        case .uk: return "\(n)-й км"
        case .kk: return "\(n)-км"
        case .pt: return "km \(n)"
        }
    }

    // MARK: - Trip edit sheet (Figma 543:119)

    static func editTripTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "editTripTitle", ru: "Редактировать поездку", en: "Edit trip")
    }
    static func tripTitleLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripTitleLabel", ru: "Название", en: "Name")
    }
    static func vehicleSectionLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleSectionLabel", ru: "Машина", en: "Car")
    }
    static func accessSectionLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "accessSectionLabel", ru: "Доступ", en: "Access")
    }
    /// Under the access row: what the current state actually means, since
    /// «Видна всем» and «Только вы» each describe half of it.
    static func privacyPublicHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyPublicHint",
           ru: "Публичная — в общей ленте",
           en: "Public — in the shared feed")
    }
    static func privacyOnlyMeHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyOnlyMeHint",
           ru: "Приватная — видите только вы",
           en: "Private — only you can see it")
    }

    /// A trip too short to be worth keeping was deleted on stop. Saying so is
    /// the whole point: the alternative is a recording that silently
    /// evaporates, which reads as data loss rather than as housekeeping.
    static func junkTripDiscarded(_ lang: LanguageManager.Language) -> String {
        tr(lang, "junkTripDiscarded",
           ru: "Поездка не сохранена — слишком короткая",
           en: "Trip not saved — too short")
    }
    static func notifAutoStartFailedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifAutoStartFailedTitle",
           ru: "Запись не началась",
           en: "Recording didn't start")
    }
    /// Names the obstacle when we know it — «что-то пошло не так» is useless
    /// standing at the car, while «нет доступа к геолокации» can be acted on.
    static func notifAutoStartFailedBody(
        _ lang: LanguageManager.Language,
        reason: MapViewModel.StartRefusal?
    ) -> String {
        switch reason {
        case .locationDenied:
            return tr(lang, "notifStartFailedNoGeo",
                      ru: "Нет доступа к геолокации — включите его в Настройках",
                      en: "No location access — turn it on in Settings")
        case .recoveryPending:
            return tr(lang, "notifStartFailedRecovery",
                      ru: "Сначала завершите прошлую поездку — откройте приложение",
                      en: "Finish the previous trip first — open the app")
        case .noFix, .unknown, .none:
            return tr(lang, "notifStartFailedManual",
                      ru: "Откройте приложение и начните поездку вручную",
                      en: "Open the app and start the trip manually")
        }
    }
    static func notifAutoStopTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifAutoStopTitle", ru: "Поездка завершена", en: "Trip completed")
    }
    static func notifAutoStopSummary(_ lang: LanguageManager.Language, km: String, time: String) -> String {
        "\(km) \(AppStrings.km(lang)) · \(time)"
    }
    static func notifAutoStopBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifAutoStopBody", ru: "Автозавершение поездки", en: "Auto-stopping trip")
    }
    static func bluetoothAudio(_ lang: LanguageManager.Language) -> String {
        tr(lang, "bluetoothAudio", ru: "Bluetooth-аудио", en: "Bluetooth Audio")
    }
    static func strongSignal(_ lang: LanguageManager.Language) -> String {
        tr(lang, "strongSignal", ru: "Сильный сигнал", en: "Strong signal")
    }
    static func mediumSignal(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mediumSignal", ru: "Средний сигнал", en: "Medium signal")
    }
    static func weakSignal(_ lang: LanguageManager.Language) -> String {
        tr(lang, "weakSignal", ru: "Слабый сигнал", en: "Weak signal")
    }
    static func done(_ lang: LanguageManager.Language) -> String {
        tr(lang, "done", ru: "Готово", en: "Done")
    }
    static func car(_ lang: LanguageManager.Language) -> String {
        tr(lang, "car", ru: "Автомобиль", en: "Car")
    }
    static func added(_ lang: LanguageManager.Language) -> String {
        tr(lang, "added", ru: "Добавлено", en: "Added")
    }
    static func linked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "linked", ru: "Привязано", en: "Linked")
    }

    // MARK: - Auth

    static func guest(_ lang: LanguageManager.Language) -> String {
        tr(lang, "guest", ru: "Гость", en: "Guest")
    }
    static func signInToSync(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInToSync", ru: "Войдите для синхронизации", en: "Sign in to sync trips")
    }
    static func signedIn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signedIn", ru: "Вы вошли", en: "Signed in")
    }
    static func synced(_ lang: LanguageManager.Language) -> String {
        tr(lang, "synced", ru: "Синхронизировано", en: "Synced")
    }
    static func syncComingSoon(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncComingSoon", ru: "Синхронизация скоро", en: "Sync coming soon")
    }
    static func signOut(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signOut", ru: "Выйти", en: "Sign out")
    }
    static func signOutConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signOutConfirmTitle", ru: "Выйти?", en: "Sign out?")
    }
    static func signOutConfirmMessage(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signOutConfirmMessage",
           ru: "Ваши поездки останутся на устройстве",
           en: "Your trips will remain on this device")
    }
    static func deleteAccount(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteAccount", ru: "Удалить аккаунт", en: "Delete account")
    }
    /// The settings row. Same words as the canon frame (117:1412 danger row).
    static func deleteAccountTitle(_ lang: LanguageManager.Language) -> String {
        deleteAccount(lang)
    }
    /// «Безвозвратно, везде» is a promise, and the flow behind it keeps it:
    /// the server account AND everything this device holds — see
    /// `LocalDataWipe`.
    static func deleteAccountSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteAccountSubtitle", ru: "Безвозвратно, везде", en: "Permanently, everywhere")
    }
    static func deleteAccountConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteAccountConfirmTitle", ru: "Удалить аккаунт?", en: "Delete account?")
    }
    /// Names everything that goes, in the order the user would miss it.
    /// A destructive dialog that hedges is worse than none: this one has to
    /// leave nobody surprised afterwards.
    static func deleteAccountConfirmBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteAccountConfirmBody",
           ru: "Аккаунт и всё, что на сервере — поездки, фото, машины, реакции и комментарии — удаляются навсегда. Поездки и фото на этом устройстве тоже будут стёрты. Вернуть это будет нельзя.",
           en: "Your account and everything on the server — trips, photos, vehicles, reactions and comments — are deleted for good. The trips and photos on this device are erased too. There is no way back.")
    }
    static func deleteAccountConfirmAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteAccountConfirmAction", ru: "Удалить навсегда", en: "Delete forever")
    }
    static func deleteAccountFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteAccountFailed",
           ru: "Не удалось удалить аккаунт. Попробуйте ещё раз.",
           en: "Couldn't delete account. Please try again.")
    }
    static func dangerZone(_ lang: LanguageManager.Language) -> String {
        tr(lang, "dangerZone", ru: "Опасная зона", en: "Danger zone")
    }

    // MARK: - Sync status sheet

    static func syncStatusTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusTitle", ru: "Очередь синхронизации", en: "Sync queue")
    }
    static func syncStatusPendingHeader(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusPendingHeader", ru: "В очереди", en: "Pending")
    }
    static func syncStatusFailedHeader(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusFailedHeader", ru: "Не удалось", en: "Failed")
    }
    static func syncStatusEmpty(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusEmpty", ru: "Всё синхронизировано.", en: "Everything is up to date.")
    }
    static func syncStatusRetry(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusRetry", ru: "Повторить сейчас", en: "Retry now")
    }
    static func syncStatusNowLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusNowLabel", ru: "Сейчас", en: "Now")
    }
    static func syncAttemptsLabel(_ count: Int, _ lang: LanguageManager.Language) -> String {
        let word: String
        switch lang {
        case .ru: word = plural(lang, count, one: "попытка", few: "попытки", many: "попыток")
        case .en: word = plural(lang, count, one: "attempt", many: "attempts")
        case .de: word = plural(lang, count, one: "Versuch", many: "Versuche")
        case .es: word = plural(lang, count, one: "intento", many: "intentos")
        case .fr: word = plural(lang, count, one: "tentative", many: "tentatives")
        case .it: word = plural(lang, count, one: "tentativo", many: "tentativi")
        case .pl: word = plural(lang, count, one: "próba", few: "próby", many: "prób")
        case .id: word = "percobaan"
        case .tr: word = "deneme"
        case .fil: word = plural(lang, count, one: "pagsubok", many: "pagsubok")
        case .uk: word = plural(lang, count, one: "спроба", few: "спроби", many: "спроб")
        case .kk: word = "әрекет"
        case .pt: word = plural(lang, count, one: "tentativa", many: "tentativas")
        }
        return "\(count) \(word)"
    }

    // MARK: - Sign-in prompt sheet

    static func signInPromptReact(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptReact", ru: "Войдите, чтобы реагировать", en: "Sign in to react")
    }
    static func signInPromptFollow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptFollow", ru: "Войдите, чтобы подписаться", en: "Sign in to follow")
    }
    static func signInPromptShare(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptShare", ru: "Войдите, чтобы поделиться", en: "Sign in to share")
    }
    static func signInPromptSync(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptSync", ru: "Войдите для синхронизации", en: "Sign in to sync")
    }
    static func signInPromptPublish(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptPublish", ru: "Войдите, чтобы опубликовать", en: "Sign in to publish")
    }
    static func signInPromptCompanions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptCompanions",
           ru: "Войдите, чтобы звать попутчиков",
           en: "Sign in to invite companions")
    }
    static func signInPromptGeneric(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptGeneric", ru: "Войдите в TripTrack", en: "Sign in to TripTrack")
    }
    static func signInPromptSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptSubtitle",
           ru: "Реакции, подписки и публикация — после входа. Ваши поездки остаются на устройстве.",
           en: "Reactions, follows and publishing — after you sign in. Your trips stay on your device.")
    }
    static func signInLoading(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInLoading", ru: "Входим…", en: "Signing in…")
    }
    static func signInErrorRetry(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInErrorRetry",
           ru: "Не удалось войти. Попробуйте ещё раз.",
           en: "Couldn't sign in. Please try again.")
    }
    /// Legal footnote with a tappable Markdown link on the last word.
    static func signInLegalMarkdown(_ lang: LanguageManager.Language, termsURL: String) -> String {
        let terms = "[\(tr(lang, "signInLegalTermsWord", ru: "условиями", en: "terms"))](\(termsURL))"
        switch lang {
        case .ru: return "Продолжая, Вы соглашаетесь с \(terms)"
        case .en: return "By continuing, you agree to the \(terms)"
        case .de: return "Wenn du fortfährst, stimmst du den \(terms) zu"
        case .es: return "Si continúas, aceptas las \(terms)"
        case .fr: return "En continuant, vous acceptez les \(terms)"
        case .it: return "Continuando, accetti i \(terms)"
        case .pl: return "Kontynuując, akceptujesz \(terms)"
        case .id: return "Dengan melanjutkan, Anda menyetujui \(terms)"
        case .tr: return "Devam ederek \(terms) kabul edersiniz"
        case .fil: return "Sa pagpapatuloy, sumasang-ayon ka sa \(terms)"
        case .uk: return "Продовжуючи, Ви погоджуєтесь з \(terms)"
        case .kk: return "Жалғастыра отырып, сіз \(terms) қабылдайсыз"
        case .pt: return "Ao continuar, você concorda com os \(terms)"
        }
    }
    static func signInPromptAppleFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInPromptAppleFailed",
           ru: "Apple-вход не сработал. Проверьте, что Вы залогинены в iCloud в настройках устройства.",
           en: "Apple sign-in failed. Make sure you're signed into iCloud in device Settings.")
    }
    static func signInFailedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInFailedTitle", ru: "Не удалось войти", en: "Sign in failed")
    }
    static func ok(_ lang: LanguageManager.Language) -> String {
        tr(lang, "ok", ru: "ОК", en: "OK")
    }

    // MARK: - Guest mode banners / CTAs

    static func guestFeedBanner(_ lang: LanguageManager.Language) -> String {
        tr(lang, "guestFeedBanner",
           ru: "Войдите, чтобы подписываться и реагировать",
           en: "Sign in to follow and react")
    }
    static func syncCardKicker(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncCardKicker", ru: "СИНХРОНИЗАЦИЯ", en: "SYNC")
    }
    static func syncCardTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncCardTitle",
           ru: "Поездки на всех устройствах",
           en: "Your trips on every device")
    }
    static func syncCardBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncCardBody",
           ru: "Войдите, чтобы открыть свою историю на других устройствах. Все поездки уже здесь.",
           en: "Sign in to see your history on your other devices. All your trips are already here.")
    }
    static func syncCardLater(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncCardLater",
           ru: "Можно позже — ничего не потеряется",
           en: "You can do it later — nothing gets lost")
    }
    /// Apple's official SIWA wording (App Review requires it on custom
    /// HIG-styled buttons — AppleSignInButton renders this).
    static func signInWithApple(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInWithApple", ru: "Войти через Apple", en: "Sign in with Apple")
    }

    // MARK: - Entity / action labels (used by sync status sheet)

    static func entityLabel(_ type: String, _ lang: LanguageManager.Language) -> String {
        switch type {
        case "trip":     return tripTitle(lang)
        case "vehicle":  return tr(lang, "entityVehicle", ru: "Машина", en: "Vehicle")
        case "photo":    return photoShort(lang)
        case "settings": return settingsTitle(lang)
        default:         return type.capitalized
        }
    }
    static func actionLabel(_ action: String, _ lang: LanguageManager.Language) -> String {
        switch action {
        case "upload": return tr(lang, "actionUpload", ru: "Загрузка", en: "Upload")
        case "update": return tr(lang, "actionUpdate", ru: "Обновление", en: "Update")
        case "delete": return tr(lang, "actionDelete", ru: "Удаление", en: "Delete")
        default:       return action.capitalized
        }
    }

    // MARK: - Garage (v0.6.0 redesign)

    static func vehicleMainLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleMainLabel", ru: "Основная", en: "Main")
    }
    static func myVehicle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myVehicle", ru: "Мой автомобиль", en: "My Vehicle")
    }
    static func renameVehicle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "renameVehicle", ru: "Переименовать", en: "Rename")
    }
    static func deleteVehicle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteVehicle", ru: "Удалить транспорт", en: "Delete vehicle")
    }
    static func deleteVehicleConfirm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteVehicleConfirm", ru: "Удалить транспорт?", en: "Delete this transport?")
    }
    static func makeMainVehicle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "makeMainVehicle", ru: "Сделать основной", en: "Make main")
    }
    static func odometerLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "odometerLabel", ru: "Одометр", en: "Odometer")
    }
    static func avgConsumptionLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avgConsumptionLabel", ru: "Ср. расход", en: "Avg. consumption")
    }
    static func stickersLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stickersLabel", ru: "Стикеры", en: "Stickers")
    }
    static func fuelSectionLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuelSectionLabel", ru: "Расход топлива", en: "Fuel consumption")
    }
    static func fuelCityRow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuelCityRow", ru: "Расход в городе", en: "City consumption")
    }
    static func fuelHighwayRow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuelHighwayRow", ru: "Расход на трассе", en: "Highway consumption")
    }
    static func fuelPriceRow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuelPriceRow", ru: "Цена топлива", en: "Fuel price")
    }
    static func addVehicleTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "addVehicleTitle", ru: "Добавить транспорт", en: "Add transport")
    }
    static func vehicleNameSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleNameSection", ru: "Название", en: "Name")
    }
    static func vehicleNamePlaceholder(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleNamePlaceholder", ru: "Например, Honda Civic", en: "e.g. Honda Civic")
    }
    static func avatarSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avatarSection", ru: "Аватар", en: "Avatar")
    }

    /// Which silhouette — the shape of the thing, not its paint. Sits above the
    /// colour row in the vehicle form, and is hidden entirely while only one
    /// silhouette exists, so a single tile never poses as a choice.
    static func avatarStyleSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avatarStyleSection", ru: "Тип", en: "Type")
    }

    /// Which paint. Separate from the silhouette so that adding a colour never
    /// costs a drawing and adding a drawing never costs the colours.
    static func avatarColorSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avatarColorSection", ru: "Цвет", en: "Color")
    }

    /// Names for the silhouettes. Nothing draws these as visible text — the
    /// tiles are pictures — but VoiceOver has no picture to read, so without
    /// them the whole row announces as seven identical buttons.
    static func avatarStyleName(_ lang: LanguageManager.Language, style: String) -> String {
        switch style {
        case "car":         return tr(lang, "avatarStyle_car", ru: "Седан", en: "Sedan")
        case "hatchback":         return tr(lang, "avatarStyle_hatchback", ru: "Хэтчбек", en: "Hatchback")
        case "crossover":         return tr(lang, "avatarStyle_crossover", ru: "Кроссовер", en: "Crossover")
        case "pickup":         return tr(lang, "avatarStyle_pickup", ru: "Пикап", en: "Pickup")
        case "van":         return tr(lang, "avatarStyle_van", ru: "Фургон", en: "Van")
        case "convertible":         return tr(lang, "avatarStyle_convertible", ru: "Кабриолет", en: "Convertible")
        case "sports":         return tr(lang, "avatarStyle_sports", ru: "Спорткар", en: "Sports car")
        default:            return tr(lang, "avatarStyle_car", ru: "Седан", en: "Sedan")
        }
    }
    static func fuelCity(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuelCity", ru: "Город", en: "City")
    }
    static func fuelHighway(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuelHighway", ru: "Трасса", en: "Highway")
    }
    static func mileageSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mileageSection", ru: "Пробег", en: "Mileage")
    }
    static func mileageAutoHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "mileageAutoHint",
           ru: "Начисляется автоматически по поездкам",
           en: "Accrues automatically from your trips")
    }
    static func stereoSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stereoSection", ru: "Магнитола", en: "Stereo")
    }
    static func btOffTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "btOffTitle", ru: "Bluetooth выключен", en: "Bluetooth is off")
    }
    static func btOffChipBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "btOffChipBody",
           ru: "Включите Bluetooth, чтобы запись стартовала по магнитоле.",
           en: "Turn on Bluetooth so recording can start from your stereo.")
    }
    static func btOffSheetBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "btOffSheetBody",
           ru: "Включите Bluetooth в Настройках, чтобы найти магнитолу и привязать её к этому авто.",
           en: "Turn on Bluetooth in Settings to find your stereo and link it to this car.")
    }
    static func settingsButton(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsButton", ru: "Настройки", en: "Settings")
    }
    static func maxVehiclesHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "maxVehiclesHint", ru: "Максимум 5 единиц транспорта", en: "Maximum 5 vehicles")
    }
    /// Trailing action of the «Гараж» section on the Я tab. NOT a count («3
    /// машины»): the house word for the category is «транспорт», which has no
    /// plural form to agree with a number, and «машины» would be wrong for a
    /// moped — the same reason the cap hint says «единиц транспорта».
    static func garageAllVehicles(_ lang: LanguageManager.Language) -> String {
        tr(lang, "garageAllVehicles", ru: "Весь транспорт", en: "All vehicles")
    }
    static func unnamedVehicle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unnamedVehicle", ru: "Без имени", en: "Unnamed")
    }
    static func sinceYear(_ lang: LanguageManager.Language, year: Int) -> String {
        switch lang {
        case .ru: return "с \(year)"
        case .en: return "since \(year)"
        case .de: return "seit \(year)"
        case .es: return "desde \(year)"
        case .fr: return "depuis \(year)"
        case .it: return "dal \(year)"
        case .pl: return "od \(year)"
        case .id: return "sejak \(year)"
        case .tr: return "\(year) yılından beri"
        case .fil: return "mula \(year)"
        case .uk: return "з \(year)"
        case .kk: return "\(year) жылдан бері"
        case .pt: return "desde \(year)"
        }
    }

    // MARK: - Garage: transport, plates, levels

    static func vehicleTypeSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleTypeSection", ru: "Тип транспорта", en: "Transport type")
    }
    static func plateSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "plateSection", ru: "Госномер · необязательно", en: "Plate · optional")
    }
    static func platePlaceholder(_ lang: LanguageManager.Language) -> String {
        tr(lang, "platePlaceholder", ru: "Например, А 123 ВС 777", en: "e.g. AB 12 CDE")
    }
    static func plateShowToOthers(_ lang: LanguageManager.Language) -> String {
        tr(lang, "plateShowToOthers", ru: "Показывать другим", en: "Show to others")
    }
    /// Says who can see it today, not what the toggle does — the toggle's own
    /// label already does that.
    static func plateVisibilityHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "plateVisibilityHint",
           ru: "По умолчанию номер видите только вы",
           en: "By default only you can see the plate")
    }
    static func privacySection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacySection", ru: "Приватность", en: "Privacy")
    }
    /// Read out for the lock glyph on a garage card. A state, not a section
    /// heading — VoiceOver announces this in place of the icon.
    static func vehicleHiddenFromOthers(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleHiddenFromOthers", ru: "Скрыт от других", en: "Hidden from others")
    }
    static func editVehicleTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "editVehicleTitle", ru: "Редактировать транспорт", en: "Edit transport")
    }
    /// The other half of `plateVisibilityHint`. Leaving the "only you can see
    /// it" line up after the toggle is switched ON reads as reassurance for a
    /// state that no longer holds.
    static func plateVisibilityHintOn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "plateVisibilityHintOn",
           ru: "Номер увидят все, кто открывает ваш профиль",
           en: "Anyone who opens your profile will see the plate")
    }
    /// One line, for the empty garage seen from inside the trip picker — the
    /// full-screen empty state's two sentences run long in a sheet.
    static func garageEmptyPickerHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "garageEmptyPickerHint",
           ru: "Поездка запишется и без транспорта",
           en: "The trip records fine without transport")
    }
    /// Row label for the auto-stop stepper. Distinct from `autoStopTimeout`,
    /// which is the section header directly above it.
    static func autoStopRowLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "autoStopRowLabel", ru: "Завершить через", en: "Stop after")
    }

    // MARK: - Stereo status (vehicle card)

    /// The stereo is linked AND the phone is playing through it right now.
    static func stereoConnectedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stereoConnectedTitle", ru: "Магнитола подключена", en: "Stereo connected")
    }
    static func stereoStartsItself(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stereoStartsItself", ru: "запись стартует сама", en: "recording starts by itself")
    }
    /// Linked, but not connected at this moment — the promise is conditional,
    /// and saying «подключена» when it is not would be a lie the card tells
    /// every time the car is parked.
    static func stereoLinkedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stereoLinkedTitle", ru: "Магнитола привязана", en: "Stereo linked")
    }
    static func stereoStartsOnConnect(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stereoStartsOnConnect",
           ru: "запись стартует при подключении",
           en: "recording starts when it connects")
    }
    static func stereoNotLinkedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stereoNotLinkedTitle", ru: "Магнитола не привязана", en: "No stereo linked")
    }
    static func stereoNotLinkedBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "stereoNotLinkedBody",
           ru: "Привяжите её, чтобы запись стартовала сама.",
           en: "Link one so recording can start by itself.")
    }
    static func showVehicleToggle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "showVehicleToggle", ru: "Показывать транспорт", en: "Show transport")
    }
    static func showVehicleHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "showVehicleHint",
           ru: "Скрытый транспорт не виден в профиле — его нельзя указать в попутчиках. В публичных поездках транспорт скрыт.",
           en: "Hidden transport does not appear in your profile and cannot be named in companions. It stays hidden on public trips.")
    }
    static func fuelPriceSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fuelPriceSection", ru: "Цена топлива", en: "Fuel price")
    }
    static func fuelPricePerUnit(_ lang: LanguageManager.Language, unit: String) -> String {
        switch lang {
        case .ru: return "Цена за \(unit)"
        case .en: return "Price per \(unit)"
        case .de: return "Preis pro \(unit)"
        case .es: return "Precio por \(unit)"
        case .fr: return "Prix par \(unit)"
        case .it: return "Prezzo al \(unit)"
        case .pl: return "Cena za \(unit)"
        case .id: return "Harga per \(unit)"
        case .tr: return "\(unit) başına fiyat"
        case .fil: return "Presyo bawat \(unit)"
        case .uk: return "Ціна за \(unit)"
        case .kk: return "\(unit) бағасы"
        case .pt: return "Preço por \(unit)"
        }
    }
    static func currencyPickerTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "currencyPickerTitle", ru: "Валюта цены", en: "Price currency")
    }
    static func currencyPickerHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "currencyPickerHint",
           ru: "Валюта цены топлива в этой машине — по умолчанию для все поездок. Другую можно выбрать на экране поездки.",
           en: "The fuel price currency for this vehicle, used by default for its trips. A trip can override it.")
    }

    // Empty garage

    static func garageEmptyTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "garageEmptyTitle", ru: "В Гараже пусто", en: "Your Garage is empty")
    }
    static func garageEmptyBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "garageEmptyBody",
           ru: "Добавьте транспорт — он будет копить уровень с каждой поездкой",
           en: "Add transport — it gains a level with every trip")
    }

    // Delete confirmation

    static func deleteVehicleBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteVehicleBody",
           ru: "Поездки и статистика сохранятся.",
           en: "Trips and statistics are kept.")
    }
    static func vehicleDeletedNote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleDeletedNote", ru: "Транспорт удалён", en: "Transport deleted")
    }

    // No-vehicle trips

    static func noVehicleOption(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noVehicleOption", ru: "Без транспорта", en: "No transport")
    }

    // Vehicle level info

    static func vehicleLevelTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleLevelTitle", ru: "Уровень машины", en: "Vehicle level")
    }
    static func vehicleLevelToNext(_ lang: LanguageManager.Language, km: String, level: Int) -> String {
        let d = "\(km) \(AppStrings.km(lang))"
        switch lang {
        case .ru: return "\(d) до уровня \(level)"
        case .en: return "\(d) to level \(level)"
        case .de: return "\(d) bis Level \(level)"
        case .es: return "\(d) hasta el nivel \(level)"
        case .fr: return "\(d) avant le niveau \(level)"
        case .it: return "\(d) al livello \(level)"
        case .pl: return "\(d) do poziomu \(level)"
        case .id: return "\(d) menuju level \(level)"
        case .tr: return "\(level). seviyeye \(d)"
        case .fil: return "\(d) papuntang level \(level)"
        case .uk: return "\(d) до рівня \(level)"
        case .kk: return "\(level)-деңгейге \(d)"
        case .pt: return "\(d) até o nível \(level)"
        }
    }
    static func vehicleLevelHowGrows(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleLevelHowGrows", ru: "Как растёт", en: "How it grows")
    }
    static func vehicleLevelHowGrowsBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleLevelHowGrowsBody",
           ru: "Единственный источник — километры в записанных поездках на этой машине. Каждый следующий уровень требует больше км, чем предыдущий: первые — за сотни, дальше — за тысячи. Потолка нет.",
           en: "The only source is kilometres from recorded trips on this vehicle. Each level costs more than the last: the first ones take hundreds, later ones thousands. There is no ceiling.")
    }
    static func vehicleLevelAffects(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleLevelAffects", ru: "На что влияет", en: "What it affects")
    }
    static func vehicleLevelAffectsBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleLevelAffectsBody",
           ru: "Ни на что не влияет и ничего не открывает — это стаж машины, её летопись. Виден вам в Гараже; у публичного транспорта его видят другие. Каждые 10 уровней цифра меняет цвет.",
           en: "It affects nothing and unlocks nothing — it is the vehicle's record of service. You see it in the Garage; on public transport others see it too. The number changes colour every 10 levels.")
    }
    static func vehicleLevelColors(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleLevelColors", ru: "Цвета уровней", en: "Level colours")
    }
    static func vehicleLevelAndAbove(_ lang: LanguageManager.Language, level: Int) -> String {
        switch lang {
        case .ru: return "\(level) и выше"
        case .en: return "\(level) and above"
        case .de: return "\(level) und höher"
        case .es: return "\(level) y superiores"
        case .fr: return "\(level) et plus"
        case .it: return "\(level) e oltre"
        case .pl: return "\(level) i wyżej"
        case .id: return "\(level) ke atas"
        case .tr: return "\(level) ve üzeri"
        case .fil: return "\(level) pataas"
        case .uk: return "\(level) і вище"
        case .kk: return "\(level) және жоғары"
        case .pt: return "\(level) e acima"
        }
    }

    // MARK: - Home feed (0.6.0)
    static func feedSegmentFollowing(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedSegmentFollowing", ru: "Подписки", en: "Following")
    }
    static func followingEmptyTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followingEmptyTitle", ru: "Пока тихо", en: "Quiet for now")
    }
    static func followingEmptyBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followingEmptyBody",
           ru: "Подпишитесь на людей, и их поездки появятся здесь.",
           en: "Follow people and their trips will show up here.")
    }
    static func followingGuestTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followingGuestTitle", ru: "Лента подписок", en: "Your following feed")
    }
    static func followingGuestBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followingGuestBody",
           ru: "Войдите, чтобы подписываться на людей и видеть их поездки здесь.",
           en: "Sign in to follow people and see their trips here.")
    }
    static func feedEmptyTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedEmptyTitle", ru: "Здесь появятся маршруты", en: "Routes will show up here")
    }
    static func feedEmptyBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedEmptyBody",
           ru: "Опубликуйте первую поездку или найдите тех, за кем интересно следить.",
           en: "Publish your first trip or find people worth following.")
    }
    static func findPeople(_ lang: LanguageManager.Language) -> String {
        tr(lang, "findPeople", ru: "Найти людей", en: "Find people")
    }
    /// Short time units for the feed-card metric runs («4 ч 58 мин»).
    static func hoursUnitShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "hoursUnitShort", ru: "ч", en: "h")
    }
    static func minutesUnitShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "minutesUnitShort", ru: "мин", en: "min")
    }
    /// Section title and accessibility label for the discussion.
    static func comments(_ lang: LanguageManager.Language) -> String {
        tr(lang, "comments", ru: "Обсуждение", en: "Discussion")
    }

    // MARK: - Activity inbox (0.6.0)
    static func activityTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "activityTitle", ru: "Активность", en: "Activity")
    }
    static func chipReactions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "chipReactions", ru: "Реакции", en: "Reactions")
    }
    static func chipFollows(_ lang: LanguageManager.Language) -> String {
        tr(lang, "chipFollows", ru: "Подписки", en: "Follows")
    }
    static func chipComments(_ lang: LanguageManager.Language) -> String {
        tr(lang, "chipComments", ru: "Комменты", en: "Comments")
    }
    /// Chip filter label for `achievement` rows.
    static func chipAchievements(_ lang: LanguageManager.Language) -> String {
        tr(lang, "chipAchievements", ru: "Достижения", en: "Achievements")
    }
    static func today(_ lang: LanguageManager.Language) -> String {
        tr(lang, "today", ru: "Сегодня", en: "Today")
    }
    static func earlier(_ lang: LanguageManager.Language) -> String {
        tr(lang, "earlier", ru: "Ранее", en: "Earlier")
    }
    static func noFilteredNotifications(_ lang: LanguageManager.Language) -> String {
        tr(lang, "noFilteredNotifications",
           ru: "Таких уведомлений пока нет",
           en: "No such notifications yet")
    }
    // MARK: - Activity rows (0.6.0)

    /// Second line of a reaction row: what happened, to what. The reaction
    /// itself is drawn as a badge on the avatar, so it is not repeated here.
    static func activityReactedTo(_ lang: LanguageManager.Language, _ trip: String) -> String {
        switch lang {
        case .ru: return "отреагировал на «\(trip)»"
        case .en: return "reacted to “\(trip)”"
        case .de: return "hat auf „\(trip)“ reagiert"
        case .es: return "reaccionó a «\(trip)»"
        case .fr: return "a réagi à « \(trip) »"
        case .it: return "ha reagito a «\(trip)»"
        case .pl: return "zareagował na «\(trip)»"
        case .id: return "bereaksi ke «\(trip)»"
        case .tr: return "«\(trip)» gezisine tepki verdi"
        case .fil: return "nag-react sa «\(trip)»"
        case .uk: return "відреагував на «\(trip)»"
        case .kk: return "«\(trip)» сапарына реакция білдірді"
        case .pt: return "reagiu a «\(trip)»"
        }
    }
    static func activityFollowedYou(_ lang: LanguageManager.Language) -> String {
        tr(lang, "activityFollowedYou", ru: "подписался на Вас", en: "started following you")
    }
    /// With the comment text when the server sent it, otherwise the trip.
    static func activityCommented(_ lang: LanguageManager.Language, text: String?, trip: String) -> String {
        if let text, !text.isEmpty {
            switch lang {
            case .ru: return "прокомментировал: «\(text)»"
            case .en: return "commented: “\(text)”"
            case .de: return "hat kommentiert: „\(text)“"
            case .es: return "comentó: «\(text)»"
            case .fr: return "a commenté : « \(text) »"
            case .it: return "ha commentato: «\(text)»"
            case .pl: return "skomentował: «\(text)»"
            case .id: return "berkomentar: «\(text)»"
            case .tr: return "yorum yaptı: «\(text)»"
            case .fil: return "nag-comment: «\(text)»"
            case .uk: return "прокоментував: «\(text)»"
            case .kk: return "пікір қалдырды: «\(text)»"
            case .pt: return "comentou: «\(text)»"
            }
        }
        switch lang {
        case .ru: return "прокомментировал «\(trip)»"
        case .en: return "commented on “\(trip)”"
        case .de: return "hat „\(trip)“ kommentiert"
        case .es: return "comentó «\(trip)»"
        case .fr: return "a commenté « \(trip) »"
        case .it: return "ha commentato «\(trip)»"
        case .pl: return "skomentował «\(trip)»"
        case .id: return "berkomentar di «\(trip)»"
        case .tr: return "«\(trip)» gezisine yorum yaptı"
        case .fil: return "nag-comment sa «\(trip)»"
        case .uk: return "прокоментував «\(trip)»"
        case .kk: return "«\(trip)» сапарына пікір қалдырды"
        case .pt: return "comentou em «\(trip)»"
        }
    }
    /// Fallback object when a trip has no title of its own.
    static func activityYourTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "activityYourTrip", ru: "Вашу поездку", en: "your trip")
    }

    // MARK: - Achievement rows (0.6.0)

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
        switch lang {
        case .ru: return "Открыто достижение «\(badge)»"
        case .en: return "Achievement unlocked: “\(badge)”"
        case .de: return "Erfolg freigeschaltet: „\(badge)“"
        case .es: return "Logro desbloqueado: «\(badge)»"
        case .fr: return "Succès débloqué : « \(badge) »"
        case .it: return "Traguardo sbloccato: «\(badge)»"
        case .pl: return "Odblokowano osiągnięcie «\(badge)»"
        case .id: return "Pencapaian terbuka: «\(badge)»"
        case .tr: return "Başarım açıldı: «\(badge)»"
        case .fil: return "Na-unlock ang tagumpay: «\(badge)»"
        case .uk: return "Відкрито досягнення «\(badge)»"
        case .kk: return "«\(badge)» жетістігі ашылды"
        case .pt: return "Conquista desbloqueada: «\(badge)»"
        }
    }
    /// Line two when the badge didn't resolve — an id this build doesn't
    /// know yet, or a server that names the badge some other way. Still a
    /// true, readable sentence instead of an empty row.
    static func activityAchievementUnlockedGeneric(_ lang: LanguageManager.Language) -> String {
        tr(lang, "activityAchievementUnlockedGeneric",
           ru: "Открыто новое достижение",
           en: "New achievement unlocked")
    }

    static func followBack(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followBack", ru: "В ответ", en: "Follow back")
    }

    // MARK: - Notification preferences — companions toggle (Fix 6)

    /// `NotificationPreferencesView`'s companions row — title/subtitle,
    /// same shape as its reactions/follows/comments/weekly-recap siblings.
    static func notifyCompanionsTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifyCompanionsTitle", ru: "Попутчики", en: "Companions")
    }
    static func notifyCompanionsSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notifyCompanionsSubtitle",
           ru: "Когда вас позовут в поездку или кто-то присоединится к вашей",
           en: "When you're invited on a trip or someone joins yours")
    }

    // MARK: - Companion invite rows (0.6.0)

    /// Chip filter label for `companion_invite` / `companion_accepted` rows.
    static func chipCompanions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "chipCompanions", ru: "Попутчики", en: "Companions")
    }
    /// Decision-row header line — the invite verb, no trip specifics (those
    /// live in the trip-shape line below it, once the preview loads).
    static func companionInviteAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionInviteAction",
           ru: "пригласил вас в поездку",
           en: "invited you on a trip")
    }
    /// `companion_accepted` action line — the OWNER's row: someone joined.
    static func companionAcceptedAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionAcceptedAction",
           ru: "присоединился к вашей поездке",
           en: "joined your trip")
    }
    /// Post-response note replacing the decision controls once the
    /// invitee has accepted this session (or the server already has it
    /// on record).
    static func companionInviteAcceptedNote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionInviteAcceptedNote",
           ru: "Вы приняли приглашение",
           en: "You accepted the invite")
    }
    static func companionInviteDeclinedNote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionInviteDeclinedNote",
           ru: "Вы отклонили приглашение",
           en: "You declined the invite")
    }
    static func companionAccept(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionAccept", ru: "Принять", en: "Accept")
    }
    static func companionDecline(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionDecline", ru: "Отклонить", en: "Decline")
    }
    static func companionRespondFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionRespondFailed",
           ru: "Не удалось ответить на приглашение",
           en: "Couldn't respond to the invite")
    }
    static func companionInvitePreviewFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionInvitePreviewFailed",
           ru: "Не удалось загрузить приглашение",
           en: "Couldn't load the invite")
    }
    /// Shown when an accepted invite's trip can't be resolved yet from the
    /// companion trips cache (see `NotificationsInboxView.openAcceptedInviteTrip`).
    static func companionTripUnavailable(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionTripUnavailable",
           ru: "Поездка пока недоступна",
           en: "Trip isn't available yet")
    }
    /// Fix 2: an invite whose `/companions/invite-preview` fetch confirms
    /// there is no longer a live PENDING row to answer — most commonly
    /// because it was already accepted or declined on ANOTHER device.
    /// Deliberately neutral about which way it went (the client has no
    /// local record of the actual outcome in this case), unlike
    /// `companionInviteAcceptedNote`/`companionInviteDeclinedNote` above.
    static func companionInviteUnavailableNote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionInviteUnavailableNote",
           ru: "Приглашение больше не активно",
           en: "This invite is no longer active")
    }

    // MARK: - Discover (0.6.0)
    static func suggestedByRegions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "suggestedByRegions",
           ru: "Рекомендуем · по Вашим регионам",
           en: "Suggested · based on your regions")
    }

    /// Rationale line of a suggested-person row (Figma 117:291). The server
    /// sends a machine key, these are its only renderings — an unknown key
    /// draws no line at all (see `SuggestionMatchReason`).
    static func suggestReasonSharedRegion(_ lang: LanguageManager.Language) -> String {
        tr(lang, "suggestReasonSharedRegion",
           ru: "Ездит в Ваших краях",
           en: "Drives in your regions")
    }
    static func suggestReasonNearby(_ lang: LanguageManager.Language) -> String {
        tr(lang, "suggestReasonNearby", ru: "Рядом с Вами", en: "Near you")
    }
    static func suggestReasonPopular(_ lang: LanguageManager.Language) -> String {
        tr(lang, "suggestReasonPopular", ru: "Популярный водитель", en: "Popular driver")
    }

    // MARK: - Share sheet / report (0.6.0)
    static func copyAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "copyAction", ru: "Копировать", en: "Copy")
    }
    static func reportAnonymousNote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportAnonymousNote",
           ru: "Жалобы анонимны — автор не узнает, кто их отправил.",
           en: "Reports are anonymous — the author won't know who sent them.")
    }

    // MARK: - Account & Sync page (0.6.0 Figma frames 1–3)
    // Category rows of the sync sheet reuse existing keys:
    // tripsTab («Поездки»), photos («Фото»), profile («Профиль»), garage («Гараж»).

    static func accountSyncTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "accountSyncTitle", ru: "Аккаунт и синхронизация", en: "Account & Sync")
    }
    static func accountAppleIdLine(_ lang: LanguageManager.Language, email: String) -> String {
        "Apple ID · \(email)"
    }
    static func accountAppleIdOnly(_ lang: LanguageManager.Language) -> String {
        "Apple ID"
    }
    static func sectionSyncLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sectionSyncLabel", ru: "Синхронизация", en: "Sync")
    }
    /// F6: deliberately NOT «iCloud-синхронизация» — sync is the TripTrack EU
    /// server + R2 (per the shipped GDPR consent copy), "iCloud" would be
    /// legally misleading.
    static func cloudSyncTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "cloudSyncTitle", ru: "Облачная синхронизация", en: "Cloud sync")
    }
    static func syncUpdatedAgo(_ lang: LanguageManager.Language, _ relative: String) -> String {
        switch lang {
        case .ru: return "Обновлено \(relative)"
        case .en: return "Updated \(relative)"
        case .de: return "Aktualisiert \(relative)"
        case .es: return "Actualizado \(relative)"
        case .fr: return "Mis à jour \(relative)"
        case .it: return "Aggiornato \(relative)"
        case .pl: return "Zaktualizowano \(relative)"
        case .id: return "Diperbarui \(relative)"
        case .tr: return "\(relative) güncellendi"
        case .fil: return "Na-update \(relative)"
        case .uk: return "Оновлено \(relative)"
        case .kk: return "\(relative) жаңартылды"
        case .pt: return "Atualizado \(relative)"
        }
    }
    /// F13 fallback subtitle when there is no lastSyncedAt for the account.
    static func syncStateOn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStateOn", ru: "Включена", en: "On")
    }
    static func syncStateOff(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStateOff", ru: "Выключена", en: "Off")
    }
    static func syncPerItemStatus(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncPerItemStatus", ru: "Статус по объектам", en: "Per-item status")
    }
    static func syncAllDone(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncAllDone", ru: "Всё синхронизировано", en: "All synced")
    }
    /// Status-row value: sync globally OFF but the queue still holds ops for
    /// explicitly-public trips — this state must remain reachable (edge #3).
    static func syncOffPublishing(_ lang: LanguageManager.Language, count: Int) -> String {
        let off = syncStateOff(lang)
        let word = tr(lang, "syncPublishingWord", ru: "публикация", en: "publishing")
        return "\(off) · \(word): \(count)"
    }
    static func syncOffState(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncOffState", ru: "Выключено", en: "Disabled")
    }
    static func syncingProgress(_ lang: LanguageManager.Language, done: Int, total: Int) -> String {
        "\(syncingNow(lang)) \(done)/\(total)"
    }
    static func syncingNow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncingNow", ru: "Синхронизация…", en: "Syncing…")
    }
    static func syncQueuedCount(_ lang: LanguageManager.Language, count: Int) -> String {
        "\(syncStatusPendingHeader(lang)): \(count)"
    }
    static func sectionPrivacyLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sectionPrivacyLabel", ru: "Приватность", en: "Privacy")
    }
    static func publicProfileTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publicProfileTitle", ru: "Публичный профиль", en: "Public profile")
    }
    static func publicProfileSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publicProfileSubtitle",
           ru: "Новые поездки приватны по умолчанию",
           en: "New trips are private by default")
    }
    static func blockedUsersShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "blockedUsersShort", ru: "Заблокированные", en: "Blocked")
    }
    static func sectionAccountLabel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sectionAccountLabel", ru: "Аккаунт", en: "Account")
    }
    static func signOutSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signOutSubtitle",
           ru: "Поездки останутся на устройстве",
           en: "Trips stay on this device")
    }
    static func clearServerTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clearServerTitle", ru: "Очистить данные на сервере", en: "Clear server data")
    }
    static func clearServerSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clearServerSubtitle",
           ru: "Удалить поездки с сервера, оставить на устройстве",
           en: "Remove trips from the server, keep them on device")
    }
    static func clearServerInProgress(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clearServerInProgress", ru: "Очищаем…", en: "Clearing…")
    }
    // Migrated verbatim from the pre-0.6.0 CloudSyncView inline strings —
    // the GDPR just-in-time consent alert (F12: confirmation flows survive).
    static func syncEnableConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncEnableConfirmTitle", ru: "Включить синхронизацию?", en: "Turn on cloud sync?")
    }
    static func syncEnableConfirmBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncEnableConfirmBody",
           ru: "Ваши поездки, фото (с удалёнными метаданными), автомобили и настройки будут загружены на наш сервер в ЕС и доступны на других Ваших устройствах. Вы можете отключить в любой момент. Подробнее — в Политике конфиденциальности.",
           en: "Your trips, photos (with metadata stripped), vehicles, and settings will be uploaded to our EU server so you can access them on your other devices. You can turn this off anytime. See our Privacy Policy for details.")
    }
    static func syncEnableConfirmAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncEnableConfirmAction", ru: "Включить", en: "Turn on")
    }
    // Migrated verbatim: wipe-server confirmation.
    static func wipeServerConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "wipeServerConfirmTitle",
           ru: "Очистить данные с сервера?",
           en: "Clear server data?")
    }
    static func wipeServerConfirmBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "wipeServerConfirmBody",
           ru: "Все Ваши поездки и фото будут удалены с сервера. Локальные данные сохранятся, Вы останетесь в аккаунте.\n\nСинхронизация будет выключена — Вы сможете включить её снова, когда захотите.",
           en: "All your trips and photos will be removed from the server. Local data stays on this device, your account is preserved.\n\nCloud sync will be turned off — you can re-enable it anytime.")
    }
    static func wipeServerConfirmAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "wipeServerConfirmAction", ru: "Очистить", en: "Clear")
    }
    // Migrated verbatim: 3-way public-trips sign-out dialog.
    static func signOutPublishedTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signOutPublishedTitle",
           ru: "У Вас есть публичные поездки",
           en: "You have public trips")
    }
    static func signOutHidePublic(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signOutHidePublic",
           ru: "Скрыть публичные и выйти",
           en: "Hide public and sign out")
    }
    static func signOutKeepPublic(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signOutKeepPublic",
           ru: "Выйти, оставить публичные в ленте",
           en: "Sign out, leave public in feed")
    }
    // Sync sheet (frame 2).
    static func syncSheetTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncSheetTitle", ru: "Синхронизация", en: "Sync")
    }
    static func syncLastAt(_ lang: LanguageManager.Language, _ relative: String) -> String {
        "\(tr(lang, "syncLastAtHead", ru: "Последняя синхронизация", en: "Last sync")): \(relative)"
    }
    static func syncFailedCount(_ lang: LanguageManager.Language, count: Int) -> String {
        "\(tr(lang, "syncFailedCountHead", ru: "Ошибки", en: "Failed")): \(count)"
    }
    // Logs journal (frame 3).
    static func logsJournalTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "logsJournalTitle", ru: "Журнал", en: "Log")
    }
    static func logsSendCTA(_ lang: LanguageManager.Language) -> String {
        tr(lang, "logsSendCTA", ru: "Отправить логи разработчику", en: "Send logs to developer")
    }
    static func logsShareFile(_ lang: LanguageManager.Language) -> String {
        tr(lang, "logsShareFile", ru: "Поделиться файлом", en: "Share file")
    }
    /// F7: truthful caption — the export header embeds account_id and log
    /// lines may contain trip metadata, so no "no personal data" claims.
    static func logsPrivacyCaption(_ lang: LanguageManager.Language) -> String {
        tr(lang, "logsPrivacyCaption",
           ru: "Логи помогают чинить баги. Перед отправкой файл можно просмотреть.",
           en: "Logs help us fix bugs. You can review the file before sending.")
    }
    static func logsEmpty(_ lang: LanguageManager.Language) -> String {
        tr(lang, "logsEmpty", ru: "Записей пока нет", en: "No entries yet")
    }
    static func logsLoadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "logsLoadFailed", ru: "Не удалось прочитать журнал", en: "Couldn't read the log")
    }
    // Blocked list.
    static func blockedSince(_ lang: LanguageManager.Language, _ date: String) -> String {
        switch lang {
        case .ru: return "Заблокирован \(date)"
        case .en: return "Blocked \(date)"
        case .de: return "Blockiert am \(date)"
        case .es: return "Bloqueado el \(date)"
        case .fr: return "Bloqué le \(date)"
        case .it: return "Bloccato il \(date)"
        case .pl: return "Zablokowany \(date)"
        case .id: return "Diblokir \(date)"
        case .tr: return "\(date) tarihinde engellendi"
        case .fil: return "Na-block noong \(date)"
        case .uk: return "Заблокований \(date)"
        case .kk: return "\(date) бұғатталды"
        case .pt: return "Bloqueado em \(date)"
        }
    }

    // MARK: - Me tab (0.6.0)

    static func meGuestName(_ lang: LanguageManager.Language) -> String {
        tr(lang, "meGuestName", ru: "Вы", en: "You")
    }
    /// Header placeholder when a signed-in account has no name yet — a prompt,
    /// not a name. Never printed as an author: see `cardAuthorName`.
    static func meAddYourName(_ lang: LanguageManager.Language) -> String {
        tr(lang, "meAddYourName", ru: "Добавьте имя", en: "Add your name")
    }
    static func achievementsSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsSection", ru: "Достижения", en: "Achievements")
    }
    /// Counter next to the section header — bare numbers, the noun lives in
    /// the header itself so the pill stays short on 360pt.
    static func achievementsProgress(
        _ lang: LanguageManager.Language, unlocked: Int, total: Int
    ) -> String {
        "\(unlocked) \(ofWord(lang)) \(total)"
    }
    static func achievementPinned(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementPinned", ru: "Закреплено", en: "Pinned")
    }
    static func achievementsEmpty(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsEmpty", ru: "Пока ничего не открыто", en: "Nothing unlocked yet")
    }
    /// Reassurance, not a call to action — achievements are never granted
    /// by tapping anything, so the hint must not read like a button.
    static func achievementsEmptyHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsEmptyHint",
           ru: "Достижения открываются сами, пока вы ездите",
           en: "Achievements unlock by themselves as you drive")
    }
    /// Same reassurance on SOMEBODY ELSE's profile. Deliberately says nothing
    /// about who the driver is: the app never learns their gender, and «пока
    /// он ездит» would be a guess printed under their name.
    static func achievementsEmptyOtherHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsEmptyOtherHint",
           ru: "Появятся после первых поездок",
           en: "They'll show up after the first drives")
    }
    static func historySection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "historySection", ru: "История", en: "History")
    }
    /// VoiceOver labels for the list/grid toggle — the control is icon-only.
    static func historyModeList(_ lang: LanguageManager.Language) -> String {
        tr(lang, "historyModeList", ru: "Списком", en: "List")
    }
    static func historyModeGrid(_ lang: LanguageManager.Language) -> String {
        tr(lang, "historyModeGrid", ru: "Плиткой", en: "Grid")
    }
    static func calendarClearFilter(_ lang: LanguageManager.Language) -> String {
        tr(lang, "calendarClearFilter", ru: "Сбросить", en: "Clear")
    }
    /// How many trips the picked days hold. Delegates to `tripsCount` so the
    /// RU declension table lives in exactly one place.
    static func calendarFilterActive(_ lang: LanguageManager.Language, count: Int) -> String {
        tripsCount(lang, n: count)
    }
    static func statsKmTotal(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsKmTotal", ru: "км всего", en: "km total")
    }
    static func statsRegions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsRegions", ru: "регионов", en: "regions")
    }
    /// Older name for the same metric tile — canon settled on `statsHoursOnRoad`,
    /// so this forwards instead of keeping a second English wording alive.
    static func statsHours(_ lang: LanguageManager.Language) -> String {
        statsHoursOnRoad(lang)
    }
    static func statsKmByMonth(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsKmByMonth", ru: "Километры по месяцам", en: "Kilometres by month")
    }
    static func statsRecords(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsRecords", ru: "РЕКОРДЫ", en: "RECORDS")
    }
    static func recordLongest(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordLongest", ru: "Самая длинная", en: "Longest")
    }
    static func recordLongestDay(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordLongestDay", ru: "Дольше всего", en: "Longest day")
    }
    static func recordPerDay(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordPerDay", ru: "за один день", en: "in one day")
    }
    static func recordStreak(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordStreak", ru: "Лучшая серия", en: "Best streak")
    }
    static func recordStreakSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordStreakSub", ru: "подряд", en: "in a row")
    }
    /// «N дней» with proper RU plural agreement (день / дня / дней).
    static func daysCount(_ lang: LanguageManager.Language, n: Int) -> String {
        "\(n) \(nounDays(lang, n))"
    }
    /// «N поездок» with proper RU plural agreement (поездка / поездки / поездок).
    static func tripsCount(_ lang: LanguageManager.Language, n: Int) -> String {
        "\(n) \(nounTrips(lang, n))"
    }
    static func statsEmptyTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsEmptyTitle", ru: "Пока нечего показать", en: "Nothing to show yet")
    }
    /// Names what the screen will hold, not what the chart is called — the
    /// empty state promises places and records, which is why people come back.
    static func statsEmptyBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsEmptyBody",
           ru: "Проедьте первую поездку — здесь появятся километры, рекорды и новые места.",
           en: "Take your first drive — kilometres, records and new places will show up here.")
    }
    static func recordTripCta(_ lang: LanguageManager.Language) -> String {
        tr(lang, "recordTripCta", ru: "Записать поездку", en: "Record a trip")
    }
    static func settingsTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsTitle", ru: "Настройки", en: "Settings")
    }
    /// Globe opt-in row. Deliberately NOT «Публичный профиль» — that exact
    /// label already names the account-visibility toggle in CloudSyncView
    /// (auth.isPublic); two same-named toggles with different semantics
    /// would be a privacy-misleading collision.
    static func settingsPublicProfile(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsPublicProfile",
           ru: "Поездки на глобальной карте",
           en: "Trips on the global map")
    }
    static func settingsNotifications(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsNotifications", ru: "Уведомления", en: "Notifications")
    }

    // MARK: - «Приватность» (nested screen — PrivacySettingsView)

    /// The row in Настройки, and the title of the screen it opens.
    static func privacyTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyTitle", ru: "Приватность", en: "Privacy")
    }
    /// The row's own subtitle: what is inside, in three words.
    static func privacyRowSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyRowSub", ru: "кто вас видит", en: "who can see you")
    }
    /// Tighter than `settingsHintPublicProfile`, which stays as the «?» body:
    /// a subtitle has one line to say what the switch does.
    static func privacyPublicProfileSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyPublicProfileSub",
           ru: "Другие смогут открыть вашу страницу",
           en: "Other drivers can open your page")
    }
    /// Says what the switch ACTUALLY controls. The server field behind it is a
    /// notification flag — turning it off does not stop anyone from tagging
    /// you, and the copy must not imply that it does.
    static func privacyCompanionSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyCompanionSub",
           ru: "Уведомлять, когда вас отмечают попутчиком",
           en: "Notify me when someone tags me as a companion")
    }
    /// Under the card. The one promise none of the three switches can break.
    static func privacyFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyFootnote",
           ru: "Приватную поездку не видит никто — ни на карте, ни в вашем профиле. Эти переключатели её не открывают.",
           en: "A private trip is visible to nobody — not on the map, not on your page. None of these switches change that.")
    }
    static func settingsInbox(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsInbox", ru: "Входящие", en: "Inbox")
    }
    static func settingsUnits(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsUnits", ru: "Единицы", en: "Units")
    }
    static func themeSystem(_ lang: LanguageManager.Language) -> String {
        tr(lang, "themeSystem", ru: "Системная", en: "System")
    }
    static func settingsAvgSpeed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsAvgSpeed", ru: "Средняя скорость", en: "Average speed")
    }
    static func settingsAccountSync(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsAccountSync", ru: "Аккаунт и синхронизация", en: "Account & sync")
    }
    static func settingsShareProfile(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsShareProfile", ru: "Поделиться профилем", en: "Share profile")
    }
    static func settingsSendLogs(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsSendLogs", ru: "Отправить логи", en: "Send debug logs")
    }
    /// Subtitle under «Отправить логи», which now sits in the card with the two
    /// author links: the logs are the attachment to that letter, and the line
    /// says what they are FOR rather than what they are.
    static func settingsSendLogsSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsSendLogsSub", ru: "если что-то сломалось", en: "when something breaks")
    }
    /// The nested screen that holds «Единицы» and «Средняя скорость» — named
    /// for what it contains, not «Прочее»: a row called «Другое» teaches
    /// nothing about whether the answer is behind it.
    static func settingsAppPrefs(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsAppPrefs", ru: "Единицы и формат", en: "Units & format")
    }
    /// Footnote under that screen's single card, in the same voice as the
    /// picker footnotes it opens.
    static func appPrefsFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "appPrefsFootnote",
           ru: "Как приложение считает и показывает цифры. На запись поездок это не влияет.",
           en: "How the app counts and shows numbers. Trip recording is unaffected.")
    }
    static func settingsProfileBackground(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsProfileBackground", ru: "Фон профиля", en: "Profile background")
    }
    static func rankProgressTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "rankProgressTitle", ru: "Уровень водителя", en: "Driver level")
    }
    static func awards(_ lang: LanguageManager.Language) -> String {
        tr(lang, "awards", ru: "Награды", en: "Awards")
    }
    static func nameEditorTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "nameEditorTitle", ru: "Имя", en: "Name")
    }
    static func nameHelper(_ lang: LanguageManager.Language, max: Int) -> String {
        switch lang {
        case .ru: return "Так Вас увидят в ленте и профиле. До \(max) символов."
        case .en: return "This is how you'll appear in the feed and profile. Up to \(max) characters."
        case .de: return "So erscheinst du im Feed und im Profil. Bis zu \(max) Zeichen."
        case .es: return "Así aparecerás en el feed y en el perfil. Hasta \(max) caracteres."
        case .fr: return "C'est ainsi que vous apparaîtrez dans le fil et le profil. Jusqu'à \(max) caractères."
        case .it: return "È così che comparirai nel feed e nel profilo. Fino a \(max) caratteri."
        case .pl: return "Tak zobaczą Cię na tablicy i w profilu. Do \(max) znaków."
        case .id: return "Begini kamu akan tampil di feed dan profil. Maksimal \(max) karakter."
        case .tr: return "Akışta ve profilde böyle görüneceksin. En fazla \(max) karakter."
        case .fil: return "Ganito ka lalabas sa feed at profile. Hanggang \(max) na karakter."
        case .uk: return "Так Вас побачать у стрічці та профілі. До \(max) символів."
        case .kk: return "Таспада және профильде осылай көрінесіз. \(max) таңбаға дейін."
        case .pt: return "É assim que você vai aparecer no feed e no perfil. Até \(max) caracteres."
        }
    }
    /// «342 подписчика» with RU plural agreement (подписчик / подписчика / подписчиков).
    static func followersCount(_ lang: LanguageManager.Language, n: Int) -> String {
        "\(n) \(followersCaption(lang, n: n))"
    }
    /// «128 подписок» with RU plural agreement (подписка / подписки / подписок).
    static func followingCountLabel(_ lang: LanguageManager.Language, n: Int) -> String {
        "\(n) \(followingCaption(lang, n: n))"
    }
    static func followDepthNote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followDepthNote",
           ru: "Глубина списка ограничена 3 уровнями связей",
           en: "List depth is limited to 3 levels of connections")
    }
    static func wrappedKmYear(_ lang: LanguageManager.Language) -> String {
        tr(lang, "wrappedKmYear", ru: "км за год", en: "km this year")
    }
    static func wrappedBestDay(_ lang: LanguageManager.Language) -> String {
        tr(lang, "wrappedBestDay", ru: "лучший день", en: "best day")
    }
    static func wrappedTopRegion(_ lang: LanguageManager.Language) -> String {
        tr(lang, "wrappedTopRegion", ru: "топ-регион", en: "top region")
    }
    static func wrappedShareText(_ lang: LanguageManager.Language, year: Int, km: String, trips: Int) -> String {
        let tail = "\(tripsCount(lang, n: trips)), \(km) \(AppStrings.km(lang)) — TripTrack"
        switch lang {
        case .ru: return "Мой \(year) на дорогах: \(tail)"
        case .en: return "My \(year) on the road: \(tail)"
        case .de: return "Mein \(year) auf der Straße: \(tail)"
        case .es: return "Mi \(year) en la carretera: \(tail)"
        case .fr: return "Mon \(year) sur la route : \(tail)"
        case .it: return "Il mio \(year) in strada: \(tail)"
        case .pl: return "Mój \(year) na drogach: \(tail)"
        case .id: return "\(year) saya di jalan: \(tail)"
        case .tr: return "Yollardaki \(year) yılım: \(tail)"
        case .fil: return "Ang \(year) ko sa kalsada: \(tail)"
        case .uk: return "Мій \(year) на дорогах: \(tail)"
        case .kk: return "Жолдағы \(year) жылым: \(tail)"
        case .pt: return "Meu \(year) na estrada: \(tail)"
        }
    }

    // MARK: - Audit-fix additions (0.6.0 post-release pass)

    /// «14 дней подряд» / "14 day streak" — trip-complete streak row.
    static func streakDaysInARow(_ lang: LanguageManager.Language, n: Int) -> String {
        let d = daysCount(lang, n: n)
        switch lang {
        case .ru: return "\(d) подряд"
        case .en: return "\(n) day streak"
        case .de: return "\(d) in Folge"
        case .es: return "\(d) seguidos"
        case .fr: return "\(d) d'affilée"
        case .it: return "\(d) di fila"
        case .pl: return "\(d) z rzędu"
        case .id: return "\(d) berturut-turut"
        case .tr: return "üst üste \(d)"
        case .fil: return "\(d) na sunod-sunod"
        case .uk: return "\(d) поспіль"
        case .kk: return "қатарынан \(d)"
        case .pt: return "\(d) seguidos"
        }
    }
    static func repeatRouteTimes(_ lang: LanguageManager.Language, n: Int) -> String {
        let t = "\(n) \(nounTimes(lang, n))"
        switch lang {
        case .ru: return "Вы проехали этот маршрут уже \(t)"
        case .en: return n == 1
            ? "You've driven this route once"
            : "You've driven this route \(t)"
        case .de: return "Du bist diese Strecke schon \(t) gefahren"
        case .es: return "Ya has hecho esta ruta \(t)"
        case .fr: return "Vous avez déjà fait cet itinéraire \(t)"
        case .it: return "Hai già percorso questo itinerario \(t)"
        case .pl: return "Przejechałeś tę trasę już \(t)"
        case .id: return "Kamu sudah melewati rute ini \(t)"
        case .tr: return "Bu rotayı \(t) geçtin"
        case .fil: return "\(t) mo nang nadaanan ang rutang ito"
        case .uk: return "Ви проїхали цей маршрут уже \(t)"
        case .kk: return "Бұл бағытты \(t) жүріп өттіңіз"
        case .pt: return "Você já fez esta rota \(t)"
        }
    }
    /// «Без авто» — shorter than noVehicle's «Без машины» (idle-HUD chip).
    static func moreActions(_ lang: LanguageManager.Language) -> String {
        tr(lang, "moreActions", ru: "Ещё", en: "More")
    }
    static func openRouteMapA11y(_ lang: LanguageManager.Language) -> String {
        tr(lang, "openRouteMapA11y", ru: "Открыть карту маршрута", en: "Open route map")
    }
    /// VoiceOver HINT (verb phrase) for the poster title button.
    static func editTitleA11y(_ lang: LanguageManager.Language) -> String {
        tr(lang, "editTitleA11y", ru: "Изменяет название поездки", en: "Edits the trip title")
    }
    static func blockedListLoadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "blockedListLoadFailed",
           ru: "Не удалось загрузить список",
           en: "Couldn't load the list")
    }
    /// Caption WITHOUT the number — the counter renders it separately.
    static func followersCaption(_ lang: LanguageManager.Language, n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "подписчик", few: "подписчика", many: "подписчиков")
        case .en: return plural(lang, n, one: "follower", many: "followers")
        case .de: return plural(lang, n, one: "Follower", many: "Follower")
        case .es: return plural(lang, n, one: "seguidor", many: "seguidores")
        case .fr: return plural(lang, n, one: "abonné", many: "abonnés")
        case .it: return plural(lang, n, one: "follower", many: "follower")
        case .pl: return plural(lang, n, one: "obserwujący", few: "obserwujących", many: "obserwujących")
        case .id: return "pengikut"
        case .tr: return "takipçi"
        case .fil: return "tagasunod"
        case .uk: return plural(lang, n, one: "підписник", few: "підписники", many: "підписників")
        case .kk: return "жазылушы"
        case .pt: return plural(lang, n, one: "seguidor", many: "seguidores")
        }
    }
    static func followingCaption(_ lang: LanguageManager.Language, n: Int) -> String {
        switch lang {
        case .ru: return plural(lang, n, one: "подписка", few: "подписки", many: "подписок")
        case .en: return "following"
        case .de: return "gefolgt"
        case .es: return "siguiendo"
        case .fr: return "abonnements"
        case .it: return "seguiti"
        case .pl: return "obserwowanych"
        case .id: return "diikuti"
        case .tr: return "takip edilen"
        case .fil: return "sinusundan"
        case .uk: return plural(lang, n, one: "підписка", few: "підписки", many: "підписок")
        case .kk: return "жазылым"
        case .pt: return "seguindo"
        }
    }
    // MARK: - Share sheet (0.6.0)

    // MARK: - Comment replies (0.6.0)

    /// Owner «…» entries on a feed card (canon).
    static func edit(_ lang: LanguageManager.Language) -> String {
        tr(lang, "edit", ru: "Редактировать", en: "Edit")
    }
    static func makePrivateAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "makePrivateAction", ru: "Сделать приватной", en: "Make private")
    }

    // Canon alert copy (Figma «Лента · Алерт · точно приватной? / точно
    // удалить?»): plain question, one line of consequence, «Нет» / «Да, …».
    // Undo toasts after the alert (canon «после "Да" в алерте»).
    static func tripHiddenToast(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripHiddenToast", ru: "Поездка скрыта из ленты", en: "Trip hidden from the feed")
    }
    static func tripDeletedToast(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripDeletedToast", ru: "Поездка удалена", en: "Trip deleted")
    }
    static func undoAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "undoAction", ru: "Отменить", en: "Undo")
    }

    static func hideFromFeedAlertTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "hideFromFeedAlertTitle", ru: "Точно скрыть из ленты?", en: "Hide from the feed?")
    }
    static func hideFromFeedAlertBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "hideFromFeedAlertBody",
           ru: "Поездка останется только в вашем дневнике.",
           en: "The trip stays in your own diary only.")
    }
    static func hideFromFeedAlertConfirm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "hideFromFeedAlertConfirm", ru: "Да, скрыть", en: "Yes, hide")
    }
    static func deleteTripAlertTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteTripAlertTitle", ru: "Точно удалить поездку?", en: "Delete this trip?")
    }
    static func deleteTripAlertBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteTripAlertBody",
           ru: "Маршрут, фото и статистика исчезнут из вашего дневника.",
           en: "Its route, photos and stats disappear from your diary.")
    }
    static func deleteTripAlertConfirm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "deleteTripAlertConfirm", ru: "Да, удалить", en: "Yes, delete")
    }
    static func no(_ lang: LanguageManager.Language) -> String {
        tr(lang, "no", ru: "Нет", en: "No")
    }

    static func makePrivateConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "makePrivateConfirmTitle",
           ru: "Сделать поездку приватной?",
           en: "Make this trip private?")
    }
    static func makePrivateConfirmBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "makePrivateConfirmBody",
           ru: "Она исчезнет из общей ленты, а реакции и комментарии к ней больше никто не увидит. Вернуть публичной можно в любой момент.",
           en: "It leaves the public feed, and its reactions and comments go with it. You can publish it again any time.")
    }

    /// Header link on the detail preview → full thread.
    static func commentsSeeAll(_ lang: LanguageManager.Language) -> String {
        tr(lang, "commentsSeeAll", ru: "Все", en: "All")
    }
    static func commentReply(_ lang: LanguageManager.Language) -> String {
        tr(lang, "commentReply", ru: "Ответить", en: "Reply")
    }
    static func commentReplyingTo(_ lang: LanguageManager.Language, _ name: String) -> String {
        switch lang {
        case .ru: return "В ответ \(name)"
        case .en: return "Replying to \(name)"
        case .de: return "Antwort an \(name)"
        case .es: return "Respondiendo a \(name)"
        case .fr: return "En réponse à \(name)"
        case .it: return "In risposta a \(name)"
        case .pl: return "Odpowiedź do \(name)"
        case .id: return "Membalas \(name)"
        case .tr: return "\(name) kişisine yanıt"
        case .fil: return "Sumasagot kay \(name)"
        case .uk: return "У відповідь \(name)"
        case .kk: return "\(name) жауап ретінде"
        case .pt: return "Respondendo a \(name)"
        }
    }

    /// Short sign-in label for chrome (feed header pill, guest states).
    static func signInShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "signInShort", ru: "Войти", en: "Sign in")
    }

    static func shareTripTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "shareTripTitle", ru: "Поделиться поездкой", en: "Share trip")
    }
    /// Sits under the preview: says what the card is FOR, so the formats
    /// above it read as choices rather than settings.
    static func shareCardCaption(_ lang: LanguageManager.Language) -> String {
        tr(lang, "shareCardCaption",
           ru: "Готовая карточка — в чат, пост или сторис",
           en: "Ready-made card — for a chat, a post or a story")
    }
    static func shareCopyLink(_ lang: LanguageManager.Language) -> String {
        tr(lang, "shareCopyLink", ru: "Копировать", en: "Copy")
    }

    /// VoiceOver label for the circular close button on sheet headers.
    static func closeSheet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "closeSheet", ru: "Закрыть", en: "Close")
    }
    static func reportProfileAction(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportProfileAction", ru: "Пожаловаться", en: "Report")
    }
    /// «…» menu entry on a public profile — toggles with the block state.
    static func blockProfileAction(
        _ lang: LanguageManager.Language, isBlocked: Bool
    ) -> String {
        isBlocked ? blockProfileUnblock(lang) : blockProfileBlock(lang)
    }
    static func blockProfileUnblock(_ lang: LanguageManager.Language) -> String {
        tr(lang, "blockProfileUnblock", ru: "Разблокировать", en: "Unblock")
    }
    static func blockProfileBlock(_ lang: LanguageManager.Language) -> String {
        tr(lang, "blockProfileBlock", ru: "Заблокировать", en: "Block")
    }
    /// The confirmation the «…» row raises. Its button reuses
    /// `blockProfileAction` above — one verb, named once.
    static func blockProfileConfirmTitle(
        _ lang: LanguageManager.Language, isBlocked: Bool
    ) -> String {
        isBlocked
            ? tr(lang, "blockProfileConfirmTitleUnblock",
                 ru: "Разблокировать пользователя?", en: "Unblock this user?")
            : tr(lang, "blockProfileConfirmTitleBlock",
                 ru: "Заблокировать пользователя?", en: "Block this user?")
    }
    static func blockProfileConfirmBody(
        _ lang: LanguageManager.Language, isBlocked: Bool
    ) -> String {
        isBlocked
            ? tr(lang, "blockProfileConfirmBodyUnblock",
                 ru: "Пользователь снова сможет видеть ваши публичные поездки и подписываться на вас.",
                 en: "This user will again be able to see your public trips and follow you.")
            : tr(lang, "blockProfileConfirmBodyBlock",
                 ru: "Пользователь не увидит ваш контент, а его поездки не появятся в вашей ленте. Вы оба автоматически отписываетесь друг от друга.",
                 en: "This user won't see your content, and their trips won't appear in your feed. Any follows between you will be removed.")
    }
    /// «…» menu entry on a public profile — puts the profile URL on the
    /// pasteboard. The share row above it reuses `settingsShareProfile`.
    static func copyProfileLink(_ lang: LanguageManager.Language) -> String {
        tr(lang, "copyProfileLink", ru: "Скопировать ссылку", en: "Copy link")
    }
    /// Toast that answers the copy — the pasteboard itself says nothing.
    static func profileLinkCopied(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileLinkCopied", ru: "Ссылка скопирована", en: "Link copied")
    }
    /// Long-press on the name in a profile. The name — not the @handle: the
    /// handle is still device-local, so it is the name that Поиск can find.
    static func profileNameCopied(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileNameCopied", ru: "Имя скопировано", en: "Name copied")
    }
    /// Comment-create throttle (10/min server-side).
    static func commentRateLimited(_ lang: LanguageManager.Language) -> String {
        tr(lang, "commentRateLimited",
           ru: "Слишком много комментариев — подождите минуту",
           en: "Too many comments — wait a minute")
    }

    // MARK: - Companions

    static func companionsSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsSection", ru: "Попутчики", en: "Companions")
    }
    static func companionsAddPrompt(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsAddPrompt", ru: "Добавить попутчиков", en: "Add companions")
    }
    static func companionsEmptyHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsEmptyHint", ru: "Кто ехал с вами?", en: "Who rode with you?")
    }
    /// Fix 2: own trip, not yet on the server — the invite row is shown
    /// disabled (not a button) with this hint instead of the ordinary
    /// `companionsEmptyHint`, because inviting isn't possible yet either.
    static func companionsPublishFirstHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsPublishFirstHint",
           ru: "Чтобы звать попутчиков, сначала опубликуйте поездку",
           en: "Publish the trip first to invite companions")
    }
    /// The OTHER reason the invite row can't act yet, and the one that used
    /// to be misreported as `companionsPublishFirstHint`: a signed-out
    /// viewer on their own trip — which may well be published already, so
    /// telling them to publish it is both wrong and a dead end. Unlike the
    /// publish hint, this row IS tappable: it opens the sign-in sheet.
    static func companionsSignInHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsSignInHint",
           ru: "Войдите, чтобы звать попутчиков",
           en: "Sign in to invite companions")
    }
    /// «Позвать» — opens the (Task 3) candidate picker. Same word for both
    /// the empty-state row and the smaller CTA appended after an existing
    /// roster.
    static func companionsInvite(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsInvite", ru: "Позвать", en: "Invite")
    }
    /// The note a roster row carries while the invite is unanswered.
    static func companionsWaiting(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsWaiting", ru: "ждёт", en: "Pending")
    }
    /// Declined rows reach the OWNER's roster only. They used to be told
    /// apart by dimming alone, which says "different" without saying how —
    /// on the roster screen, where the owner goes specifically to see who
    /// answered what, the row says it outright.
    static func companionsDeclinedNote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsDeclinedNote", ru: "отказался", en: "Declined")
    }
    /// A companion with no display name — an account that never set one.
    static func companionsNoName(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsNoName", ru: "Без имени", en: "No name")
    }

    // MARK: - Companions summary plaque (trip detail)

    /// The plaque's second line when at least one companion accepted, on
    /// the viewer's OWN trip.
    static func companionsRodeWithYou(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsRodeWithYou", ru: "Ездили вместе с вами", en: "Rode along with you")
    }
    /// Same line on someone else's trip — the viewer isn't the driver, so
    /// "с вами" would be a lie for a stranger and only accidentally true
    /// for a companion.
    static func companionsRodeTogether(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsRodeTogether", ru: "Ездили вместе", en: "Rode along")
    }
    /// The plaque's second line when NOBODY has accepted yet and the
    /// invites are still out.
    static func companionsAwaitingReply(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        switch lang {
        case .ru: return plural(lang, count, one: "Ждём ответа", many: "Ждём ответов")
        case .en: return plural(lang, count, one: "Waiting for a reply", many: "Waiting for replies")
        case .de: return plural(lang, count, one: "Warten auf eine Antwort", many: "Warten auf Antworten")
        case .es: return plural(lang, count, one: "Esperando respuesta", many: "Esperando respuestas")
        case .fr: return plural(lang, count, one: "En attente d'une réponse", many: "En attente de réponses")
        case .it: return plural(lang, count, one: "In attesa di una risposta", many: "In attesa di risposte")
        case .pl: return plural(lang, count, one: "Czekamy na odpowiedź", many: "Czekamy na odpowiedzi")
        case .id: return "Menunggu jawaban"
        case .tr: return plural(lang, count, one: "Yanıt bekleniyor", many: "Yanıtlar bekleniyor")
        case .fil: return "Naghihintay ng sagot"
        case .uk: return plural(lang, count, one: "Чекаємо відповіді", many: "Чекаємо відповідей")
        case .kk: return "Жауап күтудеміз"
        case .pt: return plural(lang, count, one: "Aguardando resposta", many: "Aguardando respostas")
        }
    }
    /// Appended after `companionsRodeWithYou` when some accepted and others
    /// haven't answered — the accepted names are what the plaque shows, so
    /// without this the pending invites would be invisible until the roster
    /// screen is opened.
    static func companionsPendingSuffix(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        switch lang {
        case .ru: return count == 1 ? "ещё один ждёт" : "ещё \(count) ждут"
        case .en: return count == 1 ? "1 more pending" : "\(count) more pending"
        case .de: return count == 1 ? "1 weitere offen" : "\(count) weitere offen"
        case .es: return count == 1 ? "1 más pendiente" : "\(count) más pendientes"
        case .fr: return count == 1 ? "1 autre en attente" : "\(count) autres en attente"
        case .it: return count == 1 ? "1 altro in attesa" : "\(count) altri in attesa"
        case .pl: return count == 1 ? "jeszcze 1 czeka" : "jeszcze \(count) czeka"
        case .id: return "\(count) lagi menunggu"
        case .tr: return "\(count) kişi daha bekliyor"
        case .fil: return "\(count) pa ang naghihintay"
        case .uk: return count == 1 ? "ще один чекає" : "ще \(count) чекають"
        case .kk: return "тағы \(count) күтуде"
        case .pt: return count == 1 ? "mais 1 aguardando" : "mais \(count) aguardando"
        }
    }
    /// The plaque's second line when every invite was declined — owner-only
    /// by construction (declined rows never leave the server for anyone
    /// else).
    static func companionsAllDeclined(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        switch lang {
        case .ru: return plural(lang, count, one: "Отказался", many: "Отказались")
        case .en: return "Declined the invite"
        case .de: return "Einladung abgelehnt"
        case .es: return "Rechazaron la invitación"
        case .fr: return "Ont refusé l'invitation"
        case .it: return "Hanno rifiutato l'invito"
        case .pl: return "Odrzucili zaproszenie"
        case .id: return "Menolak undangan"
        case .tr: return "Daveti reddetti"
        case .fil: return "Tinanggihan ang imbitasyon"
        case .uk: return plural(lang, count, one: "Відмовився", many: "Відмовились")
        case .kk: return "Шақыруды қабылдамады"
        case .pt: return "Recusaram o convite"
        }
    }
    /// Tail of the names line when more people are on the trip than the
    /// plaque spells out: «Аня К., Дмитрий П. и ещё 2».
    static func companionsAndMore(
        _ count: Int, _ lang: LanguageManager.Language
    ) -> String {
        switch lang {
        case .ru: return "и ещё \(count)"
        case .en: return "and \(count) more"
        case .de: return "und \(count) weitere"
        case .es: return "y \(count) más"
        case .fr: return "et \(count) de plus"
        case .it: return "e altri \(count)"
        case .pl: return "i jeszcze \(count)"
        case .id: return "dan \(count) lagi"
        case .tr: return "ve \(count) kişi daha"
        case .fil: return "at \(count) pa"
        case .uk: return "і ще \(count)"
        case .kk: return "және тағы \(count)"
        case .pt: return "e mais \(count)"
        }
    }
    static func companionsLoadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsLoadFailed",
           ru: "Не удалось загрузить попутчиков",
           en: "Couldn't load companions")
    }
    /// Task 7: shown alongside a cached roster (`Trip.companions`) on the
    /// viewer's own trip when today's `/companions/list` refresh failed —
    /// real rows ARE on screen, so this is deliberately quieter than
    /// `companionsLoadFailed`'s error phrasing, just flagging that they
    /// might be out of date.
    static func companionsCachedNotice(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsCachedNotice",
           ru: "Нет сети — может быть неактуально",
           en: "Offline — may be out of date")
    }
    /// Confirmation after picking photos. The system picker opens on a
    /// library that already holds everything you added before, so without a
    /// receipt afterwards there is nothing to tell "added" from "looked at
    /// the same photos again".
    static func photosAdded(_ count: Int, _ lang: LanguageManager.Language) -> String {
        let p = photosCount(lang, n: count)
        switch lang {
        case .ru: return "Добавлено \(p)"
        case .en: return "\(p) added"
        case .de: return "\(p) hinzugefügt"
        case .es: return "\(p) añadidas"
        case .fr: return "\(p) ajoutées"
        case .it: return "\(p) aggiunte"
        case .pl: return "Dodano \(p)"
        case .id: return "\(p) ditambahkan"
        case .tr: return "\(p) eklendi"
        case .fil: return "Naidagdag ang \(p)"
        case .uk: return "Додано \(p)"
        case .kk: return "\(p) қосылды"
        case .pt: return "\(p) adicionadas"
        }
    }
    static func companionsRemoveFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsRemoveFailed",
           ru: "Не удалось убрать попутчика",
           en: "Couldn't remove companion")
    }
    /// Task 6: a companion's photo pick failed to reach the server at all
    /// (the required thumbnail part never landed). Shown as an error
    /// toast; the photo strip itself is left untouched (see
    /// `CompanionPhotoUploadController`'s doc comment).
    static func companionPhotoUploadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionPhotoUploadFailed",
           ru: "Не удалось загрузить фото",
           en: "Couldn't upload photo")
    }
    /// Task 6: a companion's photo DID land (its thumbnail is on the
    /// server and it's visible on the trip) but the full-quality original
    /// didn't. Deliberately NOT phrased as a failure — the photo is there.
    static func companionPhotoUploadDegraded(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionPhotoUploadDegraded",
           ru: "Фото добавлено, но в уменьшенном качестве",
           en: "Photo added, but at reduced quality")
    }
    /// Task 6, review fix: a companion picked SEVERAL photos and only some
    /// landed — the rest were genuinely attempted and failed, not silently
    /// skipped. `succeeded`/`total` name exactly how many, so this can
    /// never be read as a flat failure when photos actually did get added.
    static func companionPhotoUploadPartial(_ succeeded: Int, _ total: Int, _ lang: LanguageManager.Language) -> String {
        let ratio = "\(succeeded) \(ofWord(lang)) \(total) \(nounPhotos(lang, total))"
        switch lang {
        case .ru: return "Добавлено \(ratio)"
        case .en: return "\(ratio) added"
        case .de: return "\(ratio) hinzugefügt"
        case .es: return "\(ratio) añadidas"
        case .fr: return "\(ratio) ajoutées"
        case .it: return "\(ratio) aggiunte"
        case .pl: return "Dodano \(ratio)"
        case .id: return "\(ratio) ditambahkan"
        case .tr: return "\(ratio) eklendi"
        case .fil: return "Naidagdag ang \(ratio)"
        case .uk: return "Додано \(ratio)"
        case .kk: return "\(ratio) қосылды"
        case .pt: return "\(ratio) adicionadas"
        }
    }
    /// Task 6, review fix: the upload itself succeeded (at least one photo
    /// landed on the server), but the follow-up refresh of the trip's
    /// photo list failed — a distinct, separate network call. The strip
    /// keeps showing whatever it showed before this attempt (see
    /// `TripDetailView.uploadCompanionPhotos`); this says why the newly
    /// added photo isn't visible YET, not that the upload failed.
    static func companionPhotoReloadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionPhotoReloadFailed",
           ru: "Фото загружено, но список не обновился. Загляните на поездку позже",
           en: "Photo uploaded, but the list didn't refresh. Check back on this trip later")
    }
    /// Fix 1: the trip owner tried to delete a companion's remote-only
    /// photo (no local row — `/photos/delete` failed). The optimistic
    /// removal from the strip is rolled back alongside this toast.
    static func companionPhotoDeleteFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionPhotoDeleteFailed",
           ru: "Не удалось удалить фото",
           en: "Couldn't delete photo")
    }
    static func companionsRemoveConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsRemoveConfirmTitle", ru: "Убрать попутчика?", en: "Remove companion?")
    }
    /// The confirmation dialog's destructive button AND the row's own
    /// remove control — deliberately NOT `delete`: a companion is being
    /// taken off the trip, not destroyed, and the dialog's own title
    /// already says «Убрать».
    static func companionsRemove(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsRemove", ru: "Убрать", en: "Remove")
    }
    /// Fix 3: a companion's own affordance for leaving someone else's
    /// trip — the «…» popover item, the confirmation dialog's title (used
    /// as a question, mirroring `deleteTrip`'s reuse pattern for its own
    /// confirmation) and its destructive button.
    static func companionsLeaveTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsLeaveTrip", ru: "Покинуть поездку", en: "Leave trip")
    }
    static func companionsLeaveConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsLeaveConfirmTitle", ru: "Покинуть эту поездку?", en: "Leave this trip?")
    }
    static func companionsLeaveFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsLeaveFailed",
           ru: "Не удалось покинуть поездку",
           en: "Couldn't leave the trip")
    }

    // MARK: - Companions picker (Task 3)

    /// `CompanionsPickerSheet`'s own header — deliberately not reusing
    /// `companionsInvite` ("Позвать"), which is the CTA that OPENS this
    /// sheet, not what the sheet itself is titled.
    static func companionsPickerTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsPickerTitle", ru: "Пригласить попутчика", en: "Invite a companion")
    }
    static func companionsSearchPlaceholder(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsSearchPlaceholder",
           ru: "Поиск по подпискам",
           en: "Search who you follow")
    }
    /// The picker's loaded-and-empty state — states the actual rule rather
    /// than implying the request is broken.
    static func companionsCandidatesEmptyTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsCandidatesEmptyTitle", ru: "Некого позвать", en: "No one to invite")
    }
    static func companionsCandidatesEmptyHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsCandidatesEmptyHint",
           ru: "Позвать можно только тех, на кого вы подписаны.",
           en: "You can only invite people you follow.")
    }
    static func companionsCandidatesLoadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsCandidatesLoadFailed",
           ru: "Не удалось загрузить список",
           en: "Couldn't load the list")
    }
    static func companionsInviteFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsInviteFailed", ru: "Не удалось позвать", en: "Couldn't invite")
    }
    /// The row state right after a successful (optimistic) tap — kept
    /// lowercase to match `companionsWaiting`'s «ждёт» styling.
    static func companionsInvited(_ lang: LanguageManager.Language) -> String {
        tr(lang, "companionsInvited", ru: "приглашён", en: "Invited")
    }

    // MARK: - «Со мной» profile section (Task 5)

    /// Section header. Reuses `ProfileTripRow` — same row `historySection`
    /// draws for the user's own trips — but each row names the driver, the
    /// one fact that tells this section apart from «История».
    static func withMeSection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "withMeSection", ru: "Со мной", en: "With me")
    }
    static func withMeLoadFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "withMeLoadFailed", ru: "Не удалось загрузить поездки", en: "Couldn't load trips")
    }
    /// The driver-name fallback for a «Со мной» row. Same copy as the four
    /// pre-existing inline `displayName ?? (lang == .ru ? "Без имени" :
    /// "No name")` spots (`TripCompanionsSection.swift`,
    /// `CompanionsPickerSheet.swift`, `TripDetailView.swift` ×2) — this task
    /// only owns `WithMeSection`'s copy of that pattern (review finding),
    /// not a sweep of the pre-existing ones.
    static func withMeDriverNoName(_ lang: LanguageManager.Language) -> String {
        tr(lang, "withMeDriverNoName", ru: "Без имени", en: "No name")
    }

    // MARK: - Achievements screens (0.6.0)

    /// Navigation title of the full achievements screen. Same copy as the
    /// profile section header — aliased rather than duplicated so the two
    /// can never drift apart mid-navigation.
    static func achievementsTitle(_ lang: LanguageManager.Language) -> String {
        achievementsSection(lang)
    }
    /// The screen's own counter, which — unlike the profile pill — has room
    /// for the verb. Built on `achievementsProgress` so «из»/«of» is written
    /// once; `AppStrings.` qualifies `unlocked` past the Int parameter.
    static func achievementsOpenedOf(
        _ lang: LanguageManager.Language, unlocked: Int, total: Int
    ) -> String {
        let progress = achievementsProgress(lang, unlocked: unlocked, total: total)
        return "\(progress) \(AppStrings.unlocked(lang))"
    }
    static func achievementsCollectHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsCollectHint",
           ru: "Собери коллекцию дорожных достижений",
           en: "Collect the road achievement set")
    }
    static func achievementsFilterAll(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsFilterAll", ru: "Все", en: "All")
    }
    static func achievementsFilterUnlocked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsFilterUnlocked", ru: "Открытые", en: "Unlocked")
    }
    static func achievementsFilterSecret(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsFilterSecret", ru: "Секретные", en: "Secret")
    }
    /// Stand-in title of a hidden badge. Typographic, so it is identical in
    /// both languages; the parameter keeps the call site uniform with every
    /// other title on the screen.
    static func achievementsSecretTitle(_ lang: LanguageManager.Language) -> String {
        "? ? ?"
    }
    static func achievementsSecretCaption(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementsSecretCaption", ru: "Секретное", en: "Secret")
    }
    /// Global rarity line. `percent` is the bare number already formatted for
    /// the locale («0,4» in RU, "0.4" in EN) — the caller owns the separator,
    /// this owns the sign and the wording around it.
    static func achievementsEarnedBy(
        _ lang: LanguageManager.Language, percent: String
    ) -> String {
        switch lang {
        case .ru: return "Получили \(percent)%"
        case .en: return "Earned by \(percent)%"
        case .de: return "Von \(percent) % erreicht"
        case .es: return "Lo tiene el \(percent) %"
        case .fr: return "Obtenu par \(percent) %"
        case .it: return "Ottenuto dal \(percent)%"
        case .pl: return "Zdobyło \(percent)%"
        case .id: return "Diperoleh \(percent)%"
        case .tr: return "%\(percent) kişide var"
        case .fil: return "Nakuha ng \(percent)%"
        case .uk: return "Отримали \(percent)%"
        case .kk: return "\(percent)% алды"
        case .pt: return "Conquistado por \(percent)%"
        }
    }
    /// Hero chips: «Легендарных 1». RU needs the genitive plural, which
    /// `BadgeRarity.titleRu()` (feminine singular, «Легендарная») can't give,
    /// so the declined forms live here with the rest of the copy. EN reuses
    /// the enum's own titles, including "Special" for `.exclusive`.
    static func achievementsRarityCount(
        _ lang: LanguageManager.Language, rarity: BadgeRarity, count: Int
    ) -> String {
        guard lang == .ru else { return "\(rarity.title(lang)) \(count)" }
        // Russian counts the rarity in the genitive plural: «Редких 3».
        let word: String
        switch rarity {
        case .common:    word = "Обычных"
        case .uncommon:  word = "Необычных"
        case .rare:      word = "Редких"
        case .epic:      word = "Эпических"
        case .legendary: word = "Легендарных"
        case .exclusive: word = "Особых"
        }
        return "\(word) \(count)"
    }
    /// The DETAIL screen is about one award — canon titles all four of its
    /// states in the singular, against the plural of the list behind it.
    static func achievementDetailTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementDetailTitle", ru: "Достижение", en: "Achievement")
    }
    static func achievementPin(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementPin", ru: "Закрепить", en: "Pin")
    }
    static func achievementUnpin(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementUnpin", ru: "Открепить", en: "Unpin")
    }
    static func achievementPinConfirmTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementPinConfirmTitle",
           ru: "Закрепить достижение?",
           en: "Pin this achievement?")
    }
    /// Says who sees it, because pinning is the one achievement action with a
    /// consequence outside the owner's own screen.
    static func achievementPinConfirmBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "achievementPinConfirmBody",
           ru: "Оно будет первым в вашем профиле — его увидят все, кто откроет вашу страницу.",
           en: "It goes to the top of your profile, where anyone who opens your page will see it.")
    }
    /// Progress toward a locked badge. Pure assembly — `current`, `target` and
    /// `unit` all arrive formatted, so the separator and the unit are the
    /// caller's; the language parameter keeps the call site uniform.
    static func achievementLockedProgress(
        _ lang: LanguageManager.Language, current: String, target: String, unit: String
    ) -> String {
        "\(current) / \(target) \(unit)"
    }

    // MARK: - «Мой профиль» hub (0.6.0, Figma 1687:119)

    static func myProfileTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileTitle", ru: "Мой профиль", en: "My profile")
    }
    static func myProfileChangeAvatar(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileChangeAvatar", ru: "Сменить аватар", en: "Change avatar")
    }
    /// The grid has no Done button — say so, or the tap reads as unsaved.
    static func myProfileAvatarHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileAvatarHint",
           ru: "Тап по эмодзи — аватар сохранится сразу",
           en: "Tap an emoji — saved right away")
    }
    /// The hub rows deliberately carry the same word as the editor each one
    /// opens, so the four below forward to the editor titles instead of
    /// keeping a second copy of the copy.
    static func myProfileRowName(_ lang: LanguageManager.Language) -> String {
        nameEditorTitle(lang)
    }
    static func myProfileRowUsername(_ lang: LanguageManager.Language) -> String {
        usernameTitle(lang)
    }
    static func myProfileRowAbout(_ lang: LanguageManager.Language) -> String {
        aboutTitle(lang)
    }
    static func myProfileRowLevel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileRowLevel", ru: "Уровень", en: "Level")
    }
    static func myProfileRowCountry(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileRowCountry", ru: "Страна", en: "Country")
    }
    /// Bottom row of the hub — opens the public profile as strangers see it.
    static func myProfileRowPreview(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileRowPreview", ru: "Как видят другие", en: "How others see you")
    }
    /// Shown under the avatar grid ONLY to someone still wearing an emoji that
    /// the curated set no longer offers. It is the one moment the fact matters:
    /// the grid is open, and the next tap is irreversible.
    static func myProfileAvatarRetired(
        _ lang: LanguageManager.Language, emoji: String
    ) -> String {
        switch lang {
        case .ru: return "\(emoji) — из набора, которого больше нет. Сменишь — вернуть уже не получится."
        case .en: return "\(emoji) is from a set that no longer exists. Change it and it is gone for good."
        case .de: return "\(emoji) stammt aus einem Set, das es nicht mehr gibt. Wechselst du, ist es für immer weg."
        case .es: return "\(emoji) es de un set que ya no existe. Si lo cambias, no habrá vuelta atrás."
        case .fr: return "\(emoji) vient d'un lot qui n'existe plus. Si vous en changez, il est perdu pour de bon."
        case .it: return "\(emoji) viene da un set che non esiste più. Se lo cambi, non torna indietro."
        case .pl: return "\(emoji) pochodzi z zestawu, którego już nie ma. Zmienisz — nie odzyskasz."
        case .id: return "\(emoji) berasal dari set yang sudah tidak ada. Kalau diganti, tidak bisa kembali."
        case .tr: return "\(emoji) artık var olmayan bir setten. Değiştirirsen bir daha geri gelmez."
        case .fil: return "Ang \(emoji) ay mula sa set na wala na. Kapag pinalitan mo, hindi na ito mababalik."
        case .uk: return "\(emoji) — з набору, якого більше немає. Зміниш — повернути вже не вийде."
        case .kk: return "\(emoji) — енді жоқ жинақтан. Ауыстырсаң, қайтару мүмкін болмайды."
        case .pt: return "\(emoji) é de um conjunto que não existe mais. Se trocar, não dá para voltar."
        }
    }
    static func myProfileRowStats(_ lang: LanguageManager.Language) -> String {
        stats(lang)
    }
    static func myProfileUsernameUnset(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileUsernameUnset", ru: "Задать юзернейм", en: "Set a username")
    }
    static func myProfileAboutUnset(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileAboutUnset", ru: "Рассказать о себе", en: "Say something")
    }
    /// «47 поездок · 2 430 км». `km` arrives grouped for the locale — the
    /// caller owns the separator, this owns the unit and the trip plural.
    static func myProfileStatsSummary(
        _ lang: LanguageManager.Language, trips: Int, km: String
    ) -> String {
        "\(tripsCount(lang, n: trips)) · \(km) \(AppStrings.km(lang))"
    }

    // MARK: - Username editor (0.6.0, Figma 1833:6714)

    static func usernameTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameTitle", ru: "Юзернейм", en: "Username")
    }
    static func usernameHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameHint",
           ru: "Уникальное имя для профиля и ссылок. Латиница, цифры и «.», «_». 3–20 символов.",
           en: "Your unique handle for links and mentions. Latin letters, digits, «.» and «_». 3–20 characters.")
    }
    static func usernameFree(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameFree", ru: "Свободно", en: "Available")
    }
    static func usernameTaken(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameTaken", ru: "Уже занято", en: "Already taken")
    }
    static func usernameTooShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameTooShort", ru: "Слишком коротко", en: "Too short")
    }
    static func usernameInvalidChars(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameInvalidChars",
           ru: "Только латиница, цифры, «.» и «_»",
           en: "Latin letters, digits, «.» and «_» only")
    }
    /// Replaces `usernameHint` under the field when the name is taken, so it
    /// has to repeat the ask — the rules line is gone at that moment.
    static func usernameTakenHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameTakenHint",
           ru: "Это имя уже использует другой водитель. Попробуйте другое.",
           en: "Another driver already uses this handle. Try another.")
    }
    /// The lookup failed, not the name — never blame the input here.
    static func usernameCheckFailed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "usernameCheckFailed",
           ru: "Не удалось проверить — попробуйте ещё раз",
           en: "Couldn't check — try again")
    }

    // MARK: - About editor (0.6.0, Figma 1873:6873)

    /// «О приложении» already owns `about(_:)` — this is the profile bio.
    static func aboutTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "aboutTitle", ru: "О себе", en: "About")
    }
    static func aboutHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "aboutHint",
           ru: "Видно всем в профиле. До 140 символов.",
           en: "Visible to everyone on your profile. Up to 140 characters.")
    }

    // MARK: - Country picker (0.6.0, Figma 675:119)

    static func countryTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "countryTitle", ru: "Страна", en: "Country")
    }
    static func countryHint(_ lang: LanguageManager.Language) -> String {
        tr(lang, "countryHint",
           ru: "Необязательно — флаг виден в вашем профиле.",
           en: "Optional — the flag shows on your profile.")
    }
    static func countrySectionAll(_ lang: LanguageManager.Language) -> String {
        tr(lang, "countrySectionAll", ru: "СТРАНЫ", en: "COUNTRIES")
    }
    static func countryNone(_ lang: LanguageManager.Language) -> String {
        tr(lang, "countryNone", ru: "Не указывать", en: "Not set")
    }
    static func countryWorld(_ lang: LanguageManager.Language) -> String {
        tr(lang, "countryWorld", ru: "Весь мир", en: "Whole world")
    }
    static func countryNeutral(_ lang: LanguageManager.Language) -> String {
        tr(lang, "countryNeutral", ru: "Нейтральный флаг", en: "Neutral flag")
    }

    // MARK: - Levels screen (0.6.0, Figma 888:3848)

    /// The pushed screen behind the LVL pill. «Уровень водителя»
    /// (`rankProgressTitle`) still names the sheet it grew out of; this is the
    /// screen title, plural, because it now lists every rank.
    static func levelsTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsTitle", ru: "Уровни", en: "Levels")
    }
    /// Rank position is 1-based over `DriverRank.allCases`, not the enum index.
    static func levelsRankOf(_ lang: LanguageManager.Language, rank: Int, total: Int, level: Int) -> String {
        let rankWord = tr(lang, "levelsRankWord", ru: "Ранг", en: "Rank")
        let levelWord = tr(lang, "levelsLevelWord", ru: "уровень", en: "level")
        return "\(rankWord) \(rank) \(ofWord(lang)) \(total) · \(levelWord) \(level)"
    }
    /// Both halves arrive pre-grouped («6 100»), so the digits are already
    /// localised by the caller's formatter and the frame never varies by language.
    static func levelsXpProgress(_ lang: LanguageManager.Language, current: String, target: String) -> String {
        "\(current) / \(target) XP"
    }
    static func levelsToNextLevel(_ lang: LanguageManager.Language, level: Int) -> String {
        switch lang {
        case .ru: return "до \(level) уровня"
        case .en: return "to level \(level)"
        case .de: return "bis Level \(level)"
        case .es: return "hasta el nivel \(level)"
        case .fr: return "avant le niveau \(level)"
        case .it: return "al livello \(level)"
        case .pl: return "do poziomu \(level)"
        case .id: return "menuju level \(level)"
        case .tr: return "\(level). seviyeye"
        case .fil: return "papuntang level \(level)"
        case .uk: return "до \(level) рівня"
        case .kk: return "\(level)-деңгейге дейін"
        case .pt: return "até o nível \(level)"
        }
    }
    /// `rank` is an already-localised `DriverRank.title(_:)`.
    static func levelsNextRank(_ lang: LanguageManager.Language, rank: String, level: Int) -> String {
        let tail = "\(rank) · \(levelsRankRangePrefix(lang)) \(level)"
        switch lang {
        case .ru: return "Дальше — \(tail)"
        case .en: return "Next — \(tail)"
        case .de: return "Als Nächstes — \(tail)"
        case .es: return "Siguiente — \(tail)"
        case .fr: return "Ensuite — \(tail)"
        case .it: return "Poi — \(tail)"
        case .pl: return "Dalej — \(tail)"
        case .id: return "Berikutnya — \(tail)"
        case .tr: return "Sırada — \(tail)"
        case .fil: return "Susunod — \(tail)"
        case .uk: return "Далі — \(tail)"
        case .kk: return "Келесі — \(tail)"
        case .pt: return "A seguir — \(tail)"
        }
    }

    /// «ур.» / «lv.» — the abbreviated level marker used in rank ranges.
    static func levelsRankRangePrefix(_ lang: LanguageManager.Language) -> String {
        switch lang {
        case .ru: return "ур."
        case .en: return "lv."
        case .de: return "Lv."
        case .es: return "niv."
        case .fr: return "niv."
        case .it: return "liv."
        case .pl: return "poz."
        case .id: return "lvl"
        case .tr: return "sv."
        case .fil: return "lvl"
        case .uk: return "рів."
        case .kk: return "дең."
        case .pt: return "nív."
        }
    }
    static func levelsHowToEarn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsHowToEarn", ru: "Как получать опыт", en: "How to earn XP")
    }
    static func levelsAllRanks(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsAllRanks", ru: "Все ранги", en: "All ranks")
    }
    /// Canon draws this uppercase inside the pill — apply `.textCase(.uppercase)`
    /// at the call site rather than shouting in the catalogue.
    static func levelsCurrentMarker(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsCurrentMarker", ru: "сейчас", en: "now")
    }
    /// `to` is nil for the open-ended top rank («ур. 100+»).
    static func levelsRankRange(_ lang: LanguageManager.Language, from: Int, to: Int?) -> String {
        let prefix = levelsRankRangePrefix(lang)
        guard let to else { return "\(prefix) \(from)+" }
        return "\(prefix) \(from)–\(to)"
    }
    // The four XP rules. Badges carry only digits and symbols, so they read the
    // same in both languages — the `lang` parameter keeps the call sites uniform.
    /// Max level: there is no target left, so the bar's left-hand readout
    /// switches from «6 100 / 6 600 XP» to a plain lifetime total.
    static func levelsXpTotal(_ lang: LanguageManager.Language, xp: String) -> String {
        switch lang {
        case .ru: return "\(xp) XP всего"
        case .en: return "\(xp) XP total"
        case .de: return "\(xp) XP insgesamt"
        case .es: return "\(xp) XP en total"
        case .fr: return "\(xp) XP au total"
        case .it: return "\(xp) XP in totale"
        case .pl: return "\(xp) XP łącznie"
        case .id: return "\(xp) XP total"
        case .tr: return "toplam \(xp) XP"
        case .fil: return "\(xp) XP sa kabuuan"
        case .uk: return "\(xp) XP усього"
        case .kk: return "барлығы \(xp) XP"
        case .pt: return "\(xp) XP no total"
        }
    }
    static func levelsMaxLevel(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsMaxLevel", ru: "максимум", en: "max level")
    }
    /// Replaces the «дальше — …» pill once there is no next rank to name.
    static func levelsFinalRank(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsFinalRank",
           ru: "Последний ранг — дальше только километры",
           en: "Final rank — from here it is just kilometres")
    }
    static func levelsRuleKmBadge(_ lang: LanguageManager.Language) -> String {
        "1 XP"
    }
    static func levelsRuleKm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsRuleKm", ru: "за каждый километр", en: "per kilometre")
    }
    static func levelsRuleFirstBadge(_ lang: LanguageManager.Language) -> String {
        "+20"
    }
    static func levelsRuleFirst(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsRuleFirst",
           ru: "за первую поездку дня",
           en: "for the first trip of the day")
    }
    static func levelsRuleRegionBadge(_ lang: LanguageManager.Language) -> String {
        "+50"
    }
    static func levelsRuleRegion(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsRuleRegion",
           ru: "за новый регион — и ещё +50% к километрам",
           en: "for a new region — plus 50% more on the distance XP")
    }
    /// Multiplication sign, not the letter x — canon sets it as ×2.
    static func levelsRuleLongBadge(_ lang: LanguageManager.Language) -> String {
        "×2"
    }
    static func levelsRuleLong(_ lang: LanguageManager.Language) -> String {
        tr(lang, "levelsRuleLong", ru: "за поездки от 200 км", en: "for trips over 200 km")
    }

    // MARK: - Settings sheet (0.6.0, Figma 580:232 / hints 1741:129)

    /// Canon's «Добавление в попутчики» toggle — who may tag you on their trip.
    ///
    /// UNUSED since the settings restructure: the row it labelled was the same
    /// server field as the one in `NotificationPreferencesView` (Входящие → ⚙),
    /// and the «Уведомления» master directly above it already served the
    /// impulse it answered. Kept as catalogue — the categories screen can take
    /// this wording — not because anything calls it today.
    static func settingsCompanionAdds(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsCompanionAdds",
           ru: "Добавление в попутчики",
           en: "Adding you as a companion")
    }
    /// Canon shortens the link subtitles; `bugsAndIdeas` / `telegramChannelSub`
    /// keep their longer wording where they already ship (About screen).
    static func settingsWriteToAuthorSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsWriteToAuthorSub", ru: "отзывы и идеи", en: "feedback and ideas")
    }
    static func settingsTelegramSub(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsTelegramSub", ru: "дневник разработки", en: "development diary")
    }
    /// Header of the «?» popover. Deliberately not a question mark — the button
    /// already is one.
    static func settingsHintTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsHintTitle", ru: "Что это", en: "What this is")
    }
    /// Hint bodies explain the consequence of the switch, not its label — the
    /// label is right above them and repeating it teaches nothing.
    static func settingsHintPublicProfile(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsHintPublicProfile",
           ru: "Другие смогут открыть вашу страницу и увидеть поездки, которые вы сделали публичными. Приватные поездки не видит никто.",
           en: "Other drivers can open your page and see the trips you made public. Nobody sees your private trips.")
    }
    static func settingsHintNotifications(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsHintNotifications",
           ru: "Реакции и комментарии к вашим поездкам, приглашения в попутчики. Записи это не касается — она идёт без уведомлений.",
           en: "Reactions and comments on your trips, plus companion invites. Recording is unaffected — it runs without notifications.")
    }
    static func settingsHintCompanionAdds(_ lang: LanguageManager.Language) -> String {
        tr(lang, "settingsHintCompanionAdds",
           ru: "Кто угодно сможет отметить вас попутчиком в своей поездке. Вы всегда подтверждаете приглашение сами.",
           en: "Anyone can tag you as a companion on their trip. You always confirm the invite yourself.")
    }

    // MARK: - Unit / language / theme pickers (0.6.0, Figma 1685:119 / 176 / 233)

    /// Footnotes under each picker list: what actually changes on pick.
    static func unitsPickerFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unitsPickerFootnote",
           ru: "Дистанция и скорость, статистика и расстояния.",
           en: "Distance and speed, stats and ranges.")
    }
    static func languagePickerFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "languagePickerFootnote",
           ru: "Интерфейс перезагрузится на выбранном языке.",
           en: "The interface reloads in the chosen language.")
    }
    static func themePickerFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "themePickerFootnote",
           ru: "Системная следует настройкам iPhone.",
           en: "System follows your iPhone setting.")
    }

    /// What VoiceOver reads over a placeholder standing in for content that
    /// has not arrived — see `ProfileHistorySkeleton`.
    static func loadingTrips(_ lang: LanguageManager.Language) -> String {
        tr(lang, "loadingTrips", ru: "Загружаем поездки", en: "Loading trips")
    }

    static func avgSpeedPickerFootnote(_ lang: LanguageManager.Language) -> String {
        tr(lang, "avgSpeedPickerFootnote",
           ru: "Общая делит расстояние на всё время поездки, вместе со стоянками. В движении считает только то время, когда вы ехали.",
           en: "Overall divides the distance by the whole trip, stops included. Moving counts only the time you were driving.")
    }

    // MARK: - Statistics screen (0.6.0, Figma 580:316 / 580:416 / 1821:119 / 1827:119)

    static func statsYearAgoToday(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsYearAgoToday", ru: "ГОД НАЗАД В ЭТОТ ДЕНЬ", en: "A YEAR AGO TODAY")
    }
    /// The range segment reuses the app-wide period words — a second copy would
    /// drift the moment one of them is retranslated.
    static func statsRangeMonth(_ lang: LanguageManager.Language) -> String {
        month(lang)
    }
    static func statsRangeYear(_ lang: LanguageManager.Language) -> String {
        year(lang)
    }
    static func statsRangeAll(_ lang: LanguageManager.Language) -> String {
        total(lang)
    }
    static func statsHoursOnRoad(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsHoursOnRoad", ru: "ч в пути", en: "h on road")
    }
    /// «Больше, чем в прошлом июне — 840 км против 610». The caller owns the
    /// declined period («июне», «году») and both already-grouped numbers; the
    /// arrow glyph is the view's, not the copy's.
    static func statsVsLastPeriod(
        _ lang: LanguageManager.Language, more: Bool, period: String,
        current: String, previous: String
    ) -> String {
        let numbers = "\(current) \(AppStrings.km(lang))"
        switch lang {
        case .ru:
            return "\(more ? "Больше" : "Меньше"), чем в прошлом \(period) — \(numbers) против \(previous)"
        case .en:
            return "\(more ? "More" : "Less") than last \(period) — \(numbers) vs \(previous)"
        case .de:
            return "\(more ? "Mehr" : "Weniger") als \(period) davor — \(numbers) gegenüber \(previous)"
        case .es:
            return "\(more ? "Más" : "Menos") que el \(period) pasado — \(numbers) frente a \(previous)"
        case .fr:
            return "\(more ? "Plus" : "Moins") que \(period) dernier — \(numbers) contre \(previous)"
        case .it:
            return "\(more ? "Più" : "Meno") del \(period) scorso — \(numbers) contro \(previous)"
        case .pl:
            return "\(more ? "Więcej" : "Mniej") niż w poprzednim okresie (\(period)) — \(numbers) wobec \(previous)"
        case .id:
            return "\(more ? "Lebih banyak" : "Lebih sedikit") dari \(period) lalu — \(numbers) berbanding \(previous)"
        case .tr:
            return "Geçen \(period) dönemine göre \(more ? "daha fazla" : "daha az") — \(numbers), önceki \(previous)"
        case .fil:
            return "\(more ? "Mas marami" : "Mas kaunti") kaysa noong nakaraang \(period) — \(numbers) kumpara sa \(previous)"
        case .uk:
            return "\(more ? "Більше" : "Менше"), ніж у минулому \(period) — \(numbers) проти \(previous)"
        case .kk:
            return "Өткен \(period) кезеңімен салыстырғанда \(more ? "көбірек" : "азырақ") — \(numbers), бұрын \(previous)"
        case .pt:
            return "\(more ? "Mais" : "Menos") que \(period) passado — \(numbers) contra \(previous)"
        }
    }
    static func statsNewPlaces(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsNewPlaces", ru: "НОВЫЕ МЕСТА", en: "NEW PLACES")
    }
    /// «За июнь: +2 новые дороги · первый раз в Каргополе». The second half is
    /// dropped whole — separator included — when there is no first-time place.
    /// `firstPlace` arrives in the prepositional case from the caller.
    static func statsNewPlacesLine(
        _ lang: LanguageManager.Language, period: String, roads: Int, firstPlace: String?
    ) -> String {
        let noun: String
        switch lang {
        case .ru: noun = plural(lang, roads, one: "новая дорога", few: "новые дороги", many: "новых дорог")
        case .en: noun = plural(lang, roads, one: "new road", many: "new roads")
        case .de: noun = plural(lang, roads, one: "neue Straße", many: "neue Straßen")
        case .es: noun = plural(lang, roads, one: "carretera nueva", many: "carreteras nuevas")
        case .fr: noun = plural(lang, roads, one: "route nouvelle", many: "routes nouvelles")
        case .it: noun = plural(lang, roads, one: "strada nuova", many: "strade nuove")
        case .pl: noun = plural(lang, roads, one: "nowa droga", few: "nowe drogi", many: "nowych dróg")
        case .id: noun = "jalan baru"
        case .tr: noun = "yeni yol"
        case .fil: noun = plural(lang, roads, one: "bagong kalsada", many: "bagong kalsada")
        case .uk: noun = plural(lang, roads, one: "нова дорога", few: "нові дороги", many: "нових доріг")
        case .kk: noun = "жаңа жол"
        case .pt: noun = plural(lang, roads, one: "estrada nova", many: "estradas novas")
        }
        let head: String
        switch lang {
        case .ru: head = "За \(period): +\(roads) \(noun)"
        case .en: head = "In \(period): +\(roads) \(noun)"
        case .de: head = "In \(period): +\(roads) \(noun)"
        case .es: head = "En \(period): +\(roads) \(noun)"
        case .fr: head = "Sur \(period) : +\(roads) \(noun)"
        case .it: head = "In \(period): +\(roads) \(noun)"
        case .pl: head = "W okresie \(period): +\(roads) \(noun)"
        case .id: head = "Dalam \(period): +\(roads) \(noun)"
        case .tr: head = "\(period) içinde: +\(roads) \(noun)"
        case .fil: head = "Sa \(period): +\(roads) \(noun)"
        case .uk: head = "За \(period): +\(roads) \(noun)"
        case .kk: head = "\(period) ішінде: +\(roads) \(noun)"
        case .pt: head = "Em \(period): +\(roads) \(noun)"
        }
        guard let firstPlace else { return head }
        switch lang {
        case .ru: return "\(head) · первый раз в \(firstPlace)"
        case .en: return "\(head) · first time in \(firstPlace)"
        case .de: return "\(head) · zum ersten Mal in \(firstPlace)"
        case .es: return "\(head) · por primera vez en \(firstPlace)"
        case .fr: return "\(head) · pour la première fois à \(firstPlace)"
        case .it: return "\(head) · per la prima volta a \(firstPlace)"
        case .pl: return "\(head) · pierwszy raz w \(firstPlace)"
        case .id: return "\(head) · pertama kali di \(firstPlace)"
        case .tr: return "\(head) · ilk kez \(firstPlace)"
        case .fil: return "\(head) · unang beses sa \(firstPlace)"
        case .uk: return "\(head) · уперше в \(firstPlace)"
        case .kk: return "\(head) · алғаш рет \(firstPlace)"
        case .pt: return "\(head) · pela primeira vez em \(firstPlace)"
        }
    }
    /// «Всего: 14 городов · 8 регионов» — lifetime counters under the period line.
    static func statsTotalsLine(
        _ lang: LanguageManager.Language, cities: Int, regions: Int
    ) -> String {
        let c = "\(groupedNumber(cities, lang)) \(nounCities(lang, cities))"
        let r = "\(groupedNumber(regions, lang)) \(nounRegions(lang, regions))"
        let head = tr(lang, "statsTotalsHead", ru: "Всего", en: "Total")
        return "\(head): \(c) · \(r)"
    }
    static func statsHallOfFame(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsHallOfFame", ru: "ДОСКА ПОЧЕТА", en: "HALL OF FAME")
    }
    static func statsRecordLongest(_ lang: LanguageManager.Language) -> String {
        recordLongest(lang)
    }
    static func statsRecordBestDay(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsRecordBestDay", ru: "Лучший день по км", en: "Best day by km")
    }
    static func statsRecordMostPhotos(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsRecordMostPhotos", ru: "Больше всего фото", en: "Most photos")
    }
    static func statsRecordChampionRoad(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsRecordChampionRoad", ru: "Дорога-чемпион", en: "Champion road")
    }
    static func statsRecordFarthest(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsRecordFarthest", ru: "Самая дальняя точка", en: "Farthest point")
    }
    /// Hall-of-Fame values carry their unit inside the number («14 фото»,
    /// «47 раз»), so the row's right column stays a single styled string.
    /// «Фото» is indeclinable in Russian — the digit does all the work.
    static func photosCount(_ lang: LanguageManager.Language, n: Int) -> String {
        "\(n) \(nounPhotos(lang, n))"
    }
    static func timesCount(_ lang: LanguageManager.Language, n: Int) -> String {
        "\(n) \(nounTimes(lang, n))"
    }
    /// Footer plaque. `date` arrives already declined («марта 2024»).
    static func statsWithTripTrackSince(
        _ lang: LanguageManager.Language, date: String
    ) -> String {
        switch lang {
        case .ru: return "С TripTrack с \(date)"
        case .en: return "With TripTrack since \(date)"
        case .de: return "Mit TripTrack seit \(date)"
        case .es: return "Con TripTrack desde \(date)"
        case .fr: return "Avec TripTrack depuis \(date)"
        case .it: return "Con TripTrack dal \(date)"
        case .pl: return "Z TripTrack od \(date)"
        case .id: return "Bersama TripTrack sejak \(date)"
        case .tr: return "\(date) tarihinden beri TripTrack ile"
        case .fil: return "Kasama ang TripTrack mula \(date)"
        case .uk: return "З TripTrack від \(date)"
        case .kk: return "\(date) бастап TripTrack-пен бірге"
        case .pt: return "Com o TripTrack desde \(date)"
        }
    }
    /// «2 430 км воспоминаний · фото и заметки в 29 поездках» — the second
    /// clause needs the prepositional case, which no existing plural helper
    /// produces (they are all genitive).
    static func statsMemoriesLine(
        _ lang: LanguageManager.Language, km: String, trips: Int
    ) -> String {
        let head = "\(km) \(AppStrings.km(lang))"
        switch lang {
        case .ru:
            let noun = plural(lang, trips, one: "поездке", few: "поездках", many: "поездках")
            return "\(head) воспоминаний · фото и заметки в \(trips) \(noun)"
        case .en:
            return "\(head) of memories · photos and notes in \(tripsCount(lang, n: trips))"
        case .de:
            return "\(head) Erinnerungen · Fotos und Notizen in \(tripsCount(lang, n: trips))"
        case .es:
            return "\(head) de recuerdos · fotos y notas en \(tripsCount(lang, n: trips))"
        case .fr:
            return "\(head) de souvenirs · photos et notes dans \(tripsCount(lang, n: trips))"
        case .it:
            return "\(head) di ricordi · foto e note in \(tripsCount(lang, n: trips))"
        case .pl:
            return "\(head) wspomnień · zdjęcia i notatki w \(tripsCount(lang, n: trips))"
        case .id:
            return "\(head) kenangan · foto dan catatan di \(tripsCount(lang, n: trips))"
        case .tr:
            return "\(head) anı · \(tripsCount(lang, n: trips)) içinde fotoğraf ve not"
        case .fil:
            return "\(head) ng alaala · mga larawan at tala sa \(tripsCount(lang, n: trips))"
        case .uk:
            let noun = plural(lang, trips, one: "поїздці", few: "поїздках", many: "поїздках")
            return "\(head) спогадів · фото та нотатки у \(trips) \(noun)"
        case .kk:
            return "\(head) естелік · \(tripsCount(lang, n: trips)) ішінде фото мен жазба"
        case .pt:
            return "\(head) de memórias · fotos e notas em \(tripsCount(lang, n: trips))"
        }
    }

    // MARK: - Public-profile preview (0.6.0, Figma 580:438 / 1716:119)

    /// Canon's second line (580:438) — what this screen IS, said every time.
    /// The card's first line names the screen; this one names its limits, and
    /// it is true of every account, not just the ones mid-sync.
    static func previewBannerSubtitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "previewBannerSubtitle",
           ru: "Превью · подписки и реакции недоступны",
           en: "Preview · following and reactions are unavailable")
    }
    /// Names the fields the server does not have yet, so a preview that shows
    /// them is not silently claiming other people can see them.
    static func previewBannerBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "previewBannerBody",
           ru: "Юзернейм, флаг и «о себе» пока хранятся только на телефоне — другие их не увидят.",
           en: "Your handle, flag and bio live on this device only — nobody else can see them yet.")
    }
    /// Stands where the follow button would be on someone else's profile.
    static func previewThisIsYou(_ lang: LanguageManager.Language) -> String {
        tr(lang, "previewThisIsYou", ru: "Это вы", en: "This is you")
    }

    // MARK: - Lifted from views in 0.6.1
    //
    // These were inline `lang == .ru ? … : …` ternaries scattered across
    // screens — invisible to the translation tables and therefore stuck in
    // English on a German phone. Same copy, now in one place.

    static func vehicleTypeCar(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleTypeCar", ru: "Авто", en: "Car")
    }
    static func vehicleTypeMoto(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleTypeMoto", ru: "Мото", en: "Moto")
    }
    static func vehicleTypeMoped(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleTypeMoped", ru: "Мопед", en: "Moped")
    }
    static func vehicleTypeBike(_ lang: LanguageManager.Language) -> String {
        tr(lang, "vehicleTypeBike", ru: "Вело", en: "Bike")
    }
    static func contentFilterContainsInappropriateLanguage(_ lang: LanguageManager.Language) -> String {
        tr(lang, "contentFilterContainsInappropriateLanguage",
           ru: "Содержит недопустимые выражения",
           en: "Contains inappropriate language")
    }
    static func contentFilterMustContainAt(_ lang: LanguageManager.Language) -> String {
        tr(lang, "contentFilterMustContainAt",
           ru: "Должно быть хотя бы одно слово",
           en: "Must contain at least one letter")
    }
    static func contentFilterTooManyRepeated(_ lang: LanguageManager.Language) -> String {
        tr(lang, "contentFilterTooManyRepeated",
           ru: "Слишком много повторов одного символа",
           en: "Too many repeated characters")
    }
    static func contentFilterTooManySymbols(_ lang: LanguageManager.Language) -> String {
        tr(lang, "contentFilterTooManySymbols",
           ru: "Слишком много знаков подряд",
           en: "Too many symbols in a row")
    }
    static func contentFilterMixingLatinAnd(_ lang: LanguageManager.Language) -> String {
        tr(lang, "contentFilterMixingLatinAnd",
           ru: "Латиница и кириллица в одном слове недопустимы",
           en: "Mixing Latin and Cyrillic in one word isn't allowed")
    }
    static func relativeTripDateJustNow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "relativeTripDateJustNow", ru: "только что", en: "just now")
    }
    static func feedViewModelThisMonth(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedViewModelThisMonth", ru: "Этот месяц", en: "This month")
    }
    static func feedViewModelLastMonth(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedViewModelLastMonth", ru: "Прошлый месяц", en: "Last month")
    }
    static func badgeDetailHiddenAchievement(_ lang: LanguageManager.Language) -> String {
        tr(lang, "badgeDetailHiddenAchievement", ru: "Скрытое достижение", en: "Hidden achievement")
    }
    static func badgeDetailLocked(_ lang: LanguageManager.Language) -> String {
        tr(lang, "badgeDetailLocked", ru: "Не получено", en: "Locked")
    }
    static func fullscreenMapClearPlayback(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fullscreenMapClearPlayback", ru: "Убрать воспроизведение", en: "Clear playback")
    }
    static func fullscreenMapZoomIn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fullscreenMapZoomIn", ru: "Приблизить", en: "Zoom in")
    }
    static func fullscreenMapZoomOut(_ lang: LanguageManager.Language) -> String {
        tr(lang, "fullscreenMapZoomOut", ru: "Отдалить", en: "Zoom out")
    }
    static func feedLoadingFeed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedLoadingFeed", ru: "Загружаем ленту…", en: "Loading feed…")
    }
    static func feedServerUnreachable(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedServerUnreachable", ru: "Нет связи с сервером", en: "Server unreachable")
    }
    static func feedSyncIncomplete(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedSyncIncomplete", ru: "Не всё синхронизировано", en: "Sync incomplete")
    }
    static func feedTryADifferent(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedTryADifferent",
           ru: "Попробуйте сменить сеть или подождите — мы повторим автоматически.",
           en: "Try a different network or wait — we'll retry automatically.")
    }
    static func feedAFewItems(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedAFewItems",
           ru: "Несколько операций не загрузились на сервер. Мы повторим автоматически — также можно нажать «Повторить» в настройках синхронизации.",
           en: "A few items didn't upload. We'll retry automatically — or tap Retry in sync settings.")
    }
    static func feedOfflineTripsAre(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedOfflineTripsAre",
           ru: "Нет сети · поездки сохраняются локально",
           en: "Offline · trips are saved on your phone")
    }
    static func feedCouldnTLoad(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedCouldnTLoad", ru: "Не удалось загрузить ленту", en: "Couldn't load feed")
    }
    static func feedCheckYourInternet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedCheckYourInternet",
           ru: "Проверьте подключение к интернету и попробуйте ещё раз.",
           en: "Check your internet connection and try again.")
    }
    static func feedPublishOneOf(_ lang: LanguageManager.Language) -> String {
        tr(lang, "feedPublishOneOf",
           ru: "Опубликовать свою поездку",
           en: "Publish one of your trips")
    }
    static func socialFeedNoReactionsYet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "socialFeedNoReactionsYet", ru: "Пока нет реакций", en: "No reactions yet")
    }
    static func socialFeedReact(_ lang: LanguageManager.Language) -> String {
        tr(lang, "socialFeedReact", ru: "Реакция", en: "React")
    }
    static func myMapAvg(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myMapAvg", ru: "ср.", en: "avg")
    }
    static func myMapMax(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myMapMax", ru: "макс.", en: "max")
    }
    static func notificationPreferencesWhenSomeoneReacts(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesWhenSomeoneReacts",
           ru: "Когда кто-то отреагирует на Вашу публичную поездку",
           en: "When someone reacts to your public trip")
    }
    static func notificationPreferencesWhenSomeoneFollows(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesWhenSomeoneFollows",
           ru: "Когда кто-то подписывается на Ваш профиль",
           en: "When someone follows your profile")
    }
    static func notificationPreferencesComments(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesComments", ru: "Комментарии", en: "Comments")
    }
    static func notificationPreferencesWhenSomeoneComments(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesWhenSomeoneComments",
           ru: "Когда кто-то комментирует Вашу публичную поездку",
           en: "When someone comments on your public trip")
    }
    static func notificationPreferencesWeeklyRecap(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesWeeklyRecap", ru: "Итоги недели", en: "Weekly recap")
    }
    static func notificationPreferencesEveryMondayHow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesEveryMondayHow",
           ru: "Каждый понедельник — сколько Вы проехали за прошлую неделю",
           en: "Every Monday — how much you drove last week")
    }
    static func notificationPreferencesWhatToNotify(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesWhatToNotify",
           ru: "Что Вас уведомлять",
           en: "What to notify you about")
    }
    static func notificationPreferencesPickWhatYou(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesPickWhatYou",
           ru: "Здесь вы выбираете, о чём приходит уведомление — и в push'ах, и в ленте уведомлений внутри приложения. Системные настройки iOS остаются под Вашим контролем отдельно.",
           en: "Pick what you want to hear about — both in push notifications and in the in-app inbox. System-level iOS notification settings remain separate.")
    }
    static func notificationPreferencesNotificationsYouTurn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationPreferencesNotificationsYouTurn",
           ru: "Уведомления, которые Вы выключите, не будут приходить ни на телефон, ни в приложение. Включить обратно можно в любой момент.",
           en: "Notifications you turn off won't reach your phone OR the in-app inbox. You can turn them back on any time.")
    }
    static func notificationsInboxFollowing(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationsInboxFollowing", ru: "Подписан", en: "Following")
    }
    static func notificationsInboxSomeone(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationsInboxSomeone", ru: "Кто-то", en: "Someone")
    }
    static func notificationsInboxNothingYet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationsInboxNothingYet", ru: "Здесь пока пусто", en: "Nothing yet")
    }
    static func notificationsInboxWhenSomeoneReacts(_ lang: LanguageManager.Language) -> String {
        tr(lang, "notificationsInboxWhenSomeoneReacts",
           ru: "Когда кто-то отреагирует на Вашу поездку или подпишется — увидите здесь.",
           en: "When someone reacts to your trip or follows you, it'll show up here.")
    }
    static func nameEditorEGAlex(_ lang: LanguageManager.Language) -> String {
        tr(lang, "nameEditorEGAlex", ru: "Например, Иван", en: "e.g., Alex")
    }
    static func profileYourTripsWill(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileYourTripsWill",
           ru: "Здесь появятся ваши поездки",
           en: "Your trips will show up here")
    }
    static func profileRecordingStartsBy(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileRecordingStartsBy",
           ru: "Запись начнётся автоматически, когда вы поедете. Аккаунт не нужен.",
           en: "Recording starts by itself once you drive. No account needed.")
    }
    static func profileRecordYourFirst(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileRecordYourFirst",
           ru: "Запишите первую поездку",
           en: "Record your first trip")
    }
    static func profileYourKilometersStreaks(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileYourKilometersStreaks",
           ru: "Здесь будут Ваши километры, серии и бейджи.",
           en: "Your kilometers, streaks and badges will appear here.")
    }
    static func statsYear(_ lang: LanguageManager.Language) -> String {
        tr(lang, "statsYear", ru: "году", en: "year")
    }
    static func syncStatusMarkerOff(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusMarkerOff", ru: "Выкл.", en: "Off")
    }
    static func syncStatusMarkerSynced(_ lang: LanguageManager.Language) -> String {
        tr(lang, "syncStatusMarkerSynced", ru: "Готово", en: "Synced")
    }
    static func roadCollectionRoads(_ lang: LanguageManager.Language) -> String {
        tr(lang, "roadCollectionRoads", ru: "дорог", en: "roads")
    }
    static func roadCollectionMastered(_ lang: LanguageManager.Language) -> String {
        tr(lang, "roadCollectionMastered", ru: "освоено", en: "mastered")
    }
    static func roadCollectionRecordATrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "roadCollectionRecordATrip",
           ru: "Запишите поездку, чтобы открыть дорогу",
           en: "Record a trip to discover a road")
    }
    static func roadCollectionRoadCollection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "roadCollectionRoadCollection", ru: "Коллекция дорог", en: "Road Collection")
    }
    static func blockedListYouHavenT(_ lang: LanguageManager.Language) -> String {
        tr(lang, "blockedListYouHavenT",
           ru: "Вы никого не блокировали",
           en: "You haven't blocked anyone")
    }
    static func blockedListUser(_ lang: LanguageManager.Language) -> String {
        tr(lang, "blockedListUser", ru: "Пользователь", en: "User")
    }
    static func discoverSearchByName(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discoverSearchByName", ru: "Поиск по имени", en: "Search by name")
    }
    static func discoverNoSuggestionsYet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discoverNoSuggestionsYet",
           ru: "Пока некого рекомендовать",
           en: "No suggestions yet")
    }
    static func discoverWhenNewDrivers(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discoverWhenNewDrivers",
           ru: "Когда в приложении появятся новые водители — увидите их здесь.",
           en: "When new drivers join, they'll show up here.")
    }
    static func discoverResults(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discoverResults", ru: "Результаты", en: "Results")
    }
    static func discoverNoUsersFound(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discoverNoUsersFound", ru: "Никого не нашли", en: "No users found")
    }
    static func discoverTryADifferent(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discoverTryADifferent",
           ru: "Попробуйте другое имя или проверьте раскладку.",
           en: "Try a different name or check your spelling.")
    }
    static func discoverFollow(_ lang: LanguageManager.Language) -> String {
        tr(lang, "discoverFollow", ru: "Подписаться", en: "Follow")
    }
    static func followListFollowers(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followListFollowers", ru: "Подписчики", en: "Followers")
    }
    static func followListNoFollowersYet(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followListNoFollowersYet", ru: "Пока никто не подписался", en: "No followers yet")
    }
    static func followListNotFollowingAnyone(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followListNotFollowingAnyone",
           ru: "Пока ни на кого не подписаны",
           en: "Not following anyone yet")
    }
    static func followListCouldnTLoad(_ lang: LanguageManager.Language) -> String {
        tr(lang, "followListCouldnTLoad",
           ru: "Не удалось загрузить список",
           en: "Couldn't load list")
    }
    static func publicProfileDriver(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publicProfileDriver", ru: "Водитель", en: "Driver")
    }
    static func publicProfileHiddenRoadsThis(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publicProfileHiddenRoadsThis",
           ru: "Тайные дороги — водитель оставил поездки приватными",
           en: "Hidden roads — this driver keeps their trips private")
    }
    static func publicProfileNoPublicTrips(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publicProfileNoPublicTrips",
           ru: "Пока нет публичных поездок",
           en: "No public trips yet")
    }
    static func publicProfileCouldnTLoad(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publicProfileCouldnTLoad",
           ru: "Не удалось загрузить профиль",
           en: "Couldn't load profile")
    }
    static func reactionsListCouldnTLoad(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reactionsListCouldnTLoad", ru: "Не удалось загрузить", en: "Couldn't load")
    }
    static func reactionsListCheckYourConnection(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reactionsListCheckYourConnection",
           ru: "Проверьте соединение и потяните вниз, чтобы обновить.",
           en: "Check your connection and pull to refresh.")
    }
    static func reactionsListBeTheFirst(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reactionsListBeTheFirst",
           ru: "Будьте первым — реакции появятся здесь.",
           en: "Be the first — reactions show up here.")
    }
    static func reportWeReviewReports(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportWeReviewReports",
           ru: "Мы рассматриваем жалобы на недопустимый контент в течение 24 часов и можем удалить контент или заблокировать пользователя-нарушителя.",
           en: "We review reports of objectionable content within 24 hours and may remove content or suspend offending accounts.")
    }
    static func reportAdditionalDetailsOptional(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportAdditionalDetailsOptional",
           ru: "Комментарий (необязательно)",
           en: "Additional details (optional)")
    }
    static func reportSubmit(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportSubmit", ru: "Отправить", en: "Submit")
    }
    static func reportReportSent(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReportSent", ru: "Жалоба отправлена", en: "Report sent")
    }
    static func reportThankYouWe(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportThankYouWe",
           ru: "Спасибо. Мы рассмотрим её в ближайшие 24 часа.",
           en: "Thank you. We'll review it within 24 hours.")
    }
    static func sharePosterPoster(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sharePosterPoster", ru: "Постер", en: "Poster")
    }
    static func sharePosterStory(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sharePosterStory", ru: "Сторис 9:16", en: "Story 9:16")
    }
    static func sharePosterStickerPng(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sharePosterStickerPng", ru: "Стикер PNG", en: "Sticker PNG")
    }
    static func sharePosterPhoto(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sharePosterPhoto", ru: "Фото-фон", en: "Photo")
    }
    static func sharePosterMinimal(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sharePosterMinimal", ru: "Минимал", en: "Minimal")
    }
    static func sharedTripLinkCopied(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sharedTripLinkCopied", ru: "Скопировано", en: "Copied")
    }
    static func sharedTripLinkCopy(_ lang: LanguageManager.Language) -> String {
        tr(lang, "sharedTripLinkCopy", ru: "Скопировать", en: "Copy")
    }
    static func storyShareSaved(_ lang: LanguageManager.Language) -> String {
        tr(lang, "storyShareSaved", ru: "Сохранено", en: "Saved")
    }
    static func suggestedUsersCarouselSuggested(_ lang: LanguageManager.Language) -> String {
        tr(lang, "suggestedUsersCarouselSuggested", ru: "Рекомендуем подписаться", en: "Suggested")
    }
    static func tripDetailMakeTripPrivate(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripDetailMakeTripPrivate",
           ru: "Сделать поездку приватной?",
           en: "Make trip private?")
    }
    static func tripDetailThisTripWill(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripDetailThisTripWill",
           ru: "Поездка пропадёт из общей ленты и из профилей других пользователей. Её увидите только Вы.\n\nРеакции и комментарии не сохранятся, если Вы потом снова сделаете её публичной.",
           en: "This trip will disappear from the social feed and from other users' profiles. Only you will see it.\n\nReactions and comments won't be preserved if you make it public again later.")
    }
    static func tripDetailMyTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripDetailMyTrip", ru: "Моя поездка", en: "My trip")
    }
    static func tripDetailYourFirstPublic(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripDetailYourFirstPublic",
           ru: "Первая публичная поездка! Поездки с фото получают больше реакций",
           en: "Your first public trip! Trips with photos get more reactions")
    }
    static func unitGallonsShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unitGallonsShort", ru: "гал", en: "gal")
    }
    static func unitLitresShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unitLitresShort", ru: "л", en: "L")
    }
    static func unitMilesShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "unitMilesShort", ru: "миль", en: "mi")
    }
    static func tripEditAPublicTrip(_ lang: LanguageManager.Language) -> String {
        tr(lang, "tripEditAPublicTrip",
           ru: "Публичную поездку видят другие пользователи в общей ленте. Вернуть её в приватные можно в любой момент.",
           en: "A public trip is visible to other people in the shared feed. You can make it private again at any time.")
    }

    /// «сек» / «sec» — the tail of a sub-minute duration.
    static func secondsUnitShort(_ lang: LanguageManager.Language) -> String {
        tr(lang, "secondsUnitShort", ru: "сек", en: "sec")
    }

    /// The narrow-column duration glues the unit to the number («1ч 19м»), so
    /// it needs shorter units than `hoursUnitShort` — see `SocialFeedTrip`.
    static func hoursUnitCompact(_ lang: LanguageManager.Language) -> String {
        tr(lang, "hoursUnitCompact", ru: "ч", en: "h")
    }
    static func minutesUnitCompact(_ lang: LanguageManager.Language) -> String {
        tr(lang, "minutesUnitCompact", ru: "м", en: "m")
    }

    static func contentFilterTooLong(_ lang: LanguageManager.Language, max: Int) -> String {
        switch lang {
        case .ru: return "Слишком длинный текст (максимум \(max))"
        case .en: return "Too long (max \(max) characters)"
        case .de: return "Zu lang (höchstens \(max) Zeichen)"
        case .es: return "Demasiado largo (máximo \(max) caracteres)"
        case .fr: return "Trop long (\(max) caractères maximum)"
        case .it: return "Troppo lungo (massimo \(max) caratteri)"
        case .pl: return "Za długi tekst (maksymalnie \(max) znaków)"
        case .id: return "Terlalu panjang (maksimal \(max) karakter)"
        case .tr: return "Çok uzun (en fazla \(max) karakter)"
        case .fil: return "Masyadong mahaba (hanggang \(max) na karakter)"
        case .uk: return "Занадто довгий текст (максимум \(max))"
        case .kk: return "Мәтін тым ұзын (ең көбі \(max) таңба)"
        case .pt: return "Muito longo (máximo de \(max) caracteres)"
        }
    }

    static func relTimeMinutesAgo(_ lang: LanguageManager.Language, _ n: Int) -> String {
        let mins = "\(n) \(minutesUnitShort(lang))"
        switch lang {
        case .ru: return "\(mins) назад"
        case .en: return "\(mins) ago"
        case .de: return "vor \(mins)"
        case .es: return "hace \(mins)"
        case .fr: return "il y a \(mins)"
        case .it: return "\(mins) fa"
        case .pl: return "\(mins) temu"
        case .id: return "\(mins) lalu"
        case .tr: return "\(mins) önce"
        case .fil: return "\(mins) ang nakalipas"
        case .uk: return "\(mins) тому"
        case .kk: return "\(mins) бұрын"
        case .pt: return "há \(mins)"
        }
    }

    static func relTimeTodayAt(_ lang: LanguageManager.Language, _ time: String) -> String {
        switch lang {
        case .ru: return "Сегодня в \(time)"
        case .en: return "Today at \(time)"
        case .de: return "Heute um \(time)"
        case .es: return "Hoy a las \(time)"
        case .fr: return "Aujourd'hui à \(time)"
        case .it: return "Oggi alle \(time)"
        case .pl: return "Dzisiaj o \(time)"
        case .id: return "Hari ini pukul \(time)"
        case .tr: return "Bugün \(time)"
        case .fil: return "Ngayon nang \(time)"
        case .uk: return "Сьогодні о \(time)"
        case .kk: return "Бүгін \(time)"
        case .pt: return "Hoje às \(time)"
        }
    }

    static func relTimeYesterdayAt(_ lang: LanguageManager.Language, _ time: String) -> String {
        switch lang {
        case .ru: return "Вчера в \(time)"
        case .en: return "Yesterday at \(time)"
        case .de: return "Gestern um \(time)"
        case .es: return "Ayer a las \(time)"
        case .fr: return "Hier à \(time)"
        case .it: return "Ieri alle \(time)"
        case .pl: return "Wczoraj o \(time)"
        case .id: return "Kemarin pukul \(time)"
        case .tr: return "Dün \(time)"
        case .fil: return "Kahapon nang \(time)"
        case .uk: return "Учора о \(time)"
        case .kk: return "Кеше \(time)"
        case .pt: return "Ontem às \(time)"
        }
    }

    /// «· всего 42» — the tail that tells a visitor the public number is not
    /// the driver's whole history.
    static func publicProfileTripsTotal(_ lang: LanguageManager.Language, total: Int) -> String {
        switch lang {
        case .ru: return "всего \(total)"
        case .en: return "\(total) total"
        case .de: return "\(total) insgesamt"
        case .es: return "\(total) en total"
        case .fr: return "\(total) au total"
        case .it: return "\(total) in totale"
        case .pl: return "łącznie \(total)"
        case .id: return "\(total) total"
        case .tr: return "toplam \(total)"
        case .fil: return "\(total) sa kabuuan"
        case .uk: return "усього \(total)"
        case .kk: return "барлығы \(total)"
        case .pt: return "\(total) no total"
        }
    }

    // The eight reasons a report can carry. Apple checks that a UGC app offers
    // a way to flag content, and a reviewer on a German phone has to be able
    // to read the list.
    static func reportReasonSpam(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonSpam", ru: "Спам / реклама", en: "Spam or advertising")
    }
    static func reportReasonHarassment(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonHarassment",
           ru: "Домогательства / травля", en: "Harassment or bullying")
    }
    static func reportReasonHate(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonHate", ru: "Разжигание ненависти", en: "Hate speech")
    }
    static func reportReasonNudity(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonNudity",
           ru: "Обнажённость / сексуальный контент", en: "Nudity or sexual content")
    }
    static func reportReasonViolence(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonViolence", ru: "Насилие или угрозы", en: "Violence or threats")
    }
    static func reportReasonIllegal(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonIllegal", ru: "Незаконные действия", en: "Illegal activity")
    }
    static func reportReasonImpersonation(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonImpersonation",
           ru: "Выдаёт себя за другое лицо", en: "Impersonation")
    }
    static func reportReasonOther(_ lang: LanguageManager.Language) -> String {
        tr(lang, "reportReasonOther", ru: "Другое", en: "Something else")
    }

    static func publishConfirmBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishConfirmBody",
           ru: "Поездка появится в общей ленте — её увидят другие пользователи. Вы всегда сможете вернуть её в приватные.",
           en: "The trip will appear in the public feed — other users will see it. You can switch it back to private anytime.")
    }
    /// Appended when cloud sync is off, so «publish» does not read as «upload
    /// my whole diary».
    static func publishConfirmCloudOff(_ lang: LanguageManager.Language) -> String {
        tr(lang, "publishConfirmCloudOff",
           ru: "Облачная синхронизация выключена — на сервер уйдёт только эта поездка, остальные останутся локально.",
           en: "Cloud sync is off — only this trip will be sent to our server, every other trip stays on your device.")
    }

    /// «2 дня назад» / "2 days ago" — the feed's own relative date, which is
    /// why it is not `relTimeDays` (that one is the bare «2 д» chip).
    static func relTimeDaysAgo(_ lang: LanguageManager.Language, _ n: Int) -> String {
        let days = "\(n) \(nounDays(lang, n))"
        switch lang {
        case .ru: return "\(days) назад"
        case .en: return "\(days) ago"
        case .de: return "vor \(days)"
        case .es: return "hace \(days)"
        case .fr: return "il y a \(days)"
        case .it: return "\(days) fa"
        case .pl: return "\(days) temu"
        case .id: return "\(days) lalu"
        case .tr: return "\(days) önce"
        case .fil: return "\(days) ang nakalipas"
        case .uk: return "\(days) тому"
        case .kk: return "\(days) бұрын"
        case .pt: return "há \(days)"
        }
    }

    /// VoiceOver labels for the replay camera button — the glyph alone does not
    /// say which of the two states tapping it produces.
    static func replayShowWholeRoute(_ lang: LanguageManager.Language) -> String {
        tr(lang, "replayShowWholeRoute",
           ru: "Показать весь маршрут", en: "Show whole route")
    }
    static func replayFollowTheCar(_ lang: LanguageManager.Language) -> String {
        tr(lang, "replayFollowTheCar", ru: "Следовать за машиной", en: "Follow the car")
    }

    /// What an unnamed car is called — used by the one-time migration off the
    /// old «Телега» default.
    static func defaultVehicleName(_ lang: LanguageManager.Language) -> String {
        tr(lang, "defaultVehicleName", ru: "Ваша машина", en: "Your car")
    }

    /// The three lines every club page promises — they belong to the FEATURE,
    /// not to one community, which is why they live here and not in the catalog.
    static func clubPerkFeed(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubPerkFeed",
           ru: "Общая лента поездок клуба", en: "A shared feed of the club's drives")
    }
    static func clubPerkLeaderboard(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubPerkLeaderboard",
           ru: "Рейтинг и достижения участников", en: "Member leaderboard and achievements")
    }
    static func clubPerkMeetups(_ lang: LanguageManager.Language) -> String {
        tr(lang, "clubPerkMeetups",
           ru: "Совместные встречи и покатушки", en: "Meetups and group drives")
    }

    /// Shown under the public-profile switch when `/auth/me` never answered:
    /// the row stays, disabled, and says why instead of vanishing.
    static func privacyProfileUnavailable(_ lang: LanguageManager.Language) -> String {
        tr(lang, "privacyProfileUnavailable",
           ru: "Не удалось спросить сервер — переключатель недоступен. Проверьте связь и откройте экран заново.",
           en: "Couldn't reach the server — the switch is unavailable. Check your connection and reopen this screen.")
    }
    // MARK: - Store recovery (0.6.1)

    /// «Не смогли открыть твои данные» — the CoreData store failed to load.
    /// Deliberately not «повреждены»: the likeliest cause is transient (the
    /// device has not been unlocked since boot, so the encrypted store is not
    /// readable yet), and the old code's guess that any failure meant
    /// corruption is exactly what destroyed a real user's library.
    static func storeRecoveryTitle(_ lang: LanguageManager.Language) -> String {
        tr(lang, "storeRecoveryTitle",
           ru: "Не смогли открыть твои данные",
           en: "We couldn't open your data")
    }

    static func storeRecoveryBody(_ lang: LanguageManager.Language) -> String {
        tr(lang, "storeRecoveryBody",
           ru: "Поездки на месте — приложение просто не смогло до них добраться. Чаще всего это временно: попробуй ещё раз.",
           en: "Your trips are still there — the app just couldn't reach them. This is usually temporary: try again.")
    }

    /// The sentence that makes the destructive button honest. It is true only
    /// because `PersistenceController.setAsideStoreAndStartFresh` moves the
    /// journal WITH the database — do not soften it if that ever changes.
    static func storeRecoveryFileKept(_ lang: LanguageManager.Language) -> String {
        tr(lang, "storeRecoveryFileKept",
           ru: "Старый файл с данными останется на телефоне — мы его не удаляем.",
           en: "The old data file stays on your phone — we don't delete it.")
    }

    static func storeRecoveryRetry(_ lang: LanguageManager.Language) -> String {
        tr(lang, "storeRecoveryRetry",
           ru: "Попробовать снова", en: "Try again")
    }

    static func storeRecoveryStartFresh(_ lang: LanguageManager.Language) -> String {
        tr(lang, "storeRecoveryStartFresh",
           ru: "Продолжить без старых данных",
           en: "Continue without the old data")
    }

    /// NOT «поездки вернутся из облака»: `cloudSyncEnabled` defaults to false
    /// (privacy opt-in) and `runFullSync` returns before `runPull` when it is
    /// off, so for the default population nothing would come back, ever. The
    /// conditional is the honest form.
    static func storeRecoveryStartFreshConfirm(_ lang: LanguageManager.Language) -> String {
        tr(lang, "storeRecoveryStartFreshConfirm",
           ru: "Приложение откроется пустым. Старый файл останется на телефоне — напиши нам, поможем достать. Если Облачная синхронизация была включена, поездки подтянутся с сервера.",
           en: "The app will start empty. The old file stays on your phone — write to us and we'll help recover it. If Cloud Sync was on, your trips will come back from the server.")
    }
}
