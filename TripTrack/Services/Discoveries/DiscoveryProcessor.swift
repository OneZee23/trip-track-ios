import Foundation
import CoreLocation
import OSLog

private let processorLog = Logger(subsystem: "com.triptrack", category: "discoveries")

/// Разбор записанного трека на находки — единственный вход к трём матчерам.
///
/// **Зовётся ТОЛЬКО после финиша**, последним в цепочке
/// `PostTripTrackProcessor` → `PlaceManager.process` → `RevealedLayerStore.ingest`:
/// трек к этому моменту окончательный (разрывы залиты, выбросы убраны), места
/// сверены, туман дорисован. Пока идёт запись, здесь не считается ничего — ни
/// подсказок, ни звуков, ни «рядом секрет»: приложение не имеет права звать
/// человека свернуть с дороги. Сторожит это `NoLiveSecretPromptsTests`, а
/// последним рубежом стоит `guard` ниже — он выходит пустым и пишет в лог,
/// а не роняет процесс: упавшая на финише поездка хуже пропущенной печати.
///
/// Каталоги приходят инъекцией (`RiddleCatalog`/`SecretCatalog`): в 0.7.0 они
/// бандловые, в волне 3 к ним добавится серверный, и ни матчеры, ни этот тип от
/// этого не меняются.
///
/// `@MainActor` — как `PlaceManager`, и по той же причине: репозиторий читает
/// `viewContext`, а сам разбор идёт на финише, когда экран уже показывает
/// итоги.
@MainActor
final class DiscoveryProcessor {

    /// Пустой каталог загадок. Живёт здесь, а не в тестах: до слияния с задачей
    /// 2 бандла в дереве нет, и `shared` обязан быть собираемым и безвредным.
    struct EmptyRiddleCatalog: RiddleCatalog {
        func all() -> [Riddle] { [] }
        func candidates(near cells: Set<String>) -> [Riddle] { [] }
    }

    /// То же для секретов. Соль пустая — считать по ней нечего, а каталог пуст.
    struct EmptySecretCatalog: SecretCatalog {
        let salt = ""
        func all() -> [SecretRecord] { [] }
    }

    static let shared = DiscoveryProcessor(
        // TODO(wave2-merge): BundleRiddleCatalog()/BundleSecretCatalog()
        riddleCatalog: EmptyRiddleCatalog(), secretCatalog: EmptySecretCatalog()
    )

    /// Ключ кэша истории в `UserDefaults`: регионы, страны и четыре крайние
    /// точки собственной карты. В базе его нет нарочно — это ПРОИЗВОДНОЕ от
    /// поездок, и потерянный кэш стоит одного перебора превью, а не колонки.
    static let historyKey = "discoveries.extremes"

    /// Значок за первую решённую загадку и за десятую.
    static let firstRiddleBadgeId = "riddle_first"
    static let tenRiddlesBadgeId = "riddle_10"
    static let borderBadgeId = "milestone_border"
    static let altitudeBadgeId = "milestone_2000"
    static let riddlesForSecondBadge = 10

    private let store: DiscoveryStore
    private let repository: TripRepository
    private let riddleCatalog: RiddleCatalog
    private let secretCatalog: SecretCatalog
    private let atlas: RegionAtlas
    private let defaults: UserDefaults
    private let unlockBadge: (String) -> Badge?
    /// Последний рубеж «поездка кончилась». Замыканием, а не чтением флага
    /// напрямую, — чтобы тест мог задать оба ответа, не заводя запись.
    private let isRecording: () -> Bool

    init(store: DiscoveryStore = .shared,
         repository: TripRepository = CoreDataTripRepository(),
         riddleCatalog: RiddleCatalog,
         secretCatalog: SecretCatalog,
         atlas: RegionAtlas = .shared,
         defaults: UserDefaults = .standard,
         unlockBadge: @escaping (String) -> Badge? = { BadgeManager.unlock(id: $0) },
         isRecording: @escaping () -> Bool = { TripManager.isAnyRecording }) {
        self.store = store
        self.repository = repository
        self.riddleCatalog = riddleCatalog
        self.secretCatalog = secretCatalog
        self.atlas = atlas
        self.defaults = defaults
        self.unlockBadge = unlockBadge
        self.isRecording = isRecording
    }

    // MARK: - Разбор

