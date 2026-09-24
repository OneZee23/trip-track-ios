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

    /// Разбор `MKError` — чистой функцией, а не разбросанными `catch`, чтобы
    /// таблицу кодов проверял тест без единого сетевого запроса (ревью
    /// раунд 1). Не-`MKError` (обрыв сети, таймаут `URLSession` и что угодно
    /// ещё под капотом MapKit) идёт туда же, куда незнакомый код `MKError`:
    /// пробовать снова, а не хоронить дыру по ошибке, которую не разобрали.
    static func from(_ error: Error) -> RoadRouteError {
        guard let code = (error as? MKError)?.code else { return .offline }
        switch code {
        case .loadingThrottled:
            return .throttled
        case .directionsNotFound, .placemarkNotFound, .decodingFailed:
            return .noRoute
        default:
            return .offline
        }
    }
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
        } catch {
            throw RoadRouteError.from(error)
        }
    }
}

/// Дыра, прошедшая фазу 1 («Анализ»): только значения, ни одного managed-
/// объекта — фаза 2 живёт на главном актёре, а объекты фонового контекста
/// фазы 1 её не переживают (контекст — локальная переменная, уходит вместе
/// со стеком). Внутренние точки несёт как ID: фаза 3 найдёт их заново на
/// СВОЁМ, отдельном фоновом контексте.
private struct PendingGap {
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
    let fromTimestamp: Date
    let toTimestamp: Date
    let fromAltitude: Double
    let toAltitude: Double
    let straightMetres: Double
    let seconds: TimeInterval
    let insideIds: [NSManagedObjectID]
}

/// Дыра, для которой маршрутизатор дал правдоподобную дорогу — то, что фаза
/// 2 несёт в фазу 3 для записи.
private struct ResolvedGap {
    let insideIds: [NSManagedObjectID]
    let route: RoadRoute
    let fromTimestamp: Date
    let toTimestamp: Date
    let fromAltitude: Double
    let toAltitude: Double
}

/// Итог фазы 1.
private enum Analysis {
    /// Поездки с таким id нет, или она `pendingDelete` — то же самое для
    /// достройки: воскрешать нечего (правило B, ревью раунд 1).
    case notFound
    /// Дыр, которым имеет смысл искать дорогу, нет — решение окончательное
    /// и уже записано ВНУТРИ фазы 1.
    case nothingToAsk
    case gaps([PendingGap])
}

/// Итог фазы 3.
private enum ApplyResult {
    case notFound
    /// `confirmation` — прочитан ЗДЕСЬ и СЕЙЧАС, для решения про реплей
    /// тумана снаружи: то же значение, унесённое из фазы 1 через две
    /// сетевые паузы фазы 2, успело бы устареть.
    case applied(replaced: Bool, confirmation: String?)
    case saveFailed
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
///
/// **`fill(tripId:)` — три фазы, и ни одна не трогает трек на главном
/// актёре** (CLAUDE.md, «Sentry App Hanging»: библиотечный проход обязан
/// жить вне `viewContext`, а разбор и запись ОДНОЙ поездки — те же точки,
/// просто поездка одна, и правило то же). «Анализ» читает трек и решает, у
/// каких дыр есть шанс на дорогу, на своём фоновом контексте — ничего не
/// пишет, кроме тривиального «дыр нет». «Спросить» — ЕДИНСТВЕННАЯ фаза на
/// главном актёре, потому что только там можно честно спросить «мы на
/// переднем плане и в сети», — и она ничего не пишет, только копит дороги.
/// «Применить» — ВТОРОЙ, свежий фоновый контекст: между «Анализом» и
/// «Применить» прошла сетевая пауза, за которую трек мог смениться под
/// ногами (пул с другого телефона, удаление), поэтому внутренние точки
/// каждой дыры ищутся заново по `NSManagedObjectID`, а не несутся из фазы 1.
/// Она же единственный писатель за весь `fill`: до неё не сохранено ничего,
/// и «наполовину применённое, несортированное» состояние после раннего
/// выхода физически невозможно, а не просто маловероятно.
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
    private let enqueue: @MainActor (UUID) -> Void
    private let cloudSyncEnabled: () -> Bool
    private var isDraining = false
    /// Шаг две секунды держится между ВСЕМИ запросами, а не только внутри
    /// одной поездки: очередь идёт по поездкам подряд.
    private var hasAskedRouter = false
    /// Поездки, упёршиеся в лимит или офлайн В ЭТОЙ сессии: следующий дренаж
    /// спрашивает их ПОСЛЕДНИМИ, чтобы одна и та же недоступная поездка не
    /// держала всю очередь вечно (ревью раунд 1, Review Focus C).
    private var stalled: Set<UUID> = []
    private var observer: NSObjectProtocol?

