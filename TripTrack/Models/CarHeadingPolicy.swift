import Foundation
import CoreLocation

/// Куда смотрит машинка на карте — одно правило на реплей и на живую запись.
///
/// Вынесено чистыми функциями по той же причине, что и `AutoTripPolicy`:
/// проверить их можно тестом, а не поездкой. Всё, что здесь есть, ловили
/// глазами на устройстве и починить «на глаз» уже не получалось — дрожание
/// стоящей машины и прокрутка через весь круг на переходе 359° → 1° выглядят
/// одинаково «как-то не так», а причины у них разные.
///
/// Градусы везде — КУРС, то есть по земле: 0 — север, 90 — восток. Во сколько
/// это превращается на экране, решает `screenAngle(course:cameraHeading:)`, и
/// только он — сглаживать экранный угол нельзя, иначе поворот карты пальцами
/// начнёт спорить со сглаживанием.
enum CarHeadingPolicy {

    // MARK: - Пороги

    /// Ниже этой сырой скорости GPS курс ЗАМОРОЖЕН.
    ///
    /// Пять километров в час. Спрашиваем сырую скорость, а не оценку фильтра —
    /// тем же правилом, которым `TripManager.shouldStoreShapePoint` сторожит
    /// одометр: доплер у стоящей машины честно ноль, а оценка Калмана на
    /// стоянке гуляет от шума позиции. Порог выше, чем у точек формы (0.5 м/с),
    /// и это не разнобой: точке формы важно, что машина СДВИНУЛАСЬ, а курсу —
    /// что она ЕДЕТ. На пешей скорости CoreLocation отдаёт курс, который
    /// меняется на девяносто градусов между двумя фиксами, и маркер на парковке
    /// вертелся бы волчком.
    static let minCourseSpeed: CLLocationSpeed = 1.4

    /// Меньше этого поворота не отрабатываем вовсе.
    ///
    /// Два градуса на длине кузова в 33 pt — это меньше полупикселя на носу,
    /// то есть невидимо. Зато без мёртвой зоны маркер пересчитывается каждый
    /// кадр и на ровной дороге едва заметно «дышит».
    static let deadZone: Double = 2

    /// Какую долю остатка добираем за кадр при 60 кадрах в секунду.
    static let framePull: Double = 0.2

    /// Потолок скорости поворота, градусов в секунду.
    ///
    /// Разворот в 180° занимает секунду. Без потолка скачок курса (въезд в
    /// тоннель и выезд из него) перебрасывал бы нос мгновенно, и глаз читает
    /// это как подмену картинки, а не как поворот.
    static let maxTurnRate: Double = 180

    /// На сколько метров вперёд смотрим в реплее.
    ///
    /// Не по разнице соседних кадров: полилиния хранит координаты в одинарной
    /// точности (шаг около 0.4 м), а при шестидесяти кадрах в секунду машина
    /// проезжает за кадр меньше полуметра — то есть межкадровый сдвиг тонет в
    /// кванте, и знак у него чистый шум. Двенадцать метров — это две длины
    /// машины: достаточно, чтобы поворот был поворотом, и мало, чтобы нос
    /// заранее уезжал в следующий перекрёсток.
    static let lookahead: Double = 12

    /// Ближе этого «вперёд» считать нельзя — там квант хранения, а не дорога.
    static let minLookaheadSpan: Double = 1

    /// С какой точности курса начинается конус «еду примерно туда».
    ///
    /// CoreLocation отдаёт `courseAccuracy` в градусах ±. Двадцать — это
    /// примерно ширина самой машины на длине корпуса: уже неточность, но ещё
    /// не вопрос «в какую сторону». Рисовать конус на всякой честной пятёрке
    /// значило бы держать на экране постоянную кляксу, которая ничего не
    /// сообщает.
    static let coneThreshold: Double = 20

    /// Шире конус не рисуется. Сто двадцать градусов раствора — это уже «не
    /// знаю», и честнее сказать это неподвижным маркером, чем веером во
    /// полкарты.
    static let coneMaxHalfAngle: Double = 60

    // MARK: - Экран

    /// Угол, под которым маркер рисуется НА ЭКРАНЕ.
    ///
    /// Одна формула на оба экрана, и в ней весь фокус: карта, повёрнутая
    /// пальцем или режимом «по курсу», уносит с собой и дорогу под маркером.
    /// В `.followWithHeading` камера сама встаёт носом по движению, разность
    /// обнуляется и машинка смотрит вверх — отдельной ветки на этот режим не
    /// нужно.
    static func screenAngle(course: Double, cameraHeading: Double) -> Double {
        normalized(course - cameraHeading)
    }

    // MARK: - Живая запись

    /// Курс, которому маркер имеет право поверить, или `nil` — «держим прежний».
    ///
    /// Три ворот, и каждые стоят на своём:
    /// - `course == nil` — CoreLocation прямо говорит «не знаю» (у него это −1,
    ///   и до 0.6.7 это −1 превращалось в 0, то есть в «строго на север»);
    /// - `courseAccuracy < 0` — то же самое, сказанное другим полем;
    /// - скорость ниже порога — курс есть, но он про шум, а не про дорогу.
    static func liveCourse(
        course: CLLocationDirection?,
        courseAccuracy: CLLocationDirectionAccuracy,
        rawSpeed: CLLocationSpeed
    ) -> Double? {
        guard let course, course >= 0, courseAccuracy >= 0 else { return nil }
        guard rawSpeed >= minCourseSpeed else { return nil }
        return normalized(course)
    }

