import Foundation
import CoreData
import CoreLocation
import MapKit
import UIKit
import os

private let fillLog = Logger(subsystem: "com.triptrack", category: "road-fill")

/// Дорога между краями дыры — ответ маршрутизатора.
struct RoadRoute {
    let coordinates: [CLLocationCoordinate2D]
    let distance: Double
    let expectedTravelTime: TimeInterval
}

enum RoadRouteError: Error, Equatable {
    /// Сети нет или Apple не ответил — попробовать потом.
    case offline
    /// Лимит запросов Apple — попробовать потом.
    case throttled
    /// Дороги между краями нет — прямая остаётся навсегда.
    case noRoute
}

protocol RoadRouter {
    func route(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> RoadRoute
}

struct MKDirectionsRouter: RoadRouter {
    func route(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async throws -> RoadRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { throw RoadRouteError.noRoute }
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid,
                                                   count: route.polyline.pointCount)
            route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: route.polyline.pointCount))
            return RoadRoute(coordinates: coords, distance: route.distance,
                             expectedTravelTime: route.expectedTravelTime)
        } catch let error as RoadRouteError {
            throw error
        } catch let error as MKError where error.code == .loadingThrottled {
            throw RoadRouteError.throttled
        } catch let error as MKError where error.code == .directionsNotFound {
            throw RoadRouteError.noRoute
        } catch {
            throw RoadRouteError.offline
        }
    }
}

/// Заменяет прямую достройку дорогой (спека §2.3) и проходит по старым
/// поездкам (§2.5).
///
/// Очередь последовательная и неспешная: не чаще запроса в две секунды,
/// только на переднем плане и при сети — у `MKDirections` есть лимит, и
/// история в сотни поездок не имеет права его выбрать. Отказ по лимиту или
/// сети — это `pending`, а не ошибка.
///
/// Прямая, открытая в тумане на финише, остаётся открытой и после того, как
/// её заменила дорога: у слоя открытого нет отката (CLAUDE.md, «Туман»). Так
/// же вела себя интерполяция Кэтмулла–Рома до 0.8.1 — новой беды это не
/// заводит, а дорога дописывает к ней настоящий коридор.
@MainActor
final class RoadGapFiller {
    static let shared = RoadGapFiller()
    static let requestSpacing: Duration = .seconds(2)

    enum Outcome: Equatable { case done, stillPending, notFound }

    private let router: RoadRouter
    private let persistence: PersistenceController
    private let isAllowedToRun: @MainActor () -> Bool
    private let pause: (Duration) async -> Void
    private let reveal: (UUID) async -> Void
    private var isDraining = false
    /// Шаг две секунды держится между ВСЕМИ запросами, а не только внутри
    /// одной поездки: очередь идёт по поездкам подряд.
    private var hasAskedRouter = false
    private var observer: NSObjectProtocol?

    init(router: RoadRouter = MKDirectionsRouter(),
         persistence: PersistenceController = .shared,
         isAllowedToRun: @escaping @MainActor () -> Bool = {
             UIApplication.shared.applicationState == .active
                 && !CacheManager.shared.networkMonitor.isOffline
         },
         pause: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         reveal: @escaping (UUID) async -> Void = { _ = await RevealedLayerStore.shared.ingest(tripId: $0) }) {
        self.router = router
        self.persistence = persistence
        self.isAllowedToRun = isAllowedToRun
        self.pause = pause
        self.reveal = reveal
    }

