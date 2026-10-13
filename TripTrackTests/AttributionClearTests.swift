import XCTest
import MapKit
@testable import TripTrack

/// Чужие вью с ТЕМИ ЖЕ подстроками в имени, что у MapKit.
///
/// На ФАЙЛОВОМ уровне, а не внутри класса теста: у вложенного Swift-класса
/// `NSStringFromClass` отдаёт МАНГЛИРОВАННОЕ имя, в которое входит имя
/// внешнего типа, — то есть `PlainView` внутри `AttributionClearTests` сам
/// содержал бы подстроку «Attribution» и ловился поиском.
private final class TTFakeAttributionLabel: UIView {}
private final class TTFakeLogoView: UIView {}
private final class TTFakeLegalLink: UIView {}
private final class TTPlainView: UIView {}

/// Логотип Apple и «Legal» обязаны быть ВИДНЫ — правило проекта, и цена его
/// нарушения не «некрасиво», а возврат из ревью.
///
/// До 17 сентября под них подкладывали светлую плиту. На устройстве она
/// читалась отдельным блоком, наехавшим на край листа, и владелец это увидел.
/// 20 сентября плиту заменил полный вырез (мгла снималась до нуля) — и на
/// дневной карте «Атласа» под ним снова читалась плита, просто без своего
/// фона: голая светлая карта. Теперь мгла под атрибуцией ПРИГЛУШАЕТСЯ до
/// половины силы (`AttributionCarve.windowFloor`), а не снимается совсем —
/// подпись лежит на смягчённой мгле, не на голой карте (задача A2, 21 сен).
@MainActor
final class AttributionClearTests: XCTestCase {

    private func hierarchy() -> (root: UIView, label: UIView, logo: UIView) {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        root.addSubview(TTPlainView(frame: root.bounds))
        let logo = TTFakeLogoView(frame: CGRect(x: 12, y: 740, width: 60, height: 16))
        let label = TTFakeAttributionLabel(frame: CGRect(x: 80, y: 740, width: 48, height: 16))
        root.addSubview(logo)
        root.addSubview(label)
        return (root, label, logo)
    }

    // MARK: Поиск

