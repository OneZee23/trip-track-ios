import Foundation
import CoreData
import CoreLocation
import OSLog

private let revealLog = Logger(subsystem: "com.triptrack", category: "reveal")

/// Открытый мир в базе: тайл geohash-5 — строка, ячейки дельта-кодом,
/// коридоры — полилиниями.
///
/// Копится инкрементально. Финиш поездки добавляет к открытому только то, чего
/// в нём не было; вкладка «Атлас» читает готовое (50–150 мс), а не пересчитывает
/// библиотеку (0.5–2 с). Источник ВСЕГДА превью-полилиния: сырые точки на карту
/// не приходят никогда — это условие производительности, а не деталь.
///
/// Открытое КУМУЛЯТИВНО: удаление поездки туман не сжимает — «где был, там
/// был». Отсюда законное расхождение, о котором надо знать: после удалений
/// `layer(before: Date())` (он считает по живым поездкам) окажется МЕНЬШЕ, чем
/// `layer()`. Это решение, а не рассинхрон.
///
/// Всё идёт на своём фоновом контексте: финиш поездки и так занят, а первая
/// сборка после обновления перебирает всю библиотеку. Поэтому чтение и запись
/// здесь `async` — главный актёр не имеет права стоять в очереди этого
/// контекста за фоновой сборкой.
/// `@unchecked Sendable` — осознанно: всё изменяемое состояние типа это ОДИН
/// фоновый контекст CoreData, и трогают его только внутри его же `perform`.
final class RevealedLayerStore: @unchecked Sendable {
    static let shared = RevealedLayerStore()

    /// Флаг «фоновая сборка после обновления прошла».
    ///
    /// Номер в ключе — версия ФОРМЫ накопленного, а не версия схемы. Поднимать
    /// его обязан всякий, кто меняет `RevealBuilder`: прогоны лежат в базе, и
    /// правило, по которому они рисуются, задним числом на них не действует.
    /// `v17` — запрет на вторую нитку в двадцати пяти метрах от первой
    /// (`RevealBuilder.neighbourClaimed`, 15 сен 2026): без пересборки двойные
    /// жилки остались бы у всех, кто уже успел собрать слой.
    /// `v18` — не форма, а ЛАТЧ: `v17` взводился и на нулевой работе, и телефон,
    /// прошедший сборку на ещё не приехавшей библиотеке, оставался без тумана
    /// НАВСЕГДА. У кого `v17` собрался честно — цена одна лишняя сборка.
    static let rebuildFlagKey = "reveal_rebuild_v18_done"
    /// Сколько поездок сборки идёт одним сохранением.
    static let rebuildBatch = 40

    /// Что разобрать сверке.
    ///
    /// Отметки по времени здесь НЕТ и быть не может: `lastModifiedAt` у своей
    /// поездки ставят часы этого телефона, у чужой она приезжает как есть с
    /// другого устройства, а дельта на сервере режется серверными часами. Окно
    /// по любой из трёх шкал однажды отсекает поездку, которой ещё не было, —
    /// и это ровно та поломка, ради которой сверка написана. Поэтому пул
    /// говорит, ЧТО он привёз (`SyncPullNotification.appliedTripIds`), а
    /// молчание («ключа нет») стоит одного полного прохода: он идемпотентен и
    /// открывает ноль ячеек там, где уже открыто.
    enum ReconcileRequest: Equatable {
        case full
        case ids(Set<UUID>)

        /// Сложение запросов: полный проход поглощает всё, списки id
        /// объединяются. Чистая функция — очередь проверяется тестом, а не
        /// гонкой двух пулов.
        static func merged(_ queued: Self?, _ incoming: Self) -> Self {
            switch (queued, incoming) {
            case (nil, let incoming): return incoming
            case (.full, _), (_, .full): return .full
            case let (.ids(a)?, .ids(b)): return .ids(a.union(b))
            }
        }

        var isEmpty: Bool {
            if case let .ids(ids) = self { return ids.isEmpty }
            return false
        }
    }

    /// Чем кончилась сверка. `queued` — не «работа потеряна», а «её сделает
    /// идущий проход»: запрос сложен в очередь и выполнится сразу за ним.
    enum ReconcileOutcome: Equatable {
        case queued
        case done(trips: Int, cells: Int)
    }

