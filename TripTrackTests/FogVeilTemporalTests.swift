import XCTest
import CoreData
import CoreLocation
import MapKit
@testable import TripTrack

/// Временной туман экрана поездки и растущая прорезь экрана записи.
///
/// Две половины одного рендерера. Первая отвечает на вопрос «каким мир был на
/// финише ЭТОЙ поездки» — и ошибиться в ней значит показать человеку дороги,
/// которых он тогда ещё не знал. Вторая отвечает за то, чтобы прорезь у машины
/// не стоила пересборки индекса путей всего мира шестьдесят раз в секунду.
final class FogVeilTemporalTests: XCTestCase {
    private var pc: PersistenceController!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: RevealedLayerStore!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        suiteName = "fog-temporal-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = RevealedLayerStore(persistence: pc, defaults: defaults)
    }

    /// Каждое поле обнуляется: XCTest держит экземпляры до конца прогона, и
    /// незакрытая `PersistenceController(inMemory:)` тянет свою модель — в логе
    /// это «Multiple NSEntityDescriptions claim TripEntity» в ЧУЖОМ классе.
    override func tearDown() {
        store = nil
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        pc = nil
        super.tearDown()
    }

    // MARK: - Фикстуры

    private static let krasnodar = CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)
    private static let rostov = CLLocationCoordinate2D(latitude: 47.2225, longitude: 39.7188)

    @discardableResult
    private func makeTrip(
        from origin: CLLocationCoordinate2D,
        northMetres: Double = 3_000,
        endDate: Date,
        withPreview: Bool = true
    ) -> UUID {
        let context = pc.container.viewContext
        let entity = TripEntity(context: context)
        let id = UUID()
        entity.id = id
        entity.startDate = endDate.addingTimeInterval(-1_800)
        entity.endDate = endDate
        entity.syncStatus = SyncStatus.synced.rawValue
        if withPreview {
            let coords = (0..<3).map { i -> CLLocationCoordinate2D in
                let t = Double(i) / 2
                return CLLocationCoordinate2D(
                    latitude: origin.latitude + (northMetres * t) / 111_320.0,
                    longitude: origin.longitude
                )
            }
            entity.previewPolyline = Trip.encodePolyline(coords)
        }
        try? context.save()
        return id
    }

    /// Накрывает ли слой эту точку хоть одним прогоном (в пределах километра).
    private func covers(_ layer: RevealedLayer, _ point: CLLocationCoordinate2D) -> Bool {
        let target = CLLocation(latitude: point.latitude, longitude: point.longitude)
        for line in layer.fine.polylines {
            let points = line.points()
            for i in 0..<line.pointCount {
                let c = points[i].coordinate
                if CLLocation(latitude: c.latitude, longitude: c.longitude)
                    .distance(from: target) < 1_000 { return true }
            }
        }
        return false
    }

    // MARK: - Мир на дату

    /// Главное правило экрана поездки: он показывает мир, каким тот был на
    /// финише. Поездка, случившаяся ПОЗЖЕ, не имеет права прочистить в нём
    /// коридор — иначе карта поездки на Чёрное море год спустя открывается уже
    /// с дорогой в Ростов, которой тогда не было.
    func testLaterTripIsNotInTheSnapshot() async {
        let firstEnd = Date(timeIntervalSince1970: 1_700_000_000)
        makeTrip(from: Self.krasnodar, endDate: firstEnd)
        makeTrip(from: Self.rostov, endDate: firstEnd.addingTimeInterval(86_400))

        let snapshot = await store.layer(before: firstEnd)
        XCTAssertFalse(snapshot.fine.polylines.isEmpty, "своя поездка в снимке есть")
        XCTAssertTrue(covers(snapshot, Self.krasnodar))
        XCTAssertFalse(covers(snapshot, Self.rostov), "поездка следующего дня — ещё не открытый мир")

        let later = await store.layer(before: firstEnd.addingTimeInterval(86_400 * 2))
        XCTAssertTrue(covers(later, Self.rostov), "к своей дате вторая поездка открыта")
        XCTAssertGreaterThan(later.cellCount, snapshot.cellCount)
    }

    /// Граница включающая: поездка, завершившаяся ровно в момент среза, в мир
    /// входит. Срез экрана поездки — это её собственный `endDate`, и исключить
    /// её значило бы показать поездку на фоне мира без неё самой.
    func testTripEndingExactlyAtTheCutoffIsIncluded() async {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        makeTrip(from: Self.krasnodar, endDate: end)

        let snapshot = await store.layer(before: end)
        XCTAssertTrue(covers(snapshot, Self.krasnodar))
    }

    /// Поездка без превью пропускается молча. Поднимать её сырые точки нельзя
    /// (условие производительности всей волны), а падать из-за неё — тем более.
    func testTripWithoutPreviewIsSkippedInTheSnapshot() async {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        makeTrip(from: Self.krasnodar, endDate: end, withPreview: false)
        makeTrip(from: Self.rostov, endDate: end, withPreview: true)

        let snapshot = await store.layer(before: end)
        XCTAssertTrue(covers(snapshot, Self.rostov))
        XCTAssertFalse(covers(snapshot, Self.krasnodar), "без превью — нечего открывать")
    }

    /// Снимок на дату в базу не пишет НИЧЕГО: это состояние одного экрана.
    func testSnapshotDoesNotTouchStoredTiles() async {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        makeTrip(from: Self.krasnodar, endDate: end)

        _ = await store.layer(before: end)
        let request: NSFetchRequest<RevealedCellEntity> = RevealedCellEntity.fetchRequest()
        XCTAssertEqual((try? pc.container.viewContext.count(for: request)) ?? -1, 0)
    }

    // MARK: - Прорезь у машины

    func testRevealProgressIsClampedToZeroAndOne() {
        XCTAssertEqual(FogRevealAnimation.progress(elapsed: 0, reduceMotion: false), 0, accuracy: 0.0001)
        XCTAssertEqual(
            FogRevealAnimation.progress(elapsed: FogRevealAnimation.duration, reduceMotion: false),
            1, accuracy: 0.0001
        )
        XCTAssertEqual(FogRevealAnimation.progress(elapsed: 99, reduceMotion: false), 1, accuracy: 0.0001,
                       "после конца прорезь не растёт дальше")
        // Часы, переставленные назад посреди поездки, дают отрицательное время.
        // Прорезь отрицательного радиуса рендерер пропустил бы вместе с кадром.
        XCTAssertEqual(FogRevealAnimation.progress(elapsed: -5, reduceMotion: false), 0, accuracy: 0.0001)

        let mid = FogRevealAnimation.progress(
            elapsed: FogRevealAnimation.duration / 2, reduceMotion: false)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
    }

    /// Reduce Motion не отменяет открытие — оно случается СРАЗУ. Человек,
    /// попросивший систему не двигать картинку, должен получить открытое место,
    /// а не отказ от него.
    func testReduceMotionOpensImmediately() {
        XCTAssertEqual(FogRevealAnimation.progress(elapsed: 0, reduceMotion: true), 1)
        XCTAssertTrue(FogRevealAnimation.isDone(elapsed: 0, reduceMotion: true))
        XCTAssertFalse(FogRevealAnimation.isDone(elapsed: 0, reduceMotion: false))
        XCTAssertTrue(FogRevealAnimation.isDone(
            elapsed: FogRevealAnimation.duration, reduceMotion: false))
    }

    /// Перерисовывается КОРОБКА вокруг машины, а не мир. Вуаль накрывает мир по
    /// определению, и `setNeedsDisplay()` без прямоугольника пересобирал бы
    /// каждый видимый тайл шестьдесят раз в секунду.
    func testRevealRectIsALocalBoxAroundThePoint() {
        let rect = FogRevealAnimation.rect(around: Self.krasnodar)
        XCTAssertTrue(rect.contains(MKMapPoint(Self.krasnodar)))
        XCTAssertLessThan(rect.width, MKMapRect.world.width / 100, "это не мир")

        let metre = MKMapPointsPerMeterAtLatitude(Self.krasnodar.latitude)
        let radius = FogVeilRenderer.revealMetres * metre
        XCTAssertGreaterThan(rect.width / 2, radius, "полный радиус прорези влезает целиком")
    }

    /// Прогресс меняется шестьдесят раз в секунду — и не стоит НИЧЕГО.
    /// Подменять ради него оверлей значило бы каждый кадр пересобирать индекс
    /// путей всего открытого мира для всех трёх уровней детали.
    func testChangingProgressDoesNotRebuildPathIndex() {
        let route = (0..<40).map { i in
            CLLocationCoordinate2D(
                latitude: Self.krasnodar.latitude + Double(i) * 0.001,
                longitude: Self.krasnodar.longitude
            )
        }
        let layer = RevealedLayer.build(runs: [route], cellCount: 40, atlas: nil)
        let veil = FogVeilOverlay(layer: layer)
        let renderer = FogVeilRenderer(veil: veil)
        let builds = renderer.chunkBuilds
        // Ноль: с 15 сентября индекс собирается на ПЕРВОЙ отрисовке своего
        // уровня, а не в `init` (тот случается на главном потоке в момент
        // открытия карты). Сколько наборов бакетов достижимо и что второй тайл
        // того же уровня не собирает их заново — держит
        // `FogVeilRendererTests.testPathIndexBuildsOnlyReachableBucketSets`.
        XCTAssertEqual(builds, 0, "индекс путей собрался в init рендерера")

        for step in 0...10 {
            veil.revealAround = FogVeilOverlay.RevealPoint(
                coordinate: Self.krasnodar, progress: Double(step) / 10
            )
        }

        XCTAssertEqual(renderer.chunkBuilds, builds,
                       "прогресс прорези пересобрал индекс путей")
        XCTAssertEqual(veil.revealAround?.progress ?? -1, 1, accuracy: 0.0001)
        XCTAssertTrue(renderer.overlay === veil, "оверлей тот же — рендерер не пересоздавали")
    }

    /// Прорезь пишется с главного потока, а читается потоками отрисовки MapKit
    /// — он зовёт `draw` одновременно, по тайлу на поток. Значение целиком
    /// (две координаты + прогресс) атомарно не пишется ничем, и порванное
    /// чтение дало бы прорезь не в том месте или радиус из чужого кадра.
    ///
    /// Инвариант, по которому это видно: обе координаты всегда равны
    /// прогрессу. Пара, склеенная из двух записей, его нарушит.
    func testRevealPointIsReadAndWrittenWhole() {
        let veil = FogVeilOverlay(layer: .empty)
        veil.revealAround = FogVeilOverlay.RevealPoint(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), progress: 0
        )

        let torn = NSMutableArray()
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for step in 0..<2_000 {
                if worker % 2 == 0 {
                    let value = Double(step % 100) / 100
                    veil.revealAround = FogVeilOverlay.RevealPoint(
                        coordinate: CLLocationCoordinate2D(latitude: value, longitude: value),
                        progress: value
                    )
                } else if let point = veil.revealAround {
                    if point.coordinate.latitude != point.progress
                        || point.coordinate.longitude != point.progress {
                        objc_sync_enter(torn)
                        torn.add(point.progress)
                        objc_sync_exit(torn)
                    }
                }
            }
        }

        XCTAssertEqual(torn.count, 0, "читатель увидел половину одной записи и половину другой")
    }
}