    func testFindsBothAttributionViews() {
        let tree = hierarchy()
        let found = AttributionCarve.attributionViews(in: tree.root)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains(tree.label))
        XCTAssertTrue(found.contains(tree.logo))
    }

    /// И ссылка «Legal» отдельной вьюхой — на iOS 18 её нет, но появиться она
    /// может в любой сборке, и закрывать её мглой нельзя ровно так же.
    func testFindsALegalLinkToo() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let legal = TTFakeLegalLink(frame: CGRect(x: 80, y: 740, width: 40, height: 16))
        root.addSubview(TTPlainView(frame: root.bounds))
        root.addSubview(legal)
        XCTAssertEqual(AttributionCarve.attributionViews(in: root), [legal])
    }

    func testFindsNothingInAStrangerHierarchy() {
        let root = UIView()
        root.addSubview(TTPlainView())
        XCTAssertTrue(AttributionCarve.attributionViews(in: root).isEmpty)
        XCTAssertNil(AttributionCarve.carveRect(in: root, space: root))
    }

    // MARK: Коробка выреза

    /// Вырез накрывает ОБЕ вьюхи атрибуции и ещё поле вокруг них.
    func testCarveCoversEveryAttributionViewWithPadding() {
        let tree = hierarchy()
        guard let carve = AttributionCarve.carveRect(in: tree.root, space: tree.root) else {
            return XCTFail("вырез обязан посчитаться")
        }
        let union = tree.logo.frame.union(tree.label.frame)
        XCTAssertEqual(carve.minX, union.minX - AttributionCarve.padding, accuracy: 0.5)
        XCTAssertEqual(carve.maxY, union.maxY + AttributionCarve.padding, accuracy: 0.5)
        XCTAssertTrue(carve.contains(union))
    }

    /// На НАСТОЯЩЕЙ карте вырез находится — или не находится, и тогда экран
    /// обязан вернуться в ночную тему. Третьего (дневная карта с нечитаемым
    /// «Legal») быть не должно ни при каком переименовании приватных классов.
    func testRealMapEitherGetsACarveOrGoesBackToNight() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        map.overrideUserInterfaceStyle = .light
        map.layoutIfNeeded()
        let carve = AttributionCarve.carveRect(in: map, space: map)
        print("[attribution] вырез на настоящей карте: \(String(describing: carve))")
        if carve == nil { map.overrideUserInterfaceStyle = .dark }
        XCTAssertTrue(carve != nil || map.overrideUserInterfaceStyle == .dark)
    }

    // MARK: Картинка маски

    /// В середине окна маска держит `windowFloor` (мгла ПРИГЛУШЕНА до половины
    /// силы, а не снята совсем — задача A2), по краю — непрозрачна, а между
    /// ними растушёвка, а не ступенька.
    func testWindowIsDimmedInsideAndSolidOutside() throws {
        let size = Self.windowSize
        let image = try XCTUnwrap(VeilCarveMask.windowImage(size: size))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { bytes in
            guard let ctx = CGContext(
                data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        func alpha(_ x: Int, _ y: Int) -> Int { Int(data[(y * w + x) * 4 + 3]) }
        let floor = Int((AttributionCarve.windowFloor * 255).rounded())
        XCTAssertLessThanOrEqual(abs(alpha(w / 2, h / 2) - floor), 1,
                       "в середине окна мгла обязана остаться на floor, а не сняться совсем")
        XCTAssertGreaterThan(alpha(0, 0), 200, "за краем окна мгла обязана остаться полной")
        // Растушёвка: где-то между ними альфа промежуточная.
        let edge = (0..<(w / 2)).map { alpha($0, h / 2) }
        XCTAssertTrue(edge.contains { $0 > floor + 5 && $0 < 235 },
                      "край окна — ступенька, а не растушёвка")
    }

    /// Альфа читается прямиком из растра — общий помощник для тестов ниже.
    private func alphaGrid(_ image: CGImage) -> (w: Int, h: Int, alpha: (Int, Int) -> Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { bytes in
            guard let ctx = CGContext(
                data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, { x, y in Int(data[(y * w + x) * 4 + 3]) })
    }

    /// Размер окна считается ТАК ЖЕ, как в бою: рамка подписи плюс поле, и
    /// сверху растушёвка с каждой стороны (`VeilCarveMask.layout`).
    ///
    /// Раньше здесь стояло 120×48 числом, и при растушёвке в шесть точек оно
    /// работало. На тридцати двух (23 сен, чтобы окно перестало читаться
    /// плашкой) такой картинки ФИЗИЧЕСКИ не хватает: спад не успевает дойти
    /// до края, и тест ловил не поломку, а свой собственный размер. Считать
    /// его от тех же чисел — единственный способ, при котором он остаётся
    /// верным на любой растушёвке.
    private static var windowSize: CGSize {
        let attribution = CGRect(x: 0, y: 0, width: 96, height: 20)
        let carve = attribution.insetBy(dx: -AttributionCarve.padding,
                                        dy: -AttributionCarve.padding)
        return carve.insetBy(dx: -AttributionCarve.feather,
                             dy: -AttributionCarve.feather).size
    }

    /// На САМОЙ границе картинки альфа обязана совпасть с полосами вокруг —
    /// то есть быть полной, а не почти полной. Второй прямоугольник с жёсткой
    /// кромкой (владелец на устройстве, задача A) — это шов там, где край
    /// окна не дотягивает до alpha=1 и полосы обрывают его резко.
    func testWindowEdgeIsFullyOpaqueLikeTheBars() throws {
        let size = Self.windowSize
        let image = try XCTUnwrap(VeilCarveMask.windowImage(size: size))
        let (w, h, alpha) = alphaGrid(image)
        // Крайний пиксель сэмплится в своём ЦЕНТРЕ, на полпикселя внутрь от
        // математической границы, — поэтому не 255 ровно, а вплотную к ней.
        XCTAssertGreaterThanOrEqual(alpha(0, h / 2), 250, "левый край — та же альфа, что у полосы рядом")
        XCTAssertGreaterThanOrEqual(alpha(w / 2, 0), 250, "верхний край — та же альфа, что у полосы рядом")
        XCTAssertGreaterThanOrEqual(alpha(w - 1, h / 2), 250)
        XCTAssertGreaterThanOrEqual(alpha(w / 2, h - 1), 250)
    }

    /// Спад — НЕПРЕРЫВНАЯ функция, а не двадцать четыре кольца. Ступеней
    /// (одинаковых соседних значений на протяжении нескольких пикселей)
    /// быть не должно: именно они читались на устройстве отдельной рамкой —
    /// эффектом Маха на границе между кольцами.
    func testWindowRampHasNoDiscreteSteps() throws {
        let size = Self.windowSize
        let image = try XCTUnwrap(VeilCarveMask.windowImage(size: size))
        let (w, h, alpha) = alphaGrid(image)
        // Индекс 0 — у самого края картинки, конец диапазона — у центра
        // выреза: альфа монотонно НЕ РАСТЁТ по мере приближения к центру.
        let ramp = (0..<(w / 2)).map { alpha($0, h / 2) }
        for i in 1..<ramp.count {
            XCTAssertLessThanOrEqual(ramp[i], ramp[i - 1], "альфа обязана падать к центру")
        }
        // Достаточно РАЗНЫХ значений на растушёвке, чтобы это была растушёвка,
        // а не горстка широких ступеней. Порог вдвое ниже прежнего (20): и
        // амплитуда теперь вдвое меньше (`windowFloor`…255, а не 0…255), и
        // сама растушёвка вдвое короче (6 pt, а не 12) — на том же экранном
        // масштабе шагов физически меньше, а не грубее.
        let distinctInFeather = Set(ramp.filter { $0 > 0 && $0 < 255 })
        XCTAssertGreaterThan(distinctInFeather.count, 10,
                             "растушёвка обязана быть непрерывной, а не ступенчатой")
    }

    /// Окно и четыре полосы — та же геометрия, что реально ставит `update`, —
    /// вместе покрывают `bounds` РОВНО, без дыр и без нахлёста. Дыра — это
    /// незакрытый кусок тумана (или наоборот, кусок с двойной альфой), и
    /// геометрия ловит её раньше, чем это увидит глаз на устройстве.
    func testWindowAndBarsTileBoundsWithoutGapsOrOverlaps() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        let carve = CGRect(x: 40, y: 700, width: 120, height: 30)
        let (window, bars) = VeilCarveMask.layout(bounds: bounds, carve: carve)
        let rects = bars + [window]
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let inter = rects[i].intersection(rects[j])
                XCTAssertTrue(
                    inter.isNull || inter.width <= 0.001 || inter.height <= 0.001,
                    "прямоугольники \(i) и \(j) перекрываются: \(inter)")
            }
        }
        let totalArea = rects.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        XCTAssertEqual(totalArea, bounds.width * bounds.height, accuracy: 0.5,
                       "сумма площадей обязана сойтись с площадью bounds без остатка")
    }

    /// Тот же тест, но коробка выреза упёрлась в край экрана — самый частый
    /// случай в жизни (атрибуция стоит у самого низа карты).
    func testWindowAndBarsTileBoundsWhenCarveTouchesTheEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        let carve = CGRect(x: -10, y: 770, width: 120, height: 40)
        let (window, bars) = VeilCarveMask.layout(bounds: bounds, carve: carve)
        let rects = bars + [window]
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                let inter = rects[i].intersection(rects[j])
                XCTAssertTrue(inter.isNull || inter.width <= 0.001 || inter.height <= 0.001)
            }
        }
    }

    /// Контраст подписи Apple на том, что остаётся в окне, — не меньше
    /// 4.5 : 1. Окно больше НЕ снимает мглу до нуля (задача A2): мгла
    /// приглушена до `windowFloor`, и подпись лежит на СМЯГЧЁННОЙ мгле, не на
    /// голой светлой карте. Худший случай — как у дымки: самый тёмный конец
    /// рампы (`.top`) на самом высоком краю диапазона непрозрачности, дальше
    /// приглушённый маской `windowFloor`.
    func testGlyphContrastInsideTheCarveClearsTheBar() {
        // Светлая карта Apple под мглой — примерно #F2F1EC у подложки суши.
        let map = UIColor(red: 0xF2/255, green: 0xF1/255, blue: 0xEC/255, alpha: 1)
        let night = FogVeilPainter.Palette.night
        let effectiveAlpha = AttributionCarve.windowFloor
            * CGFloat(night.opacityRange.upperBound)
        let worst = Self.composite(night.top, over: map, alpha: effectiveAlpha)
        let glyph = UIColor.label.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = Self.contrast(glyph, worst)
        print(String(format: "[attribution] контраст в окне %.1f : 1", ratio))
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    // MARK: Когда вырезать, а когда нет

    /// Выреза НЕТ ни под какой мглой (владелец, 26 сентября).
    ///
    /// Сначала его убрали со светлой дымки — там он читался бледной коробкой
    /// за словами «Maps / Legal» (18 сентября), а вырезать светлое из
    /// светлого нечего. Теперь он ушёл и с ночной: «зачем-то тень
    /// развеивается, убери это свойство, пусть просто значок будет поверх
    /// тумана». Цена названа и принята: на стиле «Ночь» подпись Apple
    /// остаётся тёмно-серой на тёмной мгле, около 1.6 : 1, — это открытый
    /// риск на ревью, а не забытая строка, и тест стоит здесь ровно затем,
    /// чтобы решение не отменили по невнимательности.
    func testNoCarveUnderAnyVeil() {
        XCTAssertFalse(AttributionCarve.carves(palette: .night))
        XCTAssertFalse(AttributionCarve.carves(palette: .mist))
    }

    /// И это не вкус: подпись на бледной дымке читается с запасом.
    ///
    /// Худший случай считается честно — самый тёмный конец рампы мглы на самой
    /// высокой её непрозрачности поверх светлой карты Apple.
    func testGlyphContrastOnThePaleMistClearsTheBar() {
        let map = UIColor(red: 0xF2/255, green: 0xF1/255, blue: 0xEC/255, alpha: 1)
        let mist = FogVeilPainter.Palette.mist
        let worst = Self.composite(mist.bottom, over: map,
                                   alpha: CGFloat(mist.opacityRange.upperBound))
        let glyph = UIColor.label.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = Self.contrast(glyph, worst)
        print(String(format: "[attribution] контраст на дымке %.1f : 1", ratio))
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    /// Растушёвка не меньше шести точек — вдвое короче прежней (двенадцать),
    /// потому что вдвое мягче стал сам перепад (`windowFloor` = 0.5, а не
    /// полный 0→1). У полного перепада хватало только растушёвки шире самой
    /// подписи; у половинного порог ниже — короче растушёвка уже не читается
    /// краем (задача A2, проверено на устройстве и `attr2-after-crop.png`).
    func testFeatherIsWiderThanHalfOfWhatItWasBeforeThePartialWindow() {
        XCTAssertGreaterThanOrEqual(AttributionCarve.feather, 6)
    }

    // MARK: Где стоит подпись

    /// Левый край подписи Apple совпадает с левым краем свёрнутой карточки.
    ///
    /// Карточка капится по ширине и на широком экране стоит НЕ на шестнадцати
    /// точках поля, а посередине; своё поле MapKit добавляет сверх инсета,
    /// поэтому инсет его вычитает.
    func testAttributionLeftEdgeLinesUpWithTheSheet() {
        let card = MyMapSheet.summaryMaxWidth
        let padding: CGFloat = 10

        // The 0.8.1 sheet spans the display, with a 16 pt content inset.
        let wide: CGFloat = 440
        let inset = MapBottomInset.leftInset(
            width: wide, cardMaxWidth: card, mapPadding: padding)
        XCTAssertEqual(inset + padding, 16, accuracy: 0.5)

        // Узкий экран: карточка живёт на своих шестнадцати точках поля.
        let narrow: CGFloat = 375
        let tight = MapBottomInset.leftInset(
            width: narrow, cardMaxWidth: card, mapPadding: padding)
        XCTAssertEqual(tight + padding, 16, accuracy: 0.5)

        // Карта без листа — инсета нет вовсе.
        XCTAssertEqual(
            MapBottomInset.leftInset(width: wide, cardMaxWidth: 0, mapPadding: padding), 0)
    }

    /// Подпись встаёт на двенадцать точек ВЫШЕ листа, а не на его край.
    func testBottomInsetLeavesTheGapAboveTheSheet() {
        let safeArea: CGFloat = 34
        let sheet = MyMapSheet.collapsedHeight
        let extra = MapBottomInset.additional(
            overlayHeight: sheet, safeAreaBottom: safeArea,
            gap: MapBottomInset.attributionGap)
        XCTAssertEqual(extra, sheet + MapBottomInset.attributionGap - safeArea, accuracy: 0.01)
        // Без зазора — как было: контракт карт без листа не менялся.
        XCTAssertEqual(
            MapBottomInset.additional(overlayHeight: sheet, safeAreaBottom: safeArea),
            sheet - safeArea, accuracy: 0.01)
    }

    /// Смешение полупрозрачной мглы с картой под ней.
    private static func composite(
        _ veil: UIColor, over base: UIColor, alpha: CGFloat
    ) -> UIColor {
        var vr: CGFloat = 0, vg: CGFloat = 0, vb: CGFloat = 0, va: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        veil.getRed(&vr, green: &vg, blue: &vb, alpha: &va)
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: vr * alpha + br * (1 - alpha),
                       green: vg * alpha + bg * (1 - alpha),
                       blue: vb * alpha + bb * (1 - alpha), alpha: 1)
    }

    private static func luminance(_ colour: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private static func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
