import Foundation
import CoreData
import CoreLocation

/// Места и проезды — своё хранилище, а не ещё три сотни строк в
/// `TripRepository`: у мест нет ни синка, ни связей с поездкой, и всё, что
/// про них известно, помещается в один экран кода.
///
/// `PlaceEntity` и `PlacePassEntity` без связей — как `JourneyEntity`: каскад
/// от `TripEntity` их не заберёт, поэтому удаление поездки зовёт
/// `deletePasses(tripId:)` явно, а `LocalDataWipe` называет обе сущности.
protocol PlaceStore {
    func fetchPlaces() -> [Place]
    func fetchPlace(id: UUID) -> Place?
    /// Одна ячейка — одно место. Существующему имя достаётся, только пока
    /// оно безымянно: первое имя остаётся.
    @discardableResult
    func upsertPlace(cell: String, coordinate: CLLocationCoordinate2D, name: String?) -> (place: Place, isNew: Bool)
    func recomputeCentroid(placeId: UUID, from coordinates: [CLLocationCoordinate2D])
    /// true — место было безымянным и имя реально принято; false — уже было
    /// названо, или это надгробие удалённого (не заводит место заново).
    @discardableResult
    func adoptName(_ name: String, forPlace id: UUID) -> Bool
    /// Имя рукой: перезаписывает любое; пустое — снова безымянное. Геокодер
    /// (`adoptName`) пишет только в пустое, поэтому данное рукой не откатит.
    func rename(placeId: UUID, to name: String?)
    /// Место и его проезды. Отметки остаются при своих `placeId` (надгробие):
    /// иначе сверка при запуске воскресила бы место тем же вечером.
    func deletePlace(id: UUID)
    func passes(placeId: UUID) -> [PlacePass]
    func passes(tripId: UUID) -> [PlacePass]
    func passCount(placeId: UUID) -> Int
    /// Список проездов пары (место, поездка) заменяется целиком — повторная
    /// сверка не удваивает историю.
    func replacePasses(placeId: UUID, tripId: UUID, with passes: [PlacePass])
    func deletePasses(tripId: UUID)
}

final class CoreDataPlaceStore: PlaceStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Места

    private func entity(id: UUID) -> PlaceEntity? {
        let req: NSFetchRequest<PlaceEntity> = PlaceEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? context.fetch(req).first
    }

    private func place(from e: PlaceEntity) -> Place? {
        guard let id = e.id, let cell = e.cell else { return nil }
        return Place(id: id, cell: cell, latitude: e.latitude, longitude: e.longitude,
                     name: e.name, createdAt: e.createdAt ?? Date())
    }

    func fetchPlaces() -> [Place] {
        let req: NSFetchRequest<PlaceEntity> = PlaceEntity.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return ((try? context.fetch(req)) ?? []).compactMap(place(from:))
    }

    func fetchPlace(id: UUID) -> Place? { entity(id: id).flatMap(place(from:)) }

    @discardableResult
    func upsertPlace(cell: String, coordinate: CLLocationCoordinate2D, name: String?) -> (place: Place, isNew: Bool) {
        let id = Place.id(forCell: cell)
        if let e = entity(id: id) {
            if e.name == nil, let name, !name.isEmpty { e.name = name }
            save()
            return (place(from: e)!, false)
        }
        let e = PlaceEntity(context: context)
        e.id = id
        e.cell = cell
        e.latitude = coordinate.latitude
        e.longitude = coordinate.longitude
        e.name = (name?.isEmpty ?? true) ? nil : name
        e.createdAt = Date()
        save()
        return (place(from: e)!, true)
    }

    func recomputeCentroid(placeId: UUID, from coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty, let e = entity(id: placeId) else { return }
        e.latitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        e.longitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        save()
    }

    @discardableResult
    func adoptName(_ name: String, forPlace id: UUID) -> Bool {
        guard !name.isEmpty, let e = entity(id: id), e.name == nil else { return false }
        e.name = name
        save()
        return true
    }

    func rename(placeId: UUID, to name: String?) {
        guard let e = entity(id: placeId) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        e.name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        save()
    }

    func deletePlace(id: UUID) {
        guard let e = entity(id: id) else { return }
        for p in passEntities(format: "placeId == %@", id) { context.delete(p) }
        context.delete(e)
        save()
    }

    // MARK: - Проезды

    // Аргумент — `UUID...`, а не `CVarArg...`: голый `UUID` не конформит
    // `CVarArg` (везде в проекте это `id as CVarArg`), а звать так вызовы
    // ниже — терять точность бланка. Мост в `CVarArg` — здесь, один раз.
    private func passEntities(format: String, _ args: UUID...) -> [PlacePassEntity] {
        let req: NSFetchRequest<PlacePassEntity> = PlacePassEntity.fetchRequest()
        req.predicate = NSPredicate(format: format, argumentArray: args.map { $0 as CVarArg })
        return (try? context.fetch(req)) ?? []
    }

    private func pass(from e: PlacePassEntity) -> PlacePass? {
        guard let id = e.id, let placeId = e.placeId, let tripId = e.tripId, let ts = e.timestamp else { return nil }
        return PlacePass(id: id, placeId: placeId, tripId: tripId, timestamp: ts,
                         elapsedFromStart: e.elapsedFromStart, distanceFromStart: e.distanceFromStart,
                         course: e.course)
    }

    func passes(placeId: UUID) -> [PlacePass] {
        passEntities(format: "placeId == %@", placeId).compactMap(pass(from:))
            .sorted { $0.timestamp > $1.timestamp }
    }

    func passes(tripId: UUID) -> [PlacePass] {
        passEntities(format: "tripId == %@", tripId).compactMap(pass(from:))
            .sorted { $0.timestamp < $1.timestamp }
    }

    func passCount(placeId: UUID) -> Int {
        let req: NSFetchRequest<PlacePassEntity> = PlacePassEntity.fetchRequest()
        req.predicate = NSPredicate(format: "placeId == %@", placeId as CVarArg)
        return (try? context.count(for: req)) ?? 0
    }

    func replacePasses(placeId: UUID, tripId: UUID, with passes: [PlacePass]) {
        for old in passEntities(format: "placeId == %@ AND tripId == %@", placeId, tripId) {
            context.delete(old)
        }
        for p in passes {
            let e = PlacePassEntity(context: context)
            e.id = p.id
            e.placeId = placeId
            e.tripId = tripId
            e.timestamp = p.timestamp
            e.elapsedFromStart = p.elapsedFromStart
            e.distanceFromStart = p.distanceFromStart
            e.course = p.course
        }
        save()
    }

    func deletePasses(tripId: UUID) {
        let doomed = passEntities(format: "tripId == %@", tripId)
        guard !doomed.isEmpty else { return }
        for e in doomed { context.delete(e) }
        save()
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
