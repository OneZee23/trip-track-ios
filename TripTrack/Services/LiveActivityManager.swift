import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<TripActivityAttributes>?
    private var lastUpdateDate: Date?
    private let throttleInterval: TimeInterval = 2.0
    /// staleDate horizon: if no update lands within this, iOS renders the card as
    /// "stale" (dimmed, last value) instead of a misleadingly-live frozen 0.0.
    /// Generous for sparse-GPS stretches (taiga); GPS updates refresh it far sooner.
    /// NOTE: iOS ends a Live Activity at its ~8h presentation cap. We deliberately
    /// do NOT try to recreate it past that — the recreate/resume path was racy and
    /// showed wrong elapsed time. The in-app recording, Pause and Stop are fully
    /// independent of the Live Activity and always work.
    private static let staleAfter: TimeInterval = 8 * 60

    private init() {
        // Смена единицы — то, чего активность сама не заметит.
        //
        // Язык и тема доезжают до карточки следующим апдейтом, и этого хватает:
        // их меняют, глядя в приложение, где следующая точка GPS придёт через
        // секунду. Единицу меняют там же, но смотрят потом на ЛОКСКРИН — и
        // между «переключил» и «увидел» стоит тротлинг в две секунды и пауза,
        // на которой апдейтов нет вовсе. Поэтому здесь принудительный кадр,
        // мимо ограничителя частоты, — ровно как у отметки на маршруте.
        unitObserver = NotificationCenter.default.addObserver(
            forName: .distanceUnitChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyUnitChange() }
        }
    }

    /// Отписка — формальность (синглтон живёт всё время работы приложения), но
    /// без неё наблюдатель пережил бы владельца, если синглтон однажды
    /// перестанет быть синглтоном.
    private var unitObserver: NSObjectProtocol?

    /// Current language & dark mode — read fresh on every update
    private var currentLanguage: String {
        UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    }

    private var currentIsDarkMode: Bool {
        UserDefaults.standard.bool(forKey: "liveActivityDarkMode")
    }

    /// В чём показывать — читается СВЕЖО, как язык, и по той же причине:
    /// активность живёт часами, а выбор могли поменять посреди поездки или
    /// привезти пулом со второго телефона. Поле в классе запомнило бы то, что
    /// стояло на старте записи.
    private var currentDistanceUnit: String {
        DistanceUnit.current.rawValue
    }

    /// Человек сменил единицу — перерисовать карточку немедленно.
    private func applyUnitChange() {
        guard let activity = currentActivity else { return }
        var state = activity.content.state
        let unit = currentDistanceUnit
        guard state.distanceUnit != unit else { return }
        state.distanceUnit = unit
        state.language = currentLanguage
        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))) }
        lastUpdateDate = Date()
    }

    // MARK: - Start

    func startActivity(tripId: UUID, startDate: Date, vehicleName: String, vehicleAvatar: String) {
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            return
        }

        currentActivity = nil
        lastUpdateDate = nil

        Task {
            for activity in Activity<TripActivityAttributes>.activities {
                await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }

            let attributes = TripActivityAttributes(
                tripId: tripId,
                startDate: startDate,
                vehicleName: vehicleName,
                vehicleAvatar: vehicleAvatar
            )
            checkpointCount = 0
            let initialState = TripActivityAttributes.ContentState(
                speedKmh: 0, distanceKm: 0, isPaused: false, pausedDuration: 0,
                language: currentLanguage, isDarkMode: currentIsDarkMode,
                distanceUnit: currentDistanceUnit
            )

            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: initialState, staleDate: Date().addingTimeInterval(Self.staleAfter)),
                    pushType: nil
                )
                self.currentActivity = activity
                self.lastUpdateDate = Date()
            } catch {
                #if DEBUG
                print("LiveActivity: failed to start — \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Update

    /// Провод остаётся МЕТРИЧЕСКИМ и в 0.6.7: `speedKmh`/`distanceKm` везут
    /// километры, единицу показа виджет получит отдельным полем (шаг 6).
    /// Переименовать поля нельзя — активность, начатая старым бинарником и
    /// пережившая обновление, перестала бы декодироваться и умерла посреди
    /// поездки; параметры названы так же, чтобы это было видно на вызове.
    func updateActivity(speedKmh: Double, distanceKm: Double, isPaused: Bool, pausedDuration: TimeInterval, elapsedAtPause: TimeInterval? = nil) {
        guard let activity = currentActivity else { return }

        // Throttle, but always push pause state changes
        if let lastUpdate = lastUpdateDate,
           Date().timeIntervalSince(lastUpdate) < throttleInterval {
            if activity.content.state.isPaused == isPaused {
                return
            }
        }

        let state = TripActivityAttributes.ContentState(
            speedKmh: speedKmh, distanceKm: distanceKm, isPaused: isPaused,
            pausedDuration: pausedDuration, elapsedAtPause: elapsedAtPause,
            language: currentLanguage, isDarkMode: currentIsDarkMode,
            checkpointCount: checkpointCount,
            distanceUnit: currentDistanceUnit
        )

        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))) }
        lastUpdateDate = Date()
    }

    // MARK: - Отметки

    /// Сколько отметок в текущей записи. Живёт здесь, чтобы КАЖДОЕ обновление
    /// карточки несло актуальное число, а не только то, что пришло с кнопкой.
    private(set) var checkpointCount: Int = 0

    /// Отметка поставлена — показать это немедленно.
    ///
    /// Мимо тротлинга намеренно. Кнопка на Live Activity срабатывает молча, и
    /// секундная задержка отклика читается как «не нажалось»: человек жмёт
    /// второй раз и получает две отметки вместо одной. Правило «отклик в момент
    /// касания» из CLAUDE.md — оно и здесь.
    func noteCheckpoint(count: Int) {
        checkpointCount = count
        guard let activity = currentActivity else { return }
        var state = activity.content.state
        state.checkpointCount = count
        state.distanceUnit = currentDistanceUnit
        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))) }
        lastUpdateDate = Date()
    }

    // MARK: - End

    func endActivity() {
        // End tracked activity
        if let activity = currentActivity {
            Task {
                await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
            currentActivity = nil
            lastUpdateDate = nil
        }
        // Also end any lingering activities (e.g. finished summary still showing)
        Task {
            for activity in Activity<TripActivityAttributes>.activities {
                await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    func endActivityWithSummary(distanceKm: Double, duration: String, avgSpeedKmh: Double) {
        guard let activity = currentActivity else { return }

        let finalState = TripActivityAttributes.ContentState(
            speedKmh: 0, distanceKm: distanceKm, isPaused: false, pausedDuration: 0,
            isFinished: true, finalDuration: duration, averageSpeedKmh: avgSpeedKmh,
            language: currentLanguage, isDarkMode: currentIsDarkMode,
            distanceUnit: currentDistanceUnit
        )

        Task {
            await activity.update(.init(state: finalState, staleDate: nil))
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(300)))
        }
        currentActivity = nil
        lastUpdateDate = nil
    }

    // MARK: - Cleanup

    private func endAllActivities() {
        if let activity = currentActivity {
            Task { await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
            currentActivity = nil
            lastUpdateDate = nil
        }
        for activity in Activity<TripActivityAttributes>.activities {
            Task { await activity.end(.init(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
        }
    }
}
