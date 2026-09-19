import XCTest
import CoreData
import CoreLocation
@testable import TripTrack

/// Вписанная рукой поездка ОТКРЫВАЕТ мир — вторая половина правила 0.8.0.
///
/// Первая («награды не начисляются») живёт в `ManualTripRewardsTests`. Здесь
/// обратное: гейт наград не имеет права дойти до слоя открытого, потому что
/// километры вписанной поездки настоящие (спека §2: атлас — ДА).
///
/// Отдельным классом, а не строкой в `ManualTripFlowTests`: там на каждый тест
/// заводится свой `TripManager` со своим `LocationManager`, и `async`-проход по
/// фоновому контексту поверх этой стопки ронял процесс — падал при этом
/// `MapRegionsBundleTests` через две буквы алфавита, ровно как разобрано в
/// CLAUDE.md про чужие хвосты. Здесь строка кладётся репозиторием, как её
/// кладёт пул, — ни `TripManager`, ни `LocationManager` для этого не нужны.
@MainActor
final class ManualTripAtlasTests: XCTestCase {

    /// Два хранилища и два стора — на весь класс, не на тест.
    ///
    /// Вторая пара нужна потому, что одна и та же дорога открывается ОДИН раз:
    /// записанную поездку надо разбирать на чистой базе, иначе она честно
    /// откроет ноль. А статические они по той же причине, что и в
    /// `ManualTripFlowTests`: `ingest` работает на фоновом контексте, и
    /// хранилище, умершее раньше его последнего вздоха, портит кучу — падает
    /// при этом чужой класс.
    private static let manualStack = Stack(name: "manual")
    private static let recordedStack = Stack(name: "recorded")

    final class Stack {
        let pc: PersistenceController
        let store: RevealedLayerStore
        let defaults: UserDefaults

        init(name: String) {
            pc = PersistenceController(inMemory: true)
            defaults = UserDefaults(suiteName: "manual-atlas-\(name)-\(UUID().uuidString)")!
            store = RevealedLayerStore(
                persistence: pc,
                defaults: defaults,
                // Бандла атласа тесту не нужно: проверяется «слой разбирает
                // вписанную поездку», а не геометрия регионов.
                regionId: { _ in "RU-KDA" }
            )
        }
    }

    /// Строка ровно того вида, какой её кладёт `TripManager.createManualTrip`:
    /// завершённая, с превью и с нужным `source`.
    @discardableResult
    private func makeTrip(source: TripOrigin, in stack: Stack) -> UUID {
        let context = stack.pc.container.viewContext
        let entity = TripEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.startDate = Date().addingTimeInterval(-3600)
        entity.endDate = Date()
        entity.source = source.rawValue
        entity.syncStatus = SyncStatus.pendingUpload.rawValue
        let coords = (0..<40).map { i in
            CLLocationCoordinate2D(latitude: 45.0 + Double(i) * 0.002, longitude: 38.9)
        }
        entity.previewPolyline = Trip.encodePolyline(coords)
        try? context.save()
        return id
    }

    /// Обе половины одним тестом: вписанная поездка открывает мир, и открывает
    /// РОВНО СТОЛЬКО ЖЕ, сколько записанная по той же дороге. Слой не знает
    /// про `source` вовсе, и знать не должен.
    func testAManualTripOpensTheWorldExactlyLikeARecordedOne() async throws {
        let manual = makeTrip(source: .manual, in: Self.manualStack)
        let manualDelta = await Self.manualStack.store.ingest(tripId: manual)

        XCTAssertGreaterThan(manualDelta.openedKm, 0,
                             "гейт наград до слоя открытого не ходит — километры тут настоящие")
        XCTAssertTrue(manualDelta.newRegionIds.contains("RU-KDA"))

        let recorded = makeTrip(source: .recorded, in: Self.recordedStack)
        let recordedDelta = await Self.recordedStack.store.ingest(tripId: recorded)
        XCTAssertEqual(manualDelta.openedKm, recordedDelta.openedKm, accuracy: 0.001)
    }
}
