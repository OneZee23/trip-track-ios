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
        lang == .ru ? "Регионы" : "Regions"
    }
    static func profile(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Профиль" : "Profile"
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
        lang == .ru ? "Сдвиньте для старта" : "Slide to start"
    }
    static func readyToRide(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Готов к поездке" : "Ready to ride"
    }
    static func kmh(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "км/ч" : "km/h"
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
    static func onboardingWelcome(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Добро пожаловать в TripTrack" : "Welcome to TripTrack"
    }
    static func onboardingWelcomeSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Дневник ваших дорог — маршруты, статистика, расход топлива и гараж" : "Your road diary — routes, stats, fuel costs, and your garage"
    }
    static func onboardingRecord(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Записывайте поездки" : "Record your trips"
    }
    static func onboardingRecordSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Нажмите кнопку — маршрут, скорость и расход запишутся автоматически. Управляйте машинами в гараже" : "Tap the button — route, speed, and fuel cost are recorded. Manage your cars in the garage"
    }
    static func onboardingFeed(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Ваша лента поездок" : "Your trip feed"
    }
    static func onboardingFeedSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Все маршруты в одном месте" : "All your routes in one place"
    }
    static func onboardingLocation(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Разрешите геолокацию" : "Allow location access"
    }
    static func onboardingLocationSub(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Для записи маршрутов нужен доступ к геолокации" : "Location access is needed to record your routes"
    }
    static func onboardingGo(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Поехали!" : "Let's go!"
    }
    static func onboardingAutoRecord(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Автоматическая запись" : "Automatic recording"
    }
    static func onboardingAutoRecordSub(_ lang: LanguageManager.Language) -> String {
        if lang == .ru {
            return "TripTrack сам определит, что вы за рулём, и начнёт запись. Для этого нужен фоновый доступ к геолокации и датчику движения. Батарея почти не расходуется."
        }
        return "TripTrack detects when you're driving and starts recording automatically. This requires background location and motion sensor access. Minimal battery impact."
    }
    static func onboardingAutoRecordEnable(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Включить" : "Enable"
    }
    static func onboardingAutoRecordSkip(_ lang: LanguageManager.Language) -> String {
        lang == .ru ? "Настрою позже" : "Set up later"
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
        lang == .ru ? "Убедись, что ты в машине и магнитола включена" : "Make sure you're in the car with the stereo on"
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
        lang == .ru ? "Похоже, ты в машине" : "Looks like you're in the car"
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
    static func notifTripStopBody(_ lang: LanguageManager.Language, minutes: Int) -> String {
        if lang == .ru {
            return "Bluetooth отключился. Автозавершение через \(minutes) мин"
        }
        return "Bluetooth disconnected. Auto-stop in \(minutes) min"
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

}
