import XCTest
import CoreData
import CoreLocation
import MapKit
import Metal
import QuartzCore
@testable import TripTrack

/// Бюджеты Metal-тумана на стресс-библиотеке (спека §7 «Бюджет», «Память»).
///
/// Числа здесь — СИМУЛЯТОРНЫЕ. На устройстве они ниже: там своя память,
/// свой драйвер и свой тайловый растеризатор, и меряется на нём не то же
/// самое. Сторож поэтому охраняет не абсолютную скорость, а РЕГРЕССИЮ: пока
/// сборка буферов идёт вне главного потока, а кадр отсекает куски линейным
/// проходом, эти числа стоят на месте. Выросли вдвое — значит кто-то поднял
/// точки на главный поток, завёл буфер на отрезок или снял отсечение, и
/// узнать об этом надо здесь, а не по спискам «Атлас тормозит».
///
/// Библиотека — масштаб стресс-сида `-seed-hang-stress` (400 поездок ×
/// 2 000 точек), но сеются ТОЛЬКО превью: открытый мир целиком считается по
/// `previewPolyline` (правило 0.7.0 «сырые точки на карту не приходят
/// НИКОГДА»), а восемьсот тысяч `TrackPointEntity` стоили бы минуту прогона
/// и не изменили бы ни одного из четырёх измеряемых чисел.
///
/// `@MainActor`: тесты `async` и трогают `viewContext` — см. CLAUDE.md
/// «async-тест, читающий viewContext, обязан быть @MainActor».
@MainActor
final class FogMetalBudgetTests: XCTestCase {

    // MARK: Бюджеты

    /// Сборка буферов вне главного потока, миллисекунды.
    private static let meshBuildBudgetMs: Double = 300
    /// На сколько главному потоку позволено встать, пока идёт сборка.
    private static let mainGapBudgetMs: Double = 50
    /// Кодирование кадра на улице (0.3 м/pt) и на стране (300 м/pt).
    private static let streetEncodeBudgetMs: Double = 4
    private static let countryEncodeBudgetMs: Double = 8
    /// Потолок памяти GPU под открытый мир.
    private static let byteBudget = 64 * 1024 * 1024
    /// Порог, за которым куски перестают отсекаться линейным проходом и
    /// заводится грубый индекс (спека §7).
    private static let chunkIndexThreshold = 2000

    /// Сколько кадров меряется после прогрева. Первый кадр не считается
    /// никогда — урок `DiscoveryProcessorTests`: в свежем процессе в замер
    /// попадает всё, что грелось впервые (здесь — пайплайны, текстуры и
    /// первая посылка в очередь).
    private static let measuredFrames = 5

    private static let viewport = CGSize(width: 393, height: 852)
    private static let scale: CGFloat = 3

    /// Середина стресс-библиотеки: поездка №200 на своей середине. На улице
    /// кадр стоит прямо на коридоре, на стране — накрывает десятки поездок
    /// разом.
    private static let centre = CLLocationCoordinate2D(latitude: 47.03, longitude: 40.92)

    // MARK: Слой

    /// Открытый мир стресс-библиотеки. Считается ОДИН раз на класс: сборка
    /// слоя — это разбор четырёхсот превью через `RevealBuilder`, и платить
    /// за неё трижды незачем.
    ///
    /// Держит только полилинии: ни `PersistenceController`, ни
    /// `RevealedLayerStore` за пределы `buildStressLayer()` не выходят —
    /// иначе in-memory модель дожила бы до конца прогона и роняла бы чужой
    /// класс (CLAUDE.md «Тест, не отпустивший фикстуру»).
    private static var cachedLayer: RevealedLayer?

    override class func tearDown() {
        cachedLayer = nil
        super.tearDown()
    }

    private func stressLayer() async -> RevealedLayer {
        if let cached = Self.cachedLayer { return cached }
        let layer = await buildStressLayer()
        Self.cachedLayer = layer
        return layer
    }

    /// База, слой и всё, что их держало, живут ровно до `return`.
    private func buildStressLayer() async -> RevealedLayer {
        let pc = PersistenceController(inMemory: true)
        let suiteName = "fog-metal-budget-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        seedStressLibrary(into: pc)
        let store = RevealedLayerStore(persistence: pc, defaults: defaults)
        await store.rebuildIfNeeded()
        // Атлас не спрашивается: регионы и подписи к бюджету тумана
        // отношения не имеют, а разбор бандла стоил бы больше самой сборки.
        let layer = await store.layer()
        defaults.removePersistentDomain(forName: suiteName)
        return layer
    }