    private let persistence: PersistenceController
    private let defaults: UserDefaults
    private let context: NSManagedObjectContext
    /// Сверка в одном экземпляре. Оба поля трогаются ТОЛЬКО внутри
    /// `context.perform` — очередь контекста и есть их замок.
    private var isReconciling = false
    /// Запрос, пришедший во время прохода: выполняется сразу за ним, сложением
    /// (`ReconcileRequest.merged`). Терять его нельзя — это пул, чьи строки
    /// легли в базу уже ПОСЛЕ того, как идущий проход выбрал превью.
    private var queued: ReconcileRequest?
    /// Тестовый шлагбаум перед каждым проходом. В продакшене `nil`: очередь
    /// сверки иначе проверялась бы скоростью машины, а не решением теста.
    private let beforePass: (@Sendable () async -> Void)?

    init(persistence: PersistenceController = .shared,
         defaults: UserDefaults = .standard,
         beforePass: (@Sendable () async -> Void)? = nil) {
        self.persistence = persistence
        self.defaults = defaults
        self.beforePass = beforePass
        context = persistence.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Чтение

    func tiles() async -> [RevealedTile] {
        await context.perform { self.fetchTiles() }
    }

    func claimed(in tile: String) async -> Set<RevealGrid.Cell> {
        await context.perform { self.claimedInContext(tile) }
    }

    /// Снимок для рендерера.
    ///
    /// `before == nil` — открытое, как оно есть. С датой — «временной туман»:
    /// мир, каким он был на эту дату, собирается на лету из превью поездок,
    /// завершённых до неё, и в базу НЕ пишется: это состояние одного экрана, а
    /// не состояние мира.
    ///
    /// Считает ВСЮ библиотеку до даты на каждый вызов — звать только вне
    /// главного актёра и кэшировать результат на экран, а не звать из `body`.
    func layer(before date: Date? = nil, atlas: RegionAtlas? = nil) async -> RevealedLayer {
        guard let date else {
            return RevealedLayer.build(tiles: await tiles(), atlas: atlas)
        }

        let built: (runs: [[CLLocationCoordinate2D]], cells: Int) = await context.perform {
            var runs: [[CLLocationCoordinate2D]] = []
            var claimedCells: [String: Set<RevealGrid.Cell>] = [:]
            for preview in self.fetchPreviews(endedBefore: date) {
                guard let polyline = preview.polyline else { continue }
                let coords = Trip.decodePolyline(polyline)
                guard coords.count > 1 else { continue }
                let patches = RevealBuilder.patches(for: coords) { claimedCells[$0] ?? [] }
                for (key, patch) in patches {
                    claimedCells[key, default: []].formUnion(patch.cells)
                    runs.append(contentsOf: patch.runs)
                }
            }
            return (runs, claimedCells.values.reduce(0) { $0 + $1.count })
        }
        return RevealedLayer.build(runs: built.runs, cellCount: built.cells, atlas: atlas)
    }

    // MARK: - Запись

    /// Что открыла ОДНА поездка. Возвращает число новых ячеек — ноль значит
    /// «проехал там, где уже был», и это нормальный ответ, а не поломка.
    @discardableResult
    func ingest(tripId: UUID) async -> Int {
        let added = await context.perform { () -> Int in
            let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "id == %@ AND endDate != nil AND syncStatus != %d",
                tripId as CVarArg, SyncStatus.pendingDelete.rawValue
            )
            request.fetchLimit = 1
            guard let entity = try? self.context.fetch(request).first,
                  let polyline = entity.previewPolyline else { return 0 }
            let coords = Trip.decodePolyline(polyline)
            guard coords.count > 1 else { return 0 }

            var cache: [String: Set<RevealGrid.Cell>] = [:]
            let patches = RevealBuilder.patches(for: coords) { key in
                if let hit = cache[key] { return hit }
                let cells = self.claimedInContext(key)
                cache[key] = cells
                return cells
            }
            let opened = self.mergeInContext(patches)
            guard self.saveContext() else {
                self.context.rollback()
                return 0
            }
            return opened
        }
        if added > 0 { postChanged() }
        return added
    }

    func merge(_ patches: [String: TilePatch]) async {
        let added = await context.perform { () -> Int in
            let opened = self.mergeInContext(patches)
            self.saveContext()
            return opened
        }
        if added > 0 { postChanged() }
    }

