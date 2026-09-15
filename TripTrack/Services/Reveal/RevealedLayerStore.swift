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
/// Всё идёт на своём фоновом контексте: финиш поездки и так занят, а первая
/// сборка после обновления перебирает всю библиотеку.
/// `@unchecked Sendable` — осознанно: всё изменяемое состояние типа это ОДИН
/// фоновый контекст CoreData, и трогают его только внутри его же `perform`.
/// Без этого фоновая сборка (единственный `async` метод) ругается на захват
/// `self` в `@Sendable` замыкании `performAndWait`.
final class RevealedLayerStore: @unchecked Sendable {
    static let shared = RevealedLayerStore()

    /// Флаг «фоновая сборка после обновления до v16 прошла».
    static let rebuildFlagKey = "reveal_rebuild_v16_done"
    /// Сколько поездок сборки идёт одним сохранением.
    static let rebuildBatch = 40

    private let persistence: PersistenceController
    private let defaults: UserDefaults
    private let context: NSManagedObjectContext

    init(persistence: PersistenceController = .shared, defaults: UserDefaults = .standard) {
        self.persistence = persistence
        self.defaults = defaults
        context = persistence.container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Чтение

    func tiles() -> [RevealedTile] {
        var result: [RevealedTile] = []
        context.performAndWait {
            result = fetchTiles()
        }
        return result
    }

    func claimed(in tile: String) -> Set<RevealGrid.Cell> {
        var result = Set<RevealGrid.Cell>()
        context.performAndWait {
            result = claimedInContext(tile)
        }
        return result
    }

    /// Снимок для рендерера.
    ///
    /// `before == nil` — открытое, как оно есть. С датой — «временной туман»:
    /// мир, каким он был на эту дату, собирается на лету из превью поездок,
    /// завершённых до неё, и в базу НЕ пишется: это состояние одного экрана, а
    /// не состояние мира.
    func layer(before date: Date? = nil, atlas: RegionAtlas? = nil) -> RevealedLayer {
        guard let date else {
            return RevealedLayer.build(tiles: tiles(), atlas: atlas)
        }

        var runs: [[CLLocationCoordinate2D]] = []
        var claimedCells: [String: Set<RevealGrid.Cell>] = [:]
        context.performAndWait {
            for preview in fetchPreviews(endedBefore: date) {
                guard let polyline = preview.polyline else { continue }
                let coords = Trip.decodePolyline(polyline)
                guard coords.count > 1 else { continue }
                let patches = RevealBuilder.patches(for: coords) { claimedCells[$0] ?? [] }
                for (key, patch) in patches {
                    claimedCells[key, default: []].formUnion(patch.cells)
                    runs.append(contentsOf: patch.runs)
                }
            }
        }
        let cellCount = claimedCells.values.reduce(0) { $0 + $1.count }
        return RevealedLayer.build(runs: runs, cellCount: cellCount, atlas: atlas)
    }

    // MARK: - Запись

    /// Что открыла ОДНА поездка. Возвращает число новых ячеек — ноль значит
    /// «проехал там, где уже был», и это нормальный ответ, а не поломка.
    @discardableResult
    func ingest(tripId: UUID) -> Int {
        var added = 0
        context.performAndWait {
            let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "id == %@ AND endDate != nil AND syncStatus != %d",
                tripId as CVarArg, SyncStatus.pendingDelete.rawValue
            )
            request.fetchLimit = 1
            guard let entity = try? context.fetch(request).first,
                  let polyline = entity.previewPolyline else { return }
            let coords = Trip.decodePolyline(polyline)
            guard coords.count > 1 else { return }

            var cache: [String: Set<RevealGrid.Cell>] = [:]
            let patches = RevealBuilder.patches(for: coords) { key in
                if let hit = cache[key] { return hit }
                let cells = claimedInContext(key)
                cache[key] = cells
                return cells
            }
            added = mergeInContext(patches)
            saveContext()
        }
        if added > 0 { postChanged() }
        return added
    }

