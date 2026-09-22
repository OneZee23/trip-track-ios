import XCTest
import MapKit
import Metal
@testable import TripTrack

/// Пиксели офскрин-кадра, прочитанные ОДИН раз.
///
/// Картинка приходит из `FogOffscreen.render` — `bgra8Unorm` с
/// премультиплицированной альфой, то есть в памяти байты лежат как
/// B, G, R, A. Тесту нужна почти всегда одна альфа: «мгла» — это
/// `palette.alpha`, «открыто» — ноль, и всё, что между ними, и есть перо.
///
/// Точки, а не пиксели: ширины коридора считаются в ТОЧКАХ экрана (та же
/// полуширина `FogVeilRenderer.haloHalfWidth`, делённая на метры в точке), и
/// переводить их в пиксели в каждом тесте значило бы переписать по месту то
/// самое число, которое тест и сторожит.
struct FogPixels {
    let width: Int
    let height: Int
    let scale: CGFloat
    private let bytesPerRow: Int
    private let bytes: [UInt8]

    init?(image: CGImage, scale: CGFloat) {
        guard scale > 0, let data = image.dataProvider?.data else { return nil }
        let length = CFDataGetLength(data)
        var buffer = [UInt8](repeating: 0, count: length)
        CFDataGetBytes(data, CFRange(location: 0, length: length), &buffer)
        guard length >= image.bytesPerRow * image.height else { return nil }
        bytes = buffer
        bytesPerRow = image.bytesPerRow
        width = image.width
        height = image.height
        self.scale = scale
    }

    /// Альфа в ТОЧКАХ кадра, 0…1.
    func alpha(atPoint point: CGPoint) -> Double {
        Double(pixel(atPoint: point).alpha) / 255
    }

    func alpha(atX x: Double, y: Double) -> Double {
        alpha(atPoint: CGPoint(x: x, y: y))
    }

    /// Четыре байта пикселя как они лежат в памяти.
    func pixel(atPoint point: CGPoint) -> (blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8) {
        let column = min(max(0, Int((point.x * scale).rounded(.down))), width - 1)
        let row = min(max(0, Int((point.y * scale).rounded(.down))), height - 1)
        let i = row * bytesPerRow + column * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3])
    }

    /// Середина того пикселя, в который попала точка, — в ТОЧКАХ.
    ///
    /// Именно там фрагментный шейдер и считал своё покрытие, поэтому
    /// аналитическую проверку надо сверять с ней, а не с запрошенной точкой:
    /// полпикселя в сторону — это уже шесть двести пятьдесят пятых альфы на
    /// перьевом склоне.
    func centre(ofPointAt point: CGPoint) -> CGPoint {
        let column = min(max(0, Int((point.x * scale).rounded(.down))), width - 1)
        let row = min(max(0, Int((point.y * scale).rounded(.down))), height - 1)
        return CGPoint(x: (CGFloat(column) + 0.5) / scale, y: (CGFloat(row) + 0.5) / scale)
    }

    /// Сколько РАЗНЫХ пикселей в кадре. Один — кадр ровный: ни шва, ни
    /// полосы, ни градиента в нём нет вовсе.
    var distinctPixels: Set<UInt32> {
        var seen: Set<UInt32> = []
        for row in 0..<height {
            let start = row * bytesPerRow
            for column in 0..<width {
                let i = start + column * 4
                seen.insert(UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16
                            | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3]))
            }
        }
        return seen
    }
}

/// Сторожа эталонной картинки Metal-тумана.
///
/// Эталонного СНИМКА в репозитории нет и не будет: он устареет от смены
/// палитры, разрешения симулятора и знака после запятой в перьях. Поэтому
/// проверяются СВОЙСТВА, из которых картинка складывается (спека §3, §7):
/// центр коридора открыт, вдали мгла цела, стык двух отрезков не даёт
/// бусины, пустой слой ровен, Float32 не дрожит на улице, а ширина открытого
/// та же, что у растровой вуали.
///
/// Всё это не выражается ни возвращаемым значением, ни состоянием — только
/// пикселем, и ради этого офскрин и заведён: он рисует ТЕМ ЖЕ
/// `FogFrameEncoder`, что и экран.
final class FogMetalPixelTests: XCTestCase {
    private let size = CGSize(width: 300, height: 300)
    private let scale: CGFloat = 2
    private let palette = FogVeilPainter.Palette.night

    /// Краснодар: точка карты около (1.6e8, 1.0e8), то есть кусок с большим
    /// началом — ровно то, на чём Float32 и дрожал бы без смещений.
    private let krasnodar = MKMapPoint(
        CLLocationCoordinate2D(latitude: 45.03, longitude: 38.97))

