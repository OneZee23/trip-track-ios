import CoreGraphics
import MapKit
import Metal

/// Туман без экрана: тем же кодом, что рисует «Атлас», — в картинку.
///
/// Нужен он двоим. Постеру «Поделиться»: правило 0.7.0 «постер рисует туман
/// ТЕМ ЖЕ кодом, что экран» Metal не отменяет, а `MKMapSnapshotter` оверлеев
/// не рисует — значит снимок накрывается этой картинкой. И пиксельным
/// сторожам: свойства эталонной картинки (центр коридора открыт, стыки без
/// бусин, пустой слой ровен, Float32 не дрожит) не выражаются ни
/// возвращаемым значением, ни состоянием — только пикселем.
///
/// Матрица кадра здесь без поворота: прямоугольник карты ложится в картинку
/// как есть. Всё остальное — метры на точку, полуширина ореола, перо,
/// уровень детали — считается теми же функциями, что на экране, и уезжает в
/// тот же `FogFrameEncoder`.
enum FogOffscreen {

    /// Параметры кадра для прямоугольника карты, положенного в картинку без
    /// поворота. Чистая: тест ширины спрашивает её, ничего не рисуя.
    static func params(rect: MKMapRect, sizePoints: CGSize, scale: CGFloat,
                       palette: FogVeilPainter.Palette) -> FogFrameParams? {
        guard rect.width > 0, rect.height > 0, scale > 0,
              let frame = VeilFrame(
                p00: .zero,
                p10: CGPoint(x: sizePoints.width, y: 0),
                p01: CGPoint(x: 0, y: sizePoints.height),
                // «Своя единица» кадра здесь — точка КАРТЫ: матрица переводит
                // смещения от угла прямоугольника в точки картинки, ровно как
                // на экране.
                size: CGSize(width: rect.width, height: rect.height))
        else { return nil }

        let pointsPerMapPoint = Double(sizePoints.width) / rect.width
        let centreLat = MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude
        let metresPerPoint = MKMetersPerMapPointAtLatitude(centreLat) / pointsPerMapPoint
        let halfWidth = FogVeilRenderer.haloHalfWidth(metresPerPoint: metresPerPoint) / metresPerPoint
        return FogFrameParams(
            frame: frame,
            visible: rect,
            viewportPoints: sizePoints,
            drawableSize: CGSize(width: sizePoints.width * scale,
                                 height: sizePoints.height * scale),
            halfWidthPoints: halfWidth,
            featherPoints: halfWidth * FogMetalVeil.featherRatio,
            lod: FogVeilRenderer.lod(for: MKZoomScale(pointsPerMapPoint)),
            palette: palette)
    }

    /// Картинка с премультиплицированной альфой: открытое прозрачно, мгла
    /// непрозрачна на `palette.alpha`. `nil` — Metal недоступен; зовущий
    /// возвращается к `FogVeilBitmap.render`.
    static func render(layer: RevealedLayer, rect: MKMapRect, sizePoints: CGSize,
                       scale: CGFloat, palette: FogVeilPainter.Palette) -> CGImage? {
        guard let params = params(rect: rect, sizePoints: sizePoints, scale: scale,
                                  palette: palette),
              let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let encoder = FogFrameEncoder(device: device) else { return nil }

        let width = max(1, Int(params.drawableSize.width.rounded()))
        let height = max(1, Int(params.drawableSize.height.rounded()))
        guard let coverage = FogFrameEncoder.makeCoverageTexture(
            device: device, width: width, height: height) else { return nil }

        // Цель — `.shared`: с неё читает процессор, и работает это и на
        // симуляторе, и на устройстве. Экранной вуали такая текстура не нужна
        // вовсе: там цель отдаёт сам `MTKView`.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: FogFrameEncoder.targetFormat, width: width, height: height,
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor),
              let buffer = queue.makeCommandBuffer() else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        encoder.encode(mesh: FogMesh.build(layer: layer, device: device), params: params,
                       coverage: coverage, target: pass, into: buffer)
        buffer.commit()
        // Экрана здесь нет, ждать кадра некому — читаем сразу, как только GPU
        // отработал.
        buffer.waitUntilCompleted()
        return image(from: target)
    }

    /// `bgra8Unorm` в памяти лежит как B, G, R, A — то есть для CoreGraphics
    /// это «альфа первой, порядок байт обратный».
    private static func image(from texture: MTLTexture) -> CGImage? {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(base, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                             mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: texture.width, height: texture.height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
