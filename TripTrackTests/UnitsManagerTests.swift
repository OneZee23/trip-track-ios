import XCTest
import SwiftUI
@testable import TripTrack

/// Зеркало выбора единицы для SwiftUI — и умолчание окружения.
///
/// Две вещи, которые здесь заперты, ловятся только на устройстве и выглядят
/// как «фича не работает»:
///
/// 1. **Умолчание окружения читает хранилище, а не константу.** В проекте есть
///    листы, где окружение переинжектится руками, и лист, где инжект забыли,
///    обязан показать ПРАВИЛЬНУЮ единицу — просто без живой перерисовки.
///    Замороженное умолчание показывало бы километры человеку, выбравшему мили.
/// 2. **Зеркало не заводит второго хранилища.** Единственная дверь к записи —
///    `SettingsManager.setDistanceUnit`: кроме `UserDefaults` выбор обязан
///    доехать до колонки, иначе он не уедет с телефона вообще (это чинил шаг 2).
@MainActor
final class UnitsManagerTests: XCTestCase {

    private var store: UserDefaults!
    private var suiteName: String!
    /// Что стояло у настоящего человека до прогона: `DistanceUnit.current` и
    /// умолчание окружения читают `UserDefaults.standard` жёстко — подменить
    /// его нечем, поэтому значение возвращается на место в `tearDown`.
    private var savedStandard: String?

    override func setUp() {
        super.setUp()
        suiteName = "UnitsManagerTests.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
        savedStandard = UserDefaults.standard.string(forKey: DistanceUnit.storageKey)
    }

    override func tearDown() {
        store?.removePersistentDomain(forName: suiteName)
        store = nil
        suiteName = nil
        if let savedStandard {
            UserDefaults.standard.set(savedStandard, forKey: DistanceUnit.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: DistanceUnit.storageKey)
        }
        savedStandard = nil
        super.tearDown()
    }

    // MARK: - Зеркало

    func testMirrorsWhatTheStoreAlreadyHolds() {
        store.set("miles", forKey: DistanceUnit.storageKey)
        let manager = UnitsManager(store: store, persist: { _ in })
        XCTAssertEqual(manager.distance, .miles)
    }

    /// Пустое хранилище — километры. Отсутствие ключа при этом значит «человек
    /// ещё не выбирал», и на этом признаке стоит будущая догадка по региону
    /// (шаг 10): записывать сюда умолчание нельзя.
    func testEmptyStoreReadsAsKilometres() {
        let manager = UnitsManager(store: store, persist: { _ in })
        XCTAssertEqual(manager.distance, .km)
        XCTAssertNil(store.string(forKey: DistanceUnit.storageKey),
                     "зеркало записало умолчание в хранилище — признак «не выбирал» потерян")
    }

    /// Нераспознанное значение (чужой клиент, будущая версия) читается как
    /// километры, а не как пустота.
    func testUnknownValueReadsAsKilometres() {
        store.set("kilometres", forKey: DistanceUnit.storageKey)
        XCTAssertEqual(UnitsManager(store: store, persist: { _ in }).distance, .km)
    }

    // MARK: - Запись идёт через единственную дверь

    func testSelectWritesThroughTheDoorAndNotAroundIt() {
        var doorCalls: [DistanceUnit] = []
        let manager = UnitsManager(store: store, persist: { unit in
            doorCalls.append(unit)
            // Настоящая дверь (`SettingsManager.setDistanceUnit`) кладёт
            // выбор и в хранилище, и в колонку — здесь только первая половина.
            self.store.set(unit.rawValue, forKey: DistanceUnit.storageKey)
        })

        manager.select(.miles)

        XCTAssertEqual(doorCalls, [.miles])
        XCTAssertEqual(manager.distance, .miles)
        XCTAssertEqual(store.string(forKey: DistanceUnit.storageKey), "miles")
    }

    /// Выбор того же самого — не событие. На `.distanceUnitChanged` подписан
    /// тот, кто по нему ДЕЛАЕТ работу (принудительный апдейт живой активности
    /// мимо тротлинга), и лишний повод стоил бы кадра посреди поездки.
    func testSelectingTheSameUnitDoesNothing() {
        var doorCalls = 0
        let manager = UnitsManager(store: store, persist: { _ in doorCalls += 1 })
        manager.select(.km)
        XCTAssertEqual(doorCalls, 0)
    }

    // MARK: - Пул со второго телефона

    /// Выбор со второго телефона приезжает пулом прямо в `UserDefaults` —
    /// мимо экрана настроек. Зеркало обязано это заметить и сказать тем, кого
    /// SwiftUI не перерисовывает.
    func testPullIntoTheStoreIsNoticedAndAnnounced() {
        let manager = UnitsManager(store: store, persist: { _ in })
        let announced = expectation(forNotification: .distanceUnitChanged, object: nil)

        store.set("miles", forKey: DistanceUnit.storageKey)
        manager.refreshFromStore()

        XCTAssertEqual(manager.distance, .miles)
        wait(for: [announced], timeout: 1)
    }

    // MARK: - Умолчание окружения

    /// Лист, которому окружение забыли переинжектить, обязан показать выбор
    /// человека — из хранилища, а не из константы.
    func testEnvironmentDefaultReadsTheStoredChoice() {
        UserDefaults.standard.set("miles", forKey: DistanceUnit.storageKey)
        XCTAssertEqual(DistanceUnit.current, .miles)
        XCTAssertEqual(EnvironmentValues().distanceUnit, .miles)

        UserDefaults.standard.removeObject(forKey: DistanceUnit.storageKey)
        XCTAssertEqual(DistanceUnit.current, .km)
        XCTAssertEqual(EnvironmentValues().distanceUnit, .km)
    }

    /// Явно переданная единица умолчание перебивает — иначе окружение было бы
    /// не окружением, а глобальной переменной.
    func testInjectedValueWinsOverTheDefault() {
        UserDefaults.standard.set("km", forKey: DistanceUnit.storageKey)
        var values = EnvironmentValues()
        values.distanceUnit = .miles
        XCTAssertEqual(values.distanceUnit, .miles)
    }
}
