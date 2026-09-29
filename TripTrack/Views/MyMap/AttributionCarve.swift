import UIKit
import MapKit
import os

/// Полупрозрачное окно в мгле под атрибуцией Apple — вместо ПОЛНОГО выреза.
///
/// Плита была и ушла 17 сентября: светлый фон под логотипом читался отдельным
/// блоком, наехавшим на край листа. 20 сентября плиту заменил ПОЛНЫЙ вырез —
/// мгла снималась до нуля, и на дневной карте под ней это читалось ТОЙ ЖЕ
/// плитой: владелец увидел «яркую голубую плашку», а не подпись, второй раз.
/// Проверено экспериментом (задача A2): `overrideUserInterfaceStyle` на самой
/// вью атрибуции цвет НЕ меняет — `MKAppleLogoLabel` красится по стилю КАРТЫ,
/// а не подвью, ровно как записано в каноне, — и без выреза вовсе контраст
/// подписи на мгле держится в районе 3:1, ниже порога 4.5:1.
///
/// Ответ — не убирать мглу, а ПРИГЛУШИТЬ её под подписью до 0.35 эффективной
/// альфы (`windowFloor`, при родной ~0.70): фон под подписью светлеет ровно
/// настолько, чтобы тёмный логотип читался (контраст ~7.5:1, посчитано и
/// держится `testGlyphContrastInsideTheCarveClearsTheBar`), но не становится
/// светлой картой — то есть не становится плитой. `MKAppleLogoLabel` уже сама
/// по себе плотно посажена по контенту (`bounds == intrinsicContentSize`, без
/// скрытого поля под тап), поэтому и поле, и растушёвка сжаты вслед за ней —
/// прежние 6/12 pt были рассчитаны на полный (0→1) перепад и давали видимую
/// коробку заметно крупнее самой подписи (владелец, «заметно крупнее»).
///
/// Ни одного приватного метода: только `subviews` и имя класса, как у вуали.
/// Не нашли атрибуцию — окна нет, и карта возвращается в ночную: видимость
/// важнее полярности.
@MainActor
enum AttributionCarve {

    // Числа ниже — `nonisolated`: это ЧИСЛА, у них нет актёра (0.8.3).
    //
    // Изоляция досталась им от типа: `AttributionCarve` — `@MainActor`,
    // потому что он ходит в дерево `MKMapView`, а константы поехали следом и
    // стали недоступны шейдеру и кисти, которые считают кадр вне главного
    // потока. В Swift 6 это уже ошибка компиляции, а не предупреждение.
    // Настоящие вопросы «на каком актёре это живёт» (синглтоны сервисов,
    // managed objects в замыканиях) остаются на 0.9.0 — здесь вопроса нет.

    /// Поле вокруг атрибуции — сжато вслед за уменьшенной амплитудой окна
    /// (0.35 вместо полного 0→1): четыре точки уже не читаются отдельным
    /// блоком, потому что перепад под ними вдвое мягче прежнего.
    nonisolated static let padding: CGFloat = 8
    /// Растушёвка — ТРИДЦАТЬ ДВЕ точки, и это про форму, а не про Мах-эффект.
    ///
    /// История числа: двенадцать лечили ступени (двадцать четыре кольца до
    /// задачи A, 20 сен) и полный перепад 0→1; когда спад стал непрерывной
    /// функцией, а амплитуда — половинной (`windowFloor` 0.5), хватило шести.
    /// Хватало ровно до 23 сентября, пока «Атлас» не стал НОЧНЫМ в обеих
    /// темах: до этого в светлой теме выреза не было вовсе
    /// (`carves(palette:)`), и владелец впервые увидел его на светлом
    /// телефоне — «плашка», ровно как у живой `AttributionPlate` в сентябре.
    ///
    /// Видно не перепад, а ФОРМУ: скруглённый прямоугольник, у которого край
    /// кончается за шесть точек. Тридцать две растягивают тот же перепад на
    /// расстояние, на котором глаз перестаёт собирать его в фигуру, — под
    /// подписью остаётся мягкое посветление, а не плита. Контраст при этом не
    /// меняется вовсе: середина окна как была `windowFloor`, так и осталась.
    nonisolated static let feather: CGFloat = 32
    nonisolated static let corner: CGFloat = 8
    /// Минимальная альфа МАСКИ в середине окна — НЕ ноль.
    ///
    /// Маска умножает альфу уже нарисованного растра тумана (`layer.mask`), и
    /// родная альфа мглы ~0.70: при полу-маске (0.5) под подписью остаётся
    /// эффективно ~0.35 — половина обычной мглы, а не её отсутствие. Именно
    /// «отсутствие» (floor 0) на дневной карте «Атласа» давало ЯРКУЮ плиту —
    /// под вырезом лежит не тьма, а светлый дневной MapKit. Числа посчитаны в
    /// `testGlyphContrastInsideTheCarveClearsTheBar`: 0.35 эффективной альфы
    /// держит контраст ~7.5:1 против нужных 4.5:1 по всему диапазону
    /// непрозрачности мглы (`FogVeilPainter.Palette.night.opacityRange`).
    nonisolated static let windowFloor: CGFloat = 0.5