    /// Что нашлось на треке этой поездки.
    ///
    /// Идемпотентно: повторный разбор той же поездки возвращает пустую сводку
    /// (кроме километров из дельты) — за это отвечает `DiscoveryStore.upsert`,
    /// который пишет только то, чего в базе не было, и `Discovery.id`,
    /// выведенный из вида и ключа.
    ///
    /// `.discoveriesChanged` постит стор, и только когда строка действительно
    /// легла: второго поста здесь нет нарочно, иначе «Атлас» перечитывал бы
    /// себя после каждой поездки, на которой ничего не нашлось.
    @discardableResult
    func process(tripId: UUID, delta: RevealedLayerStore.IngestDelta) async -> TripDiscoveries {
        guard !isRecording() else {
            processorLog.error("process called while recording — refused, trip \(tripId, privacy: .public)")
            return .empty(tripId: tripId)
        }
        let empty = TripDiscoveries.empty(
            tripId: tripId, newKm: delta.openedKm, newRegionIds: delta.newRegionIds)
        guard let trip = repository.fetchTripDetail(id: tripId), trip.trackPoints.count > 1 else {
            return empty
        }
        let track = trip.trackPoints

        // 1. Секреты: хеш ячейки, потом `reach`. Каталог пуст — матчер выходит
        //    на первой строке, и трек даже не хешируется.
        let secrets = SecretMatcher.matches(
            track: track, catalog: secretCatalog.all(), salt: secretCatalog.salt)

        // 2. Загадки: кандидаты по ячейкам geohash-5, как у мест.
        let riddles = RiddleMatcher.solved(
            track: track, candidates: riddleCatalog.candidates(near: TrackCells.geohash5(track)))

        // 3. Вехи: история — ПРЕДЫДУЩИЕ поездки, поэтому кэш читается ДО того,
        //    как в него сложат эту.
        let history = loadHistory(excluding: tripId)
        let milestones = MilestoneDetector.detect(
            trip: trip, track: track, history: history, atlas: atlas)

        let found = discoveries(
            trip: trip, secrets: secrets, riddles: riddles, milestones: milestones)
        fold(trip: trip, track: track, into: history)

        guard !found.isEmpty else { return empty }
        let fresh: [Discovery]
        do {
            fresh = try await store.upsert(found)
        } catch {
            processorLog.error("upsert failed: \(error.localizedDescription, privacy: .public)")
            return empty
        }
        guard !fresh.isEmpty else { return empty }

        let result = TripDiscoveries(
            tripId: tripId,
            newKm: delta.openedKm,
            newRegionIds: delta.newRegionIds,
            secrets: fresh.filter { $0.kind == .secret },
            riddles: fresh.filter { $0.kind == .riddle },
            milestones: fresh.filter { $0.kind == .milestone }
        )
        await unlockBadges(for: result)
        processorLog.notice("""
            trip \(tripId, privacy: .public): \(result.secrets.count, privacy: .public) secrets, \
            \(result.riddles.count, privacy: .public) riddles, \
            \(result.milestones.count, privacy: .public) milestones
            """)
        return result
    }

    // MARK: - Находки

    /// Печать стоит в дате поездки, а не в «сейчас»: разбор идёт на финише
    /// секундой позже, но поездка, приехавшая пулом со второго телефона,
    /// разбирается через недели — и печать обязана встать там, где человек был.
    private func discoveries(
        trip: Trip, secrets: [SecretMatch], riddles: [RiddleSolve], milestones: [MilestoneHit]
    ) -> [Discovery] {
        let foundAt = trip.startDate
        var out: [Discovery] = []
        for match in secrets {
            out.append(Discovery(
                kind: .secret, key: match.secretId, tripId: trip.id,
                coordinate: match.coordinate, foundAt: foundAt, symbol: match.symbol))
        }
        for solve in riddles {
            out.append(Discovery(
                kind: .riddle, key: solve.riddle.id, tripId: trip.id,
                coordinate: solve.riddle.coordinate, foundAt: foundAt,
                symbol: solve.riddle.type.symbol, title: solve.riddle.name))
        }
        for hit in milestones {
            out.append(Discovery(
                kind: .milestone, key: hit.key, tripId: trip.id,
                coordinate: hit.coordinate, foundAt: foundAt, symbol: hit.milestone.symbol))
        }
        return out
    }

    // MARK: - Значки

    /// Значки находок — СКРЫТЫЕ и без опыта: находка не награда, а отметка на
    /// своей карте. Открываются они мимо `BadgeStats` (ни одно правило из
    /// статистики поездок не знает про печати), поэтому и пишет их отдельная
    /// дверь — `BadgeManager.unlock(id:)`.
    private func unlockBadges(for result: TripDiscoveries) async {
        for secret in result.secrets {
            // Именной значок автора есть не у каждого секрета — `unlock`
            // отвечает `nil` на незнакомый id, и это законный ответ.
            _ = unlockBadge("secret_\(secret.key)")
        }

        if !result.riddles.isEmpty {
            let solved = await store.discoveries(kind: .riddle).count
            if solved >= 1 { _ = unlockBadge(Self.firstRiddleBadgeId) }
            if solved >= Self.riddlesForSecondBadge { _ = unlockBadge(Self.tenRiddlesBadgeId) }
        }

        for milestone in result.milestones {
            if milestone.key.hasPrefix(Milestone.countryBorder.rawValue) {
                _ = unlockBadge(Self.borderBadgeId)
            }
            if milestone.key.hasPrefix(Milestone.above2000.rawValue) {
                _ = unlockBadge(Self.altitudeBadgeId)
            }
        }
    }

    // MARK: - История собственной карты

