import MapKit
import Metal
import UIKit
import simd

/// Всё, что нужно знать, чтобы нарисовать ОДИН кадр тумана, — и ничего сверх
/// того.
///
/// Тип существует ради единственного правила: картинка на экране и картинка
/// постера обязаны получиться ОДНОЙ. Пока кадр собирался прямо в `draw(_:)`,
/// офскрину пришлось бы повторить пять формул подряд — матрицу, метры на
/// точку, полуширину ореола, перо и уровень детали, — и разойтись они могли
/// бы молча, как разошлись когда-то два счёта открытых километров. Здесь
/// зовущие приносят разные матрицы и получают одни и те же правила.
struct FogFrameParams {
    /// Матрица «смещение в точках карты → точки экрана».
    let frame: VeilFrame
    /// Прямоугольник карты, который рисуем: от его угла отсчитываются
    /// смещения кусков.
    let visible: MKMapRect
    /// Размер кадра в ТОЧКАХ. В них же считаются ширины коридора, поэтому
    /// это не пиксели.
    let viewportPoints: CGSize
    /// Размер цели в ПИКСЕЛЯХ — по нему заводится текстура покрытия. Сам
    /// энкодер его не читает: текстуру приносит зовущий (экранная вуаль её
    /// кэширует, офскрин создаёт на кадр), а число живёт здесь, чтобы обе
    /// стороны считали его одинаково.
    let drawableSize: CGSize
    /// Полуширина коридора в точках экрана — `FogVeilRenderer.haloHalfWidth`,
    /// делённая на метры в точке.
    let halfWidthPoints: Double
    /// Перо — `FogMetalVeil.featherRatio` от полуширины.
    let featherPoints: Double
    let lod: RevealedLayer.LOD
    let palette: FogVeilPainter.Palette
    /// Окно под подписью Apple. `nil` — выреза нет, и композит выходит байт в
    /// байт таким же, каким был до 0.8.0: у светлой темы окна не бывает вовсе
    /// (`AttributionCarve.carves(palette:)`), а решает это ХОСТ, как и у
    /// растровой вуали.
    let carve: FogCarveWindow?
}

/// Два прохода Metal-тумана: покрытие открытого и композит мглы.
///
/// Здесь и только здесь живёт математика эталонной картинки 0.8.0 (спека
/// §3). Экранная вуаль и офскрин зовут ОДИН `encode` — иначе постер начал бы
/// показывать не то, что человек видел на экране, и заметить это было бы
/// нечем.
final class FogFrameEncoder {

    /// Совпадать с `FogUniforms` в шейдере байт в байт.
    private struct Uniforms {
        var m: SIMD4<Float>
        var translation: SIMD2<Float>
        var viewport: SIMD2<Float>
        var halfWidth: Float
        var feather: Float
    }

    /// Совпадать с `FogCarve` в шейдере байт в байт: `float4` выравнивается
    /// на шестнадцать, три хвостовых `float` ложатся за ним подряд.
    private struct Carve {
        /// Коробка окна в точках вида: x, y, ширина, высота.
        var rect: SIMD4<Float>
        var corner: Float
        var feather: Float
        var floor: Float
        /// Ноль — окна нет; шейдер тогда не трогает альфу вовсе.
        var enabled: Float
    }

    /// Совпадать с `FogComposite` в шейдере байт в байт.
    private struct Composite {
        var colour: SIMD4<Float>
        var alpha: Float
        /// Размер вида в ТОЧКАХ — в них же задана коробка окна, и шейдеру
        /// нечем перевести свои `uv` в точки без этого числа.
        var viewport: SIMD2<Float>
        var carve: Carve
    }

    private let coveragePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState

    /// `nil` — шейдеры не собрались: зовущий остаётся на растровой вуали.
    init?(device: MTLDevice) {
        guard let library = device.makeDefaultLibrary() else { return nil }

        let coverage = MTLRenderPipelineDescriptor()
        coverage.vertexFunction = library.makeFunction(name: "fog_coverage_vertex")
        coverage.fragmentFunction = library.makeFunction(name: "fog_coverage_fragment")
        coverage.colorAttachments[0].pixelFormat = Self.coverageFormat
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
        composite.colorAttachments[0].pixelFormat = Self.targetFormat

        guard let first = try? device.makeRenderPipelineState(descriptor: coverage),
              let second = try? device.makeRenderPipelineState(descriptor: composite)
        else { return nil }
        coveragePipeline = first
        compositePipeline = second
    }

