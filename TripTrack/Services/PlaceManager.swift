import Foundation
import Combine
import CoreLocation

/// Места (0.6.8): отметка рождает место, поездка оставляет проезды.
///
/// Пять входов, и все ведут сюда:
///  • новая отметка → место (или уже известное) + история по библиотеке;
///  • финиш поездки (после `PostTripTrackProcessor`, на окончательном треке) →
///    проезды мимо всех мест;
///  • пул синка → сверка: отметки без места, поездки без сверки;
///  • удаление поездки → её проезды забываются;
///  • запуск → та же сверка, что после пула (`placesMatchedAt` помнит,
///    что уже сделано, поэтому обычный запуск не стоит ничего).
///
/// Всё считается на главном потоке через `viewContext` — как
/// `TerritoryManager.backfillIfNeeded` и `PostTripTrackProcessor`; между
/// поездками — `Task.yield()`, чтобы первая сверка большой библиотеки не
/// замораживала экран. Точки поездки поднимаются ТОЛЬКО для кандидатов
/// предфильтра: у большинства поездок мест рядом нет.
@MainActor
final class PlaceManager: ObservableObject {
    static let shared = PlaceManager()

    @Published private(set) var places: [Place] = []

    private let repository: TripRepository
    private let store: PlaceStore
    private var cancellables = Set<AnyCancellable>()
    /// Досчёт истории после новой отметки идёт отдельной задачей; тесты и
    /// вызывающие, которым нужен результат, ждут её через `settle()`.
    private var backfillTask: Task<Void, Never>?
    /// Сверка в одном экземпляре: пул приходит поверх стартовой сверки.
    private var isReconciling = false

    /// Сколько поездок сверки помечается одной пачкой.
    private static let matchBatch = 200