    init(router: RoadRouter = MKDirectionsRouter(),
         persistence: PersistenceController = .shared,
         isAllowedToRun: @escaping @MainActor () -> Bool = {
             UIApplication.shared.applicationState == .active
                 && !CacheManager.shared.networkMonitor.isOffline
         },
         pause: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
         reveal: @escaping (UUID) async -> Void = { _ = await RevealedLayerStore.shared.ingest(tripId: $0) },
         enqueue: @escaping @MainActor (UUID) -> Void = {
             SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: $0, action: .update))
         },
         cloudSyncEnabled: @escaping () -> Bool = { SettingsManager.shared.cloudSyncEnabled }) {
        self.router = router
        self.persistence = persistence
        self.isAllowedToRun = isAllowedToRun
        self.pause = pause
        self.reveal = reveal
        self.enqueue = enqueue
        self.cloudSyncEnabled = cloudSyncEnabled
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
        // Читаем ДО фонового блока и несём готовым `Bool`: `SettingsManager`
        // не MainActor, но снаружи `perform` это решение видно одной строкой,
        // а не спрятано внутрь цикла по всей библиотеке.
        let cloudSyncOn = cloudSyncEnabled()
        let changed: [UUID] = await context.perform {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "TripEntity")
            request.resultType = .managedObjectIDResultType
            request.predicate = NSPredicate(
                format: "(roadFillState == nil OR roadFillState == %@) AND endDate != nil AND isTrackProcessed == YES AND syncStatus != %d",
                RoadFillState.unchecked.rawValue, SyncStatus.pendingDelete.rawValue)
            let ids = (try? context.fetch(request)) ?? []
            var changed: [UUID] = []
            for objectID in ids {
                // Список id мог устареть за время выборки — поездку могли
                // поставить на удаление между `fetch` и этой строкой
                // (правило B, ревью раунд 1).
                guard let trip = try? context.existingObject(with: objectID) as? TripEntity,
                      trip.syncStatus != SyncStatus.pendingDelete.rawValue else { continue }
                let filledCount = PostTripTrackProcessor.fillOpenGaps(entity: trip, context: context)
                if filledCount > 0 {
                    trip.roadFillState = RoadFillState.pending.rawValue
                    PostTripTrackProcessor.regeneratePreviewPolyline(for: trip)
                    // Правило E: апдейт стоит помечать, только если у него
                    // есть шанс доехать — иначе приватная поездка без облака
                    // стынет «pendingUpload» без единого шанса когда-либо
                    // уйти (то же правило, что у правки отметки).
                    if CoreDataTripRepository.flipsPendingUpload(isPrivate: trip.isPrivate,
                                                                  cloudSyncEnabled: cloudSyncOn) {
                        trip.syncStatus = SyncStatus.pendingUpload.rawValue
                    }
                    trip.lastModifiedAt = Date()
                } else {
                    trip.roadFillState = RoadFillState.done.rawValue
                }
                // По одной: точки библиотеки не копятся в памяти контекста, а
                // смерть процесса на середине не теряет сделанного.
                do {
                    try context.save()
                    // В очередь синка — только после того, как сохранение
                    // ДЕЙСТВИТЕЛЬНО случилось: обещать доставку несохранённой
                    // правки нечем (правило F, ревью раунд 1).
                    if filledCount > 0, let id = trip.id { changed.append(id) }
                } catch {
                    fillLog.error("library scan save failed: \(String(describing: error), privacy: .public)")
                    context.rollback()
                }
                context.reset()
            }
            return changed
        }
        for id in changed { enqueue(id) }
        fillLog.notice("library scan: \(changed.count, privacy: .public) trips got straight fills")
        return changed.count
    }

    // MARK: Очередь

    /// Цикл «спроси свежий список — обработай одну поездку — повтори»: не
    /// список на весь дренаж, а перезапрос перед каждой поездкой — запись,
    /// финишировавшая ПОКА дренаж уже идёт, обязана попасть в ЭТОТ ЖЕ
    /// проход, а не ждать следующего `didBecomeActive` (ревью раунд 1,
    /// Review Focus C).
    func drainIfPossible() async {
        guard !isDraining, isAllowedToRun() else { return }
        isDraining = true
        defer { isDraining = false }

        var visited: Set<UUID> = []
        while let id = await nextPendingId(excluding: visited) {
            visited.insert(id)
            switch await fill(tripId: id) {
            case .done, .notFound:
                // Больше не застряла (или уже не поездка вовсе) — покидает
                // хвост следующего дренажа.
                stalled.remove(id)
            case .stillPending:
                stalled.insert(id)
                return
            }
        }
    }

    /// Следующая поездка на обработку: новее — раньше, поездки, упёршиеся в
    /// лимит РАНЬШЕ в этой же сессии, — позже. Список читается на фоновом
    /// контексте типизированным `NSDictionary`-запросом — на главном актёре
    /// не должно оказаться ни одной строки трека, только id.
    private func nextPendingId(excluding visited: Set<UUID>) async -> UUID? {
        let context = persistence.newBackgroundContext()
        let stalledNow = stalled
        return await context.perform {
            let request = NSFetchRequest<NSDictionary>(entityName: "TripEntity")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["id"]
            request.predicate = NSPredicate(format: "roadFillState == %@ AND syncStatus != %d",
                                            RoadFillState.pending.rawValue, SyncStatus.pendingDelete.rawValue)
            request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
            let ids = ((try? context.fetch(request)) ?? [])
                .compactMap { $0["id"] as? UUID }
                .filter { !visited.contains($0) }
            let fresh = ids.filter { !stalledNow.contains($0) }
            let laggards = ids.filter { stalledNow.contains($0) }
            return (fresh + laggards).first
        }
    }

    /// Одна поездка, три фазы — «Анализ» (фоновый контекст) → «Спросить»
    /// (главный актёр, ничего не пишет) → «Применить» (второй фоновый
    /// контекст, единственный писатель). См. доккомментарий класса.
    func fill(tripId: UUID) async -> Outcome {
        switch await analyse(tripId: tripId) {
        case .notFound:
            return .notFound
        case .nothingToAsk:
            return .done
        case .gaps(let pending):
            let (resolved, askedAll) = await ask(pending)
            // Читаем ПРЯМО перед фоновым блоком «Применить» — тот же приём,
            // что в `scanLibrary`.
            let cloudSyncOn = cloudSyncEnabled()
            switch await apply(tripId: tripId, resolved: resolved, askedAll: askedAll, cloudSyncEnabled: cloudSyncOn) {
            case .notFound:
                return .notFound
            case .saveFailed:
                // Не сохранилось — трек остался как был, поездка ждёт
                // следующего раза; в очередь синка ставить нечего.
                return .stillPending
            case .applied(let replaced, let confirmation):
                if replaced {
                    enqueue(tripId)
                    // Дорога открывает туман по-настоящему; у черновика в
                    // атлас не ходит ничего (спека §3.2).
                    if confirmation != TripConfirmation.draft.rawValue {
                        await reveal(tripId)
                    }
                }
                return askedAll ? .done : .stillPending
            }
        }
    }

    // MARK: Фаза 1 — анализ

    /// Читает трек и решает, у каких дыр есть шанс на дорогу, — целиком на
    /// фоновом контексте, главного актёра эта фаза не трогает вовсе. Ничего
    /// не пишет, кроме тривиального случая «дыр нет»: решение там уже
    /// окончательное, гонять поездку через «Спросить»/«Применить» вхолостую
    /// незачем.
    private func analyse(tripId: UUID) async -> Analysis {
        let context = persistence.newBackgroundContext()
        return await context.perform {
            let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND syncStatus != %d",
                                            tripId as CVarArg, SyncStatus.pendingDelete.rawValue)
            guard let entity = try? context.fetch(request).first else { return .notFound }

            let stored = PostTripTrackProcessor.liveTrackPoints(of: entity)
            let altitudes = PostTripTrackProcessor.altitudeLookup(stored)
            let gaps = TrackGapFinder
                .gaps(in: stored.compactMap(PostTripTrackProcessor.gapPoint), includeFilled: true)
                .filter(GapFill.isFillable)

            var pending: [PendingGap] = []
            for gap in gaps {
                let inside = stored.filter {
                    guard $0.isInterpolated, let ts = $0.timestamp else { return false }
                    return ts > gap.from.timestamp && ts < gap.to.timestamp
                }
                let insideCoordinates = inside.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                guard GapFill.isStraight(insideCoordinates, from: gap.from.coordinate, to: gap.to.coordinate)
                else { continue }
                pending.append(PendingGap(
                    fromCoordinate: gap.from.coordinate, toCoordinate: gap.to.coordinate,
                    fromTimestamp: gap.from.timestamp, toTimestamp: gap.to.timestamp,
                    fromAltitude: altitudes[gap.from.timestamp] ?? 0,
                    toAltitude: altitudes[gap.to.timestamp] ?? 0,
                    straightMetres: gap.straightMetres, seconds: gap.seconds,
                    insideIds: inside.map(\.objectID)))
            }

            guard !pending.isEmpty else {
                entity.roadFillState = RoadFillState.done.rawValue
                try? context.save()
                return .nothingToAsk
            }
            return .gaps(pending)
        }
    }

    // MARK: Фаза 2 — спросить

    /// Дыру за дырой, на главном актёре — единственном месте, где честно
    /// спросить «мы на переднем плане и в сети». Ничего не пишет, только
    /// копит дороги, которые фаза «Применить» вставит одним махом.
    /// `askedAll == false` значит «встали раньше конца» (лимит, сеть, уход в
    /// фон) — то, что осталось в `pending`, эта фаза даже не смотрела.
    private func ask(_ pending: [PendingGap]) async -> (resolved: [ResolvedGap], askedAll: Bool) {
        var resolved: [ResolvedGap] = []
        for gap in pending {
            guard isAllowedToRun() else { return (resolved, false) }
            if hasAskedRouter { await pause(Self.requestSpacing) }
            // Пауза сама способна увести приложение в фон — спросить ЕЩЁ РАЗ
            // сразу перед запросом (спека §2.5: «только на переднем плане»).
            guard isAllowedToRun() else { return (resolved, false) }
            hasAskedRouter = true

            let route: RoadRoute
            do {
                route = try await router.route(from: gap.fromCoordinate, to: gap.toCoordinate)
            } catch RoadRouteError.noRoute {
                continue
            } catch {
                fillLog.notice("road fill postponed: \(String(describing: error), privacy: .public)")
                return (resolved, false)
            }
            guard GapFill.isPlausible(routeMetres: route.distance, routeSeconds: route.expectedTravelTime,
                                      straightMetres: gap.straightMetres, gapSeconds: gap.seconds)
            else { continue }
            resolved.append(ResolvedGap(insideIds: gap.insideIds, route: route,
                                        fromTimestamp: gap.fromTimestamp, toTimestamp: gap.toTimestamp,
                                        fromAltitude: gap.fromAltitude, toAltitude: gap.toAltitude))
        }
        return (resolved, true)
    }

    // MARK: Фаза 3 — применить

    /// Второй, СВЕЖИЙ фоновый контекст — объекты фазы 1 в нём не живут
    /// (между «Анализом» и «Применить» прошла сетевая пауза, а с ней и шанс,
    /// что трек сменился под ногами), поэтому внутренние точки каждой дыры
    /// ищутся заново по `NSManagedObjectID`. Единственный писатель за весь
    /// `fill`: до неё не сохранено ровно ничего, и «наполовину применённое»
    /// состояние после раннего выхода из `fill` невозможно физически, а не
    /// по соглашению.
    private func apply(tripId: UUID, resolved: [ResolvedGap], askedAll: Bool,
                       cloudSyncEnabled: Bool) async -> ApplyResult {
        let context = persistence.newBackgroundContext()
        return await context.perform {
            let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND syncStatus != %d",
                                            tripId as CVarArg, SyncStatus.pendingDelete.rawValue)
            // Поездку могли удалить, пока «Спросить» ждало сеть — тот же
            // предикат, что у «Анализа», исключает и её саму, и надгробие.
            guard let entity = try? context.fetch(request).first else { return .notFound }

            var replaced = false
            var anySkipped = false
            for gap in resolved {
                let insidePoints: [TrackPointEntity] = gap.insideIds.compactMap { id in
                    guard let object = try? context.existingObject(with: id), !object.isDeleted,
                          let point = object as? TrackPointEntity, point.trip == entity
                    else { return nil }
                    return point
                }
                guard insidePoints.count == gap.insideIds.count else {
                    // Трек сменился под ногами (пул с другого телефона) —
                    // дыру пропускаем, следующий проход посчитает её заново.
                    anySkipped = true
                    continue
                }
                insidePoints.forEach(context.delete)
                for point in GapFill.resample(gap.route.coordinates, from: gap.fromTimestamp, to: gap.toTimestamp,
                                              altitudeFrom: gap.fromAltitude, altitudeTo: gap.toAltitude) {
                    PostTripTrackProcessor.insert(point, into: entity, context: context)
                }
                replaced = true
            }

            if replaced {
                PostTripTrackProcessor.sortTrackPoints(of: entity)
                PostTripTrackProcessor.regeneratePreviewPolyline(for: entity)
                entity.lastModifiedAt = Date()
                if CoreDataTripRepository.flipsPendingUpload(isPrivate: entity.isPrivate,
                                                              cloudSyncEnabled: cloudSyncEnabled) {
                    entity.syncStatus = SyncStatus.pendingUpload.rawValue
                }
            }
            // «Готово» — только если «Спросить» дошла до конца списка И ни
            // одна собранная дорога не пропущена: иначе то, что осталось
            // несмотренным или несогласованным, обязано попасть в следующий
            // проход, а не застыть «сделано» с недоделанным треком внутри.
            entity.roadFillState = (askedAll && !anySkipped)
                ? RoadFillState.done.rawValue : RoadFillState.pending.rawValue

            let confirmation = entity.confirmation
            do {
                try context.save()
            } catch {
                fillLog.error("road fill apply failed: \(String(describing: error), privacy: .public)")
                return .saveFailed
            }
            return .applied(replaced: replaced, confirmation: confirmation)
        }
    }
}