    /// Полуугол конуса неуверенности курса, или `nil` — конуса нет.
    ///
    /// Конус рисуется ТОЛЬКО там, где курс есть и он свежий: на стоянке
    /// маркер заморожен и держит последний достоверный угол, и раскрывать
    /// вокруг него веер было бы враньём в другую сторону — «я примерно еду
    /// туда», когда никто никуда не едет.
    ///
    /// Неизвестная точность (−1) конуса тоже не даёт: у CoreLocation это
    /// значит «поля нет», а не «плохо». Такой фикс уже отсеян воротами
    /// `liveCourse`, и рисовать по нему нечего.
    static func coneHalfAngle(
        courseAccuracy: CLLocationDirectionAccuracy,
        rawSpeed: CLLocationSpeed
    ) -> Double? {
        guard courseAccuracy > coneThreshold else { return nil }
        guard rawSpeed >= minCourseSpeed else { return nil }
        return min(courseAccuracy, coneMaxHalfAngle)
    }

    // MARK: - Реплей

    /// Курс по геометрии маршрута: куда машина поедет в ближайшие метры.
    ///
    /// `passed` — индекс последней ПРОЙДЕННОЙ точки серии (тот же, которым
    /// реплей рисует хвост). Метры набираются вдоль трека, а не по прямой:
    /// на серпантине точка в двенадцати метрах пути лежит в трёх по прямой, и
    /// счёт по прямой перепрыгнул бы через весь поворот.
    ///
    /// `nil` — если впереди ничего осмысленного не осталось (конец маршрута
    /// ближе кванта хранения). Тогда держим последний достоверный угол: на
    /// финише машина должна замереть так, как приехала.
    static func courseAlongRoute(
        from position: CLLocationCoordinate2D,
        passed: Int,
        in coords: [CLLocationCoordinate2D],
        lookahead: Double = lookahead
    ) -> Double? {
        guard coords.count >= 2 else { return nil }
        var remaining = lookahead
        var previous = position
        var index = max(0, passed + 1)
        while index < coords.count {
            remaining -= GeometryUtils.haversineDistance(previous, coords[index])
            if remaining <= 0 {
                return bearingIfMeaningful(from: position, to: coords[index])
            }
            previous = coords[index]
            index += 1
        }
        // Маршрут кончился раньше упреждения — целимся в его последнюю точку.
        guard let last = coords.last else { return nil }
        return bearingIfMeaningful(from: position, to: last)
    }

    private static func bearingIfMeaningful(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double? {
        guard GeometryUtils.haversineDistance(a, b) >= minLookaheadSpan else { return nil }
        return GeometryUtils.bearing(from: a, to: b)
    }

    // MARK: - Сглаживание

    /// Кратчайшая дуга между двумя курсами: от 359° до 1° это +2°, а не −358°.
    ///
    /// Знак сохраняем — он и есть сторона поворота. Результат в (−180, 180].
    static func shortestDelta(from current: Double, to target: Double) -> Double {
        let raw = (target - current).truncatingRemainder(dividingBy: 360)
        let wrapped = (raw + 540).truncatingRemainder(dividingBy: 360) - 180
        return wrapped
    }

    /// Один шаг доведения угла к цели.
    ///
    /// `target == nil` — курс заморожен (стоим, или GPS курса не знает): угол
    /// не меняется вовсе. Именно это и значит «не искать курс в шуме»: держим
    /// последний достоверный, а не подставляем север.
    ///
    /// Доля берётся от ОСТАТКА, а не постоянным шагом, поэтому поворот
    /// притормаживает у цели вместо того, чтобы проскочить её и вернуться.
    /// Пересчёт под реальный `dt` держит одинаковую скорость поворота на
    /// 60 и на 120 кадрах: `framePull` задан для кадра в 1/60 секунды.
    /// `instant` — Reduce Motion. Поворот при нём ОСТАЁТСЯ: это информация,
    /// и системная стрелка курса тоже не выключается. Уходит только доводка —
    /// угол встаёт сразу, без пружины. Мёртвая зона остаётся и там: она не
    /// про плавность, а про то, чтобы маркер не дышал на ровной дороге.
    static func smoothed(
        current: Double,
        target: Double?,
        dt: TimeInterval,
        instant: Bool = false
    ) -> Double {
        guard let target else { return normalized(current) }
        let delta = shortestDelta(from: current, to: target)
        guard abs(delta) > deadZone else { return normalized(current) }
        guard !instant else { return normalized(target) }
        guard dt > 0 else { return normalized(current) }

        let pull = 1 - pow(1 - framePull, min(dt, 1) * 60)
        var step = delta * pull
        let cap = maxTurnRate * dt
        step = min(max(step, -cap), cap)
        return normalized(current + step)
    }

    /// Приводит любой угол в [0, 360).
    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