    /// Фоновая сборка открытого из всей библиотеки — один раз после обновления.
    ///
    /// Собирает с НУЛЯ: ключ флага меняется вместе с формой прогонов
    /// (см. `rebuildFlagKey`), а уже накопленное новое правило задним числом не
    /// исправит — старые ячейки застолблены, и `patches` на них просто промолчит.
    /// Стирание идёт ПОСЛЕ проверки на пустую выборку, иначе запуск, потерявший
    /// библиотеку, снёс бы туман и не собрал ничего.
    ///
    /// Пустая выборка флаг НЕ взводит: на запуске, потерявшем стор, «поездок
    /// нет» значит «данные ещё не вернулись», и залатчить там значило бы
    /// оставить карту пустой навсегда (та же ловушка, что в
    /// `TerritoryManager.backfillIfNeeded`). Поездка без превью пропускается —
    /// поднимать её точки нельзя.
    ///
    /// «Не из чего собирать» — это И пустая библиотека, И библиотека БЕЗ
    /// превью: поездка пула приезжает строкой раньше, чем разобранным превью,
    /// и на ней старая проверка `!previews.isEmpty` честно проходила — стирала
    /// накопленное и писала взамен ноль. Поэтому смотрим на ПРИГОДНЫЕ превью,
    /// и только после этого стираем.
    func rebuildIfNeeded() async {
        guard !defaults.bool(forKey: Self.rebuildFlagKey) else { return }

        let previews = await context.perform { self.fetchPreviews(endedBefore: nil) }
        let usable = previews.filter { ($0.polyline?.count ?? 0) >= 16 }
        // «Пригодно по длине» ещё не значит «что-то откроет»: превью из двух
        // одинаковых точек до `RevealBuilder` доходит, а ячеек не даёт. Спросить
        // об этом надо ДО стирания — чистым счётом, без базы, — иначе запуск с
        // вырожденной библиотекой сносит накопленное и не пишет ничего.
        guard usable.contains(where: Self.opensSomething) else {
            revealLog.notice("reveal rebuild: nothing to build from, latch stays open")
            return
        }

        await context.perform { self.deleteAllInContext() }

        var total = 0
        for start in stride(from: 0, to: usable.count, by: Self.rebuildBatch) {
            let batch = Array(usable[start..<min(start + Self.rebuildBatch, usable.count)])
            total += await context.perform { () -> Int in
                var opened = 0
                var cache: [String: Set<RevealGrid.Cell>] = [:]
                for preview in batch {
                    guard let polyline = preview.polyline else { continue }
                    let coords = Trip.decodePolyline(polyline)
                    guard coords.count > 1 else { continue }
                    let patches = RevealBuilder.patches(for: coords) { key in
                        if let hit = cache[key] { return hit }
                        let cells = self.claimedInContext(key)
                        cache[key] = cells
                        return cells
                    }
                    for (key, patch) in patches {
                        cache[key, default: []].formUnion(patch.cells)
                    }
                    opened += self.mergeInContext(patches)
                }
                self.saveContext()
                return opened
            }
            await Task.yield()
        }

        // Ноль открытого — не «сборка прошла». Латч говорит «библиотека
        // разобрана», и взвести его на нулевой работе значит запереть телефон
        // без тумана навсегда: второго шанса у сборки нет.
        guard total > 0 else {
            revealLog.notice("reveal rebuild: nothing was opened, latch stays open")
            return
        }
        defaults.set(true, forKey: Self.rebuildFlagKey)
        revealLog.notice("reveal rebuild: \(total, privacy: .public) cells from \(usable.count, privacy: .public) trips")
        postChanged()
    }

