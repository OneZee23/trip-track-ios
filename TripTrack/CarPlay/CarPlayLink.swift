import Combine
import Foundation

/// Мост между экраном автомобиля и той самой `MapViewModel`, которой
/// командует телефон.
///
/// Нужен потому, что `MapViewModel` — НЕ синглтон, и это решение проекта:
/// `MyMapViewModel` синглтон, а эта живёт `@StateObject` у `ContentView`
/// (см. её собственный доккомментарий). Сцена CarPlay — отдельная сцена, до
/// окружения SwiftUI ей не достать.
///
/// Дальше было два пути, и оба плохих, кроме одного:
/// - сделать `MapViewModel.shared` — тронуть самый чувствительный класс
///   приложения ради чужой сцены;
/// - дать CarPlay свой путь к `TripManager` — ВТОРОЙ путь записи, то есть
///   ровно та поломка, из-за которой километры в 0.6.5 свели в одну функцию.
///
/// Поэтому здесь просто СЛАБАЯ ссылка: `ContentView` кладёт свою модель,
/// сцена её читает. Слабая — чтобы экран автомобиля не удерживал в живых
/// модель мёртвого экрана телефона; `nil` при этом законное состояние
/// (`CarPlayScreen.State.unavailable`), а не ошибка.
@MainActor
final class CarPlayLink {
    static let shared = CarPlayLink()

    private weak var model: MapViewModel?
    /// Кого разбудить, когда модель наконец появилась. Сцена CarPlay умеет
    /// подключиться РАНЬШЕ, чем соберётся экран телефона, и без этого сигнала
    /// она осталась бы на «Откройте приложение» до первого нажатия.
    private var onAttach: (() -> Void)?

    private init() {}

    /// Зовёт `MapViewModel.init` — там же, где менеджер часов получает свою
    /// слабую ссылку (`PhoneConnectivityManager.shared.mapViewModel = self`).
    ///
    /// Именно оттуда, а не из `.onAppear` экрана: ссылка перестаёт зависеть от
    /// жизненного цикла вида и появляется РАНЬШЕ — сцена CarPlay умеет
    /// подключиться до того, как соберётся экран телефона.
    func attach(_ model: MapViewModel) {
        guard self.model !== model else { return }
        self.model = model
        // Уведомляем СЛЕДУЮЩИМ витком главного актёра, а не отсюда. Менеджер
        // часов только ХРАНИТ ссылку, а здесь обратный вызов ещё и читает
        // модель (`state`, `objectWillChange`) — а зовут нас из `init`, то
        // есть до конца её сборки. Кадр экрана автомобиля, опоздавший на один
        // виток, невидим; чтение недостроенного объекта — нет.
        let handler = onAttach
        Task { @MainActor in handler?() }
    }

    /// Сцена CarPlay просит уведомить её о появлении модели.
    func whenAttached(_ handler: @escaping () -> Void) {
        onAttach = handler
        if model != nil { handler() }
    }

    func stopWaiting() {
        onAttach = nil
    }

    // MARK: - Состояние

    /// Что показать на экране автомобиля. Числа — те же `@Published`, что
    /// читает экран телефона: своего счётчика у CarPlay нет.
    var state: CarPlayScreen.State {
        guard let model else { return .unavailable }
        guard model.isRecording else { return .idle }
        if model.isPaused {
            return .paused(metres: model.distance, duration: model.duration)
        }
        return .recording(metres: model.distance,
                          duration: model.duration,
                          speedMetresPerSecond: model.speed)
    }

    // MARK: - Действия

    /// Действия ведут в ТЕ ЖЕ двери, что экран записи, Live Activity и часы.
    /// Ни одной своей.
    func perform(_ action: CarPlayScreen.Action) {
        guard let model else { return }
        switch action {
        case .start:
            guard !model.isRecording else { return }
            model.toggleRecording()
        case .finish:
            guard model.isRecording else { return }
            model.toggleRecording()
        case .pause:
            guard model.isRecording, !model.isPaused else { return }
            model.togglePause(source: .carPlay)
        case .resume:
            guard model.isRecording, model.isPaused else { return }
            model.togglePause(source: .carPlay)
        }
    }

    /// На что подписаться, чтобы экран автомобиля обновлялся сам.
    var publisher: AnyPublisher<Void, Never>? {
        guard let model else { return nil }
        return model.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }
}
