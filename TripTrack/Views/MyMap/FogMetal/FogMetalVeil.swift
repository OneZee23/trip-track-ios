import MapKit
import MetalKit
import UIKit
import simd
import os

/// Метал-туман «Атласа».
///
/// Растровая вуаль (`FogVeilView`) рисует мглу раз в двести миллисекунд и
/// везёт готовую картинку за картой аффинным преобразованием слоя: на жесте
/// она мылится, после жеста видно «перезагрузку», а перья коридора ложатся
/// кольцами. Здесь весь туман собирается заново КАЖДЫЙ кадр, на GPU, из
/// отрезков открытого пути — поэтому ни растягивать, ни перезаказывать нечего.
///
/// Два прохода (`FogShaders.metal`): покрытие открытого в однобайтовую
/// текстуру со смешиванием `max` (стык отрезков не даёт ни бусины, ни кольца)
/// и композит ровной мглы поверх карты с премультиплицированной альфой.
///
/// Чего здесь нарочно НЕТ: облаков, рампы глубины, подписей регионов,
/// гравировки подсказок, выреза под атрибуцией, живой прорези у машины и
/// постера. Картинка, которую эта вуаль показывает, — эталон 0.8.0 и менять
/// её не имеет права ни одна задача: числа перечислены в спеке
/// `docs/superpowers/specs/2026-09-22-080-fog-metal-design.md` §3.
@MainActor
final class FogMetalVeil: MTKView {
    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "fogmetal")

    /// Ширина пера — доля полуширины коридора. Та же мягкость, что у кисти
    /// растра, только считается на GPU в каждом кадре.
    static let featherRatio: Double = 0.4

    /// Сколько ещё тикаем после последнего движения карты.
    ///
    /// То же число и тот же смысл, что у растровой вуали
    /// (`FogVeilView.trackingTail`): палец отпущен, а карта ещё доезжает
    /// инерцией, и гасить `CADisplayLink` на каждой паузе между двумя
    /// уведомлениями значило бы заводить его заново по десять раз за жест.
    /// Своё число, а не чужое, нарочно: растровая вуаль эту карту однажды
    /// покинет, а хвост останется.
    nonisolated static let trackingTail: TimeInterval = 0.4

    private let queue: MTLCommandQueue
    private let coveragePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState

    private var mesh = FogMesh.empty
    private var meshDirty = true
    /// Слой, который уже собран. `nil` — не собирали ни разу.
    private var installedSignature: [ObjectIdentifier]?
    /// Поколение сборки: слой, который успели обогнать, свои буферы не ставит.
    private var meshToken = 0

    private var coverage: MTLTexture?

    private weak var map: MKMapView?
    private var link: CADisplayLink?
    /// Когда `CADisplayLink` пора снять. Живёт вместе с ним и продлевается
    /// каждым движением карты.
    private var linkStopAt = Date.distantPast

    /// Кадр «вне камеры» уже заказан: тема или раскладка попросили
    /// перерисовку на СТОЯЩЕЙ карте. Пока камера не тронулась и данные те же,
    /// второй такой заказ нарисовал бы ровно ту же картинку, поэтому он
    /// молчит. Снимается всем, что меняет кадр само: движением
    /// (`startTracking`), разметкой, новым слоем и привязкой к карте.
    private var restFrameDrawn = false

    /// Палитра, с которой взялись рисовать последний кадр. Тема — то
    /// единственное, что зовёт `invalidate()`, и перещёлкнутая на СТОЯЩЕЙ
    /// карте дважды она обязана доехать оба раза: сравнение с этим числом и
    /// есть разница между «второй заказ той же картинки» и «второй сменой».
    private var drawnPaletteIsDark: Bool?

    /// Последний нарисованный кадр: прямоугольник карты и три его угла на
    /// экране. Совпало — GPU не трогаем вовсе, иначе на стоящей карте мы жгли
    /// бы батарею сто двадцать раз в секунду.
    private var lastRect: MKMapRect?
    private var lastCorners: [CGPoint] = []

    /// Сколько раз мы взялись рисовать кадр и сколько времени ушло на
    /// кодирование — для замера «сколько это стоит процессору».
    ///
    /// `frames` считается ПО ВЫЗОВУ `draw(_:)`, а не по доехавшему до экрана
    /// кадру: вид без окна `currentDrawable` не даёт вовсе, и счёт «только
    /// нарисованного» молчал бы в тестах, ради которых число и открыто
    /// наружу. Вопрос у него один — «тикаем мы в покое или нет».
    private(set) var frames = 0
    private(set) var encodeSeconds: Double = 0

    /// Совпадать с `FogUniforms` в шейдере байт в байт.
    private struct Uniforms {
        var m: SIMD4<Float>
        var translation: SIMD2<Float>
        var viewport: SIMD2<Float>
        var halfWidth: Float
        var feather: Float
    }

    private struct Composite {
        var colour: SIMD4<Float>
        var alpha: Float
    }

    /// `nil` — на этом устройстве Metal недоступен или шейдеры не собрались:
    /// зовущий остаётся на растровой вуали, как до 0.8.0.
    ///
    /// Фабрикой, а не `init?()`: у `UIView` свой непроваливающийся `init()`,
    /// и переопределить его провальным Swift не даёт.
    static func make() -> FogMetalVeil? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }

        let coverage = MTLRenderPipelineDescriptor()
        coverage.vertexFunction = library.makeFunction(name: "fog_coverage_vertex")
        coverage.fragmentFunction = library.makeFunction(name: "fog_coverage_fragment")
        coverage.colorAttachments[0].pixelFormat = .r8Unorm
        // Перекрытие берёт БОЛЬШЕЕ, а не складывает: сложение давало бы на
        // каждом стыке двух отрезков светлую бусину, а на повороте — кольцо.
        coverage.colorAttachments[0].isBlendingEnabled = true
        coverage.colorAttachments[0].rgbBlendOperation = .max
        coverage.colorAttachments[0].alphaBlendOperation = .max
        coverage.colorAttachments[0].sourceRGBBlendFactor = .one
        coverage.colorAttachments[0].destinationRGBBlendFactor = .one
        coverage.colorAttachments[0].sourceAlphaBlendFactor = .one
        coverage.colorAttachments[0].destinationAlphaBlendFactor = .one

        let composite = MTLRenderPipelineDescriptor()
        composite.vertexFunction = library.makeFunction(name: "fog_composite_vertex")
        composite.fragmentFunction = library.makeFunction(name: "fog_composite_fragment")
        composite.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let first = try? device.makeRenderPipelineState(descriptor: coverage),
              let second = try? device.makeRenderPipelineState(descriptor: composite)
        else { return nil }
        return FogMetalVeil(device: device, queue: queue, coverage: first, composite: second)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue,
                 coverage: MTLRenderPipelineState, composite: MTLRenderPipelineState) {
        self.queue = queue
        self.coveragePipeline = coverage
        self.compositePipeline = composite
        super.init(frame: .zero, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isOpaque = false
        layer.isOpaque = false
        backgroundColor = .clear
        framebufferOnly = true
        // Кадр заказываем сами, с `CADisplayLink`: рисовать по расписанию
        // MTKView значит рисовать и на стоящей карте.
        isPaused = true
        enableSetNeedsDisplay = false
        // Жесты обязаны доходить до карты под нами.
        isUserInteractionEnabled = false
    }

    required init(coder: NSCoder) { fatalError("init(coder:) не используется") }

    // MARK: Данные

    /// Открытый мир. Буферы собираются вне главного потока и подменяются
    /// целиком — дозаписи в живой буфер нет: кадр может идти прямо сейчас.
    func setLayer(_ revealed: RevealedLayer) {
        let signature = FogMesh.signature(of: revealed)
        guard signature != installedSignature, let device else { return }
        installedSignature = signature
        meshToken += 1
        let token = meshToken
        Task.detached(priority: .userInitiated) {
            let built = FogMesh.build(layer: revealed, device: device)
            await MainActor.run { [weak self] in
                guard let self, token == self.meshToken else { return }
                self.mesh = built
                self.meshDirty = true
                self.restFrameDrawn = false
                self.redrawIfNeeded()
            }
        }
    }

    // MARK: Жизнь

    /// Запоминает карту и рисует ОДИН кадр. `CADisplayLink` здесь не
    /// заводится: пока карта стоит, каждый его тик спрашивал бы у неё три
    /// `convert` и выбрасывал ответ — сто двадцать раз в секунду всё время,
    /// что открыт «Атлас». Тиками командует хост из делегата карты, теми же
    /// вызовами, что и растровой вуалью.
    func attach(map: MKMapView) {
        self.map = map
        meshDirty = true
        restFrameDrawn = false
        redrawIfNeeded()
    }

    func detach() {
        stopTracking()
        map = nil
        coverage = nil
    }

    // MARK: Жест

    /// Карта тронулась: заводим `CADisplayLink` и назначаем ему хвост. Второй
    /// вызов подряд хвост продлевает, а второй ссылки не заводит — ровно как
    /// у `FogVeilView`, откуда эта модель и взята.
    func startTracking(tail: TimeInterval = trackingTail) {
        linkStopAt = Date().addingTimeInterval(tail)
        // Кадр покоя больше ни про что: камера едет, и рисовать её будет сам
        // `CADisplayLink`.
        restFrameDrawn = false
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Камера встала: досматриваем хвост и гаснем сами, в `tick`.
    func extendTracking(tail: TimeInterval = trackingTail) {
        linkStopAt = Date().addingTimeInterval(tail)
    }

    func stopTracking() {
        link?.invalidate()
        link = nil
    }

    /// Идёт ли жест. `true` с `startTracking` и до тика, на котором вышел
    /// хвост, — именно до него, а не до самого дедлайна: снимает ссылку `tick`.
    var isTracking: Bool { link != nil }

    @objc private func tick() {
        guard map != nil else { return stopTracking() }
        redrawIfNeeded()
        if Date() > linkStopAt { stopTracking() }
    }

    /// Всё, что на экране, устарело не по камере: хост сменил тему. Рисуем
    /// один кадр сейчас.
    ///
    /// Ровно один: мгла собирается заново КАЖДЫЙ кадр, и второй зов подряд на
    /// той же камере, тех же данных и той же палитре дал бы ту же картинку.
    /// А сменившаяся палитра этот запрет снимает — иначе тема, перещёлкнутая
    /// туда и обратно на стоящей карте, застряла бы до первого движения
    /// пальца.
    func invalidate() {
        if drawnPaletteIsDark != FogVeilPainter.palette.isDark { restFrameDrawn = false }
        guard !restFrameDrawn else { return }
        restFrameDrawn = true
        meshDirty = true
        redrawIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        meshDirty = true
        restFrameDrawn = false
        redrawIfNeeded()
    }

    // MARK: Кадр

    /// Кадр рисуется только если камера сдвинулась или сменились данные.
    private func redrawIfNeeded() {
        guard let map, bounds.width > 1, bounds.height > 1 else { return }
        let rect = map.visibleMapRect
        let corners = Self.corners(of: rect, map: map, in: self)
        if !meshDirty, let last = lastRect, Self.sameRect(last, rect), corners == lastCorners {
            return
        }
        lastRect = rect
        lastCorners = corners
        meshDirty = false
        draw()
    }

    private static func sameRect(_ a: MKMapRect, _ b: MKMapRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Три угла прямоугольника карты на экране — левый верхний, правый верхний,
    /// левый нижний. Тот же приём, что у `VeilFrame`: без наклона проекция
    /// аффинна, и трёх точек ей хватает.
    private static func corners(of rect: MKMapRect, map: MKMapView, in space: UIView) -> [CGPoint] {
        [
            MKMapPoint(x: rect.minX, y: rect.minY),
            MKMapPoint(x: rect.maxX, y: rect.minY),
            MKMapPoint(x: rect.minX, y: rect.maxY),
        ].map { map.convert($0.coordinate, toPointTo: space) }
    }

    /// Кадр целиком. Считается он ЗДЕСЬ и до первой проверки: «взялись
    /// рисовать» и есть то, что меряет `frames`, — иначе вид без окна, где
    /// `currentDrawable` пуст, выглядел бы для тестов покоя вечно спящим.
    override func draw(_ rect: CGRect) {
        frames += 1
        drawnPaletteIsDark = FogVeilPainter.palette.isDark
        // Слоя ещё нет (вид только что встал в дерево) — кадр пропускаем, но
        // ПАМЯТЬ о нём стираем: иначе `redrawIfNeeded` посчитал бы кадр
        // нарисованным и молчал бы до первого движения камеры.
        guard let map, let device, let drawable = currentDrawable,
              let pass = currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer() else { lastRect = nil; return }
        let started = CACurrentMediaTime()

        // Прямоугольник и углы берутся ТЕ ЖЕ, что посчитал `redrawIfNeeded`:
        // второй опрос карты дал бы другой кадр, и туман разъехался бы с ней
        // ровно на одно движение пальца.
        let visible = lastRect ?? map.visibleMapRect
        let corners = lastCorners.count == 3 ? lastCorners
            : Self.corners(of: visible, map: map, in: self)
        guard let frame = VeilFrame(p00: corners[0], p10: corners[1], p01: corners[2],
                                    size: CGSize(width: visible.width, height: visible.height))
        else { return }

        // Метры на экранную точку и полуширина ореола — те же функции, что у
        // растровой вуали: метал обязан показывать ТУ ЖЕ ширину открытого, а
        // не свою.
        let pointsPerMapPoint = Double(map.bounds.width) / visible.width
        let centreLat = MKMapPoint(x: visible.midX, y: visible.midY).coordinate.latitude
        let metresPerPoint = MKMetersPerMapPointAtLatitude(centreLat) / pointsPerMapPoint
        let halfWidth = FogVeilRenderer.haloHalfWidth(metresPerPoint: metresPerPoint) / metresPerPoint
        let feather = halfWidth * Self.featherRatio
        let lod = FogVeilRenderer.lod(for: MKZoomScale(pointsPerMapPoint))
        let chunks = mesh.chunks[lod] ?? []

        // Отсечение с запасом на коридор: кусок, чьи отрезки лежат за краем
        // экрана, всё равно красит его своим ореолом.
        let pad = (halfWidth + feather) / pointsPerMapPoint
        let needed = visible.insetBy(dx: -pad, dy: -pad)

        encodeCoverage(chunks: chunks, needed: needed, frame: frame, rect: visible,
                       halfWidth: halfWidth, feather: feather, into: buffer, device: device)
        encodeComposite(pass: pass, into: buffer)

        buffer.present(drawable)
        buffer.commit()
        encodeSeconds += CACurrentMediaTime() - started
        // Цена кодирования на процессоре — то единственное число, ради
        // которого кадр и меряется. Раз в сто двадцать кадров, чтобы
        // сам замер не стоил дороже.
        if frames % 120 == 0 {
            let perFrame = String(format: "%.2f", encodeSeconds / Double(frames) * 1000)
            let line = "метал-туман: \(frames) кадров, кодирование \(perFrame) мс/кадр"
            Self.log.notice("\(line, privacy: .public)")
        }
    }

    private func encodeCoverage(
        chunks: [FogChunk], needed: MKMapRect, frame: VeilFrame, rect: MKMapRect,
        halfWidth: Double, feather: Double, into buffer: MTLCommandBuffer, device: MTLDevice
    ) {
        guard let texture = coverageTexture(device: device) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(coveragePipeline)

        let viewport = SIMD2<Float>(Float(bounds.width), Float(bounds.height))
        let m = SIMD4<Float>(Float(frame.a), Float(frame.b), Float(frame.c), Float(frame.d))
        for chunk in chunks where chunk.rect.intersects(needed) {
            // Сдвиг куска считается в DOUBLE и только потом опускается до
            // float: в этом и весь смысл отдельного угла у каждого куска.
            let dx = chunk.origin.x - rect.minX
            let dy = chunk.origin.y - rect.minY
            var uniforms = Uniforms(
                m: m,
                translation: SIMD2<Float>(
                    Float(Double(frame.origin.x) + Double(frame.a) * dx + Double(frame.c) * dy),
                    Float(Double(frame.origin.y) + Double(frame.b) * dx + Double(frame.d) * dy)),
                viewport: viewport,
                halfWidth: Float(halfWidth),
                feather: Float(feather))
            encoder.setVertexBuffer(chunk.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: chunk.count)
        }
        encoder.endEncoding()
    }

    private func encodeComposite(pass: MTLRenderPassDescriptor, into buffer: MTLCommandBuffer) {
        guard let texture = coverage,
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(texture, index: 0)
        var composite = Self.composite(palette: FogVeilPainter.palette)
        encoder.setFragmentBytes(&composite, length: MemoryLayout<Composite>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Цвет и сила мглы — из палитры кисти, чтобы метал шёл за темой так же,
    /// как растровая вуаль.
    private static func composite(palette: FogVeilPainter.Palette) -> Composite {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = palette.top.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Composite(colour: SIMD4<Float>(Float(r), Float(g), Float(b), 1),
                         alpha: Float(palette.alpha))
    }

    private func coverageTexture(device: MTLDevice) -> MTLTexture? {
        let width = max(1, Int(drawableSize.width))
        let height = max(1, Int(drawableSize.height))
        if let texture = coverage, texture.width == width, texture.height == height {
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        coverage = device.makeTexture(descriptor: descriptor)
        if coverage == nil { Self.log.notice("метал-туман: текстура покрытия не создалась") }
        return coverage
    }
}