    // MARK: Сторожа

    /// Коридор открыт до дна, а в трёх полуширинах от него мгла ровно такая,
    /// какой её задала палитра.
    func testCorridorCentreIsClearAndFarFogIsIntact() throws {
        let box = rect(around: krasnodar, metresPerPoint: 10)
        let params = try XCTUnwrap(FogOffscreen.params(
            rect: box, sizePoints: size, scale: scale, palette: palette))
        // 10 м/pt — город: пол в метрах уже проигран, полуширина ровно
        // восемнадцать точек (`FogVeilRenderer.haloHalfWidthPoints`).
        XCTAssertEqual(params.halfWidthPoints, 18, accuracy: 0.001)

        let pixels = try render(
            layer(through: [CGPoint(x: -50, y: 150), CGPoint(x: 350, y: 150)], in: box),
            in: box)

        XCTAssertLessThanOrEqual(
            pixels.alpha(atX: 150, y: 150), 0.02 * Double(palette.alpha),
            "на осевой линии коридора мглы не остаётся")
        XCTAssertEqual(
            pixels.alpha(atX: 150, y: 150 + 3 * params.halfWidthPoints),
            Double(palette.alpha), accuracy: 1.0 / 255,
            "в трёх полуширинах от дороги мгла обязана быть целой")
    }

    /// Стык двух отрезков — ни бусины, ни кольца.
    ///
    /// Это и есть та причина, по которой покрытие смешивается через `max`:
    /// сложение альф давало бы на каждой вершине ломаной светлое пятно, и на
    /// городском масштабе дорога читалась бы пунктиром из узлов.
    func testJointsLeaveNoBeads() throws {
        let box = rect(around: krasnodar, metresPerPoint: 10)
        let nodes = dogleg
        let pixels = try render(layer(through: nodes, in: box), in: box)

        var alphas: [Double] = []
        for i in 0..<(nodes.count - 1) {
            let a = nodes[i], b = nodes[i + 1]
            let length = Double(hypot(b.x - a.x, b.y - a.y))
            var walked = 0.0
            while walked <= length {
                let f = walked / length
                alphas.append(pixels.alpha(atX: Double(a.x) + Double(b.x - a.x) * f,
                                           y: Double(a.y) + Double(b.y - a.y) * f))
                walked += 2
            }
        }

        let highest = try XCTUnwrap(alphas.max())
        let lowest = try XCTUnwrap(alphas.min())
        XCTAssertLessThanOrEqual(highest, 0.01,
                                 "вдоль осевой линии покрытие обязано быть полным")
        XCTAssertLessThanOrEqual(highest - lowest, 1.0 / 255,
                                 "вершина ломаной не имеет права отличаться от её середины")

        // Осевой линии одной мало: в однобайтовом покрытии сумма двух
        // капсул упирается в единицу, и на самой дороге сложение от
        // максимума не отличить. Бусина живёт НА ПЕРЕ — с внешней стороны
        // излома, где обе капсулы меряются от одной и той же вершины и
        // сложение удвоило бы их покрытие. Поэтому альфа там сверяется с
        // одной капсулой, посчитанной вручную.
        let params = try XCTUnwrap(FogOffscreen.params(
            rect: box, sizePoints: size, scale: scale, palette: palette))
        let inner = params.halfWidthPoints - params.featherPoints
        for i in 1..<(nodes.count - 1) {
            let vertex = nodes[i]
            let into = unit(from: nodes[i - 1], to: vertex)
            let out = unit(from: vertex, to: nodes[i + 1])
            // Направление, в котором ближайшая точка ОБЕИХ капсул — сама
            // вершина: за концом первого отрезка и до начала второго.
            let away = unit(from: .zero, to: CGPoint(x: into.x - out.x, y: into.y - out.y))
            // Середина пера: одна капсула даёт здесь ровно половину
            // покрытия, две сложенные — единицу, то есть дыру.
            let reach = CGFloat(params.halfWidthPoints - params.featherPoints / 2)
            let asked = CGPoint(x: vertex.x + away.x * reach, y: vertex.y + away.y * reach)
            let centre = pixels.centre(ofPointAt: asked)
            let distance = Double(hypot(centre.x - vertex.x, centre.y - vertex.y))
            XCTAssertEqual(
                pixels.alpha(atPoint: asked),
                Double(palette.alpha) * smoothstep(inner, params.halfWidthPoints, distance),
                accuracy: 2.0 / 255,
                "с внешней стороны вершины перекрытие обязано браться МАКСИМУМОМ, а не суммой")
        }
    }

