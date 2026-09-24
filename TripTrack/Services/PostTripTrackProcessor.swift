import Foundation
import CoreData
import CoreLocation

/// Post-trip track reconstruction: removes GPS spikes, fills gaps with
/// straight interpolated points (a road comes later from `RoadGapFiller`) and
/// regenerates trip statistics.
final class PostTripTrackProcessor {

    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    /// Process a single trip: fill gaps, regenerate polyline, recalculate stats.
    func processTrip(_ tripId: UUID) async {
        await MainActor.run {
            processOnContext(tripId)
        }
    }

    /// Process all unprocessed trips (call at app launch).
    func processUnprocessedTrips() async {
        await MainActor.run {
            let context = persistenceController.container.viewContext
            let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "endDate != nil AND isTrackProcessed == NO"
            )

            guard let entities = try? context.fetch(request) else { return }
            for entity in entities {
                guard let id = entity.id else { continue }
                processOnContext(id)
            }
        }
    }

    // MARK: - Core Processing

    private func processOnContext(_ tripId: UUID) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)

        guard let entity = try? context.fetch(request).first else { return }

        // Skip if already processed
        guard !entity.isTrackProcessed else { return }

        // Load original (non-interpolated) track points sorted by timestamp
        guard let allPoints = entity.trackPoints?.array as? [TrackPointEntity] else { return }
        let originalPoints = allPoints
            .filter { !$0.isInterpolated }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        guard originalPoints.count >= 2 else {
            entity.roadFillState = RoadFillState.done.rawValue
            entity.isTrackProcessed = true
            persistenceController.save()
            return
        }

        // Remove spike points (GPS multipath / jumps)
        let cleanedPoints = removeSpikePoints(originalPoints, context: context)
        guard cleanedPoints.count >= 2 else {
            entity.roadFillState = RoadFillState.done.rawValue
            entity.isTrackProcessed = true
            persistenceController.save()
            return
        }
        // Удалённые выбросы уходят из связи только после обработки изменений:
        // без этого достройка ниже считала бы дыры по точкам, которых уже нет.
        context.processPendingChanges()

        // Прямая достройка — сразу; дорогу спросит `RoadGapFiller`, когда
        // будет сеть (спека §2.3).
        let filled = Self.fillOpenGaps(entity: entity, context: context)
        entity.roadFillState = (filled > 0 ? RoadFillState.pending : .done).rawValue

        Self.regeneratePreviewPolyline(for: entity)
        recalculateStats(for: entity)

        entity.isTrackProcessed = true
        entity.lastModifiedAt = Date()
        if filled > 0 {
            // Правка трека = правка поездки: иначе пул вернул бы трек без
            // достройки и заменил бы его целиком.
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
        }
        persistenceController.save()
        if filled > 0 {
            Task { @MainActor in
                SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
            }
        }
    }

    // MARK: - Spike Removal

    /// Remove GPS spike points that deviate too far from the surrounding track.
    /// A spike is a point that creates an implausible detour: the angle between
    /// (prev → point) and (point → next) is sharp AND the point is far from the
    /// straight line between prev and next.
    private func removeSpikePoints(_ points: [TrackPointEntity], context: NSManagedObjectContext) -> [TrackPointEntity] {
        guard points.count >= 3 else { return points }

        var keepFlags = Array(repeating: true, count: points.count)
        // Always keep first and last
        keepFlags[0] = true
        keepFlags[points.count - 1] = true

        for i in 1..<(points.count - 1) {
            let prev = points[i - 1]
            let curr = points[i]
            let next = points[i + 1]

            let locPrev = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let locCurr = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
            let locNext = CLLocation(latitude: next.latitude, longitude: next.longitude)

            let distPrevCurr = locCurr.distance(from: locPrev)
            let distCurrNext = locNext.distance(from: locCurr)
            let distPrevNext = locNext.distance(from: locPrev)

            // Spike detection: the detour via curr is much longer than the direct path
            // (prev → curr → next) vs (prev → next)
            let detour = distPrevCurr + distCurrNext
            let directPath = distPrevNext

            // Skip if distances are too small to judge
            guard directPath > 5 else { continue }

            // A spike creates a large detour ratio
            let detourRatio = detour / max(directPath, 1.0)

            // Also check speed: if the implied speed to reach this point is implausible
            var implausibleSpeed = false
            if let tPrev = prev.timestamp, let tCurr = curr.timestamp {
                let dt = tCurr.timeIntervalSince(tPrev)
                if dt > 0 {
                    let speed = distPrevCurr / dt  // m/s
                    // > 50 m/s (~180 km/h) in city is suspicious
                    if speed > 50 && distPrevCurr > 50 {
                        implausibleSpeed = true
                    }
                }
            }

            // Remove if: big detour (>3.0x) OR implausible speed with moderate deviation
            if detourRatio > 3.0 || (implausibleSpeed && detourRatio > 1.5) {
                keepFlags[i] = false
                context.delete(curr)
            }
        }

        return zip(points, keepFlags).compactMap { $1 ? $0 : nil }
    }

    // MARK: - Достройка

    /// Закрыть прямыми все открытые дыры поездки. Возвращает число дыр.
    /// Общая для финиша и прохода по истории (`RoadGapFiller.scanLibrary`),
    /// поэтому контекст — параметром: проход идёт на фоновом.
    @discardableResult
    static func fillOpenGaps(entity: TripEntity, context: NSManagedObjectContext) -> Int {
        let stored = liveTrackPoints(of: entity)
        let gaps = TrackGapFinder.openGaps(in: stored.compactMap(gapPoint)).filter(GapFill.isFillable)
        guard !gaps.isEmpty else { return 0 }
        let altitudes = altitudeLookup(stored)
        for gap in gaps {
            let fill = GapFill.resample([gap.from.coordinate, gap.to.coordinate],
                                        from: gap.from.timestamp, to: gap.to.timestamp,
                                        altitudeFrom: altitudes[gap.from.timestamp] ?? 0,
                                        altitudeTo: altitudes[gap.to.timestamp] ?? 0)
            for point in fill { insert(point, into: entity, context: context) }
        }
        sortTrackPoints(of: entity)
        return gaps.count
    }

    /// Точки поездки без помеченных на удаление.
    static func liveTrackPoints(of entity: TripEntity) -> [TrackPointEntity] {
        (entity.trackPoints?.array as? [TrackPointEntity] ?? []).filter { !$0.isDeleted }
    }

    static func gapPoint(_ p: TrackPointEntity) -> TrackGapFinder.Point? {
        guard let ts = p.timestamp else { return nil }
        return .init(latitude: p.latitude, longitude: p.longitude, timestamp: ts,
                     isInterpolated: p.isInterpolated)
    }

    /// Высота настоящих точек по времени — края дыры берут её отсюда.
    static func altitudeLookup(_ points: [TrackPointEntity]) -> [Date: Double] {
        var map: [Date: Double] = [:]
        for p in points where !p.isInterpolated {
            if let ts = p.timestamp { map[ts] = p.altitude }
        }
        return map
    }

    static func insert(_ point: TrackPoint, into entity: TripEntity, context: NSManagedObjectContext) {
        let e = TrackPointEntity(context: context)
        e.id = point.id
        e.latitude = point.latitude
        e.longitude = point.longitude
        e.altitude = point.altitude
        e.speed = point.speed
        e.course = point.course
        e.horizontalAccuracy = point.horizontalAccuracy
        e.timestamp = point.timestamp
        e.isInterpolated = point.isInterpolated
        e.trip = entity
    }

    /// Связь с точками ордерная, и новые точки встают в КОНЕЦ. Трек читают без
    /// сортировки (карта, реплей, пейлоад синка с его `sortOrder`), поэтому
    /// после вставки порядок чинится по времени.
    static func sortTrackPoints(of entity: TripEntity) {
        let sorted = liveTrackPoints(of: entity)
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        entity.trackPoints = NSOrderedSet(array: sorted)
    }

    // MARK: - Preview Polyline

    /// Превью — из ВСЕХ сохранённых точек: настоящих, грубых и достроенных. До
    /// 0.8.1 интерполяция жила только в превью, и «Атлас» с картой поездки
    /// спорили о том, где машина ехала (спека §2.3).
    static func regeneratePreviewPolyline(for entity: TripEntity) {
        let coordinates = liveTrackPoints(of: entity)
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard coordinates.count >= 2 else { return }
        let simplified = GeometryUtils.simplifyRDP(coordinates, epsilon: 0.00003)
        entity.previewPolyline = Trip.encodePolyline(simplified)
        // Кэш держал старую форму до перезапуска приложения.
        if let id = entity.id { Trip.invalidatePreviewCache(for: id) }
    }

    // MARK: - Stats Recalculation

    private func recalculateStats(for entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              points.count > 1 else { return }

        let sorted = points.sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }

        // Тот же пятиметровый шаг, что у записи и финализации: три копии этого
        // цикла расходились бы на плотных точках 0.6.5, а побеждала бы та, что
        // отработала последней.
        let trusted = sorted.filter {
            TripDistanceGate.countsForDistance(horizontalAccuracy: $0.horizontalAccuracy,
                                               isInterpolated: $0.isInterpolated)
        }
        let totalDistance = TripDistanceGate.totalDistance(
            trusted.map {
                TripDistanceGate.Sample(latitude: $0.latitude, longitude: $0.longitude, timestamp: $0.timestamp)
            }
        )
        let maxSpeed = trusted.dropFirst().reduce(0.0) { max($0, $1.speed) }

        entity.distance = totalDistance
        entity.maxSpeed = maxSpeed

        if let start = entity.startDate, let end = entity.endDate {
            let elapsed = end.timeIntervalSince(start)
            entity.averageSpeed = elapsed > 0 ? totalDistance / elapsed : 0
        }
    }
}
