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
                entity.story = item.story
                entity.verified = item.verified
                entity.finders = item.finders.map(NSNumber.init(value:))
                entity.firstFinderName = item.firstFinderName
                entity.firstFinderAt = item.firstFinderAt
                entity.rarity = item.rarity
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

    /// Дописать к находке то, чего телефон знать не мог: историю, счётчик
    /// нашедших, первооткрывателя, редкость.
    ///
    /// **Дописать, а не переписать.** `foundAt` не трогается никогда — печать
    /// стоит в дате, когда человек там был, и серверная дата (заявка могла
    /// уехать позже, со второго телефона, из другого часового пояса) не имеет
    /// права её сдвинуть. `verified` ходит только false → true: подтверждение
    /// добывается треком на сервере, и ответ, пришедший без трека (Cloud Sync
    /// выключили между находкой и раскрытием), не имеет права снять уже
    /// полученное. `title` и `story` пустой строкой не затираются — пустое
    /// поле сервера это «текста ещё нет», а не «текста больше нет».
    ///
    /// Находки, которой ответ адресован, может не быть вовсе — ответ на чужой
    /// или уже стёртый id просто игнорируется (`false`).
    @discardableResult
    func apply(reveal: SecretRevealResponse) async -> Bool {
        guard let id = reveal.discoveryId else { return false }
        let changed = await context.perform { () -> Bool in
            let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let entity = (try? self.context.fetch(request))?.first else { return false }
            if let title = reveal.title, !title.isEmpty { entity.title = title }
            if let story = reveal.story, !story.isEmpty { entity.story = story }
            if let finders = reveal.finders { entity.finders = NSNumber(value: finders) }
            if let first = reveal.first {
                entity.firstFinderName = first.displayName
                entity.firstFinderAt = first.foundAt
            }
            if let rarity = reveal.rarity, !rarity.isEmpty { entity.rarity = rarity }
            if reveal.verified { entity.verified = true }
            guard self.context.hasChanges else { return false }
            do {
                try self.context.save()
            } catch {
                self.context.rollback()
                discoveryLog.error("reveal apply failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
            return true
        }
        if changed { postChanged() }
        return changed
    }

    /// Находка, приехавшая пулом. Отдельный тип, а не `Discovery`, ровно из-за
    /// одного поля: **координата необязательна**. Контракт волны 3 её не везёт
    /// (сервер хранит заявку, а не место), и у `Discovery` пустого значения
    /// координаты нет — нули в ней это точка в океане, а не «неизвестно».
    /// Поэтому «где» решает тот, кто разбирает пул, а «что с этим делать» —
    /// `applyRemote` ниже.
    struct Remote {
        let id: UUID
        let kind: DiscoveryKind
        let key: String
        let tripId: UUID
        let coordinate: CLLocationCoordinate2D?
        let foundAt: Date
        let symbol: SealSymbol
        let title: String?
        let story: String?
        let verified: Bool
    }

    /// Находки, приехавшие пулом со второго телефона.
    ///
    /// Не `upsert`: там «первая находка побеждает» означает «молча пропустить
    /// уже лежащее», а здесь у лежащего надо ещё и дописать текст, который
    /// сервер знает, а этот телефон — нет. Новую строку кладём как обычно;
    /// `foundAt` у уже лежащей не трогаем по тому же правилу.
    ///
    /// **Новую строку заводим только там, где знаем МЕСТО.** Уже лежащей
    /// находке место не нужно — оно у неё своё; а новая без координаты встала
    /// бы печатью в Гвинейском заливе. Поэтому `coordinate == nil` дописывает,
    /// но не заводит.
    ///
    /// Синхронный (`performAndWait`), как `wipe()`: зовёт его `PullApplier` —
    /// синхронная точка на главном актёре, — а работы здесь на десяток строк.
    /// Возвращает, изменилось ли что-нибудь: по этому ответу пул решает, будить
    /// ли «Атлас».
    @discardableResult
    func applyRemote(_ items: [Remote]) -> Bool {
        guard !items.isEmpty else { return false }
        var changed = false
        context.performAndWait {
            let known = existingRows(among: items.map(\.id))
            for item in items {
                if let entity = known[item.id] {
                    if let title = item.title, !title.isEmpty, entity.title != title {
                        entity.title = title
                    }
                    if let story = item.story, !story.isEmpty, entity.story != story {
                        entity.story = story
                    }
                    if item.verified && !entity.verified { entity.verified = true }
                } else if let coordinate = item.coordinate {
                    let entity = DiscoveryEntity(context: context)
                    entity.id = item.id
                    entity.kind = item.kind.rawValue
                    entity.key = item.key
                    entity.tripId = item.tripId
                    entity.latitude = coordinate.latitude
                    entity.longitude = coordinate.longitude
                    entity.foundAt = item.foundAt
                    entity.symbol = item.symbol.rawValue
                    entity.title = item.title
                    entity.story = item.story
                    entity.verified = item.verified
                }
            }
            guard context.hasChanges else { return }
            do {
                try context.save()
                changed = true
            } catch {
                context.rollback()
                discoveryLog.error("remote apply failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if changed { postChanged() }
        return changed
    }

    // MARK: - Чтение

    /// Одна находка по её выведенному id. Нужна повторной попытке раскрытия:
    /// в очереди синка лежит `id`, а серверу нужны вид, ключ и поездка.
    func discovery(id: UUID) async -> Discovery? {
        await context.perform {
            let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return ((try? self.context.fetch(request))?.first).flatMap(Self.discovery(from:))
        }
    }

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

    /// Строки по id — одной выборкой на пакет, как `existingIds`, но с самими
    /// объектами: пулу мало знать, что строка есть, ему её ещё дописывать.
    private func existingRows(among ids: [UUID]) -> [UUID: DiscoveryEntity] {
        let request: NSFetchRequest<DiscoveryEntity> = DiscoveryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", Set(ids) as NSSet)
        let rows = (try? context.fetch(request)) ?? []
        return Dictionary(rows.compactMap { row in row.id.map { ($0, row) } },
                          uniquingKeysWith: { first, _ in first })
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
            story: entity.story,
            verified: entity.verified,
            finders: entity.finders?.intValue,
            firstFinderName: entity.firstFinderName,
            firstFinderAt: entity.firstFinderAt,
            rarity: entity.rarity
        )
    }

    private func postChanged() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .discoveriesChanged, object: nil)
        }
    }
}