    /// Однобайтовое покрытие и четырёхбайтовая цель. Форматы перечислены
    /// здесь, потому что их обязаны совпасть трое: пайплайн, текстура
    /// экранной вуали и текстура офскрина.
    static let coverageFormat: MTLPixelFormat = .r8Unorm
    static let targetFormat: MTLPixelFormat = .bgra8Unorm

    /// Текстура покрытия. Заводит её зовущий, а описание лежит тут: экран
    /// кэширует свою между кадрами, офскрин создаёт на кадр, но описание у
    /// них обязано быть одно.
    static func makeCoverageTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: coverageFormat, width: max(1, width), height: max(1, height),
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }

    /// Кадр целиком: коридоры в покрытие, мгла поверх карты в цель.
    func encode(mesh: FogMesh, params: FogFrameParams, coverage: MTLTexture,
                target: MTLRenderPassDescriptor, into buffer: MTLCommandBuffer) {
        encodeCoverage(mesh: mesh, params: params, coverage: coverage, into: buffer)
        encodeComposite(params: params, coverage: coverage, target: target, into: buffer)
    }

    private func encodeCoverage(mesh: FogMesh, params: FogFrameParams,
                                coverage: MTLTexture, into buffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = coverage
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard params.viewportPoints.width > 0, params.visible.width > 0,
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(coveragePipeline)

        let frame = params.frame
        let rect = params.visible
        let viewport = SIMD2<Float>(Float(params.viewportPoints.width),
                                    Float(params.viewportPoints.height))
        let m = SIMD4<Float>(Float(frame.a), Float(frame.b), Float(frame.c), Float(frame.d))

        // Отсечение с запасом на коридор: кусок, чьи отрезки лежат за краем
        // кадра, всё равно красит его своим ореолом.
        let mapPointsPerPoint = rect.width / Double(params.viewportPoints.width)
        let pad = (params.halfWidthPoints + params.featherPoints) * mapPointsPerPoint
        let needed = rect.insetBy(dx: -pad, dy: -pad)

        for chunk in mesh.chunks[params.lod] ?? [] where chunk.rect.intersects(needed) {
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
                halfWidth: Float(params.halfWidthPoints),
                feather: Float(params.featherPoints))
            encoder.setVertexBuffer(chunk.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                                   instanceCount: chunk.count)
        }
        encoder.endEncoding()
    }

    private func encodeComposite(params: FogFrameParams, coverage: MTLTexture,
                                 target: MTLRenderPassDescriptor, into buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: target) else { return }
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setFragmentTexture(coverage, index: 0)
        var composite = Self.composite(params: params)
        encoder.setFragmentBytes(&composite, length: MemoryLayout<Composite>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Цвет и сила мглы — из палитры кисти, чтобы метал шёл за темой так же,
    /// как растровая вуаль. Плюс окно под подписью, если его дал хост.
    private static func composite(params: FogFrameParams) -> Composite {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = params.palette.top.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Composite(colour: SIMD4<Float>(Float(r), Float(g), Float(b), 1),
                         alpha: Float(params.palette.alpha),
                         viewport: SIMD2<Float>(Float(params.viewportPoints.width),
                                                Float(params.viewportPoints.height)),
                         carve: carve(params.carve))
    }

    /// Окна нет — в буфер уезжают нули с погашенным `enabled`, и композит
    /// остаётся тем же, каким был до выреза: множителя альфы не появляется.
    private static func carve(_ window: FogCarveWindow?) -> Carve {
        guard let window else {
            return Carve(rect: .zero, corner: 0, feather: 0, floor: 1, enabled: 0)
        }
        return Carve(
            rect: SIMD4<Float>(Float(window.rect.minX), Float(window.rect.minY),
                               Float(window.rect.width), Float(window.rect.height)),
            corner: Float(window.corner),
            feather: Float(window.feather),
            floor: Float(window.floor),
            enabled: 1)
    }
}
