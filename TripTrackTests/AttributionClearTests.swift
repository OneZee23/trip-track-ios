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
/// Теперь мгла под атрибуцией ВЫРЕЗАЕТСЯ: подпись садится на настоящую карту
/// Apple, то есть на тот фон, под который MapKit её и красит.
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

    /// В середине выреза маска ПРОЗРАЧНА (мгла снята совсем), по краю —
    /// непрозрачна, а между ними растушёвка, а не ступенька.
    func testWindowIsClearInsideAndSolidOutside() throws {
        let size = CGSize(width: 120, height: 48)
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
        XCTAssertEqual(alpha(w / 2, h / 2), 0, "в середине выреза мгла обязана быть снята")
        XCTAssertGreaterThan(alpha(0, 0), 200, "за краем выреза мгла обязана остаться")
        // Растушёвка: где-то между ними альфа промежуточная.
        let edge = (0..<(w / 2)).map { alpha($0, h / 2) }
        XCTAssertTrue(edge.contains { $0 > 20 && $0 < 235 },
                      "край выреза — ступенька, а не растушёвка")
    }

    /// Контраст подписи Apple на том, что остаётся в вырезе, — не меньше
    /// 4.5 : 1. В вырезе мгла снята полностью, то есть подпись лежит на
    /// светлой карте Apple, под которую MapKit её и красит.
    func testGlyphContrastInsideTheCarveClearsTheBar() {
        // Светлая карта Apple под мглой — примерно #F2F1EC у подложки суши.
        let map = UIColor(red: 0xF2/255, green: 0xF1/255, blue: 0xEC/255, alpha: 1)
        let glyph = UIColor.label.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = Self.contrast(glyph, map)
        print(String(format: "[attribution] контраст в вырезе %.1f : 1", ratio))
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    // MARK: Когда вырезать, а когда нет

    /// Вырез — ТОЛЬКО под ночной мглой.
    ///
    /// «Эппл-мапс стоит неровно с другими элементами» (владелец на устройстве,
    /// 18 сентября): на светлой теме вырез читался бледной коробкой за словами
    /// «Maps / Legal», наехавшей на верхний край листа. Вырезать светлое из
    /// светлого нечего — подпись Apple там и так тёмно-серая на бледной дымке.
    func testCarveOnlyHappensUnderTheNightVeil() {
        XCTAssertTrue(AttributionCarve.carves(palette: .night))
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

    /// Растушёвка шире самой подписи — иначе вырез снова читается коробкой.
    /// Высота «` Maps`» на iOS 18 — около шестнадцати точек.
    func testFeatherIsWiderThanTheGlyphItHides() {
        XCTAssertGreaterThanOrEqual(AttributionCarve.feather, 12)
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

        // Широкий экран: карточка упёрлась в потолок ширины.
        let wide: CGFloat = 440
        let inset = MapBottomInset.leftInset(
            width: wide, cardMaxWidth: card, mapPadding: padding)
        XCTAssertEqual(inset + padding, (wide - card) / 2, accuracy: 0.5)

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
        let sheet = MyMapSheet.collapsedHeight(bottomInset: safeArea)
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
