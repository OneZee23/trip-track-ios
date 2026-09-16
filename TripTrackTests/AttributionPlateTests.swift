import XCTest
import MapKit
@testable import TripTrack

/// Логотип Apple и «Legal» обязаны быть ВИДНЫ — это правило проекта, и цена
/// его нарушения не «некрасиво», а возврат из ревью.
///
/// С фикс-волны 2 карта «Атласа» дневная, а туман над ней тёмный; атрибуция —
/// сабвью самой карты, и цвет её следует стилю КАРТЫ, то есть она стала
/// тёмно-серой на тёмном (замер по кадрам: контраст 1.6 : 1). Подложка
/// возвращает ей светлый фон.
///
/// Проверяется здесь именно ОБЕЩАНИЕ, а не реализация: подложка либо стоит
/// под атрибуцией, либо карта вернулась в ночную. Третьего — дневной карты с
/// нечитаемым «Legal» — быть не должно ни при каком переименовании приватных
/// классов MapKit.

/// Чужие вью с ТЕМИ ЖЕ подстроками в имени, что у MapKit.
///
/// На ФАЙЛОВОМ уровне, а не внутри класса теста, и это не стиль: у вложенного
/// Swift-класса `NSStringFromClass` отдаёт МАНГЛИРОВАННОЕ имя, в которое
/// входит имя внешнего типа, — то есть `PlainView` внутри
/// `AttributionPlateTests` сам содержит подстроку «Attribution» и ловился
/// поиском. Классы MapKit объектные, и у них имя простое, но тест на этом
/// однажды уже соврал в обе стороны сразу.
private final class TTFakeAttributionLabel: UIView {}
private final class TTFakeLogoView: UIView {}
private final class TTFakeLegalLink: UIView {}
private final class TTPlainView: UIView {}

@MainActor
final class AttributionPlateTests: XCTestCase {

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

    /// Находятся ОБЕ вьюхи — и «Legal», и логотип: видны обязаны быть обе.
    func testFindsBothAttributionViews() {
        let tree = hierarchy()
        let found = AttributionPlate.attributionViews(in: tree.root)
        XCTAssertEqual(found.count, 2)
        XCTAssertTrue(found.contains(tree.label))
        XCTAssertTrue(found.contains(tree.logo))
    }

    /// И ссылка «Legal» отдельной вьюхой — на iOS 18 её нет, но появиться она
    /// может в любой сборке, и тогда закрывать её туманом нельзя ровно так же.
    func testFindsALegalLinkToo() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let legal = TTFakeLegalLink(frame: CGRect(x: 80, y: 740, width: 40, height: 16))
        root.addSubview(TTPlainView(frame: root.bounds))
        root.addSubview(legal)
        XCTAssertEqual(AttributionPlate.attributionViews(in: root), [legal])
    }

    /// Незнакомое дерево — пустой ответ, а не догадка.
    func testFindsNothingInAStrangerHierarchy() {
        let root = UIView()
        root.addSubview(TTPlainView())
        XCTAssertTrue(AttributionPlate.attributionViews(in: root).isEmpty)
    }

    // MARK: Посадка

    /// Подложка встаёт НИЖЕ атрибуции и накрывает обе её вьюхи с полем.
    func testPlateSitsBelowAttributionAndCoversIt() {
        let tree = hierarchy()
        let plate = AttributionPlate()
        XCTAssertTrue(plate.attach(to: tree.root))
        XCTAssertTrue(plate.isSeated)
        XCTAssertTrue(plate.sitsBelowAttribution,
                      "подложка выше атрибуции — она её закрыла, а не подсветила")

        let box = plate.frameInSuperview
        XCTAssertNotNil(box)
        guard let box else { return }
        let union = tree.logo.frame.union(tree.label.frame)
        XCTAssertEqual(box.minX, union.minX - AttributionPlate.padding, accuracy: 0.5)
        XCTAssertEqual(box.maxY, union.maxY + AttributionPlate.padding, accuracy: 0.5)
        XCTAssertTrue(box.contains(union), "подложка обязана накрыть атрибуцию целиком")
    }

    /// Атрибуции нет — подложка не садится, и зовущий получает сигнал вернуть
    /// карту в ночную. Молча остаться на дневной нельзя.
    func testFallsBackWhenAttributionIsMissing() {
        let bare = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        bare.addSubview(TTPlainView())
        var fellBack = false
        let plate = AttributionPlate()
        plate.onAttributionNotFound = { fellBack = true }
        for _ in 0..<AttributionPlate.maxTries { _ = plate.attach(to: bare) }
        XCTAssertFalse(plate.isSeated)
        XCTAssertTrue(fellBack, "дневная карта с нечитаемым «Legal» — это возврат из ревью")
    }

    /// На НАСТОЯЩЕЙ карте обещание держится целиком: либо подложка стоит, либо
    /// карта ушла в ночную. Третьего состояния быть не должно.
    ///
    /// Именно так, а не «подложка обязана встать»: имена классов у MapKit
    /// приватные, и день, когда они изменятся, наступит без нашего участия.
    /// Тест обязан поймать не переименование, а ПОТЕРЮ читаемости.
    func testRealMapEitherGetsThePlateOrGoesBackToNight() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        map.overrideUserInterfaceStyle = .light
        let plate = AttributionPlate()
        plate.onAttributionNotFound = { map.overrideUserInterfaceStyle = .dark }
        map.layoutIfNeeded()
        for _ in 0..<AttributionPlate.maxTries { _ = plate.attach(to: map) }
        print("[attribution] на настоящей карте подложка села: \(plate.isSeated), "
              + "стиль \(map.overrideUserInterfaceStyle == .dark ? "ночной" : "дневной")")
        XCTAssertTrue(plate.isSeated || map.overrideUserInterfaceStyle == .dark,
                      "дневная карта без подложки — нечитаемая атрибуция")
        if plate.isSeated { XCTAssertTrue(plate.sitsBelowAttribution) }
    }

    /// Контраст глифа на подложке — не меньше 4.5 : 1.
    ///
    /// Считается по самой подложке и цвету, которым MapKit рисует атрибуцию на
    /// ДНЕВНОЙ карте (`UIColor.label` в светлом окружении). Это то же число,
    /// которое меряется на кадре, только без кадра: пиксель тут ничего не
    /// добавит, а зависимость от плиток Apple добавит флейк.
    func testGlyphContrastOnThePlateClearsTheBar() {
        let plate = AttributionPlate.fill.withAlphaComponent(AttributionPlate.opacity)
        // Подложка лежит на тумане — самый тёмный возможный фон под ней.
        let under = FogVeilPainter.veilColorTop
        let blended = Self.blend(plate, over: under)
        let glyph = UIColor.label.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .light))
        let ratio = Self.contrast(glyph, blended)
        print(String(format: "[attribution] контраст глифа на подложке %.1f : 1", ratio))
        XCTAssertGreaterThanOrEqual(ratio, 4.5,
                                    "атрибуция на подложке читается хуже, чем требует ревью")
    }

    // MARK: Внутри

    private static func blend(_ top: UIColor, over bottom: UIColor) -> UIColor {
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        bottom.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: tr * ta + br * (1 - ta), green: tg * ta + bg * (1 - ta),
                       blue: tb * ta + bb * (1 - ta), alpha: 1)
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