    /// Без коридоров кадр — одна краска на все девяносто тысяч точек.
    ///
    /// Швы, полосы и «подгружаемые квадратики» растровой вуали 0.7.0 видны
    /// именно здесь: у неё пустой кадр состоял из тайлов и полос, у этого —
    /// из одного значения.
    func testEmptyLayerIsOneFlatColour() throws {
        let box = rect(around: krasnodar, metresPerPoint: 10)
        let empty = RevealedLayer(
            fine: MKMultiPolyline(), mid: MKMultiPolyline(), far: MKMultiPolyline(),
            cellCount: 0, openedKm: 0, regionIds: [])
        let pixels = try render(empty, in: box)

        XCTAssertEqual(pixels.distinctPixels.count, 1,
                       "пустой слой обязан дать РОВНО одну краску на весь кадр")
        XCTAssertEqual(pixels.alpha(atX: 0, y: 0), Double(palette.alpha), accuracy: 1.0 / 255,
                       "и краска эта — мгла палитры")
    }

    /// Улица в дальнем углу мира выглядит ровно так же, как улица у начала
    /// координат.
    ///
    /// Точка карты доходит до 2.7e8, а Float32 несёт семь значащих цифр:
    /// абсолютная координата в буфере давала бы на улице шаг сетки в метры,
    /// то есть дрожащий коридор. Поэтому в буфере лежат СМЕЩЕНИЯ от угла
    /// своего куска, а экранный перенос куска считается в Double. Уберите
    /// это — и профиль ниже разъедется.
    func testStreetZoomHasNoFloat32Jitter() throws {
        let street = 0.3
        let far = rect(around: krasnodar, metresPerPoint: street)
        // Тот же кадр у начала координат: там угол куска — ноль, и дрожать
        // Float32 нечем даже при абсолютных координатах.
        let near = rect(around: MKMapPoint(x: 20_000, y: 20_000), metresPerPoint: street)
        XCTAssertGreaterThan(far.midX, 1e8, "дальний кадр обязан лежать в куске с большим началом")

        // Диагональ, а не горизонталь: огрублённая координата X сдвигает
        // наклонный коридор и ПО ВЕРТИКАЛИ, то есть поперёк профиля, — на
        // горизонтальной линии то же огрубление не видно вовсе.
        let axis = [CGPoint(x: -50, y: 60), CGPoint(x: 350, y: 240)]
        let there = try render(layer(through: axis, in: far), in: far)
        let here = try render(layer(through: axis, in: near), in: near)

        var profile: [Double] = []
        for y in stride(from: 0.0, through: 150.0, by: 0.5) {
            let a = there.alpha(atX: 150, y: y)
            profile.append(a)
            XCTAssertEqual(a, here.alpha(atX: 150, y: y), accuracy: 1.0 / 255,
                           "на \(y) pt поперёк коридора профили разошлись")
        }
        // Сравнивать плоские нули можно вечно: профиль обязан быть профилем.
        let spread = try XCTUnwrap(profile.max()) - (try XCTUnwrap(profile.min()))
        XCTAssertGreaterThan(spread, 0.05, "поперёк коридора обязано быть перо, а не ровное поле")
    }

    /// Ширина открытого — та же, что у растровой вуали, на улице и на стране.
    ///
    /// Полная ширина коридора — `2 × haloHalfWidth / м-на-точку`, и её держит
    /// таблица `HaloWidthTests`. Здесь она меряется ПО ПИКСЕЛЯМ, и мерить
    /// приходится по половине альфы: у самого края мгла редеет на доли
    /// процента, а восьмибитная альфа таких долей не различает. Перо при этом
    /// срезано ВНУТРЬ (`smoothstep(hw − feather, hw, d)`), поэтому половина
    /// альфы приходится на `hw − feather/2`, и измеренная ширина равна полной
    /// МИНУС одно перо. Числа эти связаны намертво: поедет `featherRatio` —
    /// поедет и здесь.
    func testHalfWidthFollowsTheHaloRule() throws {
        for metresPerPoint in [0.3, 300.0] {
            let box = rect(around: krasnodar, metresPerPoint: metresPerPoint)
            let params = try XCTUnwrap(FogOffscreen.params(
                rect: box, sizePoints: size, scale: scale, palette: palette))
            let full = 2 * FogVeilRenderer.haloHalfWidth(metresPerPoint: metresPerPoint)
                / metresPerPoint
            XCTAssertEqual(params.halfWidthPoints * 2, full, accuracy: 1e-9,
                           "\(metresPerPoint) м/pt: офскрин обязан взять ширину у общего правила")

            let pixels = try render(
                layer(through: [CGPoint(x: -50, y: 150), CGPoint(x: 350, y: 150)], in: box),
                in: box)
            let measured = openWidth(in: pixels, atX: 150)
            XCTAssertEqual(measured, full - params.featherPoints, accuracy: 1,
                           "\(metresPerPoint) м/pt: открытое по половине альфы вышло \(measured) pt")
        }
    }

