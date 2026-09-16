import UIKit
import CoreGraphics
import os

/// Облака тумана — ОДИН бесшовный тайл шума, из которого берутся обе половины
/// «клубящегося»: неровности плотности на заливке и рваный край коридора.
///
/// Почему один тайл, а не шум на лету. Кисть рисует туман кусками (тайл у
/// плиточного рендерера, полоса у растра, целая картинка у постера), и узор
/// обязан совпасть на их общих границах пиксель в пиксель. Считать шум в
/// каждом пикселе значило бы платить за это миллионами вызовов на кадр;
/// положить текстуру на МИРОВУЮ сетку (период — `FogVeilRenderer.hazeCell`,
/// как у дымки) значит получить и бесшовность, и неподвижность при панораме
/// даром: два соседа считают положение узора от одних и тех же мировых
/// координат, а не от своих.
///
/// Почему fBm, а не одна октава: у одной октавы виден период решётки, и туман
/// читается как обои. Четыре октавы дают крупные клубы с мелкой рванью по
/// краю — то, что владелец назвал «тёмные облака с текстурой».
///
/// Движения у облаков нет: один кадр растра стоит десятки миллисекунд, а
/// анимация потребовала бы шестидесяти в секунду.
final class CloudTexture {
    static let shared = CloudTexture()

    /// Сторона тайла в текселях. 512: при периоде `hazeCell(.fine)` (≈ 3.4 км
    /// на широте Краснодара) это ~6.7 м на тексель, то есть на масштабе улицы
    /// клуб размером с двор. Меньше — узор становится виден решёткой, больше —
    /// растёт и время сборки, и вес картинки в памяти.
    static let size = 512
    /// Амплитуды октав. Не «каждая вдвое слабее предыдущей»: при чистом
    /// делении пополам вторая октава — половина, третья четверть, и на
    /// масштабе города клубы читались как ровный градиент. Первые ДВЕ подняты
    /// (1 и 0.8), мелочь придавлена — крупные комки видно, а рвань по краю
    /// коридора остаётся.
    static let octaveAmplitudes: [Double] = [1, 0.8, 0.3, 0.15]
    static var octaves: Int { octaveAmplitudes.count }
    /// Решётка первой октавы. Восемь ячеек на 512 текселей — 64 текселя на
    /// ячейку, то есть самый крупный клуб занимает восьмую часть тайла.
    static let baseLattice = 8
    /// Сид. Постоянный и записанный числом, а не взятый у часов: два телефона
    /// и постер обязаны нарисовать ОДИН И ТОТ ЖЕ туман, иначе картинка, которой
    /// человек делится, разъезжается с тем, что он видит.
    static let seed: UInt64 = 0x7472_6970_7472_6B31

    /// Множитель плотности заливки. Единица — туман как есть, нижняя граница —
    /// самое плотное место облака.
    ///
    /// 0.70. Стояло 0.86 — и это было верно ровно для почти чёрной вуали, на
    /// которой размах в 14 % упирался нижним краем в ноль. Тон тумана поднят
    /// (`FogVeilPainter.veilColorTop`), и теперь 30 % размаха — это разница в
    /// полтора десятка уровней RGB, то есть видимые комки, а не догадка.
    static let densityRange: ClosedRange<Double> = 0.70...1.0

    /// Сколько прожигания остаётся в самом «плотном» месте перьевой ленты.
    ///
    /// Четверть. Мерено тем же тестом, что держит рваность
    /// (`FogVeilPainterTests.testCorridorEdgeIsRaggedOnlyWithClouds`): при 0.40
    /// размах плотности вдоль прямой дороги — 17 уровней из 255, то есть
    /// семь процентов, и на почти чёрной вуали край по-прежнему читается
    /// линией. При 0.25 — около сорока, и край начинает клубиться. Ниже
    /// опускать нельзя: в ленте появляются острова тумана, оторванные от
    /// берега, и «открыто» перестаёт быть связным.
    static let edgeKeepRange: ClosedRange<Double> = 0.25...1.0