    /// Кэш истории: регионы, страны и четыре крайние точки по ПРОЙДЕННЫМ
    /// поездкам.
    ///
    /// Без него каждая веха стоила бы перебора всей библиотеки с атласом на
    /// каждой точке. Складывается монотонно (объединение множеств и максимумы),
    /// поэтому повторное сложение той же поездки ничего не меняет — и
    /// бухгалтерии «какие поездки уже учтены» не нужно.
    private struct HistoryCache: Codable {
        struct Point: Codable {
            let latitude: Double
            let longitude: Double
            var coordinate: CLLocationCoordinate2D {
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            init(_ coordinate: CLLocationCoordinate2D) {
                latitude = coordinate.latitude
                longitude = coordinate.longitude
            }
        }

        var regionIds: [String] = []
        var countryCodes: [String] = []
        var north: Point?
        var south: Point?
        var east: Point?
        var west: Point?
    }

    /// Через сколько точек трека спрашивается атлас при складывании истории.
    /// Точки лежат в пяти метрах, регион — сотни километров: чаще незачем.
    private static let regionSampleStride = 50

    private func loadHistory(excluding tripId: UUID) -> MilestoneDetector.History {
        history(from: cache(excluding: tripId))
    }

    private func history(from cache: HistoryCache) -> MilestoneDetector.History {
        let extremes = MilestoneDetector.Extremes(
            north: cache.north?.coordinate, south: cache.south?.coordinate,
            east: cache.east?.coordinate, west: cache.west?.coordinate)
        let empty = extremes == MilestoneDetector.Extremes()
        return MilestoneDetector.History(
            visitedRegionIds: Set(cache.regionIds),
            visitedCountryCodes: Set(cache.countryCodes),
            // Пустые экстремумы — это «мерить не от чего», а не «нулевая
            // широта»: первая поездка не имеет права выдать четыре печати.
            extremes: empty ? nil : extremes)
    }

    /// Кэш из `UserDefaults`, а если его там нет — собранный по превью всех
    /// ПРОШЛЫХ поездок. Превью, а не точки: крайняя точка карты и регион
    /// упрощение на десяток метров переживают, а подъём миллиона точек на
    /// финише — нет.
    private func cache(excluding tripId: UUID) -> HistoryCache {
        if let data = defaults.data(forKey: Self.historyKey),
           let stored = try? JSONDecoder().decode(HistoryCache.self, from: data) {
            return stored
        }
        var built = HistoryCache()
        for ref in repository.tripPreviews(needingPlaceMatch: false) where ref.id != tripId {
            let coordinates = ref.previewCoordinates
            guard !coordinates.isEmpty else { continue }
            absorb(coordinates, into: &built, regionStride: 1)
        }
        save(built)
        return built
    }

    /// Сложить эту поездку в историю — уже ПОСЛЕ того, как по ней посчитаны
    /// вехи. Иначе «первый регион» не случился бы никогда: он сравнивается с
    /// тем же набором, в который себя и кладёт.
    private func fold(trip: Trip, track: [TrackPoint], into history: MilestoneDetector.History) {
        var cache = HistoryCache(
            regionIds: Array(history.visitedRegionIds),
            countryCodes: Array(history.visitedCountryCodes),
            north: history.extremes?.north.map(HistoryCache.Point.init),
            south: history.extremes?.south.map(HistoryCache.Point.init),
            east: history.extremes?.east.map(HistoryCache.Point.init),
            west: history.extremes?.west.map(HistoryCache.Point.init)
        )
        absorb(track.map(\.coordinate), into: &cache, regionStride: Self.regionSampleStride)
        save(cache)
    }

    private func absorb(
        _ coordinates: [CLLocationCoordinate2D], into cache: inout HistoryCache, regionStride: Int
    ) {
        var regions = Set(cache.regionIds)
        var countries = Set(cache.countryCodes)
        for (index, coordinate) in coordinates.enumerated() {
            if cache.north.map({ coordinate.latitude > $0.latitude }) ?? true {
                cache.north = HistoryCache.Point(coordinate)
            }
            if cache.south.map({ coordinate.latitude < $0.latitude }) ?? true {
                cache.south = HistoryCache.Point(coordinate)
            }
            if cache.east.map({ coordinate.longitude > $0.longitude }) ?? true {
                cache.east = HistoryCache.Point(coordinate)
            }
            if cache.west.map({ coordinate.longitude < $0.longitude }) ?? true {
                cache.west = HistoryCache.Point(coordinate)
            }
            guard index % max(1, regionStride) == 0 || index == coordinates.count - 1 else { continue }
            guard let region = atlas.region(containing: coordinate) else { continue }
            regions.insert(region.id)
            countries.insert(region.countryCode)
        }
        cache.regionIds = regions.sorted()
        cache.countryCodes = countries.sorted()
    }

    private func save(_ cache: HistoryCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: Self.historyKey)
    }

    /// Стирание аккаунта: история — производное от поездок, и пережить их она
    /// не имеет права.
    func forgetHistory() {
        defaults.removeObject(forKey: Self.historyKey)
    }
}
