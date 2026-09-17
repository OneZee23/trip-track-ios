import XCTest
import CoreGraphics
@testable import TripTrack

/// Текстура облаков — один тайл на весь мир, и держат её два свойства.
///
/// **Бесшовность.** Кисть рисует туман кусками (тайл, полоса, целая
/// картинка), а узор кладётся на МИРОВУЮ сетку: значит, соседние ячейки
/// сетки стыкуются краями, и шов шириной в тексель ляжет линией через весь
/// экран. Увидеть его на картинке 512×512 глазами нельзя — только счётом.
///
/// **Детерминированность.** Постер обязан нарисовать тот же туман, что
/// экран, а второй телефон — тот же, что первый. Сид взят числом, а не у
/// часов, и это правило проверяется здесь, потому что нарушить его можно
/// одной строкой, и никто не заметит.
final class CloudTextureTests: XCTestCase {

    // MARK: Бесшовность

    /// Узор ПЕРИОДИЧЕН по стороне тайла: тексель за правым краем — это тексель
    /// у левого. На этом стоит стыковка ячеек мировой сетки.
    func testTextureWrapsAtItsOwnEdge() {
        let size = CloudTexture.size
        for y in stride(from: 0, to: size, by: 7) {
            XCTAssertEqual(CloudTexture.sample(x: 0, y: y),
                           CloudTexture.sample(x: size, y: y),
                           "столбец за правым краем обязан повторить левый (y = \(y))")
            XCTAssertEqual(CloudTexture.sample(x: y, y: 0),
                           CloudTexture.sample(x: y, y: size),
                           "ряд за нижним краем обязан повторить верхний (x = \(y))")
        }
    }

    /// И — отдельно — на самом шве нет СТУПЕНИ: значение у последнего столбца
    /// отличается от первого не сильнее, чем у любых двух соседних столбцов.
    ///
    /// Периодичности одной мало: функция, периодичная по единице, но рвущаяся
    /// на границе периода, даёт ровно ту же линию через экран.
    func testTheWrapIsNotAStep() {
        let size = CloudTexture.size
        var seam = 0.0
        var inside = 0.0
        for y in 0..<size {
            seam += abs(Double(CloudTexture.sample(x: size - 1, y: y))
                        - Double(CloudTexture.sample(x: 0, y: y)))
            inside += abs(Double(CloudTexture.sample(x: size / 2, y: y))
                          - Double(CloudTexture.sample(x: size / 2 + 1, y: y)))
        }
        let seamMean = seam / Double(size)
        let insideMean = inside / Double(size)
        print(String(format: "[clouds] шов %.3f уровня, обычная пара соседей %.3f",
                     seamMean, insideMean))
        XCTAssertLessThan(seamMean, max(insideMean * 3, 1.5),
                          "на шве тайла узор рвётся — значит по карте пойдёт линия")
    }

    // MARK: Детерминированность

    /// Две сборки подряд дают байт в байт одно и то же.
    func testNoiseIsDeterministic() {
        let first = CloudTexture.noise()
        let second = CloudTexture.noise()
        XCTAssertEqual(first, second, "шум обязан зависеть только от сида")
        XCTAssertEqual(first.count, CloudTexture.size * CloudTexture.size)
    }

    /// И сид записан числом, а не взят у часов: замороженный вектор.
    ///
    /// Три текселя и контрольная сумма всего тайла: цель — поймать смену
    /// формулы или сида в диффе, а не сравнивать 262 144 байта глазами.
    func testFrozenSamples() {
        let noise = CloudTexture.noise()
        let checksum = noise.reduce(0) { ($0 &* 31 &+ UInt32($1)) & 0xFFFF_FFFF }
        XCTAssertEqual(CloudTexture.sample(x: 0, y: 0), 40)
        XCTAssertEqual(CloudTexture.sample(x: 128, y: 384), 132)
        XCTAssertEqual(CloudTexture.sample(x: 511, y: 511), 41)
        XCTAssertEqual(checksum, 1_396_163_471,
                       "формула или сид облаков изменились — постер разойдётся с экраном")
        // Один и тот же шум, пройденный двумя путями: тексель картинки обязан
        // совпасть с чистой функцией, иначе замороженный вектор охраняет не то.
        XCTAssertEqual(noise[384 * CloudTexture.size + 128],
                       CloudTexture.sample(x: 128, y: 384))
    }

