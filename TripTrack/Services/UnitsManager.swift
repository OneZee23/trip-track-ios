import Combine
import SwiftUI

/// Выбранная единица расстояния — для SwiftUI и для всех, кто вне его.
///
/// Экраны читают её из `@Environment(\.distanceUnit)` и перерисовываются, как
/// на смене языка; сервисы (`NotificationManager`, `LiveActivityManager`,
/// `AutoTripService`, `MapViewModel`) читают `DistanceUnit.current` свежо на
/// каждом вызове, а о смене узнают из `.distanceUnitChanged` — им перерисовка
/// не поможет, у них уже отправленное уведомление и уже живая активность на
/// локскрине.
///
/// **Писать выбор сам этот класс НЕ ИМЕЕТ ПРАВА.** Единственная дверь —
/// `SettingsManager.setDistanceUnit`: кроме `UserDefaults` выбор обязан
/// доехать до колонки `UserSettingsEntity.distanceUnit`, иначе он не уедет с
/// телефона вообще (ровно этот обрыв чинил шаг 2 версии). Здесь — зеркало для
/// SwiftUI и сигнал для остальных, а не второе хранилище.
@MainActor
final class UnitsManager: ObservableObject {
    static let shared = UnitsManager()

    /// Что показывать ПРЯМО СЕЙЧАС. Меняется здесь только вслед за
    /// хранилищем — своего мнения у зеркала нет.
    @Published private(set) var distance: DistanceUnit

    private let store: UserDefaults
    private let persist: (DistanceUnit) -> Void
    private var cancellables = Set<AnyCancellable>()

    /// `store` и `persist` разведены для тестов: синглтон пишет через
    /// `SettingsManager` (то есть в базу и в очередь синка), а тест — в свой
    /// сьют, не поднимая CoreData и не воюя с синглтоном за общий ключ.
    init(
        store: UserDefaults = .standard,
        persist: @escaping (DistanceUnit) -> Void = { SettingsManager.shared.setDistanceUnit($0) }
    ) {
        self.store = store
        self.persist = persist
        self.distance = Self.read(from: store)
        // Подписка на изменение САМОГО хранилища, а не на `.syncPullCompleted`.
        // Приехавший пулом выбор кладёт в `UserDefaults` обработчик пула у
        // `SettingsManager`, а порядок обработчиков одного уведомления не
        // определён: подписавшись на пул, зеркало могло бы прочитать
        // хранилище ДО того, как в него положили приехавшее. Заодно ловится
        // всякий другой писатель — например голое `@AppStorage` на экране,
        // который забудут провести через дверь.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFromStore()
            }
            .store(in: &cancellables)
    }

    /// Человек выбрал единицу на экране настроек.
    func select(_ unit: DistanceUnit) {
        guard unit != distance else { return }
        persist(unit)
        refreshFromStore()
    }

    /// Перечитать хранилище и, если выбор изменился, сказать об этом всем.
    ///
    /// Уведомление постится ТОЛЬКО на настоящей смене: на него подписан тот,
    /// кто по нему делает работу — принудительный апдейт Live Activity мимо
    /// тротлинга, — и «сменилось на то же самое» стоило бы кадра посреди
    /// поездки.
    func refreshFromStore() {
        let stored = Self.read(from: store)
        guard stored != distance else { return }
        distance = stored
        NotificationCenter.default.post(name: .distanceUnitChanged, object: nil)
    }

    private static func read(from store: UserDefaults) -> DistanceUnit {
        DistanceUnit(rawValue: store.string(forKey: DistanceUnit.storageKey) ?? "") ?? .km
    }
}

extension Notification.Name {
    /// Человек сменил единицу расстояния. Для тех, кого не перерисовывает
    /// SwiftUI: живая активность на локскрине, уже собранные тексты
    /// уведомлений, вотч.
    static let distanceUnitChanged = Notification.Name("distanceUnitChanged")
}

// MARK: - Окружение

private struct DistanceUnitKey: EnvironmentKey {
    /// Вычисляемое, а не `static let`, и это важно вдвойне.
    ///
    /// В проекте есть листы, где окружение переинжектится руками
    /// (`ContentView`, `PublicVehicleView` и ещё десяток): у листа своё
    /// окружение, и то, что не переложили явно, приходит сюда, к умолчанию.
    /// Лист, где инжект забыли, обязан показать ПРАВИЛЬНУЮ единицу — просто
    /// без живой перерисовки на смене. Замороженное в `let` умолчание
    /// показывало бы то, что стояло на первом обращении, то есть километры
    /// человеку, выбравшему мили.
    static var defaultValue: DistanceUnit { .current }
}

extension EnvironmentValues {
    /// В чём этот экран печатает расстояния. Дальше — только в `Measure`:
    /// сама по себе единица ничего не форматирует.
    var distanceUnit: DistanceUnit {
        get { self[DistanceUnitKey.self] }
        set { self[DistanceUnitKey.self] = newValue }
    }
}
