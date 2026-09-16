import Foundation
import CoreData
import CoreLocation
import OSLog

private let discoveryLog = Logger(subsystem: "com.triptrack", category: "discoveries")

/// Найденное в базе: одна строка на находку, ключ — выведенный `id`.
///
/// Копится так же, как открытый мир: финиш поездки добавляет только то, чего
/// ещё не находили, а экраны читают готовое. Поэтому `upsert` возвращает
/// ТОЛЬКО новые находки — из них собирается блок «Открыто» на экране итогов,
/// и «нашёл то же самое второй раз» обязано дать пустой список, а не радостное
/// уведомление.
///
/// **Первая находка побеждает.** Уже лежащую строку повторный `upsert` не
/// трогает: печать стоит в дате, когда человек там был ВПЕРВЫЕ, и второй
/// проезд не имеет права её передатировать или перевесить на новую поездку.
///
/// Всё на своём фоновом контексте: финиш поездки и так занят, а разбор трека
/// идёт сразу за превью, местами и инжестом тумана. Поэтому чтение и запись
/// здесь `async` — главный актёр не имеет права стоять в очереди этого
/// контекста. `@unchecked Sendable` осознанно: всё изменяемое состояние типа —
/// ОДИН контекст CoreData, и трогают его только внутри его же `perform`.
final class DiscoveryStore: @unchecked Sendable {
    static let shared = DiscoveryStore()

    private let context: NSManagedObjectContext

    init(persistence: PersistenceController = .shared) {
        context = persistence.container.newBackgroundContext()
        // Ограничение уникальности по `id` не роняет сохранение, а сливает:
        // две поездки, разобранные внахлёст, находят одно и то же.
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Запись

    /// Записать найденное. Возвращает ТОЛЬКО то, чего в базе не было.
    ///
    /// Бросает, если сохранение не прошло: находки — единственный результат
    /// разбора трека, и молча потерянная печать выглядит как «приложение
    /// ничего не нашло», то есть как отсутствие фичи.
    @discardableResult
    func upsert(_ items: [Discovery]) async throws -> [Discovery] {
        guard !items.isEmpty else { return [] }
        let fresh = try await context.perform { () -> [Discovery] in
            // Одна выборка на весь пакет: разбор трека приносит десятки
            // находок, и запрос на каждую был бы десятками походов в базу.
            let known = self.existingIds(among: items.map(\.id))
            var added: [Discovery] = []
            var seen = Set<UUID>()
            for item in items where !known.contains(item.id) && seen.insert(item.id).inserted {
                let entity = DiscoveryEntity(context: self.context)
                entity.id = item.id
                entity.kind = item.kind.rawValue
                entity.key = item.key
                entity.tripId = item.tripId
                entity.latitude = item.coordinate.latitude
                entity.longitude = item.coordinate.longitude
                entity.foundAt = item.foundAt
                entity.symbol = item.symbol.rawValue
                entity.title = item.title
                entity.verified = item.verified
                added.append(item)
            }
            guard self.context.hasChanges else { return [] }
            do {
                try self.context.save()
            } catch {
                self.context.rollback()
                discoveryLog.error("save failed: \(error.localizedDescription, privacy: .public)")
                throw error
            }
            return added
        }
        if !fresh.isEmpty { postChanged() }
        return fresh
    }

    /// Стереть найденное. Синхронный нарочно: единственный вызывающий —
    /// `LocalDataWipe.run()`, синхронная точка на главном актёре, а работы
    /// здесь на один delete.
    func wipe() {
        context.performAndWait {
            let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
            for entity in (try? context.fetch(request)) ?? [] { context.delete(entity) }
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    discoveryLog.error("wipe failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            // `LocalDataWipe` стирает пакетом мимо контекстов, и в этом
            // остались бы зарегистрированные «призраки» стёртых строк.
            context.reset()
        }
        // Кэш истории вех (`discoveries.extremes`) лежит рядом с находками и
        // стирается вместе с ними: он выведен из поездок, и пережить их не
        // имеет права — иначе после «удалить везде» вернувшиеся синком поездки
        // не дали бы ни одного «первого региона». Стирается ОТСЮДА, а не из
        // `LocalDataWipe`: имя `DiscoveryProcessor` за пределами этой папки
        // запрещено сторожем `NoLiveSecretPromptsTests`.
        UserDefaults.standard.removeObject(forKey: DiscoveryProcessor.historyKey)
        postChanged()
    }

    // MARK: - Чтение

    /// Всё найденное, свежее сверху.
    func all() async -> [Discovery] {
        await context.perform { self.fetch(kind: nil) }
    }

    func discoveries(kind: DiscoveryKind) async -> [Discovery] {
        await context.perform { self.fetch(kind: kind) }
    }

    func contains(id: UUID) async -> Bool {
        await context.perform { !self.existingIds(among: [id]).isEmpty }
    }

    // MARK: - Внутри контекста

    private func fetch(kind: DiscoveryKind?) -> [Discovery] {
        let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
        if let kind { request.predicate = NSPredicate(format: "kind == %@", kind.rawValue) }
        request.sortDescriptors = [NSSortDescriptor(key: "foundAt", ascending: false)]
        request.fetchBatchSize = 200
        return ((try? context.fetch(request)) ?? []).compactMap(Self.discovery(from:))
    }

    private func existingIds(among ids: [UUID]) -> Set<UUID> {
        let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", Set(ids) as NSSet)
        request.propertiesToFetch = ["id"]
        return Set(((try? context.fetch(request)) ?? []).compactMap(\.id))
    }

    /// Строка без вида или символа — не находка, а мусор миграции: молча
    /// пропускаем, как `tripFromEntity` пропускает висячий отрезок.
    private static func discovery(from entity: DiscoveryEntity) -> Discovery? {
        guard let kindRaw = entity.kind, let kind = DiscoveryKind(rawValue: kindRaw),
              let key = entity.key,
              let tripId = entity.tripId,
              let foundAt = entity.foundAt,
              let symbolRaw = entity.symbol, let symbol = SealSymbol(rawValue: symbolRaw)
        else { return nil }
        return Discovery(
            kind: kind,
            key: key,
            tripId: tripId,
            coordinate: CLLocationCoordinate2D(latitude: entity.latitude, longitude: entity.longitude),
            foundAt: foundAt,
            symbol: symbol,
            title: entity.title,
            verified: entity.verified
        )
    }

    private func postChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .discoveriesChanged, object: nil)
        }
    }
}
