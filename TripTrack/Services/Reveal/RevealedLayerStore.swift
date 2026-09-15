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
    /// Докуда стор разобрал библиотеку: самая свежая `lastModifiedAt` среди
    /// разобранных поездок — не «когда мы последний раз считали».
    ///
    /// Отметка в `UserDefaults`, своей колонки у поездки в этой волне не
    /// заводим. Сравнивается она именно с `lastModifiedAt`, потому что пул
    /// пишет это поле КАЖДОЙ применённой поездке и оно непустое по типу
    /// (`TripSyncPayload.lastModifiedAt: Date`, `applyRemoteTrip`), тогда как
    /// `serverCreatedAt` ставится один раз и говорит «у строки есть серверный
    /// близнец», а не «строка изменилась».
    static let lastIngestKey = "reveal_last_ingest_at"
    /// Запас назад от отметки. У поездки пула `lastModifiedAt` серверная, у
    /// своей — телефонная, и одних часов у них нет: без запаса поездка,
    /// правленная на втором телефоне за минуту до нашего финиша, не попала бы
    /// в сверку никогда. Повторный разбор не стоит ничего — ячейки
    /// идемпотентны, второй заход открывает ноль.
    static let ingestSlack: TimeInterval = 86_400
    /// Сколько поездок сборки идёт одним сохранением.
    static let rebuildBatch = 40

    /// Чем кончилась сверка. `busy` — не «ошибка», а «уже идёт»: пул поверх
    /// стартовой сверки обычное дело.
    enum ReconcileOutcome: Equatable {
        case busy
        case done(trips: Int, cells: Int)
    }

    private let persistence: PersistenceController
    private let defaults: UserDefaults
    private let context: NSManagedObjectContext
    /// Сверка в одном экземпляре. Трогается ТОЛЬКО внутри `context.perform` —
    /// очередь контекста и есть её замок.
    private var isReconciling = false

    init(persistence: PersistenceController = .shared, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
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
        let result = await context.perform { () -> (added: Int, changedAt: Date?) in
            let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "id == %@ AND endDate != nil AND syncStatus != %d",
                tripId as CVarArg, SyncStatus.pendingDelete.rawValue
            )
            request.fetchLimit = 1
            guard let entity = try? self.context.fetch(request).first,
                  let polyline = entity.previewPolyline else { return (0, nil) }
            let changedAt = Self.changedAt(entity.lastModifiedAt, entity.serverCreatedAt)
            let coords = Trip.decodePolyline(polyline)
            guard coords.count > 1 else { return (0, nil) }

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
                return (0, nil)
            }
            return (opened, changedAt)
        }
        // Отметку двигает и финиш: иначе пул через секунду после него разбирал
        // бы ту же поездку заново. Ячейки от этого не пострадали бы (второй
        // заход открывает ноль), но работа была бы честно лишней.
        advanceStamp(to: result.changedAt)
        if result.added > 0 { postChanged() }
        return result.added
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
        guard !usable.isEmpty else {
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
        // Сборка разобрала библиотеку целиком — сверке после первого пула
        // незачем проходить по ней второй раз.
        advanceStamp(to: usable.compactMap(\.changedAt).max())
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
    /// Идемпотентна: берёт поездки, изменившиеся после отметки, а повторный
    /// разбор уже открытого добавляет ноль ячеек.
    @discardableResult
    func reconcile() async -> ReconcileOutcome {
        let started = await context.perform { () -> Bool in
            guard !self.isReconciling else { return false }
            self.isReconciling = true
            return true
        }
        guard started else {
            revealLog.notice("reveal reconcile: already running")
            return .busy
        }
        let outcome = await runReconcile()
        await context.perform { self.isReconciling = false }
        return outcome
    }

    private func runReconcile() async -> ReconcileOutcome {
        let stamp = defaults.object(forKey: Self.lastIngestKey) as? Date
        let since = stamp?.addingTimeInterval(-Self.ingestSlack)
        let previews = await context.perform {
            self.fetchPreviews(endedBefore: nil, changedSince: since)
        }
        let usable = previews.filter { ($0.polyline?.count ?? 0) >= 16 }
        guard !usable.isEmpty else { return .done(trips: 0, cells: 0) }

        var total = 0
        var high: Date?
        for start in stride(from: 0, to: usable.count, by: Self.rebuildBatch) {
            let batch = Array(usable[start..<min(start + Self.rebuildBatch, usable.count)])
            let step = await context.perform { () -> (opened: Int, high: Date?) in
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
                // Отметка двигается ТОЛЬКО за сохранением: упавшее сохранение,
                // отмеченное как сделанное, потеряло бы эти поездки навсегда.
                guard self.saveContext() else {
                    self.context.rollback()
                    return (0, nil)
                }
                return (opened, batch.compactMap(\.changedAt).max())
            }
            total += step.opened
            if let stepHigh = step.high, high == nil || high! < stepHigh { high = stepHigh }
            await Task.yield()
        }

        advanceStamp(to: high)
        revealLog.notice("reveal reconcile: \(total, privacy: .public) cells from \(usable.count, privacy: .public) trips")
        if total > 0 { postChanged() }
        return .done(trips: usable.count, cells: total)
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
        // Вместе с данными снимается и отметка сверки: иначе вернувшиеся
        // синком поездки «уже разобраны», а разбирать их некому.
        defaults.removeObject(forKey: Self.lastIngestKey)
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
        /// Когда строка последний раз менялась — тем полем, которое пишет пул.
        let changedAt: Date?
    }

    /// Дата правки строки. `lastModifiedAt` — то, что пул ставит каждой
    /// применённой поездке; `serverCreatedAt` подстраховывает строки, у
    /// которых колонка правки пуста (наследство до sync-ready полей).
    private static func changedAt(_ modified: Date?, _ created: Date?) -> Date? {
        switch (modified, created) {
        case let (m?, c?): return max(m, c)
        case let (m?, nil): return m
        case let (nil, c?): return c
        case (nil, nil): return nil
        }
    }

    /// Отметка идёт только вперёд: сверка и финиш ходят вперемешку.
    private func advanceStamp(to date: Date?) {
        guard let date else { return }
        let current = defaults.object(forKey: Self.lastIngestKey) as? Date
        guard current == nil || current! < date else { return }
        defaults.set(date, forKey: Self.lastIngestKey)
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
    private func fetchPreviews(endedBefore date: Date?, changedSince: Date? = nil) -> [Preview] {
        let request = Self.previewRequest(endedBefore: date, changedSince: changedSince)
        return ((try? context.fetch(request)) ?? []).compactMap { row in
            guard let id = row["id"] as? UUID else { return nil }
            return Preview(
                id: id,
                polyline: row["previewPolyline"] as? Data,
                changedAt: Self.changedAt(
                    row["lastModifiedAt"] as? Date,
                    row["serverCreatedAt"] as? Date
                )
            )
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
    /// `changedSince` — сверка: строки без обеих дат сюда не попадают, и это
    /// решение. Пул ставит `lastModifiedAt` всегда (поле непустое по типу),
    /// значит пустые обе даты бывают только у местной строки, которую уже
    /// разобрала разовая сборка; брать их каждый пул значило бы перебирать
    /// доисторическую библиотеку заново на каждом заходе в приложение.
    static func previewRequest(endedBefore date: Date?, changedSince: Date?) -> NSFetchRequest<NSDictionary> {
        let request = NSFetchRequest<NSDictionary>(entityName: "TripEntity")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "previewPolyline", "lastModifiedAt", "serverCreatedAt"]
        var predicates = [NSPredicate(
            format: "endDate != nil AND syncStatus != %d", SyncStatus.pendingDelete.rawValue
        )]
        if let date { predicates.append(NSPredicate(format: "endDate <= %@", date as NSDate)) }
        if let changedSince {
            predicates.append(NSPredicate(
                format: "lastModifiedAt >= %@ OR serverCreatedAt >= %@",
                changedSince as NSDate, changedSince as NSDate
            ))
        }
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
