import XCTest
import MapKit
import Metal
@testable import TripTrack

/// Окно под подписью Apple Maps в Metal-тумане.
///
/// Вопрос у него ровно один и он не про красоту: под ночной мглой (0.70)
/// тёмно-серая подпись «` Maps`» даёт контраст около 3:1, то есть не читается,
/// — а спрятать её нельзя (API нет, попытка рискует ревью). Мглу под ней
/// ПРИГЛУШАЮТ до половины силы; снимать её целиком уже пробовали, и владелец
/// дважды увидел под подписью светлую плашку (17 и 20 сентября). Числа —
/// общие с растровой маской (`AttributionCarve`), и проверяются они здесь
/// пикселем, потому что иначе не проверяются ничем: ни возвращаемым
/// значением, ни состоянием непрерывность спада не выражается.
///
/// Кто решает, БЫВАЕТ ли окно, — хост (`MyMapRepresentable`,
/// `AttributionCarve.carves(palette:)`), ровно как у растра: под бледной
/// дымкой светлой темы выреза нет вовсе. Шейдер этого не знает и не обязан —
/// он рисует то окно, которое ему дали, и проверка этого ниже отдельным
/// тестом.
@MainActor
final class FogMetalCarveTests: XCTestCase {
    private let size = CGSize(width: 300, height: 300)
    /// Три пикселя на точку, а не два. На спаде в шесть точек между двумя
    /// соседними пикселями лежит физически заметный кусок растушёвки, и чем
    /// мельче сетка, тем честнее вопрос «ступенька это или непрерывная
    /// функция»; дальше мельчить — это кадр в три тысячи пикселей ради одной
    /// строки профиля.
    private let scale: CGFloat = 3
    private let palette = FogVeilPainter.Palette.night

