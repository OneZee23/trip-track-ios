#if DEBUG
import Foundation
import CoreData
import CoreLocation

/// Fills an empty simulator store with a believable set of drives so «Моя
/// карта» can actually be looked at — region fills, clusters, city dots, the
/// region card and the trip card all need real trips to exist.
///
/// Runs ONLY when the `-seed-map-demo` launch argument is present, which
/// nothing but a manual simulator run or a UI test ever passes, and is
/// compiled out of release builds entirely.
enum DebugMapSeed {
    static let launchArgument = "-seed-map-demo"
    /// Вторым аргументом поверх обычного сида поездок добавляет одну отметку
    /// на демо-поездке — иначе «Места» на скриншотах и QA стоят пустой полкой,
    /// а сеять настоящее место настоящим проездом здесь нечем.
    static let placesArgument = "-seed-places-demo"
    /// Третьим аргументом поверх обычного сида собирает две самые старые
    /// демо-поездки в путешествие — иначе карточку и экран путешествия для
    /// скриншотов и QA нечем наполнить, а заводить настоящее объединение
    /// руками на каждом прогоне UI-теста не из чего.
    static let journeyArgument = "-seed-journey-demo"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var isPlacesRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(placesArgument)
    }

    static var isJourneyRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(journeyArgument)
    }

    private struct Route {
        let title: String
        let region: String
        let daysAgo: Int
        let waypoints: [(Double, Double)]
        /// How many times this road was driven. The fog of roads only means
        /// anything when some roads are worn — a commute has to outshine the
        /// one-off run to the sea.
        var repeats: Int = 1
    }

    /// Real roads around Krasnodar Krai, plus one in Rostov Oblast and one in
    /// Georgia, so the map has more than a single blob to show: several
    /// regions, a border crossing, and trips far enough apart to cluster.
    private static let routes: [Route] = [
        Route(title: "Краснодар → Геленджик", region: "Krasnodar Krai", daysAgo: 86,
              waypoints: [(45.035, 38.975), (44.900, 38.780), (44.780, 38.500),
                          (44.640, 38.230), (44.561, 38.077)]),
        Route(title: "Краснодар → Горячий Ключ", region: "Krasnodar Krai", daysAgo: 72,
              waypoints: [(45.035, 38.975), (44.900, 39.020), (44.760, 39.080), (44.630, 39.130)]),
        // The two repeated routes are also the most RECENT, which is what a
        // commute actually is — and it puts them at the top of the region
        // card's trip list, where the fog screenshot test can reach them.
        Route(title: "Утренний круг по бетонке", region: "Krasnodar Krai", daysAgo: 6,
              waypoints: [(45.035, 38.975), (45.090, 39.060), (45.120, 38.980),
                          (45.060, 38.900), (45.035, 38.975)], repeats: 22),
        Route(title: "На работу", region: "Krasnodar Krai", daysAgo: 2,
              waypoints: [(45.035, 38.975), (45.020, 39.030), (45.010, 39.090)], repeats: 9),
        // City blocks, not a highway — without something at this scale the
        // street-zoom screenshot is one line across empty farmland, which is
        // where the fog is easiest to get wrong and hardest to notice.
        Route(title: "По городу", region: "Krasnodar Krai", daysAgo: 1,
              waypoints: [(45.0355, 38.9750), (45.0355, 38.9820), (45.0310, 38.9820),
                          (45.0310, 38.9900), (45.0260, 38.9900), (45.0260, 38.9800),
                          (45.0300, 38.9800), (45.0300, 38.9720), (45.0355, 38.9720),
                          (45.0355, 38.9750)], repeats: 6),
        Route(title: "Геленджик → Джубга", region: "Krasnodar Krai", daysAgo: 54,
              waypoints: [(44.561, 38.077), (44.480, 38.300), (44.400, 38.520), (44.320, 38.700)]),
        Route(title: "Сочи → Красная Поляна", region: "Krasnodar Krai", daysAgo: 33,
              waypoints: [(43.585, 39.723), (43.560, 39.850), (43.600, 40.020),
                          (43.660, 40.130), (43.680, 40.200)]),
        Route(title: "Адлер → Сочи", region: "Krasnodar Krai", daysAgo: 30,
              waypoints: [(43.430, 39.920), (43.470, 39.870), (43.520, 39.800), (43.585, 39.723)]),
        Route(title: "Сочи → Лазаревское", region: "Krasnodar Krai", daysAgo: 21,
              waypoints: [(43.585, 39.723), (43.700, 39.560), (43.820, 39.400), (43.910, 39.330)]),
        Route(title: "Краснодар → Ростов-на-Дону", region: "Rostov Oblast", daysAgo: 14,
              waypoints: [(45.035, 38.975), (45.400, 39.100), (45.900, 39.300),
                          (46.500, 39.500), (47.222, 39.719)]),
        Route(title: "По Ростову", region: "Rostov Oblast", daysAgo: 12,
              waypoints: [(47.222, 39.719), (47.260, 39.760), (47.240, 39.820), (47.200, 39.740)]),
        Route(title: "Батуми → Кобулети", region: "Adjara", daysAgo: 5,
              waypoints: [(41.640, 41.640), (41.720, 41.700), (41.790, 41.760)]),
    ]

    static func run(
        persistence: PersistenceController = .shared,
        territory: TerritoryManager
    ) {
        let context = persistence.container.viewContext
        let existing: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        existing.fetchLimit = 1
        if let found = try? context.count(for: existing), found > 0 {
            // Повторный запуск с тем же аргументом: поездки на месте, сеять
            // маршруты заново незачем, а отметке сеяться, кроме них, негде.
            if isPlacesRequested { seedPlaceDemo(persistence: persistence) }
            if isJourneyRequested { seedJourneyDemo(persistence: persistence) }
            return
        }

        for route in routes {
        for pass in 0..<route.repeats {
            // Real GPS never repeats itself: every pass wanders a few metres
            // either side of the last one, all the way along. That wander is
            // exactly what the fog has to collapse, so the fixture has to
            // have it — a fixed per-pass offset would have let five tidy
            // parallel ribbons pass for one road.
            let coordinates = densify(route.waypoints, stepMeters: 400)
                .enumerated()
                .map { index, point -> CLLocationCoordinate2D in
                    let phase = Double(index) * 0.6 + Double(pass) * 1.7
                    return CLLocationCoordinate2D(
                        latitude: point.latitude + sin(phase) * 0.00008,
                        longitude: point.longitude + cos(phase * 1.3) * 0.00008
                    )
                }
            let start = Calendar.current.date(
                byAdding: .day, value: -(route.daysAgo + pass * 2), to: Date()) ?? Date()
            let seconds = Double(coordinates.count) * 24

            let trip = TripEntity(context: context)
            trip.id = UUID()
            trip.startDate = start
            trip.endDate = start.addingTimeInterval(seconds)
            trip.title = route.title
            trip.region = route.region
            trip.isPrivate = true
            trip.distance = pathLength(coordinates)
            trip.maxSpeed = 32
            trip.averageSpeed = trip.distance / max(seconds, 1)

            for (index, coordinate) in coordinates.enumerated() {
                let point = TrackPointEntity(context: context)
                point.id = UUID()
                point.latitude = coordinate.latitude
                point.longitude = coordinate.longitude
                point.altitude = 40
                // Enough spread that the speed gradient has something to show.
                point.speed = 14 + Double((index * 7) % 18)
                point.course = 0
                point.horizontalAccuracy = 5
                point.timestamp = start.addingTimeInterval(Double(index) * 24)
                point.trip = trip
                territory.recordVisit(coordinate: coordinate)
            }
        }
        }
        persistence.save()
        if isPlacesRequested { seedPlaceDemo(persistence: persistence) }
        if isJourneyRequested { seedJourneyDemo(persistence: persistence) }
    }

    // MARK: - Путешествие (0.6.8)

    /// Для скриншотов и QA: путешествие из двух самых СВЕЖИХ демо-поездок, а
    /// не самых старых. Тот же приём, что уже держит «Утренний круг по
    /// бетонке» наверху карточки региона в фог-сиде («самые новые… карточка
    /// сверху, где до неё дотянется тест»): 47 демо-поездок сортируются в
    /// «Мои» по дате последнего плеча, и карточка путешествия из самых старых
    /// легла бы в самый низ ленты — до неё UI-тест не докрутит за разумное
    /// число свайпов.
    ///
    /// Первая (более ранняя) остаётся приватной (сама поездка уже сеется
    /// так), вторая становится публичной прямо в сущности —
    /// `TripManager.updatePrivacy` заодно ставит поездку в очередь синка, а
    /// гостевому сиду синк не нужен и без входа в аккаунт всё равно не уйдёт
    /// (`SyncEnqueuer.enqueue`). Идемпотентно: если хоть одно `JourneyEntity`
    /// уже есть, повторный запуск ничего не делает.
    private static func seedJourneyDemo(persistence: PersistenceController) {
        let context = persistence.container.viewContext
        let existing: NSFetchRequest<JourneyEntity> = JourneyEntity.fetchRequest()
        existing.fetchLimit = 1
        if let found = try? context.count(for: existing), found > 0 { return }

        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchLimit = 2
        guard let newest = try? context.fetch(request), newest.count == 2,
              let laterId = newest[0].id, let earlierId = newest[1].id else { return }

        newest[1].isPrivate = true
        newest[0].isPrivate = false
        try? context.save()

        let repository = CoreDataTripRepository(persistenceController: persistence)
        guard let first = repository.fetchTripDetail(id: earlierId),
              let second = repository.fetchTripDetail(id: laterId) else { return }

        // `run()` executes synchronously on the main thread (called from
        // `TripTrackApp.init()`, before the first render) — the same
        // guarantee `PersistenceController.viewContext` above already relies
        // on — so it is safe to enter `JourneyManager`'s actor here directly
        // instead of dropping this onto a detached `Task` the way
        // `seedPlaceDemo` does for `PlaceManager`. A detached task would race
        // the UI test, which taps into «Мои» within the same run loop turn.
        MainActor.assumeIsolated {
            _ = try? JourneyManager.shared.create(from: [first, second], title: "Демо-путешествие")
        }
    }

    // MARK: - Отметка (0.6.8)

    /// Для скриншотов и QA: место с историей без реальной поездки — сама
    /// поездка уже засеяна выше, здесь только одна отметка посередине трека.
    /// Идемпотентно: если у выбранной поездки уже есть отметка, повторный
    /// запуск ничего не делает.
    private static func seedPlaceDemo(persistence: PersistenceController) {
        let context = persistence.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: true)]
        guard let trips = try? context.fetch(request),
              let target = trips.first(where: { ($0.trackPoints?.count ?? 0) >= 40 }),
              let tripId = target.id,
              (target.checkpoints?.count ?? 0) == 0 else { return }

        // Через репозиторий, а не через `TripManager`: тот заодно ставит
        // отметку в очередь синка и зовёт геокодер, чей ответ переписал бы
        // «Демо-место» настоящим названием — обоим побочным эффектам здесь не
        // место.
        let repository = CoreDataTripRepository(persistenceController: persistence)
        guard let trip = repository.fetchTripDetail(id: tripId), !trip.trackPoints.isEmpty else { return }

        let points = trip.trackPoints
        let index = points.count / 2
        let prefix = TripRouteLocator.distancePrefix(points)
        let fix = TripRouteLocator.fix(at: index, in: points, prefix: prefix, origin: trip.startDate)
        let checkpoint = TripCheckpoint(
            timestamp: fix.timestamp,
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            distanceFromStart: fix.distanceFromStart,
            elapsedFromStart: fix.elapsedFromStart,
            name: "Демо-место")
        guard let saved = repository.addCheckpoint(checkpoint, to: tripId) else { return }
        // Историю места (проезды по всей библиотеке) досчитает фоновая
        // задача внутри `PlaceManager` — для скриншота и QA достаточно, что
        // место появилось, а не что оно сразу знает «обычно».
        Task { @MainActor in
            PlaceManager.shared.registerCheckpoint(saved, tripId: tripId)
        }
    }

    // MARK: - Geometry

    /// Waypoints alone would leave 40 km between GPS points; the map needs a
    /// track, and the region attribution walks segment midpoints.
    private static func densify(
        _ waypoints: [(Double, Double)], stepMeters: Double
    ) -> [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []
        for i in 1..<waypoints.count {
            let a = CLLocationCoordinate2D(latitude: waypoints[i - 1].0, longitude: waypoints[i - 1].1)
            let b = CLLocationCoordinate2D(latitude: waypoints[i].0, longitude: waypoints[i].1)
            let steps = max(1, Int(GeometryUtils.haversineDistance(a, b) / stepMeters))
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                out.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        if let last = waypoints.last {
            out.append(CLLocationCoordinate2D(latitude: last.0, longitude: last.1))
        }
        return out
    }

    private static func pathLength(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        return (1..<coordinates.count).reduce(0) {
            $0 + GeometryUtils.haversineDistance(coordinates[$1 - 1], coordinates[$1])
        }
    }
}
#endif
