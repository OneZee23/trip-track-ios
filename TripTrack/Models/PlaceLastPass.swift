import Foundation

/// «Дача · вчера · на 7 мин быстрее обычного» — строка над «Моими местами».
///
/// Это ответ вкладки на вопрос «зачем сюда возвращаться». Список мест честно
/// показывает, что у человека есть, но не даёт повода открыть его во второй
/// раз; а каждая поездка через уже знакомое место оставляет здесь ОДНО
/// сравнение с тем, как обычно, — то самое, ради чего место и заводят.
///
/// Чистой функцией, потому что вся ценность в ГРАНИЦАХ (спека §3.6), и
/// проверяются они числом, а не открытым экраном:
/// - сравнение идёт ВНУТРИ направления, а не со всеми проездами: дорога «туда»
///   и дорога «обратно» занимают разное время, и смешав их, мы сравнивали бы
///   поездку на работу с поездкой домой;
/// - медиана считается БЕЗ последнего проезда и значима от трёх: иначе
///   свежий проезд сравнивался бы сам с собой и «быстрее обычного» выходило бы
///   всегда;
/// - порог двойной — не меньше пяти минут И не меньше десятой доли медианы:
///   находка обязана оставаться редкой, а «быстрее на минуту» после каждой
///   поездки обесценило бы её за неделю;
/// - «дольше обычного» говорится теми же словами и тем же цветом: это не
///   провал, а наблюдение.
enum PlaceLastPass {

    /// Готовая строка для показа.
    struct Reading: Equatable {
        let placeId: UUID
        /// Когда был проезд — печатает уже зовущий, у него язык.
        let at: Date
        /// Насколько отличался от обычного, всегда положительное число секунд.
        let delta: TimeInterval
        /// `true` — быстрее обычного, `false` — дольше.
        let isFaster: Bool
    }

    /// Минимум проездов В НАПРАВЛЕНИИ, при котором медиана что-то значит.
    /// Считается БЕЗ последнего: два «других» проезда — это уже не случайность.
    static let significantPasses = 2

    /// Пороги показа: оба обязаны быть взяты.
    static let minimumDelta: TimeInterval = 5 * 60
    static let minimumShare: Double = 0.1

    /// Сравнить последний проезд места с тем, как обычно.
    ///
    /// `passes` — все проезды ОДНОГО места; порядок не важен.
    static func reading(placeId: UUID, passes: [PlacePass]) -> Reading? {
        guard let last = passes.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        let others = passes.filter { $0.id != last.id }
        // Направление у последнего проезда может быть неизвестно (курса нет) —
        // тогда сравнивать не с чем: брать все проезды подряд значило бы
        // сравнить дорогу туда с дорогой обратно.
        guard last.hasCourse else { return nil }
        let sameWay = others.filter {
            $0.hasCourse
                && PlaceStats.angularDistance($0.course, last.course) <= PlaceStats.directionTolerance
        }
        guard sameWay.count >= significantPasses else { return nil }

        let median = median(of: sameWay.map(\.elapsedFromStart))
        guard median > 0 else { return nil }
        let delta = last.elapsedFromStart - median
        let size = abs(delta)
        guard size >= minimumDelta, size >= median * minimumShare else { return nil }

        return Reading(placeId: placeId, at: last.timestamp, delta: size, isFaster: delta < 0)
    }

    private static func median(of values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}
