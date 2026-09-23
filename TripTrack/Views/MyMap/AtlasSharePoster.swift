import UIKit
import MapKit
import os

/// Постер «Атласа»: снимок карты, накрытый ТЕМ ЖЕ туманом, что на экране, с
/// прожжёнными коридорами, печатями найденного и одной подписью внизу.
///
/// Зачем он вообще собирается руками. `MKMapSnapshotter` НЕ рисует оверлеи —
/// ни вуаль, ни жилку, ни аннотации, — поэтому «просто снять карту» дало бы
/// открытую карту Apple: картинку МИРА вместо картинки того, что человек
/// открыл. Ровно ради этого случая кисть тумана разрезана на чистые функции
/// (`FogVeilPainter`, `FogVeilBitmap.render`): постер рисует туман тем же
/// кодом и на тех же порогах, что экран, и разъехаться им нечем.
///
/// Композиция — ЧИСТАЯ функция (`render`): на вход готовый снимок, окно,
/// слой открытого, найденные печати и уже собранная подпись; на выход
/// картинка. Ни сети, ни языка, ни базы внутри — иначе проверялось бы это
/// только глазами на телефоне, а проверять надо пиксель: светлее ли коридор
/// тумана и стоит ли печать там, куда её проецирует карта.
///
/// Единиц и склонений здесь нет НАРОЧНО: подпись приезжает строкой, собранной
/// `Measure` и `AppStrings` у экрана. Второй сборщик расстояния в проекте
/// завёл бы вторые километры — ту же поломку, из-за которой одометр собрали в
/// `TripDistanceGate`.
enum AtlasSharePoster {
    /// Почему постер не собрался — в системный лог. Отказ здесь молчаливый по
    /// природе: лист «Поделиться» всё равно откроется с текстом, и без этой
    /// строки «картинки нет» отличить от «картинка есть, но человек выбрал
    /// „Скопировать“» нечем.
    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "atlas-share")


    // MARK: - Размеры

    /// Портрет 540×960 точек при `renderScale` = 2, то есть 1080×1920
    /// пикселей — рабочий размер картинки для мессенджеров и «Историй».
    ///
    /// Точки + 2×, а не 1080 точек при 1×: MapKit растеризует свои подписи и
    /// обводки дорог под масштаб трейта, и на 1× снимок выходит заметно мягче
    /// при том же итоговом разрешении (то же решение, что у
    /// `SharePosterRenderer`).
    static let renderPointSize = CGSize(width: 540, height: 960)
    static let renderScale: CGFloat = 2

    /// Высота нижней плашки с подписью, в точках постера.
    static let captionHeight: CGFloat = 148

    /// Диаметр печати на постере. Крупнее экранных 26 pt: постер смотрят
    /// уменьшенным в ленте мессенджера, и медальон в 26 pt там становится
    /// точкой.
    static let sealSize: CGFloat = 34

    /// Запас вокруг открытого, долями его же размера. Без него крайняя дорога
    /// упирается в край картинки и читается как обрезанная.
    static let padding: Double = 0.10

    /// Минимальная сторона окна в метрах. Один двор, снятый без пола, уехал бы
    /// на уровень зданий, где туман — это просто тёмный экран.
    static let minimumSpanMetres: Double = 4_000

    // MARK: - Чистая композиция

    /// Собрать постер поверх готового снимка.
    ///
    /// - Parameters:
    ///   - snapshot: картинка карты РОВНО на `region` (её размер в точках и
    ///     задаёт размер постера).
    ///   - region: окно, которым снимок снят. Проекция считается от него же —
    ///     см. `mapRect(for:)`, парная к `region(for:)`.
    ///   - layer: открытое — из него и вуаль, и коридоры, и жилка.
    ///   - seals: НАЙДЕННОЕ. Список уже только найденное (`MyMapViewModel
    ///     .seals` читает базу находок), и ничего не найденного сюда прийти не
    ///     может: круги подсказок (`riddleHints`) — отдельный тип и в постер
    ///     не передаются вовсе. Нарисовать подсказку значило бы выдать то,
    ///     ради чего загадка и существует.
    ///   - caption: уже собранная строка подписи.
    static func render(
        snapshot: UIImage,
        region: MKCoordinateRegion,
        layer: RevealedLayer,
        seals: [Discovery],
        caption: String,
        scale: CGFloat
    ) -> UIImage {
        let size = snapshot.size
        let rect = mapRect(for: region)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            snapshot.draw(in: CGRect(origin: .zero, size: size))

            drawVeil(in: cg, rect: rect, size: size, scale: scale, layer: layer)
            drawSeals(rect: rect, size: size, scale: scale, seals: seals)
            drawCaption(in: cg, size: size, caption: caption)
        }
    }

    /// Туман тем же кодом, которым его рисует экран.
    ///
    /// Правило 0.7.0 — постер обязан рисовать ТУ ЖЕ картинку, что экран, — и
    /// Metal его не отменяет, а меняет исполнителя: с 0.8.0 «Атлас» рисует
    /// мглу `FogMetalVeil`, значит и снимок накрывается ей же —
    /// `FogOffscreen.render` собирает тот же кадр теми же порогами, только
    /// без экрана. Растровый путь остаётся ОТКАТОМ: Metal выключен флагом или
    /// недоступен на устройстве — постер собирает `FogVeilBitmap.render`, и
    /// отличается он от экрана ровно так же, как и сам экран в откате.
    ///
    /// Окна под подписью Apple (`carve`) у постера нет: подписи в кадре нет
    /// вовсе, вырезать нечего.
    ///
    /// В откате индекс путей собирается прямо здесь, синхронно: постер
    /// рисуется в фоне и один раз, а ждать фоновую сборку ради одной картинки
    /// незачем.
    private static func drawVeil(
        in cg: CGContext, rect: MKMapRect, size: CGSize, scale: CGFloat, layer: RevealedLayer
    ) {
        guard !layer.isEmpty else { return }
        if FogMetalAvailability.isActive,
           let image = FogOffscreen.render(
               layer: layer, rect: rect, sizePoints: size, scale: scale,
               palette: FogVeilPainter.palette) {
            // Кадр офскрина лежит РОВНО на `rect`, без припуска, — значит и
            // кладётся он на всю картинку.
            place(image, in: cg, box: CGRect(origin: .zero, size: size), size: size)
            return
        }
        // Облака — синхронно, как и индекс: постер собирается в фоне и один
        // раз, а туман без них разошёлся бы с экраном.
        CloudTexture.shared.prepare()
        let index = MapPathIndex()
        index.prepare(
            source: { layer.polylines(for: $0) },
            transform: { CGPoint(x: $0.x, y: $0.y) }
        )
        guard let band = FogVeilBitmap.render(
            rect: rect, sizePoints: size, scale: scale, index: index, selected: [],
            visited: Set(layer.regionKm.filter { $0.value > 0 }.map(\.key))
        ) else { return }

        // Растр приходит с припуском снизу (`drawnRect`), поэтому кладётся по
        // нему, а не по запрошенному прямоугольнику: иначе постер растянул бы
        // картинку на пиксель и размыл край коридора.
        let drawn = band.drawnRect
        let box = CGRect(
            x: CGFloat((drawn.minX - rect.minX) / rect.width) * size.width,
            y: CGFloat((drawn.minY - rect.minY) / rect.height) * size.height,
            width: CGFloat(drawn.width / rect.width) * size.width,
            height: CGFloat(drawn.height / rect.height) * size.height
        )
        place(band.image, in: cg, box: box, size: size)
    }

    /// Положить кадр тумана в постер. Оба пути — и Metal, и растр — кладут
    /// картинку ОДНИМ способом: разойдись они переворотом, туман встал бы
    /// вверх ногами ровно у одного из них, и заметить это можно было бы
    /// только глазами.
    private static func place(
        _ image: CGImage, in cg: CGContext, box: CGRect, size: CGSize
    ) {
        cg.saveGState()
        // CGImage рисуется в перевёрнутой системе координат UIKit.
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(x: box.minX, y: size.height - box.maxY,
                                  width: box.width, height: box.height))
        cg.restoreGState()
    }

    /// Печати рисуются `UIImage.draw(in:)`, то есть в ТЕКУЩИЙ контекст UIKit,
    /// который открыл `UIGraphicsImageRenderer`: медальон приходит готовым от
    /// `SealPainter`, и перекладывать его в `CGContext` руками значило бы
    /// потерять его масштаб.
    private static func drawSeals(
        rect: MKMapRect, size: CGSize, scale: CGFloat, seals: [Discovery]
    ) {
        guard !seals.isEmpty else { return }
        for seal in seals {
            let point = project(seal.coordinate, rect: rect, size: size)
            // Печать за краем картинки стоит целого медальона: её рисование
            // CoreGraphics всё равно отбросит, а кэш `SealPainter` она
            // засеет.
            guard point.x > -sealSize, point.x < size.width + sealSize,
                  point.y > -sealSize, point.y < size.height + sealSize else { continue }
            let image = SealPainter.image(
                kind: seal.kind, symbol: seal.symbol, size: sealSize, scale: scale)
            image.draw(in: CGRect(
                x: point.x - sealSize / 2, y: point.y - sealSize / 2,
                width: sealSize, height: sealSize))
        }
    }

    /// Плашка внизу: рампа в цвет вуали, подпись и марка.
    ///
    /// Рампа, а не сплошная полоса: постер обязан читаться как одна картинка,
    /// а не как карта с приклеенной подписью. Цвет — `veilColorBottom`, то
    /// есть тот же, которым туман кончается на нижнем крае экрана.
    private static func drawCaption(in cg: CGContext, size: CGSize, caption: String) {
        let strip = CGRect(x: 0, y: size.height - captionHeight,
                           width: size.width, height: captionHeight)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                FogVeilPainter.veilColorBottom.withAlphaComponent(0).cgColor,
                FogVeilPainter.veilColorBottom.withAlphaComponent(0.88).cgColor,
                FogVeilPainter.veilColorBottom.withAlphaComponent(0.97).cgColor,
            ] as CFArray,
            locations: [0, 0.55, 1]
        ) {
            cg.saveGState()
            cg.clip(to: strip)
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: strip.midX, y: strip.minY),
                end: CGPoint(x: strip.midX, y: strip.maxY),
                options: [.drawsAfterEndLocation]
            )
            cg.restoreGState()
        }

        let inset: CGFloat = 32
        let width = size.width - inset * 2
        let line = fitted(caption, font: font("Inter-ExtraBold", size: 27, weight: .heavy),
                          width: width, floor: 17)
        let captionSize = line.size()
        line.draw(at: CGPoint(x: inset, y: size.height - 84 - captionSize.height / 2))

        let mark = NSAttributedString(string: "TripTrack", attributes: [
            .font: font("Inter-SemiBold", size: 15, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.45),
            .kern: 0.6,
        ])
        mark.draw(at: CGPoint(x: inset, y: size.height - 46))
    }

    /// Строка, ужатая по ширине плашки. Постер печатается на тринадцати
    /// языках, и немецкая подпись длиннее русской на четверть — обрезать её
    /// многоточием значило бы потерять число, ради которого постер и сняли.
    private static func fitted(
        _ text: String, font: UIFont, width: CGFloat, floor: CGFloat
    ) -> NSAttributedString {
        var size = font.pointSize
        while size > floor {
            let candidate = font.withSize(size)
            let string = NSAttributedString(string: text, attributes: [
                .font: candidate, .foregroundColor: UIColor.white,
            ])
            if string.size().width <= width { return string }
            size -= 1
        }
        return NSAttributedString(string: text, attributes: [
            .font: font.withSize(floor), .foregroundColor: UIColor.white,
        ])
    }

    /// Inter с откатом на системный: шрифт регистрируется в рантайме
    /// (`TripTrackApp`), а постер собирается и в тесте, где регистрации не
    /// было.
    private static func font(_ name: String, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    // MARK: - Проекция

    /// Точка на картинке по координате — той же проекцией, которой снят снимок.
    static func project(
        _ coordinate: CLLocationCoordinate2D, rect: MKMapRect, size: CGSize
    ) -> CGPoint {
        let point = MKMapPoint(coordinate)
        return CGPoint(
            x: CGFloat((point.x - rect.minX) / rect.width) * size.width,
            y: CGFloat((point.y - rect.minY) / rect.height) * size.height
        )
    }

    /// Окно → мировой прямоугольник, углами.
    ///
    /// Пара `region(for:)` / `mapRect(for:)` обязана быть обратимой: окно
    /// уезжает в `MKMapSnapshotter`, а проекция печатей считается от
    /// прямоугольника, и разойдись они — печать встала бы мимо своей дороги.
    /// Считать середину окна СРЕДНИМ ПО МИРОВЫМ ТОЧКАМ нельзя: Меркатор не
    /// линеен по широте, и середина прямоугольника в точках карты не равна
    /// середине его широт в градусах.
    static func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(
            x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x), height: abs(bottomRight.y - topLeft.y))
    }

    /// Мировой прямоугольник → окно, обратимо к `mapRect(for:)`.
    static func region(for rect: MKMapRect) -> MKCoordinateRegion {
        let top = MKMapPoint(x: rect.midX, y: rect.minY).coordinate
        let bottom = MKMapPoint(x: rect.midX, y: rect.maxY).coordinate
        let left = MKMapPoint(x: rect.minX, y: rect.midY).coordinate
        let right = MKMapPoint(x: rect.maxX, y: rect.midY).coordinate
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (top.latitude + bottom.latitude) / 2,
                longitude: (left.longitude + right.longitude) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: abs(top.latitude - bottom.latitude),
                longitudeDelta: abs(right.longitude - left.longitude))
        )
    }

    /// Окно постера по открытому: коробка всего открытого с запасом, полом и
    /// пропорцией картинки.
    ///
    /// Пропорция подгоняется ЗДЕСЬ, а не оставляется снапшоттеру: тот
    /// раздвинет окно сам, вернёт картинку на другое окно и молча — а проекция
    /// печатей считается по тому окну, которое мы ему дали.
    static func frame(for layer: RevealedLayer, size: CGSize = renderPointSize) -> MKMapRect? {
        guard !layer.isEmpty, size.width > 0, size.height > 0 else { return nil }
        var rect = layer.fine.boundingMapRect
        // Нулевая сторона — это НЕ поломка: дорога вдоль одной параллели даёт
        // коробку нулевой высоты, и раньше она возвращала бы `nil`, то есть
        // «постера у тебя нет». Её выправляет пол ниже, поэтому проверяется
        // только осмысленность чисел.
        guard rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height >= 0 else { return nil }
        rect = rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)

        let metre = MKMapPointsPerMeterAtLatitude(
            MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude)
        let floorWidth = minimumSpanMetres * metre
        if rect.width < floorWidth {
            rect = rect.insetBy(dx: -(floorWidth - rect.width) / 2, dy: 0)
        }
        if rect.height < floorWidth {
            rect = rect.insetBy(dx: 0, dy: -(floorWidth - rect.height) / 2)
        }

        // Пропорция: растягиваем ту сторону, которой не хватает, — обрезать
        // открытое ради формы нельзя.
        let wanted = Double(size.width / size.height)
        let have = rect.width / rect.height
        if have < wanted {
            rect = rect.insetBy(dx: -(rect.height * wanted - rect.width) / 2, dy: 0)
        } else if have > wanted {
            rect = rect.insetBy(dx: 0, dy: -(rect.width / wanted - rect.height) / 2)
        }
        return rect
    }

    // MARK: - Снимок

    /// Снять карту и собрать постер. `nil` — открывать нечего или снимок не
    /// пришёл (сеть); зовущий в этом случае делится одним текстом.
    @MainActor
    static func make(vm: MyMapViewModel, caption: String) async -> UIImage? {
        let layer = vm.revealed
        let seals = vm.seals
        guard let rect = frame(for: layer) else {
            log.notice("постер: открытого нет, картинки не будет")
            return nil
        }
        let window = region(for: rect)
        guard let snapshot = await snapshot(region: window) else {
            log.notice("постер: снимок карты не приехал")
            return nil
        }
        guard !looksUnrendered(snapshot) else {
            log.notice("постер: вместо карты пустая сетка")
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            render(snapshot: snapshot, region: window, layer: layer, seals: seals,
                   caption: caption, scale: renderScale)
        }.value
    }

    /// СВЕТЛАЯ карта без точек интереса — та же подложка, что под туманом на
    /// экране.
    ///
    /// Светлая, а не тёмная, с 23 сентября: карта «Атласа» —
    /// единственная дневная в приложении (`MyMapRepresentable`,
    /// `overrideUserInterfaceStyle = .light`), и это про полярность, а не про
    /// тему: сквозь тёмную мглу должна просвечивать светлая карта. Постер
    /// оставался ночным с 17 сентября и показывал не то, что на экране, — а
    /// правило у него одно: та же картинка теми же числами. Лесенка повторов — от `SharePosterRenderer`: холодная выборка
    /// плиток регулярно приходит пустой с первого раза.
    static func snapshot(region: MKCoordinateRegion) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let options = MKMapSnapshotter.Options()
            options.region = region
            options.size = renderPointSize
            options.scale = renderScale
            options.pointOfInterestFilter = .excludingAll
            let config = MKStandardMapConfiguration(elevationStyle: .flat)
            config.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = config
            options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

            for delay in [UInt64(0), 700_000_000, 2_000_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                if Task.isCancelled { return nil }
                if let snapshot = try? await MKMapSnapshotter(options: options).start() {
                    return snapshot.image
                }
            }
            return nil
        }.value
    }

    /// Снимок, который МОЖНО показать: `nil` — карты в нём нет.
    ///
    /// Одна дверь на два места показа: постер (`make` выше) и мини-карта
    /// решённой загадки на карточке (`RiddleMiniMap`). Там и там ответ один —
    /// пустая сетка с водяным знаком «Maps» хуже, чем честный тёмный фон.
    static func usableSnapshot(_ image: UIImage?) -> UIImage? {
        guard let image, !looksUnrendered(image) else { return nil }
        return image
    }

    /// Пришла ли вместо карты ПУСТАЯ сетка MapKit.
    ///
    /// `MKMapSnapshotter.start()` не отказывает, когда плиток нет: он отдаёт
    /// светлую подложку в клетку с «Maps» в углу (проверено на симуляторе без
    /// доступа к плиткам). Туман такую подложку накроет, а вот в прожжённых
    /// коридорах она окажется БЕЛОЙ — постер с белыми дорогами по чёрному не
    /// похож ни на экран, ни на карту; лучше отдать один текст, как и при
    /// полном отказе снимка.
    ///
    /// Два условия сразу, и второе важнее первого: подложка не только светлая,
    /// но и РОВНАЯ. Настоящая карта — вода, зелень, подписи, дороги — даёт
    /// разброс даже в светлой теме, и одной яркости хватило бы, чтобы
    /// однажды съесть постер человеку, у которого карта просто светлая.
    static func looksUnrendered(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return true }
        let side = 24
        var data = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }

        var luminance: [Double] = []
        luminance.reserveCapacity(side * side)
        for i in stride(from: 0, to: data.count, by: 4) {
            luminance.append(0.299 * Double(data[i + 2]) + 0.587 * Double(data[i + 1])
                             + 0.114 * Double(data[i]))
        }
        let mean = luminance.reduce(0, +) / Double(luminance.count)
        guard mean > 230 else { return false }
        let flat = luminance.filter { abs($0 - mean) < 8 }.count
        return Double(flat) / Double(luminance.count) > 0.9
    }

    // MARK: - Лист «Поделиться»

    /// Системный лист с картинкой и текстом.
    ///
    /// Ждать свободный контроллер обязательно — по той же причине, что и у
    /// `ShareLinkPresenter`: лист поднимается из действия, которое отработало,
    /// пока ещё закрывался предыдущий, и UIKit молча роняет `present` на
    /// контроллере в переходе. Отсюда же и `topPresentedViewController` —
    /// «Атлас» живёт под своим листом, и корневой контроллер показать поверх
    /// него не сможет.
    @MainActor
    static func present(image: UIImage?, text: String, title: String) async {
        for _ in 0..<20 {
            if let top = ShareLinkPresenter.topPresentedViewController(),
               !top.isBeingDismissed,
               top.presentedViewController == nil {
                var items: [Any] = []
                if let image { items.append(PosterActivityItem(image: image, title: title)) }
                items.append(text)
                let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
                av.popoverPresentationController?.sourceView = top.view
                av.popoverPresentationController?.sourceRect = CGRect(
                    x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1
                )
                top.present(av, animated: true)
                return
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }
}

/// Постер, объявленный листу картинкой.
///
/// Файлом `.png` во временной папке, а не голой `UIImage`: так лист называет
/// вложение и говорит «Изображение PNG», а мессенджеры отправляют его
/// фотографией, а не перекодированным блобом из буфера обмена (то же решение,
/// что у `StoryShareSheet.shareImage`). Голая картинка остаётся откатом на
/// случай, когда файл не записался.
final class PosterActivityItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let title: String
    private let file: URL?

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
        self.file = {
            guard let png = image.pngData() else { return nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TripTrack-Atlas")
                .appendingPathExtension("png")
            return (try? png.write(to: url, options: .atomic)) == nil ? nil : url
        }()
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        file ?? image
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewController(
        _ controller: UIActivityViewController,
        thumbnailImageForActivityType activityType: UIActivity.ActivityType?,
        suggestedSize size: CGSize
    ) -> UIImage? {
        image
    }
}
