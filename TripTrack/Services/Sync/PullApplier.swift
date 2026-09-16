import Foundation
import CoreData
import CoreLocation

/// Что пул кладёт в `userInfo` своего `.syncPullCompleted`.
///
/// Ключ ОДИН и типизирован нарочно: слушателям пула (`RevealedLayerSync`)
/// нужно знать не «когда», а «ЧТО приехало». Время для этого не годится —
/// `lastModifiedAt` у своей поездки ставят часы этого телефона, у чужой она
/// приезжает как есть с другого устройства, а дельта на сервере режется
/// серверными часами: три шкалы, и любое окно по времени однажды отсекает
/// поездку, которой ещё не было. Список применённых id не зависит ни от
/// одних часов.
///
/// Пустой список — законный ответ «пул ничего не привёз», а ОТСУТСТВИЕ ключа
/// значит «неизвестно» (старый постер, чужой вызов, тест) и стоит слушателю
/// полного прохода.
enum SyncPullNotification {
    /// `[UUID]` — поездки, применённые этим пулом.
    static let appliedTripIds = "syncPullAppliedTripIds"
}

@MainActor
final class PullApplier {
    private let repo: TripRepository = CoreDataTripRepository()
    private let discoveries: DiscoveryStore

    init(discoveries: DiscoveryStore = .shared) {
        self.discoveries = discoveries
    }

    /// Возвращает id применённых поездок — их несёт `.syncPullCompleted`.
    @discardableResult
    func apply(_ response: SyncPullResponse) -> [UUID] {
        for p in response.trips.upserted { repo.applyRemoteTrip(p) }

        // A tombstone for a trip this device never mirrored is not about our
        // copy — see `deleteTripHardIfMirrored`. Remember the ones we kept:
        // their photos need the same protection.
        var keptTripIds = Set<UUID>()
        for id in response.trips.deleted where !repo.deleteTripHardIfMirrored(id: id) {
            keptTripIds.insert(id)
        }

        for p in response.vehicles.upserted { repo.applyRemoteVehicle(p) }
        for id in response.vehicles.deleted {
            Self.purgeLocalRemains(ofVehicle: id)
            repo.deleteVehicleHard(id: id)
        }
        for p in response.photos.upserted { repo.applyRemotePhoto(p) }

        // `/trips/delete` cascades `isDeleted` onto every photo row of the
        // trip, so the SAME pull that carries a trip id in `trips.deleted`
        // carries its photo ids here. Deleting them unguarded hands the user
        // back a trip with an empty gallery — and since `deletePhotoHard`
        // removes only the row, the JPEGs stay in Documents with nothing
        // pointing at them.
        for id in response.photos.deleted {
            if let tripId = repo.tripId(forPhoto: id), keptTripIds.contains(tripId) { continue }
            repo.deletePhotoHard(id: id)
        }
        if let s = response.settings {
            repo.applyRemoteSettings(s)
        }
        if let journeys = response.journeys {
            for p in journeys.upserted { repo.applyRemoteJourney(p) }
            for id in journeys.deleted { repo.deleteJourneyHard(id: id) }
        }
        if let section = response.discoveries {
            applyDiscoveries(section)
        }
        // One save for the whole batch instead of N saves (one per row).
        // CoreData performance scales linearly with save count, so a
        // pull of 50 trips drops from 50× saveContext() to 1×.
        repo.flushPendingApplies()
        // Раньше перечитывали только когда приехали НАСТРОЙКИ. Но архив и
        // продажа приезжают в записи МАШИНЫ, а настройки при этом могут не
        // прийти вовсе: чужое устройство трогает свою строку настроек только
        // если убранная машина была выбрана именно на нём. В результате
        // CoreData уже знала, что машина в архиве, а список в памяти — ещё
        // нет, и запись уходила на архивную машину до конца сеанса.
        let vehiclesChanged = !response.vehicles.upserted.isEmpty
            || !response.vehicles.deleted.isEmpty
        if response.settings != nil || vehiclesChanged {
            SettingsManager.shared.reloadFromCoreData()
        }
        return response.trips.upserted.map(\.id)
    }