    func merge(_ patches: [String: TilePatch]) {
        var added = 0
        context.performAndWait {
            added = mergeInContext(patches)
            saveContext()
        }
        if added > 0 { postChanged() }
    }

    /// Фоновая сборка открытого из всей библиотеки — один раз после обновления.
    ///
    /// Пустая выборка флаг НЕ взводит: на запуске, потерявшем стор, «поездок
    /// нет» значит «данные ещё не вернулись», и залатчить там значило бы
    /// оставить карту пустой навсегда (та же ловушка, что в
    /// `TerritoryManager.backfillIfNeeded`). Поездка без превью пропускается —
    /// поднимать её точки нельзя.
    func rebuildIfNeeded() async {
        guard !defaults.bool(forKey: Self.rebuildFlagKey) else { return }

        var previews: [Preview] = []
        context.performAndWait { previews = fetchPreviews(endedBefore: nil) }
        guard !previews.isEmpty else {
            revealLog.notice("reveal rebuild: no trips yet, latch stays open")
            return
        }

        var total = 0
        for start in stride(from: 0, to: previews.count, by: Self.rebuildBatch) {
            let batch = previews[start..<min(start + Self.rebuildBatch, previews.count)]
            context.performAndWait {
                var cache: [String: Set<RevealGrid.Cell>] = [:]
                for preview in batch {
                    guard let polyline = preview.polyline else { continue }
                    let coords = Trip.decodePolyline(polyline)
                    guard coords.count > 1 else { continue }
                    let patches = RevealBuilder.patches(for: coords) { key in
                        if let hit = cache[key] { return hit }
                        let cells = claimedInContext(key)
                        cache[key] = cells
                        return cells
                    }
                    for (key, patch) in patches {
                        cache[key, default: []].formUnion(patch.cells)
                    }
                    total += mergeInContext(patches)
                }
                saveContext()
            }
            await Task.yield()
        }

        defaults.set(true, forKey: Self.rebuildFlagKey)
        revealLog.notice("reveal rebuild: \(total, privacy: .public) cells from \(previews.count, privacy: .public) trips")
        postChanged()
    }

    /// Стереть открытое. Флаг сборки снимается вместе с данными: он говорит
    /// «сборка прошла», а не «сборка когда-то запускалась», — иначе после
    /// «удалить везде» вернувшиеся синком поездки остались бы без тумана.
    func wipe() {
        context.performAndWait {
            let request: NSFetchRequest<RevealedCellEntity> = RevealedCellEntity.fetchRequest()
            for entity in (try? context.fetch(request)) ?? [] { context.delete(entity) }
            saveContext()
        }
        defaults.set(false, forKey: Self.rebuildFlagKey)
        postChanged()
    }

    // MARK: - Внутри контекста

    /// Поездка без превью — законная строка выборки: она ГОВОРИТ, что
    /// библиотека не пуста, хотя открыть ею нечего. Отличать «поездок нет» от
    /// «превью нет» обязательно — от этого зависит, взводить ли флаг.
    private struct Preview {
        let id: UUID
        let polyline: Data?
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
    private func fetchPreviews(endedBefore date: Date?) -> [Preview] {
        let request = NSFetchRequest<NSDictionary>(entityName: "TripEntity")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id", "previewPolyline"]
        var predicates = [NSPredicate(
            format: "endDate != nil AND syncStatus != %d", SyncStatus.pendingDelete.rawValue
        )]
        if let date { predicates.append(NSPredicate(format: "endDate <= %@", date as NSDate)) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: true)]
        request.fetchBatchSize = 200
        return ((try? context.fetch(request)) ?? []).compactMap { row in
            guard let id = row["id"] as? UUID else { return nil }
            return Preview(id: id, polyline: row["previewPolyline"] as? Data)
        }
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            revealLog.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func postChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .revealedLayerChanged, object: nil)
        }
    }
}