    /// Размах шума занимает заметную часть шкалы: fBm, схлопнувшийся в узкую
    /// полосу вокруг середины, — это ровная заливка, а не облака.
    func testNoiseUsesItsRange() {
        let noise = CloudTexture.noise()
        let low = noise.min() ?? 0
        let high = noise.max() ?? 0
        print("[clouds] размах шума \(low)…\(high)")
        XCTAssertLessThan(Int(low), 90, "самое светлое облако слишком тёмное")
        XCTAssertGreaterThan(Int(high), 165, "самое тёмное облако слишком светлое")
    }

    // MARK: Картинки

    /// Обе картинки собираются, и каждая — своей природы: плотность
    /// непрозрачная (её накладывают умножением), маска несёт альфу (ею
    /// режется перьевая лента).
    func testBothImagesAreBuiltFromTheSameNoise() throws {
        let images = try XCTUnwrap(CloudTexture.images(from: CloudTexture.noise()))
        XCTAssertEqual(images.density.width, CloudTexture.size)
        XCTAssertEqual(images.mask.width, CloudTexture.size)
        XCTAssertEqual(images.density.alphaInfo, .premultipliedLast,
                       "облако догущает мглу своей альфой, а не красит её цветом")
        XCTAssertEqual(images.mask.alphaInfo, .premultipliedLast,
                       "маска края живёт своей альфой")
    }

    /// Облако догущает мглу ровно до верхней границы и ни на уровень выше.
    ///
    /// С «ночной карты» облака лепят НЕПРОЗРАЧНОСТЬ, а не цвет: туман
    /// заливается на `opacityRange.lowerBound`, текстура кладётся поверх тем
    /// же тоном, и вместе они обязаны дать `upperBound`. Проверяется
    /// арифметика композиции, а не картинка: ошибка здесь — это мгла, сквозь
    /// которую не видно карту, то есть ровно то, что владелец назвал игровой
    /// доской.
    func testCloudTopUpLandsOnTheUpperBound() {
        let low = CloudTexture.opacityRange.lowerBound
        let composed = low + (1 - low) * CloudTexture.cloudTopUp
        XCTAssertEqual(composed, CloudTexture.opacityRange.upperBound, accuracy: 1e-9)
        XCTAssertLessThan(CloudTexture.opacityRange.upperBound, 0.85,
                          "сквозь туман обязана быть видна настоящая карта")
    }

    /// `prepare` идемпотентна и отдаёт те же картинки — её зовут из трёх
    /// фоновых мест сразу (рендерер, вуаль, постер), и вторая сборка стоила бы
    /// сотни миллисекунд на ровном месте.
    func testPrepareIsIdempotent() throws {
        let first = try XCTUnwrap(CloudTexture.shared.prepare())
        let second = try XCTUnwrap(CloudTexture.shared.prepare())
        XCTAssertTrue(first.density === second.density)
        XCTAssertTrue(first.mask === second.mask)
    }

    // MARK: - Диск

    /// Круглый путь через дисковый кэш (запись → PNG → чтение) обязан вернуть
    /// шум байт в байт. Кэш — 8-битный серый PNG, и гамма или цветовой профиль
    /// на нём молча сдвинули бы значение: второй запуск (кэш тёплый) нарисовал
    /// бы чуть другие облака, чем первый (кэша ещё нет), — а постер обещает
    /// «тот же туман, что экран» именно на такой паре запусков.
    func testDiskCacheRoundTripIsByteEqual() throws {
        let noise = CloudTexture.noise()
        CloudTexture.writeCache(noise)
        let cached = try XCTUnwrap(CloudTexture.cachedNoise(), "кэш не прочитался с диска")
        XCTAssertEqual(cached, noise, "круглый путь через PNG обязан вернуть тот же шум")
    }
}
