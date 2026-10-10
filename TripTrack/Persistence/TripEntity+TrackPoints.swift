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
    var orderedTrackPoints: [TrackPointEntity] {
        guard let set = trackPoints as? Set<TrackPointEntity> else { return [] }
        return set.sorted(by: TripEntity.trackPointOrder)
    }

    /// Порядок точек: время, при равном — `id`. Без второго ключа две точки
    /// одной секунды (достройка дыры, пул со второго телефона) меняли бы
    /// местами от запуска к запуску.
    static func trackPointOrder(_ a: TrackPointEntity, _ b: TrackPointEntity) -> Bool {
        let ta = a.timestamp ?? .distantPast, tb = b.timestamp ?? .distantPast
        if ta != tb { return ta < tb }
        return (a.id?.uuidString ?? "") < (b.id?.uuidString ?? "")
    }
}