    /// Находки со второго телефона.
    ///
    /// Своя база остаётся источником правды: у находки, которая на этом
    /// телефоне уже есть, пул дописывает только текст и `verified` — ни даты,
    /// ни поездки он не двигает (правило «первая находка побеждает» то же, что
    /// у `upsert`).
    ///
    /// Координаты в контракте нет: сервер её не хранит. У загадки место
    /// выводится из собственного ключа (`"<type>:<geohash7>"`, центр ячейки —
    /// ±75 м, то есть тот же объект), у секрета вывести неоткуда — в каталоге
    /// лежат одни усечённые хеши. Что делать с находкой без места, решает
    /// `DiscoveryStore.applyRemote`: дописать можно, завести — нет.
    private func applyDiscoveries(_ section: SyncPullResponse.DiscoveriesSection) {
        let rows = section.upserted.compactMap(Self.remote(from:))
        guard !rows.isEmpty else { return }
        discoveries.applyRemote(rows)
    }

    /// Чистое превращение строки пула в находку. `nil` — строку не применить
    /// вовсе: незнакомый вид или нет поездки, по которой её открывать.
    static func remote(from payload: DiscoverySyncPayload) -> DiscoveryStore.Remote? {
        guard let kind = DiscoveryKind(rawValue: payload.kind),
              let tripId = payload.tripId
        else { return nil }
        return DiscoveryStore.Remote(
            id: Discovery.id(kind: kind, key: payload.secretId),
            kind: kind,
            key: payload.secretId,
            tripId: tripId,
            coordinate: coordinate(forKind: kind, key: payload.secretId),
            foundAt: payload.foundAt,
            symbol: payload.symbol.flatMap(SealSymbol.init(rawValue:)) ?? .generic,
            title: payload.title,
            story: payload.story,
            verified: payload.verified ?? false)
    }

    /// Место находки по её ключу. Умеет ровно один вид — загадку, у которой
    /// geohash-7 ячейки стоит во второй половине ключа.
    private static func coordinate(
        forKind kind: DiscoveryKind, key: String
    ) -> CLLocationCoordinate2D? {
        guard kind == .riddle else { return nil }
        let parts = key.split(separator: ":")
        guard parts.count == 2, parts[1].count >= 5 else { return nil }
        return GeohashEncoder.centerCoordinate(of: String(parts[1]))
    }

    /// То же, что называет руками `SettingsManager.deleteVehicle`, — но для
    /// машины, удалённой на ДРУГОМ телефоне.
    ///
    /// `deleteVehicleHard` удаляет ровно `VehicleEntity`, и этого мало.
    /// Связи с машиной у `VehiclePhotoEntity` нет — `vehicleId` там обычный
    /// атрибут, значит каскад её не заберёт: и строки, и сами JPEG остались бы
    /// в Documents навсегда, а каталог исключён из резервной копии, и добраться
    /// до них уже нечем. Привязка магнитолы пережила бы машину и продолжила
    /// указывать в мёртвый id: при следующем подключении `AutoTripService`
    /// сохранил бы выбранной несуществующую машину, и поездка молча записалась
    /// бы «Без транспорта». А забытый вопрос о видимости снимков не задался бы
    /// заново, если бы машина с тем же id вернулась синком.
    ///
    /// Порядок важен: снимки убираются ДО `deleteVehicleHard`, пока по
    /// `vehicleId` ещё есть что искать.
    static func purgeLocalRemains(
        ofVehicle id: UUID,
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
        settings: SettingsManager = .shared,
        defaults: UserDefaults = .standard
    ) {
        VehiclePhotoStore.deleteAllLocally(of: id, context: context)
        settings.removeBluetoothDevice(forVehicle: id)
        VehiclePhotoVisibilityAsk.forget(id, defaults)
    }
}