    /// Сколько проходов разметки ждём атрибуцию: она появляется в дереве
    /// карты не обязательно к первому.
    nonisolated static let maxTries = 20

    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "attribution")
    private static var loggedFallback = false

    /// Подстрок ТРИ, и каждая оплачена наблюдением. На iOS 18 атрибуция — это
    /// одна вью `MKAppleLogoLabel` (та самая «` Maps`»), отдельной «Legal» в
    /// этой конфигурации нет вовсе; в других сборках рядом с ней живёт ссылка
    /// со словом `Attribution` или `Legal` в имени. Имена приватные, и Apple
    /// вправе их переписать — поэтому пустой ответ это законный случай.
    static let nameNeedles = ["Attribution", "Logo", "Legal"]

    /// Вьюхи атрибуции — по ПОДСТРОКЕ имени класса, обходом ВШИРЬ.
    static func attributionViews(in root: UIView) -> [UIView] {
        var queue = root.subviews
        var head = 0
        var found: [UIView] = []
        while head < queue.count {
            let view = queue[head]
            head += 1
            let name = NSStringFromClass(type(of: view))
            if nameNeedles.contains(where: name.contains) {
                found.append(view)
                continue
            }
            queue.append(contentsOf: view.subviews)
        }
        return found
    }

    /// Коробка выреза в координатах `space` — объединение всех вьюх атрибуции
    /// с полем. `nil` — вырезать нечего.
    static func carveRect(in root: UIView, space: UIView) -> CGRect? {
        var union = CGRect.null
        for view in attributionViews(in: root) where !view.isHidden && view.bounds.width > 0 {
            union = union.union(view.convert(view.bounds, to: space))
        }
        guard !union.isNull, union.width > 1, union.height > 1 else { return nil }
        return union.insetBy(dx: -padding, dy: -padding)
    }

    /// Нужен ли вырез при этой палитре мглы. **С 26 сентября 2026 — НИКОГДА.**
    ///
    /// Решение владельца на устройстве, принятое с названной ценой: «под Apple
    /// Maps зачем-то тень развеивается, убери это свойство, пусть просто
    /// значок будет поверх тумана, криво это выглядит». Окно и правда читалось
    /// отдельным предметом — растушёвка стояла 32 pt при подписи в две
    /// строки, то есть пятно выходило вдвое шире того, что оно приглушало.
    ///
    /// **Цена принята сознательно.** Подпись Apple красит MapKit по стилю
    /// САМОЙ карты, а карта «Атласа» дневная всегда, — то есть подпись
    /// тёмно-серая. На стиле «Ночь» её контраст на мгле около 1.6 : 1, и без
    /// окна логотип с «Legal» там практически не видны. Прятать их нельзя по
    /// правилам App Store, поэтому это открытый риск на ревью, а не
    /// косметика; стиль при этом не умолчание — его выбирают руками.
    ///
    /// Механизм ЖИВ и проверен (`FogMetalCarveTests`, `VeilCarveMask`):
    /// выключен ровно один ответ, и вернуть окно — снова одна строка. Пока
    /// она стоит так, `carveRect` не зовётся ни разу, а шейдер получает
    /// `carve == nil`.
    static func carves(palette: FogVeilPainter.Palette) -> Bool { false }

    /// Про откат рассказываем один раз за запуск.
    static func noteFallback() {
        guard !loggedFallback else { return }
        loggedFallback = true
        log.notice("атрибуция не найдена — карта возвращается в ночную")
    }
}

/// Маска вуали с вырезом: всё непрозрачно, кроме скруглённого окна под
/// атрибуцией.
///
/// Устроена по тому же принципу, что `VeilRevealMask`: четыре непрозрачные
/// полосы вокруг коробки плюс картинка с мягким окном внутри неё. Прозрачное
/// в маске — это невидимое на экране, то есть открытая карта Apple. Картинка
/// перерисовывается ТОЛЬКО когда коробка меняет размер (разметка, высота
/// листа, поворот), а не на кадр движения карты.
final class VeilCarveMask {
    let layer = CALayer()
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private let window = CALayer()
    private var drawnSize: CGSize = .zero