    /// Сверка после пула: поездки со второго телефона (и вся библиотека на
    /// восстановленном) приезжают прямо в CoreData, мимо финиша и мимо
    /// разовой сборки.
    ///
    /// Разовая сборка их не спасает: миграции идут из `MapViewModel.init`, а
    /// первый пул — по `didBecomeActive`, то есть ПОСЛЕ. На запуске, где
    /// библиотека приходит пулом, сборка видит пустую базу и выходит, и без
    /// этой двери тумана не было бы весь сеанс (а с прежним безусловным латчем
    /// — никогда). Точки поездке пула не нужны: стор читает только превью, а
    /// оно приезжает вместе с поездкой.
    ///
    /// `request` — ЧТО разобрать: `.ids` от самого пула (он знает, что привёз),
    /// `.full` когда неизвестно. Времени здесь нет нигде: см. `ReconcileRequest`.
    /// Идемпотентна — повторный разбор открытого добавляет ноль ячеек.
    @discardableResult
    func reconcile(_ request: ReconcileRequest = .full) async -> ReconcileOutcome {
        // Запрос, пришедший во время прохода, складывается с очередью и
        // выполняется сразу за ним: идущий проход выбрал превью РАНЬШЕ, чем
        // строки этого пула легли в базу, и ответить ему «занято» значило бы
        // потерять их до следующего запуска.
        let mine = await context.perform { () -> Bool in
            self.queued = ReconcileRequest.merged(self.queued, request)
            guard !self.isReconciling else { return false }
            self.isReconciling = true
            return true
        }
        guard mine else {
            revealLog.notice("reveal reconcile: queued behind a running pass")
            return .queued
        }

        var trips = 0
        var cells = 0
        while let next = await context.perform({ () -> ReconcileRequest? in
            guard let next = self.queued else {
                self.isReconciling = false
                return nil
            }
            self.queued = nil
            return next
        }) {
            let step = await runPass(next)
            trips += step.trips
            cells += step.cells
        }
        if cells > 0 { postChanged() }
        return .done(trips: trips, cells: cells)
    }

    private func runPass(_ request: ReconcileRequest) async -> (trips: Int, cells: Int) {
        await beforePass?()
        guard !request.isEmpty else { return (0, 0) }
        let ids: Set<UUID>? = {
            if case let .ids(ids) = request { return ids }
            return nil
        }()
        let previews = await context.perform { self.fetchPreviews(endedBefore: nil, ids: ids) }
        let usable = previews.filter { ($0.polyline?.count ?? 0) >= 16 }
        guard !usable.isEmpty else { return (0, 0) }

        var total = 0
        for start in stride(from: 0, to: usable.count, by: Self.rebuildBatch) {
            let batch = Array(usable[start..<min(start + Self.rebuildBatch, usable.count)])
            total += await context.perform { () -> Int in
                var opened = 0
                var cache: [String: Set<RevealGrid.Cell>] = [:]
                for preview in batch {
                    guard let polyline = preview.polyline else { continue }
                    let coords = Trip.decodePolyline(polyline)
                    guard coords.count > 1 else { continue }
                    let patches = RevealBuilder.patches(for: coords) { key in
                        if let hit = cache[key] { return hit }
                        let cells = self.claimedInContext(key)
                        cache[key] = cells
                        return cells
                    }
                    for (key, patch) in patches {
                        cache[key, default: []].formUnion(patch.cells)
                    }
                    opened += self.mergeInContext(patches)
                }
                guard self.saveContext() else {
                    self.context.rollback()
                    return 0
                }
                return opened
            }
            await Task.yield()
        }
        revealLog.notice("reveal reconcile: \(total, privacy: .public) cells from \(usable.count, privacy: .public) trips")
        return (usable.count, total)
    }

    /// Стереть открытое. Флаг сборки снимается вместе с данными: он говорит
    /// «сборка прошла», а не «сборка когда-то запускалась», — иначе после
    /// «удалить везде» вернувшиеся синком поездки остались бы без тумана.
    /// Синхронный нарочно: единственный вызывающий — `LocalDataWipe.run()`,
    /// синхронная точка на главном актёре, а работы здесь на один delete.
    func wipe() {
        context.performAndWait {
            deleteAllInContext()
            // `LocalDataWipe` стирает пакетом мимо контекстов, и в этом
            // остались бы зарегистрированные «призраки» стёртых строк.
            context.reset()
        }
        defaults.set(false, forKey: Self.rebuildFlagKey)
        postChanged()
    }

    // MARK: - Внутри контекста

    /// Снести открытое целиком. Зовут двое: `wipe()` (стирание аккаунта) и
    /// пересборка после смены формы прогонов.
    private func deleteAllInContext() {
        let request: NSFetchRequest<RevealedCellEntity> = RevealedCellEntity.fetchRequest()
        for entity in (try? context.fetch(request)) ?? [] { context.delete(entity) }
        saveContext()
    }

