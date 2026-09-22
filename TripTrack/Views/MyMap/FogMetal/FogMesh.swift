import MapKit
import Metal
import simd

/// Один отрезок открытого пути так, как его видит GPU.
///
/// Точки — СМЕЩЕНИЯ от угла своего куска, а не сами точки карты. В этом весь
/// фокус с точностью: абсолютная точка карты доходит до 2.7e8, а float32 несёт
/// около семи значащих цифр — то есть на улице коридор дрожал бы метрами. В
/// пределах куска (≈5 км) смещение укладывается в миллиметры.
struct FogSegment {
    var p0: SIMD2<Float>
    var p1: SIMD2<Float>
}

/// Кусок открытого мира — квадрат сетки 32768 точек карты (≈5 км) со своими
/// отрезками в одном буфере. Отсекается целиком, рисуется одним instanced-
/// вызовом.
final class FogChunk {
    /// Угол квадрата сетки: от него отсчитываются смещения в буфере.
    let origin: MKMapPoint
    /// Настоящие границы отрезков куска — по ним идёт отсечение.
    let rect: MKMapRect
    let count: Int
    let buffer: MTLBuffer

    init(origin: MKMapPoint, rect: MKMapRect, count: Int, buffer: MTLBuffer) {
        self.origin = origin
        self.rect = rect
        self.count = count
        self.buffer = buffer
    }
}

/// Буферы GPU на весь открытый мир — по куску на квадрат сетки, по набору на
/// уровень детали.
///
/// Иммутабельна: собирается вне главного потока и подменяется целиком. Никакой
/// дозаписи в живой буфер — кадр может идти прямо сейчас.
struct FogMesh {
    let chunks: [RevealedLayer.LOD: [FogChunk]]

    static let empty = FogMesh(chunks: [:])

    var isEmpty: Bool { chunks.values.allSatisfy(\.isEmpty) }

    var segmentCount: Int { chunks.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } } }

    /// Сторона квадрата сетки в точках карты. 32768 — это ≈5 км на экваторе:
    /// достаточно мелко, чтобы отсечение выбрасывало почти весь мир, и
    /// достаточно крупно, чтобы у зрелой библиотеки не набежали тысячи
    /// вызовов отрисовки.
    static let chunkSize: Double = 32768

    /// Чем узнаётся уже собранный слой — тот же приём, что у `FogVeilView`:
    /// полилинии пересоздаются только вместе со слоем.
    static func signature(of layer: RevealedLayer) -> [ObjectIdentifier] {
        layer.polylines(for: .fine).map(ObjectIdentifier.init)
    }

    /// Собирает буферы. Зовётся ВНЕ главного потока: у зрелой библиотеки это
    /// сотни тысяч отрезков.
    static func build(layer: RevealedLayer, device: MTLDevice) -> FogMesh {
        var chunks: [RevealedLayer.LOD: [FogChunk]] = [:]
        for lod in RevealedLayer.LOD.allCases {
            chunks[lod] = build(polylines: layer.polylines(for: lod), device: device)
        }
        return FogMesh(chunks: chunks)
    }

    private static func build(polylines: [MKPolyline], device: MTLDevice) -> [FogChunk] {
        /// Отрезки, разложенные по квадратам сетки. Ключ — целочисленные
        /// координаты квадрата, а не geohash: арифметика та же, а строк не
        /// заводится ни одной.
        var buckets: [SIMD2<Int32>: [FogSegment]] = [:]
        var bounds: [SIMD2<Int32>: MKMapRect] = [:]

        for line in polylines where line.pointCount > 1 {
            let points = line.points()
            for i in 0..<(line.pointCount - 1) {
                let a = points[i], b = points[i + 1]
                // Квадрат выбирается по СЕРЕДИНЕ отрезка: так отрезок,
                // легший ровно на границу сетки, не прыгает между соседями от
                // округления его начала.
                let key = SIMD2<Int32>(
                    Int32(floor((a.x + b.x) / 2 / chunkSize)),
                    Int32(floor((a.y + b.y) / 2 / chunkSize))
                )
                let origin = MKMapPoint(x: Double(key.x) * chunkSize,
                                        y: Double(key.y) * chunkSize)
                buckets[key, default: []].append(FogSegment(
                    p0: SIMD2<Float>(Float(a.x - origin.x), Float(a.y - origin.y)),
                    p1: SIMD2<Float>(Float(b.x - origin.x), Float(b.y - origin.y))
                ))
                let box = MKMapRect(
                    x: min(a.x, b.x), y: min(a.y, b.y),
                    width: max(abs(a.x - b.x), 1), height: max(abs(a.y - b.y), 1))
                bounds[key] = bounds[key].map { $0.union(box) } ?? box
            }
        }

        var built: [FogChunk] = []
        built.reserveCapacity(buckets.count)
        for (key, segments) in buckets {
            guard let rect = bounds[key], !segments.isEmpty else { continue }
            let length = MemoryLayout<FogSegment>.stride * segments.count
            guard let buffer = segments.withUnsafeBytes({
                device.makeBuffer(bytes: $0.baseAddress!, length: length, options: .storageModeShared)
            }) else { continue }
            built.append(FogChunk(
                origin: MKMapPoint(x: Double(key.x) * chunkSize, y: Double(key.y) * chunkSize),
                rect: rect, count: segments.count, buffer: buffer))
        }
        return built
    }
}
