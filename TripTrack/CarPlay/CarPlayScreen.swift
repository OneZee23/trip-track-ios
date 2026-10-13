import Foundation

/// Что показано на экране автомобиля — ЧИСТОЙ функцией.
///
/// Чистой, потому что проверить сам CarPlay нечем: шаблоны живут только внутри
/// подключённой сцены, и единственный способ увидеть их — симулятор CarPlay
/// глазами. А вопрос, на который экран отвечает, проверяемый: какие строки и
/// какие кнопки человек видит в каждом состоянии записи. Тот же приём, что у
/// `ProPaywallPhase` и `ProShowcase`: решение — значение, сборка шаблона —
/// тонкий слой над ним.
enum CarPlayScreen {

    /// В каком состоянии запись прямо сейчас.
    ///
    /// Перечислением, а не парой булевых: «пишется И на паузе И недоступно» не
    /// существует, а из трёх флагов такое сочетание собирается легко.
    enum State: Equatable {
        /// Пишется. Метры и секунды — те же, что на экране телефона.
        case recording(metres: Double, duration: String, speedMetresPerSecond: Double)
        /// На паузе. Скорости здесь нет: она ноль по определению, и показывать
        /// её значило бы показывать ноль как факт о дороге.
        case paused(metres: Double, duration: String)
        /// Ничего не пишется.
        case idle
        /// Командовать записью НЕЧЕМ: `MapViewModel` живёт в `ContentView`, и
        /// пока экран телефона ни разу не собрался, его нет.
        ///
        /// Это честный ответ, а не заглушка. Показать здесь кнопку «Начать»,
        /// которая ничего не сделает, — нажатие, которое ничего не делает, то
        /// есть хуже отсутствующего.
        case unavailable
    }

    /// Что человек может нажать. Действий не больше двух: кнопок на
    /// `CPInformationTemplate` мало, а за рулём выбирать из пяти нельзя.
    enum Action: Equatable {
        case start
        case pause
        case resume
        case finish
    }

    /// Строка «название — значение».
    struct Item: Equatable {
        let title: String
        /// `nil` — строка без значения, то есть просто фраза.
        let detail: String?
    }

    /// Готовый экран.
    struct Model: Equatable {
        let title: String
        let items: [Item]
        let actions: [Action]
    }

    /// Собрать экран.
    ///
    /// - Parameters:
    ///   - unit: единица человека. Параметр ОБЯЗАТЕЛЕН и без умолчания — тот
    ///     же рычаг, что у `Measure.unit:`: CarPlay это новое место показа
    ///     (правило 0.6.7), и оно физически не соберётся, не назвав единицу.
    static func model(
        _ state: State,
        unit: DistanceUnit,
        lang: LanguageManager.Language
    ) -> Model {
        switch state {
        case .recording(let metres, let duration, let speed):
            return Model(
                title: AppStrings.carPlayRecordingTitle(lang),
                items: [
                    Item(title: AppStrings.carPlayDistance(lang),
                         detail: Measure.distance(metres: metres, unit: unit, lang: lang)),
                    Item(title: AppStrings.carPlayTime(lang), detail: duration),
                    Item(title: AppStrings.carPlaySpeed(lang),
                         detail: Measure.speed(ms: speed, unit: unit, lang: lang)),
                ],
                actions: [.pause, .finish])

        case .paused(let metres, let duration):
            return Model(
                title: AppStrings.carPlayPausedTitle(lang),
                items: [
                    Item(title: AppStrings.carPlayDistance(lang),
                         detail: Measure.distance(metres: metres, unit: unit, lang: lang)),
                    Item(title: AppStrings.carPlayTime(lang), detail: duration),
                ],
                actions: [.resume, .finish])

        case .idle:
            return Model(
                title: AppStrings.carPlayIdleTitle(lang),
                items: [Item(title: AppStrings.carPlayIdleBody(lang), detail: nil)],
                actions: [.start])

        case .unavailable:
            return Model(
                title: AppStrings.carPlayIdleTitle(lang),
                items: [Item(title: AppStrings.carPlayUnavailableBody(lang), detail: nil)],
                actions: [])
        }
    }

    /// Подпись кнопки.
    static func title(_ action: Action, lang: LanguageManager.Language) -> String {
        switch action {
        case .start:  return AppStrings.carPlayStart(lang)
        case .pause:  return AppStrings.carPlayPause(lang)
        case .resume: return AppStrings.carPlayResume(lang)
        case .finish: return AppStrings.carPlayFinish(lang)
        }
    }
}