    /// Поездка без превью — законная строка выборки: она ГОВОРИТ, что
    /// библиотека не пуста, хотя открыть ею нечего. Отличать «поездок нет» от
    /// «превью нет» обязательно — от этого зависит, взводить ли флаг.
    private struct Preview {
        let id: UUID
        let polyline: Data?
    }

    /// Откроет ли это превью хоть что-нибудь. Чистый счёт, без базы: `claimed`
    /// отвечает «пусто», то есть вопрос — «есть ли тут вообще геометрия».
    private static func opensSomething(_ preview: Preview) -> Bool {
        guard let polyline = preview.polyline else { return false }
        let coords = Trip.decodePolyline(polyline)
        guard coords.count > 1 else { return false }
        return !RevealBuilder.patches(for: coords, claimed: { _ in [] }).isEmpty
    }

    private func fetchTiles() -> [RevealedTile] {
        let request: NSFetchRequest<RevealedCellEntity> = RevealedCellEntity.fetchRequest()
        request.fetchBatchSize = 200
        return ((try? context.fetch(request)) ?? []).compactMap { entity in
            guard let key = entity.key else { return nil }
            return RevealedTile(
                key: key,
                cells: entity.cells ?? Data(),
                geometry: entity.geometry ?? Data(),
                updatedAt: entity.updatedAt ?? Date()
            )
        }
    }

    private func fetchEntity(_ key: String) -> RevealedCellEntity? {
        let request: NSFetchRequest<RevealedCellEntity> = RevealedCellEntity.fetchRequest()
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func claimedInContext(_ key: String) -> Set<RevealGrid.Cell> {
        guard let entity = fetchEntity(key), let cells = entity.cells else { return [] }
        return Set(RevealGrid.decode(cells, in: key))
    }

    @discardableResult
    private func mergeInContext(_ patches: [String: TilePatch]) -> Int {
        var added = 0
        let now = Date()
        for (key, patch) in patches {
            let entity = fetchEntity(key) ?? {
                let fresh = RevealedCellEntity(context: context)
                fresh.key = key
                fresh.version = 1
                return fresh
            }()
            var cells = Set(RevealGrid.decode(entity.cells ?? Data(), in: key))
            let before = cells.count
            cells.formUnion(patch.cells)
            added += cells.count - before

            var runs = RevealedTile.decodeRuns(entity.geometry ?? Data())
            runs.append(contentsOf: patch.runs)

            entity.cells = RevealGrid.encode(Array(cells), in: key)
            entity.geometry = RevealedTile.encodeRuns(runs)
            entity.cellCount = Int32(cells.count)
            entity.updatedAt = now
        }
        return added
    }

    /// Превью завершённых поездок, по возрастанию даты: кто проехал первым, тот
    /// и владеет геометрией — как и на живом финише.
    private func fetchPreviews(endedBefore date: Date?, ids: Set<UUID>? = nil) -> [Preview] {
        let request = Self.previewRequest(endedBefore: date, ids: ids)
        return ((try? context.fetch(request)) ?? []).compactMap { row in
            guard let id = row["id"] as? UUID else { return nil }
            return Preview(id: id, polyline: row["previewPolyline"] as? Data)
        }
    }

    /// Запрос превью отдельно от выполнения — чтобы его настройки проверял
    /// тест, а не глаз в логе.
    ///
    /// `fetchBatchSize` здесь НЕ ставится, и это не забывчивость: на
    /// `dictionaryResultType` без `objectID` в `propertiesToFetch` CoreData
    /// печатает «Returning unbatched results» на КАЖДЫЙ вызов и всё равно
    /// отдаёт выборку одной порцией — то есть настройка не работала, а шум
    /// в логе прятал настоящие ошибки стора.
    ///
    /// `ids` — сверка по списку от пула: разбираем ровно то, что приехало.
    static func previewRequest(endedBefore date: Date?, ids: Set<UUID>? = nil) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "TripEntity")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "previewPolyline"]
        var predicates = [NSPredicate(
            format: "endDate != nil AND syncStatus != %d", SyncStatus.pendingDelete.rawValue
        )]
        if let date { predicates.append(NSPredicate(format: "endDate <= %@", date as NSDate)) }
        if let ids { predicates.append(NSPredicate(format: "id IN %@", ids as NSSet)) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        return request
    }

    @discardableResult
    private func saveContext() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            revealLog.error("save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func postChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .revealedLayerChanged, object: nil)
        }
    }
}
