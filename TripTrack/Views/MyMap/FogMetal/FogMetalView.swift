import MapKit
import MetalKit
import UIKit
import simd
import os

/// Метал-туман «Атласа» — спайк.
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
/// постера. Спайк отвечает на один вопрос — как туман ведёт себя под пальцем.
@MainActor
final class FogMetalView: MTKView {
    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "fogmetal")

    /// Ширина пера — доля полуширины коридора. Та же мягкость, что у кисти
    /// растра, только считается на GPU в каждом кадре.
    static let featherRatio: Double = 0.4

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

    /// Последний нарисованный кадр: прямоугольник карты и три его угла на
    /// экране. Совпало — GPU не трогаем вовсе, иначе на стоящей карте мы жгли
    /// бы батарею сто двадцать раз в секунду.
    private var lastRect: MKMapRect?
    private var lastCorners: [CGPoint] = []

    /// Сколько кадров нарисовано и сколько времени ушло на кодирование — для
    /// замера «сколько это стоит процессору».
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
    /// зовущий остаётся на растровой вуали, как будто спайка нет.
    ///
    /// Фабрикой, а не `init?()`: у `UIView` свой непроваливающийся `init()`,
    /// и переопределить его провальным Swift не даёт.
    static func make() -> FogMetalView? {
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
        return FogMetalView(device: device, queue: queue, coverage: first, composite: second)
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
                self.redrawIfNeeded()
            }
        }
    }

    // MARK: Жизнь

    func attach(map: MKMapView) {
        self.map = map
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func detach() {
        link?.invalidate()
        link = nil
        map = nil
        coverage = nil
    }

    @objc private func tick() { redrawIfNeeded() }

    override func layoutSubviews() {
        super.layoutSubviews()
        meshDirty = true
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

    override func draw(_ rect: CGRect) {
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
        // растровой вуали: спайк обязан показывать ТУ ЖЕ ширину открытого, а
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
        frames += 1
        encodeSeconds += CACurrentMediaTime() - started
        // Цена кодирования на процессоре — то единственное число, ради
        // которого спайк вообще меряется. Раз в сто двадцать кадров, чтобы
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

    /// Цвет и сила мглы — из палитры кисти, чтобы спайк шёл за темой так же,
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
