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
    /// Третьим аргументом поверх обычного сида собирает в путешествие
    /// настоящее плечо дороги («Краснодар → Ростов-на-Дону») и городскую
    /// поездку по месту («По Ростову») — лист публикации (S5) называет
    /// плечи по имени, и без настоящей дороги ему было бы нечего называть:
    /// две городские поездки подряд (как в первой версии сида) дают
    /// «0 плеч, 1 городская поездка» и пустой лист.
    static let journeyArgument = "-seed-journey-demo"
    /// Четвёртым аргументом кладёт на ту же дорогу («Краснодар →
    /// Ростов-на-Дону») две отметки и отрезок между ними: скобка в «Моментах»
    /// иначе не показывается нигде, а завести отрезок руками в UI-тесте —
    /// это два листа и четыре тапа до первого же кадра.
    static let segmentArgument = "-seed-segment-demo"
    /// Пятым аргументом клонирует «Краснодар → Ростов-на-Дону» ещё дважды на
    /// других датах — иначе у мест демо-отрезка (0.6.5+0.6.8) ровно один
    /// проезд, «Здесь 1 раз» ничего не отвечает, и строка истории отрезка
    /// вовсе не рисуется (показывается от двух проездов). Три поездки по
    /// одной дороге дают трём проездам появиться там, где их посчитает
    /// штатная сверка `PlaceManager.reconcile()` на запуске.
    static let placesRichArgument = "-seed-places-rich"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var isPlacesRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(placesArgument)
    }

    static var isPlacesRichRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(placesRichArgument)
    }

    static var isJourneyRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(journeyArgument)
    }

    static var isSegmentRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(segmentArgument)
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
            if isPlacesRichRequested { seedPlacesRich(persistence: persistence) }
            if isPlacesRequested { seedPlaceDemo(persistence: persistence) }
            if isJourneyRequested { seedJourneyDemo(persistence: persistence) }
            if isSegmentRequested { seedSegmentDemo(persistence: persistence) }
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
        if isPlacesRichRequested { seedPlacesRich(persistence: persistence) }
        if isPlacesRequested { seedPlaceDemo(persistence: persistence) }
        if isJourneyRequested { seedJourneyDemo(persistence: persistence) }
        if isSegmentRequested { seedSegmentDemo(persistence: persistence) }
    }

    // MARK: - Богатый сид мест (0.6.8)

    /// Клонирует «Краснодар → Ростов-на-Дону» ещё дважды, на 40 и 66 дней
    /// назад, с теми же точками трека (сдвинутыми во времени) — сама
    /// сверка (`PlaceManager.reconcile()` на запуске) тогда находит у
    /// обоих мест демо-отрезка (`seedSegmentDemo`) три проезда вместо
    /// одного: «Здесь 3 раза» и строка истории отрезка (видна от двух
    /// проездов) становятся видны на симуляторе без трёх дней реальной
    /// записи. Ничего в `PlaceEntity`/`PlacePassEntity` не пишет — это
    /// работа сверки, как у `seedPlaceDemo`.
    ///
    /// Идемпотентно: если поездок с этим названием уже ≥ 3 — выход.
    /// `seedSegmentDemo` и `seedJourneyDemo` сами выбирают среди
    /// одноимённых поездок ту, что нужна им (самую свежую) — см. их
    /// комментарии; здесь достаточно того, что клоны СУЩЕСТВУЮТ, а не
    /// того, где они стоят в списке.
    private static func seedPlacesRich(persistence: PersistenceController) {
        let context = persistence.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", "Краснодар → Ростов-на-Дону")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        guard let matches = try? context.fetch(request), matches.count < 3,
              let original = matches.first, let originalStart = original.startDate else { return }
        let originalPoints = (original.trackPoints?.array as? [TrackPointEntity]) ?? []
        guard !originalPoints.isEmpty else { return }

        for daysAgo in [40, 66] {
            guard let newStart = Calendar.current.date(
                byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            let offset = newStart.timeIntervalSince(originalStart)

            let clone = TripEntity(context: context)
            clone.id = UUID()
            clone.title = original.title
            clone.region = original.region
            clone.isPrivate = true
            clone.distance = original.distance
            clone.maxSpeed = original.maxSpeed
            clone.averageSpeed = original.averageSpeed
            clone.previewPolyline = original.previewPolyline
            clone.startDate = newStart
            clone.endDate = original.endDate.map { $0.addingTimeInterval(offset) }
            // `syncStatus` нарочно не копируется — как у базового сида: файл
            // `#if DEBUG`-only, синка нет, оба остаются на дефолте CoreData.

            for point in originalPoints {
                let copy = TrackPointEntity(context: context)
                copy.id = UUID()
                copy.latitude = point.latitude
                copy.longitude = point.longitude
                copy.altitude = point.altitude
                copy.speed = point.speed
                copy.course = point.course
                copy.horizontalAccuracy = point.horizontalAccuracy
                copy.timestamp = (point.timestamp ?? originalStart).addingTimeInterval(offset)
                copy.trip = clone
            }
        }
        persistence.save()
    }

    // MARK: - Путешествие (0.6.8)

    /// Для скриншотов и QA: путешествие из НАЗВАННЫХ демо-поездок, а не
    /// просто самых свежих. Первая версия сида брала две самые новые поездки
    /// по дате — обе оказались городскими («По городу», «На работу»), а лист
    /// публикации (S5) называет плечи по имени: без настоящей дороги в окне
    /// он показывал «0 плеч, 1 городская поездка» и не мог показать то, ради
    /// чего его сеяли. Берём по названию: «Краснодар → Ростов-на-Дону»
    /// (daysAgo 14) — настоящее плечо дороги, остаётся приватным (сеется так
    /// по умолчанию) и становится именованной строкой в листе публикации
    /// («Краснодар → Ростов-на-Дону · дата · км · сейчас приватная»); «По
    /// Ростову» (daysAgo 12) — городская поездка следом, становится публичной
    /// прямо в сущности и кормит строку «Ещё 1 поездка уже публичная». Если у
    /// «По Ростову» когда-нибудь появятся повторы (`repeats`), в путешествие
    /// уходят ВСЕ его проезды — членство в окне у `JourneyManager.create` и
    /// так считается по дате, а не по счётчику проездов.
    ///
    /// Публичность — прямо в сущности, а не через `TripManager.updatePrivacy`:
    /// та заодно ставит поездку в очередь синка, а гостевому сиду синк не
    /// нужен и без входа в аккаунт всё равно не уйдёт (`SyncEnqueuer.enqueue`).
    /// Идемпотентно: если хоть одно `JourneyEntity` уже есть, повторный запуск
    /// ничего не делает.
    private static func seedJourneyDemo(persistence: PersistenceController) {
        let context = persistence.container.viewContext
        let existing: NSFetchRequest<JourneyEntity> = JourneyEntity.fetchRequest()
        existing.fetchLimit = 1
        if let found = try? context.count(for: existing), found > 0 { return }

        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "title == %@ OR title == %@", "Краснодар → Ростов-на-Дону", "По Ростову")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: true)]
        guard let matches = try? context.fetch(request), !matches.isEmpty else { return }

        let cityLegs = matches.filter { $0.title == "По Ростову" }
        // `-seed-places-rich` клонирует то же название дороги на 40 и 66
        // дней назад — плечом путешествия остаётся только САМЫЙ СВЕЖИЙ из
        // них (daysAgo 14). Окно путешествия ниже берётся по `legs`, и
        // клоны внутри него раздули бы его до 66 дней и утащили в
        // `excludedTripIds` всё, что случилось между («Геленджик → Джубга»,
        // «Сочи → Красная Поляна» и другие демо-маршруты).
        guard let roadLeg = matches
            .filter({ $0.title == "Краснодар → Ростов-на-Дону" })
            .max(by: { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }),
              !cityLegs.isEmpty else { return }

        cityLegs.forEach { $0.isPrivate = false }
        try? context.save()

        let repository = CoreDataTripRepository(persistenceController: persistence)
        let legs = ([roadLeg] + cityLegs).compactMap(\.id).compactMap(repository.fetchTripDetail(id:))
        guard legs.count == 1 + cityLegs.count else { return }

        // `run()` executes synchronously on the main thread (called from
        // `TripTrackApp.init()`, before the first render) — the same
        // guarantee `PersistenceController.viewContext` above already relies
        // on — so it is safe to enter `JourneyManager`'s actor here directly
        // instead of dropping this onto a detached `Task` the way
        // `seedPlaceDemo` does for `PlaceManager`. A detached task would race
        // the UI test, which taps into «Мои» within the same run loop turn.
        MainActor.assumeIsolated {
            _ = try? JourneyManager.shared.create(from: legs, title: "Демо-путешествие")
        }
    }

    // MARK: - Отрезок (0.6.8)

    /// Для скриншотов и QA: две отметки на настоящей дороге и отрезок между
    /// ними. Поездка берётся по НАЗВАНИЮ («Краснодар → Ростов-на-Дону»), как
    /// у путешествия: скобка отрезка показывает «сколько между», и это число
    /// обязано быть похоже на дорогу, а не на круг по кварталу.
    ///
    /// Отметки ставятся на 30 % и 70 % пути по `TripRouteLocator.distancePrefix`
    /// — тем же пятиметровым шагом, каким набирается одометр, иначе «421 км»
    /// в скобке разошлось бы с итогом поездки.
    ///
    /// Через репозиторий, а не через `TripManager`: тот заодно ставит поездку
    /// в очередь синка и зовёт геокодер, чей ответ переписал бы «Кореновск»
    /// настоящим названием посреди кадра. Идемпотентно: у поездки уже есть
    /// отрезок — выход.
    ///
    /// `-seed-places-rich` клонирует то же название на других датах (40 и
    /// 66 дней назад) — сортировка по убыванию `startDate` с `fetchLimit`
    /// держит выбор на САМОЙ СВЕЖЕЙ из них (daysAgo 14, оригинал), а не на
    /// первой попавшейся: без сортировки `fetchLimit = 1` был бы
    /// недетерминирован ровно с того момента, как у названия появился
    /// второй кандидат.
    private static func seedSegmentDemo(persistence: PersistenceController) {
        let context = persistence.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", "Краснодар → Ростов-на-Дону")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TripEntity.startDate, ascending: false)]
        request.fetchLimit = 1
        let repository = CoreDataTripRepository(persistenceController: persistence)
        guard let entity = try? context.fetch(request).first, let tripId = entity.id,
              let trip = repository.fetchTripDetail(id: tripId),
              trip.segments.isEmpty, trip.trackPoints.count > 10 else { return }

        let points = trip.trackPoints
        let prefix = TripRouteLocator.distancePrefix(points)
        let total = prefix.last ?? 0
        guard total > 0 else { return }

        func checkpoint(atFraction fraction: Double, name: String) -> TripCheckpoint? {
            guard let index = prefix.firstIndex(where: { $0 >= total * fraction }) else { return nil }
            let fix = TripRouteLocator.fix(
                at: index, in: points, prefix: prefix, origin: trip.startDate)
            return repository.addCheckpoint(
                TripCheckpoint(
                    timestamp: fix.timestamp,
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude,
                    distanceFromStart: fix.distanceFromStart,
                    elapsedFromStart: fix.elapsedFromStart,
                    name: name),
                to: tripId)
        }

        guard let from = checkpoint(atFraction: 0.3, name: "Кореновск"),
              let to = checkpoint(atFraction: 0.7, name: "Батайск") else { return }
        _ = repository.addSegment(tripId: tripId, fromCheckpointId: from.id, toCheckpointId: to.id)
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