    /// Та же геометрия, что у `DebugMapSeed.runHangStressIfNeeded`: четыреста
    /// диагональных поездок, каждая ≈7 км, сдвинутых на 0.01° друг от друга —
    /// то есть пересекающийся пучок на четыре градуса в обе стороны, а не
    /// одна линия и не четыреста далёких.
    private func seedStressLibrary(into pc: PersistenceController,
                                   trips: Int = 400, pointsPerTrip: Int = 2000) {
        let context = pc.container.viewContext
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        for t in 0..<trips {
            autoreleasepool {
                let trip = TripEntity(context: context)
                trip.id = UUID()
                let start = base.addingTimeInterval(-Double(t + 1) * 3600)
                trip.startDate = start
                trip.endDate = start.addingTimeInterval(Double(pointsPerTrip) * 5)
                trip.isPrivate = true
                trip.title = "Stress \(t)"
                trip.syncStatus = SyncStatus.synced.rawValue
                let latBase = 45.0 + Double(t) * 0.01
                let lonBase = 38.9 + Double(t) * 0.01
                var coords: [CLLocationCoordinate2D] = []
                coords.reserveCapacity(pointsPerTrip)
                for p in 0..<pointsPerTrip {
                    coords.append(CLLocationCoordinate2D(
                        latitude: latBase + Double(p) * 0.00003,
                        longitude: lonBase + Double(p) * 0.00002))
                }
                trip.previewPolyline = Trip.encodePolyline(coords)
                trip.distance = 7_000
                trip.maxSpeed = 20
                trip.averageSpeed = 14
            }
            if t % 20 == 0 { try? context.save() }
        }
        try? context.save()
    }

    // MARK: Сборка буферов

    /// Буферы собираются вне главного потока и укладываются в бюджет, а
    /// главный поток при этом не встаёт.
    ///
    /// Сторож здесь тот же, что у `PlaceReconcileMainThreadTests`: разрыв
    /// ответа главной очереди мерится СНАРУЖИ. Элапсед сам по себе ничего не
    /// доказывал бы — он одинаков и когда фон честно считает триста
    /// миллисекунд, и когда главный поток стоит все триста.
    func testMeshBuildsOffMainWithinBudget() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal недоступен") }
        let layer = await stressLayer()
        XCTAssertFalse(layer.isEmpty, "стресс-библиотека обязана открыть мир")

        let watchdog = MainThreadWatchdog()
        watchdog.start()
        let started = CACurrentMediaTime()
        let mesh = await Task.detached(priority: .userInitiated) {
            FogMesh.build(layer: layer, device: device)
        }.value
        let elapsedMs = (CACurrentMediaTime() - started) * 1000
        watchdog.stop()

