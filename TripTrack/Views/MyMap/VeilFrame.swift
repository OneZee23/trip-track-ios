import MapKit

/// Привязка растра тумана к экрану — аффинная матрица, выведенная из ТРЁХ
/// точек, и невязка, которой она себя проверяет.
///
/// Зачем это отдельный тип. Экранная вуаль (`FogVeilView`) не перерисовывает
/// туман на каждый кадр жеста: она везёт готовый растр за картой одним
/// преобразованием слоя. Верно это ровно до тех пор, пока проекция «мировая
/// точка → экран» остаётся аффинной, то есть пока карта не наклонена: без
/// наклона это перенос, масштаб и поворот, и больше ничего. При наклоне
/// появляется перспектива, которую аффинной матрицей не выразить, — и коридор
/// уедет от дороги под ним.
///
/// Поэтому матрица здесь чистая, а рядом с ней живёт `residual`: она считает
/// ЧЕТВЁРТЫЙ угол двумя способами — матрицей и самой картой — и расходятся они
/// только при наклоне. Так «включили `isPitchEnabled`» падает тестом, а не
/// поездкой.
struct VeilFrame {
    /// Столбцы матрицы: (a, b) — куда уезжает единица ширины растра,
    /// (c, d) — единица его высоты. Сдвиг хранится отдельно, в `origin`.
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let d: CGFloat
    /// Экранная точка левого верхнего угла растра.
    let origin: CGPoint
    /// Размер растра в его собственных точках.
    let size: CGSize

    /// Три угла растра, спроецированные картой: левый верхний, правый верхний,
    /// левый нижний. Четвёртый нарочно НЕ берётся — он и есть проверка.
    init?(p00: CGPoint, p10: CGPoint, p01: CGPoint, size: CGSize) {
        guard size.width > 0, size.height > 0,
              p00.x.isFinite, p00.y.isFinite,
              p10.x.isFinite, p10.y.isFinite,
              p01.x.isFinite, p01.y.isFinite else { return nil }
        a = (p10.x - p00.x) / size.width
        b = (p10.y - p00.y) / size.width
        c = (p01.x - p00.x) / size.height
        d = (p01.y - p00.y) / size.height
        origin = p00
        self.size = size
    }

    /// Преобразование для `CALayer.setAffineTransform`. Сдвига в нём нет:
    /// слой ставится на место своей `position`, иначе один и тот же сдвиг
    /// учитывался бы дважды.
    var transform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: 0, ty: 0)
    }

    /// Куда уехал центр растра — это и есть `position` слоя.
    var centre: CGPoint { point(atX: 0.5, y: 0.5) }

    /// Точка растра, заданная долями его ширины и высоты (0…1).
    func point(atX fx: CGFloat, y fy: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + a * size.width * fx + c * size.height * fy,
            y: origin.y + b * size.width * fx + d * size.height * fy
        )
    }

    /// Насколько предсказание матрицы разошлось с тем, что ответила карта, в
    /// экранных точках. Ноль — проекция аффинна (карта не наклонена).
    func residual(measured: CGPoint, atX fx: CGFloat, y fy: CGFloat) -> CGFloat {
        let predicted = point(atX: fx, y: fy)
        return hypot(measured.x - predicted.x, measured.y - predicted.y)
    }
}

/// Кто и когда имеет право заказать новый растр.
///
/// Правило живёт отдельным типом по той же причине, что `AutoTripPolicy`: во
/// время жеста перерисовка запрещена почти всегда, и ошибка здесь видна не
/// исключением, а забитой фоновой очередью и рывками карты под пальцем. Такое
/// проверяется только счётом.
struct VeilRenderGate {
    /// Чаще этого растр не заказывается НИКОГДА — ни на жесте, ни после него.
    ///
    /// Пять раз в секунду, а не десять: полный кадр `.fine` стоит десятки
    /// миллисекунд, и при десяти заказах в секунду очередь начинает
    /// обгонять сама себя (спайк 15 сен: отдельные кадры доходили до 460 мс
    /// на борьбе за процессор). Потолок задания — «не чаще 10/с», и пять в
    /// него входит с запасом.
    static let throttle: TimeInterval = 0.2

    /// Во сколько раз растр имеет право растянуться, прежде чем считаться
    /// устаревшим. Двойка, а не 1.25: у тумана нет ни одной резкой границы,
    /// кроме перьевого края коридора, — растянутый вдвое он читается тем же
    /// туманом, а перерисовка на каждый щипок забивает очередь.
    static let staleZoomRatio: Double = 2.0

    private var lastRenderAt: TimeInterval = -.greatestFiniteMagnitude
    /// Сколько раз гейт пропустил заказ — счёт для теста «жест не рисует
    /// кадр за кадром».
    private(set) var renders = 0
    /// Мировой прямоугольник растра, который сейчас на экране.
    var raster: MKMapRect?

    /// Нужна ли новая картинка. Два повода: видимое вылезло за край растра или
    /// масштаб ушёл больше чем в `ratio` раз (растр стал мылом).
    ///
    /// `needed` — видимое, ОБРЕЗАННОЕ по миру: на полностью выведенной карте
    /// `visibleMapRect` вылезает за полюса, и сравнение с необрезанным
    /// заказывало бы новый растр каждые сто миллисекунд вечно.
    static func isStale(
        raster: MKMapRect, needed: MKMapRect, ratio: Double, margin: Double
    ) -> Bool {
        if !raster.contains(needed.origin)
            || !raster.contains(MKMapPoint(x: needed.maxX - 1, y: needed.maxY - 1)) { return true }
        guard needed.width > 0 else { return true }
        return raster.width / needed.width > ratio * margin
    }

    /// Можно ли заказывать растр прямо сейчас. Пропуск засчитывается сразу:
    /// отрисовка идёт на фоне, и второй заказ до её конца — это как раз то,
    /// чего гейт не пускает.
    ///
    /// `settled` — камера встала. ВО ВРЕМЯ ЖЕСТА проверка растяжения
    /// выключается вовсе: сто пятьдесят миллисекунд отрисовки посреди щипка
    /// человек видит, а растянутый вдвое туман — нет.
    mutating func allows(
        now: TimeInterval, needed: MKMapRect, settled: Bool, margin: Double
    ) -> Bool {
        let stale: Bool
        if let raster {
            stale = Self.isStale(
                raster: raster, needed: needed,
                ratio: settled ? Self.staleZoomRatio : .greatestFiniteMagnitude,
                margin: margin
            )
        } else {
            stale = true
        }
        guard stale, now - lastRenderAt > Self.throttle else { return false }
        lastRenderAt = now
        renders += 1
        return true
    }

    /// Следующий заказ пойдёт без задержки — данные сменились, и растянутый
    /// туман показывает уже не то, что открыто.
    mutating func invalidate() {
        lastRenderAt = -.greatestFiniteMagnitude
        raster = nil
    }
}