    init(repository: TripRepository = CoreDataTripRepository(),
         store: PlaceStore = CoreDataPlaceStore(context: PersistenceController.shared.container.viewContext)) {
        self.repository = repository
        self.store = store
        reload()
        // Поездка и отметки со второго телефона приезжают пулом прямо в
        // CoreData — мимо всех, кто зовёт менеджер руками.
        NotificationCenter.default.publisher(for: .syncPullCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reconcile() }
            }
            .store(in: &cancellables)
    }

    func reload() { places = store.fetchPlaces() }

    func passes(for placeId: UUID) -> [PlacePass] { store.passes(placeId: placeId) }

    func stats(for placeId: UUID) -> PlaceStats { PlaceStats.build(from: store.passes(placeId: placeId)) }

    /// Дождаться досчёта истории, начатого `registerCheckpoint`.
    func settle() async { await backfillTask?.value }

    // MARK: - Отметка → место

    /// Каждая отметка с координатой — место; две в одной ячейке — одно.
    /// Новое место сразу получает историю по всей библиотеке; у известного
    /// история уже есть, а проезд ЭТОЙ поездки допишет финиш (или сверка,
    /// если поездка уже завершена).
    /// `recording` — отметка поставлена на ходу, кнопкой: тогда история нового
    /// места откладывается (см. `deferHistory`).
    func registerCheckpoint(_ checkpoint: TripCheckpoint, tripId: UUID, recording: Bool = false) {
        let cell = Place.cell(latitude: checkpoint.latitude, longitude: checkpoint.longitude)
        let (place, isNew) = store.upsertPlace(cell: cell, coordinate: checkpoint.coordinate, name: checkpoint.name)
        repository.setPlaceId(forCheckpoint: checkpoint.id, placeId: place.id)
        store.recomputeCentroid(placeId: place.id, from: repository.checkpointCoordinates(placeId: place.id))
        reload()
        // «Новое» — это место БЕЗ истории, а не только что вставленная строка:
        // геокодер на тёплом кэше заводит место именем раньше регистрации
        // (см. `adoptName`), и по `isNew` такое место осталось бы без
        // бэкфилла навсегда.
        if isNew || store.passCount(placeId: place.id) == 0 {
            if recording {
                deferHistory(place.id)
            } else {
                backfillTask = Task { [weak self] in
                    await self?.matchAllTrips(against: place)
                }
            }
        } else if repository.tripPreviews(needingPlaceMatch: false).contains(where: { $0.id == tripId }) {
            backfillTask = Task { [weak self] in
                await self?.process(tripId: tripId)
            }
        }
    }

    /// Геокодер назвал отметку — безымянное место берёт то же имя.
    ///
    /// Имя приходит из кэша геокодера СИНХРОННО, то есть раньше, чем
    /// регистрация проставит отметке `placeId` (порядок вызовов в
    /// `TripManager.addCheckpoint`). Пока имя искали по `placeId`, у дома и
    /// знакомых регионов — где кэш как раз тёплый — место оставалось
    /// безымянным навсегда. Поэтому место берём по ЯЧЕЙКЕ отметки: она даёт
    /// тот же id (`Place.id(forCell:)`), и гонки больше нет.
    func adoptName(_ name: String, forCheckpoint id: UUID, tripId: UUID) {
        guard let checkpoint = repository.fetchTripDetail(id: tripId)?
                .checkpoints.first(where: { $0.id == id }) else { return }
        if let placeId = checkpoint.placeId {
            // Место уже зарегистрировано — или это надгробие удалённого, и
            // тогда заводить его заново нельзя.
            store.adoptName(name, forPlace: placeId)
        } else {
            // Регистрация ещё не дошла: заводим место сразу с именем, она
            // найдёт его уже названным (и досчитает историю — проездов у него
            // ещё нет).
            let cell = Place.cell(latitude: checkpoint.latitude, longitude: checkpoint.longitude)
            store.upsertPlace(cell: cell, coordinate: checkpoint.coordinate, name: name)
        }
        reload()
    }

    // MARK: - Поездка → проезды

    /// Проезды одной поездки мимо всех мест. Зовётся после финиша (на
    /// окончательном треке). Поездка без мест рядом всё равно помечается
    /// сверенной — иначе запуск перебирал бы её вечно.
    func process(tripId: UUID) async {
        // Нет среди завершённых — поездка ещё пишется или уже удалена: сверять
        // нечего, и метку ставить НЕЛЬЗЯ (её финиш тогда сверки не получит).
        // С финиша ссылка находится всегда — трек только что закрыт.
        if let ref = repository.tripPreviews(needingPlaceMatch: false)
            .first(where: { $0.id == tripId }) {
            await process(ref, places: store.fetchPlaces())
            repository.markPlacesMatched(tripId: tripId)
        }
        await drainPendingHistory()
    }

    /// То же, но ссылку и список мест держит вызывающий: сверка библиотеки
    /// берёт их ОДИН раз на весь проход, а не на каждую поездку — при тысяче
    /// поездок это был миллион строк превью с блобами на главном потоке.
    /// Метку «сверено» ставит вызывающий, пачкой.
    func process(_ ref: TripPreviewRef, places: [Place]) async {
        let candidates = candidatePlaces(for: ref, places: places)
        guard !candidates.isEmpty,
              let trip = repository.fetchTripDetail(id: ref.id), trip.trackPoints.count > 1 else { return }
        // Одна выборка проездов на поездку, а не по одной на каждое место.
        let existing = store.passes(tripId: ref.id)
        var changed = false
        for place in candidates {
            let passes = PlaceMatcher.passes(through: place, tripId: trip.id, points: trip.trackPoints, startDate: trip.startDate)
            if !passes.isEmpty || existing.contains(where: { $0.placeId == place.id }) {
                store.replacePasses(placeId: place.id, tripId: trip.id, with: passes)
                changed = true
            }
        }
        if changed { NotificationCenter.default.post(name: .placesChanged, object: nil) }
    }

    /// История нового места по всей библиотеке: предфильтр по превью,
    /// точки — только у кандидатов.
    func matchAllTrips(against place: Place) async {
        var changed = false
        for ref in repository.tripPreviews(needingPlaceMatch: false) {
            guard PlaceMatcher.isCandidate(place: place, tripCells: PlaceMatcher.cells(of: ref.previewCoordinates)),
                  let trip = repository.fetchTripDetail(id: ref.id), trip.trackPoints.count > 1 else { continue }
            let passes = PlaceMatcher.passes(through: place, tripId: trip.id, points: trip.trackPoints, startDate: trip.startDate)
            if !passes.isEmpty {
                store.replacePasses(placeId: place.id, tripId: trip.id, with: passes)
                changed = true
            }
            await Task.yield()
        }
        if changed { NotificationCenter.default.post(name: .placesChanged, object: nil) }
    }

    /// Сверка — после пула и при запуске. Идемпотентна: трогает только
    /// отметки без места и поездки без `placesMatchedAt`.
    func reconcile() async {
        // Пул во время стартовой сверки — обычное дело: сверка идёт с первого
        // экрана, пул приходит через секунду. Второй проход идемпотентен, но
        // бесполезен: то, что первый уже пометил, он пропустит, а остальное
        // первый и досверит.
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        for (checkpoint, tripId) in repository.checkpointsWithoutPlace() {
            registerCheckpoint(checkpoint, tripId: tripId)
            await settle()
        }
        await drainPendingHistory()
        // Обе выборки — по одной на весь проход. Места читаются ПОСЛЕ отметок:
        // строкой выше могли родиться новые.
        let places = store.fetchPlaces()
        let pending = repository.tripPreviews(needingPlaceMatch: true)
        guard !places.isEmpty else {
            // Главный случай первого запуска после обновления: мест нет вовсе,
            // сверять не с чем. Поднимать точки всей библиотеки ради этого
            // незачем — метку ставим одной пачкой.
            repository.markPlacesMatched(tripIds: pending.map(\.id))
            reload()
            return
        }
        var done: [UUID] = []
        for ref in pending {
            await process(ref, places: places)
            done.append(ref.id)
            // Пачками: прерванный проход (человек закрыл приложение на
            // середине первой сверки) не теряет всё сделанное.
            if done.count >= Self.matchBatch {
                repository.markPlacesMatched(tripIds: done)
                done.removeAll()
            }
            await Task.yield()
        }
        repository.markPlacesMatched(tripIds: done)
        reload()
    }

    // MARK: - Удаление

    func forget(tripId: UUID) {
        // Поездка без проездов — обычное дело (мест рядом не было), и будить
        // ею экраны незачем: удаление любой поездки перерисовывало бы места.
        guard !store.passes(tripId: tripId).isEmpty else { return }
        store.deletePasses(tripId: tripId)
        NotificationCenter.default.post(name: .placesChanged, object: nil)
    }

    /// Место и проезды уходят; отметки остаются при своих `placeId` —
    /// надгробие, чтобы сверка не воскресила место тем же вечером. Новая
    /// отметка в той же ячейке заведёт его заново (тот же id).
    func delete(placeId: UUID) {
        store.deletePlace(id: placeId)
        reload()
        NotificationCenter.default.post(name: .placesChanged, object: nil)
    }

    // MARK: - Отложенная история

    /// Места, которым история ещё не досчитана. Ключ `UserDefaults`, а не поле
    /// в памяти: на парковке система убивает приложение свободно, и потерянный
    /// здесь id — это место без истории навсегда.
    private static let pendingHistoryKey = "places.pendingHistory"

    /// Не `private`: очередь читает и чистит тест — без неё «отложили» и
    /// «потеряли» выглядят с экрана одинаково.
    var pendingHistoryIds: [UUID] {
        get {
            (UserDefaults.standard.array(forKey: Self.pendingHistoryKey) as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
        }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: Self.pendingHistoryKey) }
    }

    /// Отложить историю нового места до финиша.
    ///
    /// Досчёт — это `fetchTripDetail` и `distancePrefix` по плотному треку на
    /// каждой поездке библиотеки: сотни миллисекунд на главном актёре без
    /// разрыва. Кнопку отметки жмут на ходу, в машине, и заминка там дороже
    /// любой истории, которая подождёт полчаса до финиша.
    private func deferHistory(_ placeId: UUID) {
        guard !pendingHistoryIds.contains(placeId) else { return }
        pendingHistoryIds.append(placeId)
    }

    /// Досчитать отложенное. Зовётся с финиша и со сверки — то есть тогда,
    /// когда человек уже не за рулём.
    private func drainPendingHistory() async {
        for id in pendingHistoryIds {
            // Место могли удалить, пока оно ждало, — тогда просто забываем.
            if let place = store.fetchPlace(id: id) {
                await matchAllTrips(against: place)
            }
            pendingHistoryIds.removeAll { $0 == id }
        }
    }

    // MARK: - Предфильтр

    /// Места, мимо которых поездка могла пройти. Список приходит параметром —
    /// хранилище здесь не читается: иначе выборка шла бы на каждую поездку.
    private func candidatePlaces(for ref: TripPreviewRef, places: [Place]) -> [Place] {
        guard !places.isEmpty else { return [] }
        let cells = PlaceMatcher.cells(of: ref.previewCoordinates)
        return places.filter { PlaceMatcher.isCandidate(place: $0, tripCells: cells) }
    }
}