        print(String(format: "[fog metal] сборка FogMesh: %.0f мс вне main, главный поток стоял максимум %.0f мс, отрезков %d",
                     elapsedMs, watchdog.maxGapMs, mesh.segmentCount))
        XCTAssertGreaterThan(mesh.segmentCount, 0)
        XCTAssertLessThan(elapsedMs, Self.meshBuildBudgetMs,
                          "сборка буферов вылезла из бюджета спеки §7")
        XCTAssertLessThan(watchdog.maxGapMs, Self.mainGapBudgetMs,
                          "сборка буферов держала главный поток — она обязана идти вне него")
    }

    // MARK: Кадр

    /// Кодирование кадра на двух масштабах спеки: улица и страна.
    ///
    /// Мерится ПРОЦЕССОРНОЕ время кодирования — от первой команды до
    /// последней, без `waitUntilCompleted`: за кадр на экране отвечает
    /// `CADisplayLink`, и то, что держит его в бюджете, — это цена обхода
    /// кусков и посылки вызовов отрисовки, а не время GPU, которое идёт
    /// параллельно.
    func testFrameEncodeFitsTheBudgetAtStreetAndCountryZoom() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal недоступен") }
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let frameEncoder = try XCTUnwrap(FogFrameEncoder(device: device))
        let layer = await stressLayer()
        let mesh = FogMesh.build(layer: layer, device: device)

        let street = try params(metresPerPoint: 0.3)
        let country = try params(metresPerPoint: 300)
        // Без этого замер честно мерил бы пустой кадр: сдвинь кто-нибудь
        // середину библиотеки — и отсечение выбросило бы всё, а бюджет
        // сошёлся бы сам собой.
        let streetChunks = visibleChunkCount(mesh: mesh, params: street)
        let countryChunks = visibleChunkCount(mesh: mesh, params: country)
        XCTAssertGreaterThan(streetChunks, 0, "кадр улицы обязан стоять на коридоре")
        XCTAssertGreaterThan(countryChunks, streetChunks,
                             "кадр страны обязан накрывать больше кусков, чем кадр улицы")

        let streetMs = try medianEncodeMs(mesh: mesh, params: street,
                                          device: device, queue: queue, encoder: frameEncoder)
        let countryMs = try medianEncodeMs(mesh: mesh, params: country,
                                           device: device, queue: queue, encoder: frameEncoder)

        print(String(format: "[fog metal] кодирование кадра: улица (0.3 м/pt, %@, кусков %d) %.2f мс, страна (300 м/pt, %@, кусков %d) %.2f мс",
                     String(describing: street.lod), streetChunks, streetMs,
                     String(describing: country.lod), countryChunks, countryMs))
        XCTAssertLessThan(streetMs, Self.streetEncodeBudgetMs,
                          "кадр на улице вылез из бюджета спеки §7")
        XCTAssertLessThan(countryMs, Self.countryEncodeBudgetMs,
                          "кадр на стране вылез из бюджета спеки §7")
    }

    // MARK: Память и куски

    /// Память буферов и число кусков — два числа, которыми меряется цена
    /// открытого мира.
    ///
    /// Число кусков `.far` здесь не «ощущение», а порог решения: отсечение в
    /// `FogFrameEncoder` — линейный проход по кускам своего уровня, и пока
    /// их меньше `chunkIndexThreshold`, грубый индекс (сетка «ключ → куски»)
    /// не заводится. Падение этой проверки и есть команда его завести.
    func testMeshMemoryAndChunkCountFitTheBudget() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal недоступен") }
        let layer = await stressLayer()
        let mesh = FogMesh.build(layer: layer, device: device)

        let megabytes = Double(mesh.byteSize) / 1024 / 1024
        let far = mesh.chunkCount(lod: .far)
        print(String(format: "[fog metal] буферы: %.1f МБ; кусков fine %d, mid %d, far %d",
                     megabytes, mesh.chunkCount(lod: .fine), mesh.chunkCount(lod: .mid), far))

        XCTAssertLessThan(mesh.byteSize, Self.byteBudget,
                          "буферы открытого мира вылезли за 64 МБ спеки §7")
        XCTAssertLessThan(far, Self.chunkIndexThreshold,
                          "кусков .far стало больше порога — пора заводить грубый индекс")
    }

    // MARK: Помощники

    /// Параметры кадра для видимого прямоугольника с заданными метрами на
    /// точку. Прямоугольник считается ОТ метров на точку, а не наоборот:
    /// `FogOffscreen.params` выводит масштаб из него сам, и задавать надо то
    /// число, которое названо в спеке.
    private func params(metresPerPoint: Double) throws -> FogFrameParams {
        let centre = MKMapPoint(Self.centre)
        let mapPointsPerMetre = MKMapPointsPerMeterAtLatitude(Self.centre.latitude)
        let width = Double(Self.viewport.width) * metresPerPoint * mapPointsPerMetre
        let height = Double(Self.viewport.height) * metresPerPoint * mapPointsPerMetre
        let rect = MKMapRect(x: centre.x - width / 2, y: centre.y - height / 2,
                             width: width, height: height)
        return try XCTUnwrap(FogOffscreen.params(
            rect: rect, sizePoints: Self.viewport, scale: Self.scale,
            palette: FogVeilPainter.Palette.night))
    }

    /// Сколько кусков доживёт до вызова отрисовки — тем же отсечением, что в
    /// `FogFrameEncoder.encodeCoverage`: видимый прямоугольник, раздутый на
    /// полуширину коридора с пером.
    private func visibleChunkCount(mesh: FogMesh, params: FogFrameParams) -> Int {
        let mapPointsPerPoint = params.visible.width / Double(params.viewportPoints.width)
        let pad = (params.halfWidthPoints + params.featherPoints) * mapPointsPerPoint
        let needed = params.visible.insetBy(dx: -pad, dy: -pad)
        return (mesh.chunks[params.lod] ?? []).filter { $0.rect.intersects(needed) }.count
    }

    /// Медиана по `measuredFrames` кадрам после прогрева. Медиана, а не
    /// минимум: сторож ловит регрессию, а минимум по нескольким попыткам
    /// отвечал бы на вопрос «а как быстро бывает», который никого не
    /// защищает.
    private func medianEncodeMs(mesh: FogMesh, params: FogFrameParams,
                                device: MTLDevice, queue: MTLCommandQueue,
                                encoder: FogFrameEncoder) throws -> Double {
        let width = max(1, Int(params.drawableSize.width.rounded()))
        let height = max(1, Int(params.drawableSize.height.rounded()))
        let coverage = try XCTUnwrap(FogFrameEncoder.makeCoverageTexture(
            device: device, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: FogFrameEncoder.targetFormat, width: width, height: height,
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // Цель никто не читает — меряется кодирование, а не картинка.
        descriptor.storageMode = .private
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        var samples: [Double] = []
        for frame in 0...Self.measuredFrames {
            let buffer = try XCTUnwrap(queue.makeCommandBuffer())
            let started = CACurrentMediaTime()
            encoder.encode(mesh: mesh, params: params, coverage: coverage,
                           target: pass, into: buffer)
            let elapsedMs = (CACurrentMediaTime() - started) * 1000
            buffer.commit()
            // Ждём ВНЕ замера: следующий кадр иначе встал бы в очередь к GPU
            // и мерил бы его, а не кодирование.
            buffer.waitUntilCompleted()
            if frame > 0 { samples.append(elapsedMs) }
        }
        return samples.sorted()[samples.count / 2]
    }
}