    /// Возвращение в приложение — повод дожать очередь.
    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.drainIfPossible() }
        }
    }

    // MARK: Старые поездки

    /// Поездки, которые ещё никто не смотрел (`unchecked`, уже обработанные
    /// финишем): прямая достройка сразу, дорога — очередью. Километры не
    /// пересчитываются — достройка в них не входит (спека §2.5).
    ///
    /// На СВОЁМ фоновом контексте и по одной поездке: проход трогает каждую
    /// поездку библиотеки, а главный поток держать нельзя (Sentry App
    /// Hanging, CLAUDE.md). Идемпотентно: поездка покидает `unchecked` за один
    /// проход, а пустая выборка — «делать нечего», без всякого латча.
    @discardableResult
    func scanLibrary() async -> Int {
        let context = persistence.newBackgroundContext()
        let changed: [UUID] = await context.perform {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "TripEntity")
            request.resultType = .managedObjectIDResultType
            request.predicate = NSPredicate(
                format: "(roadFillState == nil OR roadFillState == %@) AND endDate != nil AND isTrackProcessed == YES AND syncStatus != %d",
                RoadFillState.unchecked.rawValue, SyncStatus.pendingDelete.rawValue)
            let ids = (try? context.fetch(request)) ?? []
            var changed: [UUID] = []
            for objectID in ids {
                guard let trip = try? context.existingObject(with: objectID) as? TripEntity else { continue }
                if PostTripTrackProcessor.fillOpenGaps(entity: trip, context: context) > 0 {
                    trip.roadFillState = RoadFillState.pending.rawValue
                    PostTripTrackProcessor.regeneratePreviewPolyline(for: trip)
                    trip.syncStatus = SyncStatus.pendingUpload.rawValue
                    trip.lastModifiedAt = Date()
                    if let id = trip.id { changed.append(id) }
                } else {
                    trip.roadFillState = RoadFillState.done.rawValue
                }
                // По одной: точки библиотеки не копятся в памяти контекста, а
                // смерть процесса на середине не теряет сделанного.
                try? context.save()
                context.reset()
            }
            return changed
        }
        for id in changed {
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: .update))
        }
        fillLog.notice("library scan: \(changed.count, privacy: .public) trips got straight fills")
        return changed.count
    }

    // MARK: Очередь

    func drainIfPossible() async {
        guard !isDraining, isAllowedToRun() else { return }
        isDraining = true
        defer { isDraining = false }
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "roadFillState == %@ AND syncStatus != %d",
                                        RoadFillState.pending.rawValue, SyncStatus.pendingDelete.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        let ids = ((try? persistence.container.viewContext.fetch(request)) ?? []).compactMap(\.id)
        for id in ids {
            if await fill(tripId: id) == .stillPending { return }
        }
    }

    /// Одна поездка: каждую ещё ПРЯМУЮ (или пустую) дыру — дорогой, если
    /// маршрут правдоподобен. Уже дорогу не трогает — второй раз не спрашивает.
    func fill(tripId: UUID) async -> Outcome {
        let context = persistence.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
        guard let entity = try? context.fetch(request).first else { return .notFound }

        let stored = PostTripTrackProcessor.liveTrackPoints(of: entity)
        let altitudes = PostTripTrackProcessor.altitudeLookup(stored)
        let gaps = TrackGapFinder
            .gaps(in: stored.compactMap(PostTripTrackProcessor.gapPoint), includeFilled: true)
            .filter(GapFill.isFillable)
        var replaced = false

        for gap in gaps {
            let inside = stored.filter {
                guard $0.isInterpolated, let ts = $0.timestamp else { return false }
                return ts > gap.from.timestamp && ts < gap.to.timestamp
            }
            let insideCoordinates = inside.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            guard GapFill.isStraight(insideCoordinates, from: gap.from.coordinate, to: gap.to.coordinate) else { continue }

            guard isAllowedToRun() else { return .stillPending }
            if hasAskedRouter { await pause(Self.requestSpacing) }
            hasAskedRouter = true

            let route: RoadRoute
            do {
                route = try await router.route(from: gap.from.coordinate, to: gap.to.coordinate)
            } catch RoadRouteError.noRoute {
                continue
            } catch {
                fillLog.notice("road fill postponed: \(String(describing: error), privacy: .public)")
                return .stillPending
            }
            // Пока ждали ответа, поездку могли удалить.
            guard !entity.isDeleted, entity.managedObjectContext != nil else { return .notFound }
            guard GapFill.isPlausible(routeMetres: route.distance, routeSeconds: route.expectedTravelTime,
                                      straightMetres: gap.straightMetres, gapSeconds: gap.seconds) else { continue }

            inside.forEach(context.delete)
            for point in GapFill.resample(route.coordinates, from: gap.from.timestamp, to: gap.to.timestamp,
                                          altitudeFrom: altitudes[gap.from.timestamp] ?? 0,
                                          altitudeTo: altitudes[gap.to.timestamp] ?? 0) {
                PostTripTrackProcessor.insert(point, into: entity, context: context)
            }
            replaced = true
        }

        entity.roadFillState = RoadFillState.done.rawValue
        if replaced {
            PostTripTrackProcessor.sortTrackPoints(of: entity)
            PostTripTrackProcessor.regeneratePreviewPolyline(for: entity)
            entity.syncStatus = SyncStatus.pendingUpload.rawValue
            entity.lastModifiedAt = Date()
        }
        persistence.save()
        guard replaced else { return .done }
        SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
        // Дорога открывает туман по-настоящему; у черновика в атлас не ходит
        // ничего (спека §3.2).
        if entity.confirmation != TripConfirmation.draft.rawValue {
            await reveal(tripId)
        }
        return .done
    }
}
