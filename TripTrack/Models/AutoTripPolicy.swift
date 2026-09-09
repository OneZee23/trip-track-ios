import Foundation

/// Single source of truth for every threshold the auto-trip / recording
/// subsystem uses. Anything timing-, distance-, or speed-related that's
/// not exposed in user settings should live here so we can tune in one
/// place instead of grepping for `5 * 60` across seven files.
enum AutoTripPolicy {

    // MARK: - Что делать, когда магнитола отключилась

    /// Решение об отключении Bluetooth, вынесенное из `AutoTripService`.
    ///
    /// Вынесено не для красоты. Правило «поставленную на паузу поездку не
    /// завершает никто» записано в этом коде прямым текстом и соблюдалось в
    /// двух дверях из четырёх: путь по бездействию и восстановление стоячей
    /// поездки паузу проверяли, а отключение магнитолы — нет. В сентябре 2026
    /// это дважды за одну поездку разорвало человеку маршрут: он глушил мотор
    /// у магазина, магнитола отваливалась, и через три минуты запись
    /// закрывалась — при том что пауза была нажата вручную.
    ///
    /// Чистая функция затем, чтобы правило можно было проверить тестом, а не
    /// поездкой в Джанхот.
    enum BluetoothDisconnectDecision: Equatable {
        /// Не трогаем запись вовсе.
        case ignore
        /// Завершить сразу — только полная автоматика и только при двойном
        /// подтверждении, что человек приехал.
        case stopNow
        /// Спросить и НЕ действовать самим.
        case promptOnly
        /// Спросить и завершить, если не ответят.
        case promptThenStop(afterMinutes: Int)
    }

    static func onBluetoothDisconnect(
        mode: AutoRecordMode,
        isRecording: Bool,
        isPaused: Bool,
        isIdleBeyondFastStop: Bool,
        tripDistance: Double,
        tripDuration: TimeInterval,
        autoStopTimeout: Int
    ) -> BluetoothDisconnectDecision {
        guard isRecording else { return .ignore }

        // Пауза — самое сильное «я остановился нарочно», какое человек может
        // дать приложению. Сильнее любого датчика: магнитола знает только про
        // зажигание, а пауза — про намерение.
        guard !isPaused else { return .ignore }

        switch mode {
        case .off:
            return .ignore

        case .remind:
            // Режим называется «напоминания». Раньше он спрашивал и всё равно
            // завершал через три минуты — то есть был автоматикой с отсрочкой,
            // а человек выбирал не её.
            return .promptOnly

        case .auto:
            // Магнитола выключена И поездка уже стояла — двойное подтверждение,
            // что приехали. Трёхминутная отсрочка нужна против дребезга
            // Bluetooth, а не против очевидно законченной поездки.
            if isIdleBeyondFastStop { return .stopNow }

            // Магнитола выключена после НАСТОЯЩЕЙ поездки — человек вышел и
            // пошёл пешком. Ждать отсрочку значит дописать в поездку двести
            // метров ходьбы.
            if tripDistance >= immediateEndOnBtDisconnectMinDistance,
               tripDuration >= immediateEndOnBtDisconnectMinDuration {
                return .stopNow
            }

            return .promptThenStop(afterMinutes: autoStopTimeout)
        }
    }

    // MARK: - Trigger debounce

    /// Window in which a duplicate BT/audio event with the same `(type, name)`
    /// is dropped. Prevents two simultaneous `.connected` events (BT scan +
    /// audio route notification firing on the same wake) from doubling up.
    static let eventDeduplicationWindow: TimeInterval = 5

    /// Minimum gap between two `triggerTripStart` calls. BT and motion can
    /// detect the same drive within milliseconds; without this the second
    /// detector double-starts.
    static let triggerDeduplicationWindow: TimeInterval = 30

    /// `automotive ended` → `automotive` again within this window is treated
    /// as the *same* driving session (so the remind-once flag stays set).
    /// Beyond this gap, the next automotive event is a fresh session.
    static let newDrivingSessionGap: TimeInterval = 10 * 60

    // MARK: - Inactivity / staleness

    /// How long the trip can sit without meaningful distance gain before the
    /// auto-stop prompt fires (`.auto` mode only).
    static let inactivityTimeout: TimeInterval = 10 * 60

    /// On foreground entry, trips this idle are ended now. Background
    /// `Timer.scheduledTimer` doesn't fire while the app is suspended, so
    /// otherwise a 30-min-old idle trip would still be "recording" at wake.
    static let staleTripTimeout: TimeInterval = 15 * 60

    /// BT-disconnect happens, but `lastDistanceChangeTime` is already older
    /// than this — don't bother with the 3-min grace, end now (the grace
    /// is for BT flap, not for already-parked trips).
    static let bluetoothDisconnectFastStopIdleThreshold: TimeInterval = 5 * 60

    /// Distance gain (m) that resets the inactivity clock. Anything smaller
    /// is treated as drift / parking-lot crawl. `TripManager.handleNewLocation`
    /// already filters drift and sub-5m points, so any actual `entity.distance`
    /// growth reflects real movement; the 100m gate just absorbs slow-roll
    /// at a stop light without restarting the window.
    static let meaningfulMovementDistance: Double = 100

    // MARK: - BT-disconnect immediate-end gates

    /// On BT off, end immediately if the trip is at least this long
    /// (distance, m). The 3-min grace is reserved for trips so short they
    /// could only be a glitch.
    static let immediateEndOnBtDisconnectMinDistance: Double = 500

    /// On BT off, end immediately if the trip is at least this long (s).
    static let immediateEndOnBtDisconnectMinDuration: TimeInterval = 180

    // MARK: - Junk-trip classification

    /// Trips below `(minDistance AND minDuration)` are treated as parking-
    /// lot manoeuvres and silently discarded.
    static let junkTripMinDistance: Double = 500
    static let junkTripMinDuration: TimeInterval = 120

    /// Trips below this max speed (km/h) for longer than `walkingMinDuration`
    /// are CMMotion misfires (recorded the user walking, not driving).
    static let junkTripWalkingSpeedKmh: Double = 15
    static let junkTripWalkingMinDuration: TimeInterval = 180

    // MARK: - Background launch

    /// Background task lifetime after an auto-start while the app is
    /// suspended — long enough for GPS to warm up and the trip to anchor
    /// before iOS reclaims us.
    static let backgroundLaunchTaskTimeout: TimeInterval = 25

    // MARK: - Audio route stabilization

    /// Wait this long after `didBecomeActive` before re-checking the audio
    /// route. At unlock, iOS can briefly show a non-BT output for one tick
    /// before the route settles back; without this delay we'd interpret
    /// the transient state as a disconnect and fire a stop prompt.
    static let audioRouteSettleDelay: TimeInterval = 1.0
}