    /// Краснодар — та же точка, что у остальных пиксельных сторожей.
    private let krasnodar = MKMapPoint(
        CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97))

    /// Коробка примерно там же, где стоит настоящая подпись: у нижнего края,
    /// слева. Числа взяты руками — место подписи задаёт MapKit, а тесту важна
    /// геометрия окна, а не то, где именно Apple поставила логотип.
    private let box = CGRect(x: 40, y: 220, width: 120, height: 26)

    // MARK: Сторожа

    /// Середина окна — мгла на пол своей силы, за пером — мгла целая.
    func testWindowDimsToTheFloorAndIsWholeBeyondTheFeather() throws {
        let window = FogCarveWindow.attribution(rect: box)
        XCTAssertEqual(window.floor, AttributionCarve.windowFloor)
        XCTAssertEqual(window.feather, AttributionCarve.feather)
        XCTAssertEqual(window.corner, AttributionCarve.corner)

        let pixels = try render(carve: window)
        let midY = Double(box.midY)

        XCTAssertEqual(
            pixels.alpha(atX: Double(box.midX), y: midY),
            Double(palette.alpha) * Double(window.floor), accuracy: 1.0 / 255,
            "в середине окна мгла обязана остаться на полу, а не сняться совсем")
        XCTAssertEqual(
            pixels.alpha(atX: Double(box.maxX) + Double(window.feather) + 2, y: midY),
            Double(palette.alpha), accuracy: 1.0 / 255,
            "за пером окна мгла обязана быть ровно такой, какой её задала палитра")
    }

    /// Спад — непрерывная функция, а не кольца.
    ///
    /// Это та же поломка, которую растровая маска пережила 20 сентября:
    /// двадцать четыре сплошных кольца читались на устройстве не растушёвкой,
    /// а вторым прямоугольником с жёсткой кромкой (эффект Маха на границе
    /// между ступенями). Здесь проверяются три её признака сразу: альфа
    /// наружу не падает, обрыва нет ни на одном пикселе, и промежуточных
    /// значений на растушёвке много.
    ///
    /// Потолок шага задан ДОЛЕЙ амплитуды, а не числом вида «2/255»: у
    /// `smoothstep` на шести точках самый крутой участок идёт примерно на
    /// 0.0875 альфы за точку, то есть на трёх пикселях в точке одиннадцать
    /// двести пятьдесят пятых между соседями — это не ступенька, это сама
    /// функция, и требовать от неё двух двести пятьдесят пятых значило бы
    /// требовать кадр в три тысячи пикселей.
    func testWindowRampIsContinuous() throws {
        let window = FogCarveWindow.attribution(rect: box)
        let pixels = try render(carve: window)
        let midY = Double(box.midY)
        let step = 1 / Double(scale)

        var profile: [Double] = []
        var x = Double(box.midX)
        while x <= Double(box.maxX) + Double(window.feather) + 10 {
            profile.append(pixels.alpha(atX: x, y: midY))
            x += step
        }

        let amplitude = Double(palette.alpha) * (1 - Double(window.floor))
        for i in 1..<profile.count {
            XCTAssertGreaterThanOrEqual(
                profile[i], profile[i - 1] - 1.0 / 255,
                "наружу от окна мгла обязана густеть, а не редеть (пиксель \(i))")
            XCTAssertLessThanOrEqual(
                profile[i] - profile[i - 1], amplitude / 8,
                "обрыв на пикселе \(i) — это ступенька, а не растушёвка")
        }

        let lowest = Double(palette.alpha) * Double(window.floor)
        let inside = profile.filter { $0 > lowest + 2.0 / 255 && $0 < Double(palette.alpha) - 2.0 / 255 }
        XCTAssertGreaterThan(Set(inside.map { Int(($0 * 255).rounded()) }).count, 10,
                             "растушёвка обязана быть непрерывной, а не горстью широких ступеней")
    }

    /// Углы окна скруглены, а не срезаны прямым углом.
    ///
    /// По диагонали от угла коробки скруглённый прямоугольник отходит дальше,
    /// чем прямой: на той же диагонали, где у прямого угла мгла ещё
    /// приглушена, у скруглённого она уже целая. Иначе `corner` в уносимом на
    /// GPU буфере можно было бы обнулить и не заметить этого ничем.
    func testWindowCornersAreRounded() throws {
        let window = FogCarveWindow.attribution(rect: box)
        let pixels = try render(carve: window)
        // Точка снаружи угла по диагонали: от прямого угла до неё
        // `feather × 0.8` по каждой оси (то есть окно бы её ещё задело), от
        // скруглённого — заметно больше.
        let reach = Double(window.feather) * 0.8
        XCTAssertEqual(
            pixels.alpha(atX: Double(box.maxX) + reach, y: Double(box.maxY) + reach),
            Double(palette.alpha), accuracy: 1.0 / 255,
            "за скруглённым углом мгла обязана быть целой")
        // А по прямой от той же стороны на то же расстояние — ещё не целая:
        // иначе тест выше проходил бы и при выключенном окне.
        XCTAssertLessThan(
            pixels.alpha(atX: Double(box.maxX) + reach, y: Double(box.midY)),
            Double(palette.alpha) - 1.0 / 255,
            "по прямой от края окна на том же расстоянии мгла обязана быть ещё приглушена")
    }

    /// Без окна кадр остаётся ТЕМ ЖЕ, каким был до этой задачи.
    ///
    /// Эталон 0.8.0 (спека §3) меняться не имеет права, а вырез — это новое
    /// поле в буфере композита: погашенный `enabled` обязан значить «ничего
    /// не произошло», а не «окно нулевого размера в левом верхнем углу».
    func testWithoutAWindowTheFrameStaysFlat() throws {
        let pixels = try render(carve: nil)
        XCTAssertEqual(pixels.distinctPixels.count, 1,
                       "без окна пустой слой обязан дать РОВНО одну краску на весь кадр")
        XCTAssertEqual(pixels.alpha(atX: Double(box.midX), y: Double(box.midY)),
                       Double(palette.alpha), accuracy: 1.0 / 255)
    }

    /// Решает, бывает ли окно, ХОСТ, а не шейдер.
    ///
    /// Под бледной дымкой светлой темы окна нет — но знает об этом
    /// `AttributionCarve.carves(palette:)`, и зовёт его `MyMapRepresentable`
    /// перед тем, как отдать окно обеим вуалям. Сам кадр рисует то, что ему
    /// дали: у шейдера нет права решать за хост, иначе решений стало бы два.
    /// Эта же развязка у растра, и проверяется она там так же —
    /// `AttributionClearTests.testCarveOnlyHappensUnderTheNightVeil`.
    func testTheLightPaletteGateLivesInTheHostNotTheShader() throws {
        XCTAssertFalse(AttributionCarve.carves(palette: .mist),
                       "под бледной дымкой окна не бывает — и решает это хост")
        XCTAssertTrue(AttributionCarve.carves(palette: .night))

        let mist = FogVeilPainter.Palette.mist
        let window = FogCarveWindow.attribution(rect: box)
        let pixels = try render(carve: window, palette: mist)
        XCTAssertEqual(
            pixels.alpha(atX: Double(box.midX), y: Double(box.midY)),
            Double(mist.alpha) * Double(window.floor), accuracy: 1.0 / 255,
            "дали окно — шейдер рисует окно, какой бы ни была палитра")
    }

    // MARK: Фикстуры

    /// Пустой слой: коридоров в кадре нет вовсе, и всё, что видно, —
    /// работа окна. Смешивать её с перьями коридора значило бы мерить две
    /// вещи одним числом.
    private var emptyLayer: RevealedLayer {
        RevealedLayer(fine: MKMultiPolyline(), mid: MKMultiPolyline(), far: MKMultiPolyline(),
                      cellCount: 0, openedKm: 0, regionIds: [])
    }

    private func render(carve: FogCarveWindow?,
                        palette: FogVeilPainter.Palette? = nil) throws -> FogPixels {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal недоступен") }
        let mapPointsPerMetre = MKMapPointsPerMeterAtLatitude(krasnodar.coordinate.latitude)
        let width = Double(size.width) * 10 * mapPointsPerMetre
        let height = Double(size.height) * 10 * mapPointsPerMetre
        let rect = MKMapRect(x: krasnodar.x - width / 2, y: krasnodar.y - height / 2,
                             width: width, height: height)
        let image = try XCTUnwrap(FogOffscreen.render(
            layer: emptyLayer, rect: rect, sizePoints: size, scale: scale,
            palette: palette ?? self.palette, carve: carve))
        return try XCTUnwrap(FogPixels(image: image, scale: scale))
    }
}