    // MARK: Фикстуры

    /// Единичный вектор из одной точки кадра в другую.
    private func unit(from: CGPoint, to: CGPoint) -> CGPoint {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: (to.x - from.x) / length, y: (to.y - from.y) / length)
    }

    /// Тот же спад, что в `fog_coverage_fragment`, — руками.
    private func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Ломаная из трёх отрезков под 30°, 120° и снова 30° — две вершины, на
    /// которых и появлялись бы бусины.
    private var dogleg: [CGPoint] {
        var points = [CGPoint(x: 80, y: 60)]
        for degrees in [30.0, 120.0, 30.0] {
            let radians = degrees * .pi / 180
            let last = points[points.count - 1]
            points.append(CGPoint(x: last.x + 90 * cos(radians), y: last.y + 90 * sin(radians)))
        }
        return points
    }

    /// Прямоугольник карты вокруг точки, дающий РОВНО столько метров на точку
    /// экрана: `FogOffscreen.params` берёт широту из его середины, поэтому
    /// число сходится обратно без округления.
    private func rect(around centre: MKMapPoint, metresPerPoint: Double) -> MKMapRect {
        let mapPointsPerMetre = MKMapPointsPerMeterAtLatitude(centre.coordinate.latitude)
        let width = Double(size.width) * metresPerPoint * mapPointsPerMetre
        let height = Double(size.height) * metresPerPoint * mapPointsPerMetre
        return MKMapRect(x: centre.x - width / 2, y: centre.y - height / 2,
                         width: width, height: height)
    }

    /// Точка кадра → точка карты: та же матрица, что у `FogOffscreen`, только
    /// наоборот.
    private func mapPoint(atX x: Double, y: Double, in rect: MKMapRect) -> MKMapPoint {
        MKMapPoint(x: rect.minX + x / Double(size.width) * rect.width,
                   y: rect.minY + y / Double(size.height) * rect.height)
    }

    /// Слой с одной ломаной, положенной во ВСЕ три уровня детали: иначе
    /// выбранный уровень мог бы спрятать отрезок, и тест проверял бы пустоту.
    ///
    /// Ломаная строится ПО ТОЧКАМ КАРТЫ, а не по координатам. Разница здесь
    /// не стилистическая: у самой кромки Меркатора (`MKMapPoint(x: 20 000,
    /// y: 20 000)` — это 85.0488° с. ш.) один градус широты стоит миллионы
    /// точек карты, и круг «точка карты → координата → точка карты» уводит
    /// отрезок на четыреста тысяч точек в сторону. Кадр у начала координат
    /// после такого круга выходил ровным полем без единого коридора.
    private func layer(through points: [CGPoint], in rect: MKMapRect) -> RevealedLayer {
        let mapPoints = points.map { mapPoint(atX: Double($0.x), y: Double($0.y), in: rect) }
        func line() -> MKMultiPolyline {
            MKMultiPolyline([MKPolyline(points: mapPoints, count: mapPoints.count)])
        }
        return RevealedLayer(fine: line(), mid: line(), far: line(),
                             cellCount: 1, openedKm: 1, regionIds: [])
    }

    /// Кадр офскрина. Metal нет — тест пропускается, а не падает: на такой
    /// машине и само приложение откатывается на растровую вуаль.
    private func render(_ layer: RevealedLayer, in rect: MKMapRect) throws -> FogPixels {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("Metal недоступен") }
        let image = try XCTUnwrap(FogOffscreen.render(
            layer: layer, rect: rect, sizePoints: size, scale: scale, palette: palette))
        XCTAssertEqual(image.width, Int(size.width * scale))
        XCTAssertEqual(image.height, Int(size.height * scale))
        return try XCTUnwrap(FogPixels(image: image, scale: scale))
    }

    /// Ширина открытого по половине альфы, в точках. Шаг — один ПИКСЕЛЬ:
    /// мельче кадра мерить нечем.
    private func openWidth(in pixels: FogPixels, atX x: Double) -> Double {
        let step = 1 / Double(scale)
        let threshold = Double(palette.alpha) / 2
        var first: Double?
        var last: Double?
        var y = 0.0
        while y < Double(size.height) {
            if pixels.alpha(atX: x, y: y) < threshold {
                if first == nil { first = y }
                last = y
            }
            y += step
        }
        guard let first, let last else { return 0 }
        return last - first + step
    }
}
