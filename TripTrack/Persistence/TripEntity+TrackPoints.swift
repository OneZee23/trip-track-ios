import CoreData

/// Точки трека в порядке времени — единственный способ их читать (v23).
///
/// До v23 связь `trackPoints` была упорядоченной (`NSOrderedSet`), и CoreData
/// на КАЖДОМ сохранении пересчитывала ключи порядка, линейно ища каждую точку
/// среди уже записанных. На многочасовой записи сохранение пачки держало
/// главный поток больше двух секунд (Sentry APPLE-IOS-P, 9 окт 2026;
/// `RecordingSaveCostTests`). Порядок при этом и так задавало время:
/// `PostTripTrackProcessor` после каждой поездки сортировал связь по
/// `timestamp`. Теперь связь — простое множество, а порядок восстанавливается
/// здесь, при чтении, по той же `timestamp` и, при равном времени, по `id`,
/// чтобы ответ не зависел от порядка в памяти.
///
/// `entity.trackPoints?.array` больше не существует, а `as? [TrackPointEntity]`
/// у `NSSet` компилируется и молча даёт `nil` — ровно та ловушка 0.8.0 («каст,
/// который всегда nil»). Поэтому все чтения идут через этот файл.
extension TripEntity {
    /// Все точки поездки по времени, включая удалённые в несохранённом контексте.
    ///
    /// Сортируются КЛЮЧИ, а не объекты. Прежний компаратор на каждом из
    /// N·log N сравнений читал `timestamp` и `id` у управляемого объекта: мост
    /// `NSDate` → `Date`, а у ещё не загруженной точки — отдельный запрос в
    /// SQLite. На поездке в десятки тысяч точек это секунды главного потока на
    /// финише записи и на восстановлении (Sentry APPLE-IOS-X, -V, -W, -B,
    /// 0.9.0 (88)). Теперь незагруженные точки поднимаются ОДНИМ запросом,
    /// каждое поле читается один раз, а порядок прежний — держит
    /// `TrackPointOrderTests`.
    var orderedTrackPoints: [TrackPointEntity] {
        guard let set = trackPoints as? Set<TrackPointEntity>, !set.isEmpty else { return [] }
        prefetchFaultedTrackPoints(set)
        return set.map { (key: TrackPointOrderKey($0), point: $0) }
            .sorted { $0.key < $1.key }
            .map(\.point)
    }

    /// Один запрос вместо запроса на каждую точку. Удалённые в несохранённом
    /// контексте запрос не вернёт, но из множества они никуда не деваются:
    /// он только заполняет данные, а ответ по-прежнему собирается из связи.
    private func prefetchFaultedTrackPoints(_ set: Set<TrackPointEntity>) {
        guard let context = managedObjectContext, !objectID.isTemporaryID,
              set.contains(where: \.isFault) else { return }
        let request = NSFetchRequest<TrackPointEntity>(entityName: "TrackPointEntity")
        request.predicate = NSPredicate(format: "trip == %@", self)
        request.returnsObjectsAsFaults = false
        _ = try? context.fetch(request)
    }

    /// Порядок точек: время, при равном — `id`. Без второго ключа две точки
    /// одной секунды (достройка дыры, пул со второго телефона) меняли бы
    /// местами от запуска к запуску.
    static func trackPointOrder(_ a: TrackPointEntity, _ b: TrackPointEntity) -> Bool {
        TrackPointOrderKey(a) < TrackPointOrderKey(b)
    }
}

/// Ключ порядка точки, прочитанный из объекта один раз.
///
/// `id` сравнивается байтами, и это тот же порядок, что у прежнего
/// сравнения `uuidString`: каждый байт печатается двумя шестнадцатеричными
/// цифрами, `0-9` в ASCII идут раньше `A-F`, а дефисы стоят на одних местах.
/// Точка без `id` идёт раньше любой с ним — как пустая строка раньше.
struct TrackPointOrderKey: Comparable {
    let time: TimeInterval
    let id: (UInt64, UInt64)?

    init(time: Date?, id: UUID?) {
        self.time = (time ?? .distantPast).timeIntervalSinceReferenceDate
        self.id = id.map { uuid in
            withUnsafeBytes(of: uuid.uuid) { raw in
                let bytes = Array(raw)
                let hi = bytes[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                let lo = bytes[8..<16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                return (hi, lo)
            }
        }
    }

    init(_ point: TrackPointEntity) {
        self.init(time: point.timestamp, id: point.id)
    }

    static func < (a: Self, b: Self) -> Bool {
        if a.time != b.time { return a.time < b.time }
        switch (a.id, b.id) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (x?, y?): return x < y
        }
    }

    static func == (a: Self, b: Self) -> Bool {
        a.time == b.time && a.id?.0 == b.id?.0 && a.id?.1 == b.id?.1
    }
}