/// Кэш снимка на дату: один перебор библиотеки на дату, сброс по
/// `.revealedLayerChanged`.
@MainActor
final class TemporalFogCacheTests: XCTestCase {
    /// Кэш ходит в общий `RevealedLayerStore.shared`, подменить его нечем —
    /// поэтому проверяется не содержимое слоя, а ТОЖДЕСТВО ответа: второй
    /// спрашивающий с той же датой обязан получить ту же сборку, не перебирая
    /// библиотеку заново. `MKMultiPolyline` — класс, и `===` отвечает на это
    /// буквально.
    func testSameDateIsAnsweredFromTheCache() async {
        let cache = TemporalFogCache()
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let first = await cache.layer(before: date)
        let second = await cache.layer(before: date)
        XCTAssertTrue(first.fine === second.fine, "та же дата — тот же посчитанный слой")
    }

    func testDifferentDatesAreComputedSeparately() async {
        let cache = TemporalFogCache()
        let a = await cache.layer(before: Date(timeIntervalSince1970: 1_700_000_000))
        let b = await cache.layer(before: Date(timeIntervalSince1970: 1_600_000_000))
        XCTAssertFalse(a.fine === b.fine, "разные даты — разные миры")
    }

    /// Открытое пополнилось — снимок «сейчас» обязан пересчитаться. Иначе
    /// карточка итогов до конца жизни экрана показывала бы мир без только что
    /// законченной поездки.
    func testRevealedLayerChangedInvalidates() async {
        let cache = TemporalFogCache()
        let first = await cache.layer(before: nil)

        NotificationCenter.default.post(name: .revealedLayerChanged, object: nil)
        // Наблюдатель кэша стоит на главной очереди — дать ей провернуться.
        try? await Task.sleep(nanoseconds: 60_000_000)

        let second = await cache.layer(before: nil)
        XCTAssertFalse(first.fine === second.fine, "после уведомления слой пересчитан")
    }

    /// `reload` не верит кэшу вовсе: его зовёт тот, кто сам услышал
    /// уведомление, и порядок наблюдателей у `NotificationCenter` не наш.
    func testReloadIgnoresTheCache() async {
        let cache = TemporalFogCache()
        let first = await cache.layer(before: nil)
        let again = await cache.reload(before: nil)
        XCTAssertFalse(first.fine === again.fine)
    }
}