    init() {
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "sublayers": NSNull()]
        for bar in bars {
            bar.backgroundColor = UIColor.white.cgColor
            bar.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            layer.addSublayer(bar)
        }
        window.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull()]
        layer.addSublayer(window)
    }

    /// Окно и четыре полосы, вместе покрывающие `bounds` без зазора и без
    /// нахлёста. Чистая функция — тестируется без настоящего `CALayer`, и
    /// `update` обязан звать ровно её, а не пересчитывать `box` заново: два
    /// счёта одной геометрии однажды разойдутся, как километры в 0.6.5.
    static func layout(bounds: CGRect, carve: CGRect) -> (window: CGRect, bars: [CGRect]) {
        let box = carve.insetBy(dx: -AttributionCarve.feather, dy: -AttributionCarve.feather)
        return (box, VeilRevealMask.barsAround(bounds: bounds, hole: box))
    }

    /// Ставит вырез. `carve` — уже с полем, в координатах вуали.
    func update(bounds: CGRect, carve: CGRect) {
        layer.frame = bounds
        let (box, barRects) = VeilCarveMask.layout(bounds: bounds, carve: carve)
        window.frame = box
        if drawnSize != box.size {
            window.contents = VeilCarveMask.windowImage(size: box.size)
            window.contentsScale = UIScreen.main.scale
            drawnSize = box.size
        }
        for (bar, rect) in zip(bars, barRects) {
            bar.frame = rect
        }
    }

    /// Белое поле с мягким скруглённым окном посередине.
    ///
    /// Альфа СЧИТАНА, а не наложена кольцами: у каждого пикселя — расстояние
    /// до скруглённого прямоугольника выреза (`carve`, то есть картинка минус
    /// `feather` со всех сторон), поделённое на `feather`. Прежняя версия
    /// клала двадцать четыре сплошных кольца друг на друга, и на устройстве
    /// это читалось не растушёвкой, а «вторым прямоугольником с жёсткой
    /// кромкой» — эффект Маха на границе между соседними ступенями, который
    /// не лечится увеличением их числа (десять колец на 0.6.5 читались
    /// коробкой, двадцать четыре — ореолом с кромкой). У НЕПРЕРЫВНОЙ функции
    /// ступеней нет вовсе, и Маху не на чем сработать. На самой границе
    /// картинки (расстояние ровно `feather`) альфа — точно 1.0, то же самое
    /// значение, что у полос вокруг: край окна и полосы сходятся БЕЗ шва по
    /// построению, а не потому что случайно совпали.
    ///
    /// В центре (расстояние ≤ 0) альфа — не ноль, а `windowFloor`: маска
    /// оставляет мгле половину её обычной силы вместо того, чтобы снимать её
    /// целиком (задача A2, 21 сентября). Полное снятие открывало дневную карту
    /// «Атласа» ЦЕЛИКОМ, и это и читалось «яркой плашкой» — приглушение вместо
    /// выреза решает тот же вопрос читаемости, не вскрывая под подписью
    /// светлый прямоугольник дневной карты.
    static func windowImage(size: CGSize) -> CGImage? {
        guard size.width > 1, size.height > 1 else { return nil }
        let scale = UIScreen.main.scale
        let pixelWidth = max(1, Int((size.width * scale).rounded()))
        let pixelHeight = max(1, Int((size.height * scale).rounded()))
        let cx = size.width / 2, cy = size.height / 2
        // Половина стороны СКРУГЛЁННОГО прямоугольника выреза — той самой
        // `carve`, а не картинки целиком: картинка шире её ровно на `feather`.
        let halfW = size.width / 2 - AttributionCarve.feather
        let halfH = size.height / 2 - AttributionCarve.feather
        let corner = AttributionCarve.corner
        let coreW = max(halfW - corner, 0)
        let coreH = max(halfH - corner, 0)
        let feather = AttributionCarve.feather

        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        // dx/dy по осям считаются один раз на столбец/строку, а не на пиксель
        // — расстояние до скруглённого прямоугольника раскладывается по осям.
        let dxByColumn = (0..<pixelWidth).map { px -> CGFloat in
            let x = (CGFloat(px) + 0.5) / scale
            return max(abs(x - cx) - coreW, 0)
        }
        let dyByRow = (0..<pixelHeight).map { py -> CGFloat in
            let y = (CGFloat(py) + 0.5) / scale
            return max(abs(y - cy) - coreH, 0)
        }
        for py in 0..<pixelHeight {
            let dy = dyByRow[py]
            let rowBase = py * pixelWidth * 4
            for px in 0..<pixelWidth {
                let dx = dxByColumn[px]
                let distance = (dx * dx + dy * dy).squareRoot() - corner
                let ramp = min(max(distance / feather, 0), 1)
                // floor…1, а не 0…1: центр окна оставляет мгле половину силы,
                // а не снимает её целиком (см. докстринг выше).
                let alpha = AttributionCarve.windowFloor
                    + (1 - AttributionCarve.windowFloor) * ramp
                let a = UInt8((alpha * 255).rounded())
                let idx = rowBase + px * 4
                // Премультиплицированный белый: R=G=B=A — маску читают только
                // по альфе, но канал обязан быть согласован с ней.
                pixels[idx] = a
                pixels[idx + 1] = a
                pixels[idx + 2] = a
                pixels[idx + 3] = a
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