    /// Имя файла кэша. Версия в имени, а не в содержимом: поменялась формула —
    /// поменялось имя, и старый файл просто перестаёт открываться.
    static let cacheName = "cloud-v1.png"

    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "clouds")

    /// Две картинки из одного шума: `density` кладётся на заливку в режиме
    /// умножения (поэтому непрозрачная серая), `mask` — на перьевую ленту
    /// коридора в режиме `.destinationIn` (поэтому важен её АЛЬФА-канал).
    struct Images {
        let density: CGImage
        let mask: CGImage
    }

    private let lock = NSLock()
    private var images: Images?

    private init() {}

    /// Готовые картинки — или `nil`, если текстуру ещё никто не собрал.
    ///
    /// До готовности кисть рисует туман БЕЗ облаков и с геометрическим краем:
    /// это честный промежуточный кадр, а не дыра. Ждать здесь нельзя — зовут
    /// это потоки отрисовки MapKit.
    var ready: Images? {
        lock.lock(); defer { lock.unlock() }
        return images
    }

    /// Собрать, если ещё не собрано. Зовётся С ФОНОВОГО потока (сборка
    /// рендерера, сборка индекса вуали, постер) и блокирует ровно того, кто
    /// позвал: класть её в свою очередь значило бы рисовать первый кадр без
    /// облаков даже там, где ждать было некому.
    @discardableResult
    func prepare() -> Images? {
        lock.lock()
        if let images { lock.unlock(); return images }
        lock.unlock()

        let noise = Self.cachedNoise() ?? {
            let fresh = Self.noise()
            Self.writeCache(fresh)
            return fresh
        }()
        guard let built = Self.images(from: noise) else { return nil }

        lock.lock()
        // Гонка двух фоновых сборок безвредна: шум детерминирован, и обе
        // положили бы одинаковые картинки. Двойная цена (~100 мс fBm ещё раз)
        // принята сознательно: сериализовать два фоновых потока одним замком
        // значило бы держать одного из них в очереди на самом кадре, которого
        // ждёт человек, — дороже, чем посчитать дважды.
        if images == nil { images = built }
        let out = images
        lock.unlock()
        return out
    }

    /// Только для теста: забыть собранное.
    func forget() {
        lock.lock(); images = nil; lock.unlock()
    }

    // MARK: - Шум

    /// Значение fBm в долях тайла. ПЕРИОДИЧНО по единице: `value(u: 0) ==
    /// value(u: 1)`, и на этом стоит вся бесшовность.
    ///
    /// Чистая функция: и период, и детерминированность проверяются только
    /// счётом — на картинке 512×512 шов шириной в тексель не виден глазами, а
    /// на карте он ложится линией через весь экран.
    static func value(u: Double, v: Double) -> Double {
        var sum = 0.0
        var total = 0.0
        var lattice = baseLattice
        for (index, amplitude) in octaveAmplitudes.enumerated() {
            sum += amplitude * octave(u: u, v: v, lattice: lattice, index: index)
            total += amplitude
            lattice *= 2
        }
        return total > 0 ? sum / total : 0
    }

    /// Тексель тайла — те же байты, что лежат в картинке. Индексы берутся по
    /// модулю, поэтому `sample(x: 0) == sample(x: size)`.
    static func sample(x: Int, y: Int) -> UInt8 {
        let v = value(u: Double(x) / Double(size), v: Double(y) / Double(size))
        return UInt8(max(0, min(255, (v * 255).rounded())))
    }

    /// Весь тайл одним проходом.
    static func noise() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            let v = Double(y) / Double(size)
            for x in 0..<size {
                let n = value(u: Double(x) / Double(size), v: v)
                out[y * size + x] = UInt8(max(0, min(255, (n * 255).rounded())))
            }
        }
        return out
    }

    /// Одна октава значения-шума на решётке `lattice`, замкнутой в кольцо.
    ///
    /// Замыкание — это `% lattice` в обращении к узлам: узел решётки за правым
    /// краем тайла обязан быть тем же, что за левым, иначе тайл перестаёт
    /// стыковаться сам с собой.
    private static func octave(u: Double, v: Double, lattice: Int, index: Int) -> Double {
        let x = u * Double(lattice)
        let y = v * Double(lattice)
        let x0 = Int(x.rounded(.down))
        let y0 = Int(y.rounded(.down))
        let fx = smooth(x - Double(x0))
        let fy = smooth(y - Double(y0))
        let a = corner(x0, y0, lattice, index)
        let b = corner(x0 + 1, y0, lattice, index)
        let c = corner(x0, y0 + 1, lattice, index)
        let d = corner(x0 + 1, y0 + 1, lattice, index)
        let top = a + (b - a) * fx
        let bottom = c + (d - c) * fx
        return top + (bottom - top) * fy
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    private static func corner(_ i: Int, _ j: Int, _ lattice: Int, _ index: Int) -> Double {
        let x = ((i % lattice) + lattice) % lattice
        let y = ((j % lattice) + lattice) % lattice
        var z = seed &+ UInt64(bitPattern: Int64(x) &* 374_761_393
                                &+ Int64(y) &* 668_265_263
                                &+ Int64(index) &* 2_246_822_519)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z % 1_000_000) / 1_000_000
    }

    // MARK: - Картинки

    /// Обе картинки из одних байтов шума.
    static func images(from noise: [UInt8]) -> Images? {
        guard noise.count == size * size else { return nil }
        guard let density = grayImage(from: noise, range: densityRange),
              let mask = alphaImage(from: noise, range: edgeKeepRange) else { return nil }
        return Images(density: density, mask: mask)
    }

    /// Непрозрачный серый: умножение на него и есть «множитель плотности».
    private static func grayImage(from noise: [UInt8], range: ClosedRange<Double>) -> CGImage? {
        let span = range.upperBound - range.lowerBound
        var bytes = [UInt8](repeating: 0, count: size * size)
        for i in 0..<noise.count {
            let level = range.lowerBound + span * Double(noise[i]) / 255
            bytes[i] = UInt8(max(0, min(255, (level * 255).rounded())))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Чёрный с переменной альфой: `.destinationIn` оставляет от прожжённого
    /// ровно её долю.
    private static func alphaImage(from noise: [UInt8], range: ClosedRange<Double>) -> CGImage? {
        let span = range.upperBound - range.lowerBound
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<noise.count {
            let keep = range.lowerBound + span * Double(noise[i]) / 255
            // Премультиплицированный чёрный: RGB нули, значение несёт альфа.
            bytes[i * 4 + 3] = UInt8(max(0, min(255, (keep * 255).rounded())))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: - Кэш

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheName)
    }

    /// Шум с диска. Кладётся в `Caches/`, а не в `Documents/`: система вправе
    /// его стереть, и это ничего не ломает — следующий запуск пересчитает.
    ///
    /// Не `private`: `CloudTextureTests` зовёт её вместе с `writeCache`
    /// напрямую, чтобы проверить круглый путь через PNG байт в байт — гамма
    /// или цветовой профиль на нём сдвинули бы серое значение молча.
    static func cachedNoise() -> [UInt8]? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let source = UIImage(data: data)?.cgImage,
              source.width == size, source.height == size else { return nil }
        var bytes = [UInt8](repeating: 0, count: size * size)
        let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return ok ? bytes : nil
    }

    static func writeCache(_ noise: [UInt8]) {
        guard let url = cacheURL, let image = grayImage(from: noise, range: 0...1),
              let data = UIImage(cgImage: image).pngData() else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Не беда: следующий запуск пересчитает шум за те же сто
            // миллисекунд в фоне. Молчать всё же нельзя — если кэш не пишется
            // НИКОГДА, эти сто миллисекунд платятся на каждом запуске.
            log.notice("кэш облаков не записался: \(error.localizedDescription, privacy: .public)")
        }
    }
}
