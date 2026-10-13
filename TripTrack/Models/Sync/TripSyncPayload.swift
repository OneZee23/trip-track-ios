import CoreLocation
import Foundation

struct TripPhotoMetadataPayload: Codable {
    let id: UUID
    let filename: String
    let caption: String?
    let timestamp: Date
    let sortOrder: Int
    /// 0.6.5: когда и где снят кадр — чтобы на новом телефоне снимки встали
    /// на маршрут так же, как на старом. Опционально в обе стороны: старый
    /// сервер ключей не шлёт, старый клиент их не понимает, и ни тот ни другой
    /// не имеют права уронить синхронизацию целиком.
    var capturedAt: Date?
    var exifLatitude: Double?
    var exifLongitude: Double?
}

/// Отметка на маршруте в проводе (0.6.5). Зеркало `TripCheckpoint`.
struct TripCheckpointPayload: Codable {
    let id: UUID
    let timestamp: Date
    /// Координата отметки. ОПЦИОНАЛЬНА с 0.8.3, и это правка контракта на
    /// обеих сторонах — ради приватной зоны у дома.
    ///
    /// До 0.8.3 широта и долгота были обязательными, и выбор был из двух
    /// поломок: отправить ноль (точка в Гвинейском заливе) или выбросить
    /// отметку из пейлоада, потеряв её вместе с именем на втором телефоне.
    /// Теперь есть третий ответ: отметка уезжает целиком — с именем, временем
    /// и «от старта», — но без адреса. На втором телефоне она есть в
    /// «Моментах» и её нет на карте: ровно то же самое уже делает обрезанный
    /// трек.
    ///
    /// `nil` на ВХОДЕ значит два разных случая, и разводит их
    /// `applyRemoteTrip`: если своя копия отметки есть, её координата
    /// остаётся (сервер про это место просто молчит); если копии нет — место
    /// потеряно, и отметка заводится пустой (`TripCheckpoint.hasCoordinate`).
    let latitude: Double?
    let longitude: Double?
    let distanceFromStart: Double
    let elapsedFromStart: Double
    let name: String?
    let photoId: UUID?
    /// Прикреплённые рукой снимки. Опционально в обе стороны: старый сервер
    /// ключа не знает и не отдаёт — тогда пусто, а не ошибка.
    let photoIds: [UUID]?
    let placeId: UUID?
    let sortOrder: Int
}

/// Отрезок между двумя отметками в проводе (0.6.8). Зеркало `TripSegment`.
///
/// Времени и километров здесь нет НАРОЧНО: их считают из двух отметок, а
/// посланное число стало бы вторым счётом, который однажды разойдётся с
/// одометром поездки.
struct TripSegmentPayload: Codable {
    let id: UUID
    let fromCheckpointId: UUID
    let toCheckpointId: UUID
    let name: String?
}

struct TripSyncPayload: Codable {
    let id: UUID
    let title: String?
    let description: String?
    let startDate: Date
    let endDate: Date?
    let distance: Double
    let maxSpeed: Double
    let averageSpeed: Double
    let fuelUsed: Double
    let elevation: Double
    /// 0.5.6+ extended metrics — computed locally from track points before
    /// upload so the server can echo them back on /social/feed without
    /// having to fetch + reduce track points for every reader. Optional in
    /// the wire format for forward/backward compat with older servers.
    let maxAltitude: Double?
    let drivingTime: Int?
    let stoppedTime: Int?
    let region: String?
    let isPrivate: Bool
    let vehicleId: UUID?
    /// Поездка пассажиром. Опционально: сервер без этой колонки ключа не шлёт,
    /// и старый бэкенд обязан декодироваться, а не ронять всю синхронизацию.
    var isTransfer: Bool?
    let fuelCurrency: String?
    let previewPolyline: String?
    let badgesJson: String?
    let xpEarned: Int?
    let conflictVersion: Int
    let lastModifiedAt: Date
    /// When the server first accepted this trip.
    ///
    /// The backend has always sent it — `serializeTrip` emits it on
    /// `/sync/pull` and `/trips/detail` — and the client simply never decoded
    /// it, so every trip that arrived by pull carried a nil `serverCreatedAt`
    /// locally. That nil is what made deleting a pulled trip take the "it was
    /// never on the server" short-circuit, leaving the row alive server-side
    /// forever. Optional because an older server omits it and because locally
    /// built upload payloads have nothing to put here yet.
    let serverCreatedAt: Date?
    // Optional: server omits track points in sync/pull responses (delta sync returns metadata only).
    // Present on upload (client → server) and on /trips/detail response.
    let trackPoints: [TrackPointPayload]?
    let photos: [TripPhotoMetadataPayload]?
    /// Отметки едут внутри поездки, а не отдельной очередью: их единицы, они
    /// бессмысленны без неё, и отдельный тип синк-операции ради них — это
    /// второй диалект того же разговора.
    var checkpoints: [TripCheckpointPayload]?
    /// Отрезки — той же дисциплиной, что отметки: едут внутри поездки, список
    /// целиком заменяет прежний, ключ отсутствует — старый сервер, локальное
    /// не трогать.
    var segments: [TripSegmentPayload]?
    /// Записана треком или вписана рукой (0.8.0). `nil` — старый сервер про
    /// поле молчит, локальное не трогаем; см. `TripOrigin.init(from:)` —
    /// незнакомая строка внутри читается как «записана треком», а не роняет
    /// весь пейлоад.
    var source: TripOrigin? = nil
    /// Как ехал плагин-гибрид (0.8.3). См. `TripEnergyMode`.
    ///
    /// **Ключ едет ВСЕГДА, и «Авто» тоже — строкой.** Дисциплина у него не
    /// такая, как у `source` и `checkpoints`: там отсутствие ключа значит
    /// «старый сервер молчит», и это единственное, что оно может значить. А
    /// здесь «Авто» — законный ОТВЕТ человека, вернувшего выбор обратно, и
    /// уезжай он отсутствием ключа, возврат с «Электро» на «Авто» не доехал бы
    /// до второго телефона никогда: пул прочитал бы молчание и оставил
    /// «Электро». Поэтому оптиональность здесь описывает только приходящее
    /// (старый сервер), а исходящее всегда несёт строку.
    /// СТРОКОЙ, а не типом, и это не небрежность.
    ///
    /// `TripSyncPayload` кодируется СИНТЕЗИРОВАННЫМ `Codable`, а тот на
    /// незнакомом значении бросает — то есть роняет пейлоад поездки целиком.
    /// Терпимый `init(from:)` у самого типа (приём `TripOrigin`) эту половину
    /// чинит, но заводит вторую: незнакомый режим с будущего клиента прочитался
    /// бы как «Авто» и ЗАТЁР бы локальный выбор человека. Строка разводит все
    /// три случая честно: ключа нет — старый сервер; значение знакомо — это
    /// ответ; значение незнакомо — мнения у нас о нём нет, локальное не трогаем.
    /// Ровно так же разобран `dashboardUnits` у машины — только там для этого
    /// пришлось писать весь `Codable` руками.
    var energyMode: String? = nil
    /// Absent means an older peer; an explicit empty array clears boundaries.
    var recordingBreaks: [Date]? = nil
}

extension TripSyncPayload {
    /// `zone` по умолчанию читается из нынешних настроек — это и есть
    /// продовый путь. Параметром она вынесена ПОТОМУ, что иначе пейлоад
    /// зависит от глобального `UserDefaults` молча: любой тест, собравший
    /// поездку, начинал резать её треком, если в контейнере симулятора
    /// осталась включённая зона от соседнего прогона. Так и случилось —
    /// кадровый тест экрана дома оставил зону включённой, и `TripSyncPayload
    /// MapperTests` покраснел в другом конце набора. Значение по умолчанию
    /// вычисляется в момент ВЫЗОВА, поэтому продовые два места ничего не
    /// передают и читают живое.
    init(trip: Trip, entity: TripEntity,
         zone: Zone? = HomeSettings.load().activeZone) {
        self.id = trip.id
        self.title = trip.title
        self.description = trip.tripDescription
        self.startDate = trip.startDate
        self.endDate = trip.endDate
        self.distance = trip.distance
        self.maxSpeed = trip.maxSpeed
        self.averageSpeed = trip.averageSpeed
        self.fuelUsed = trip.fuelUsed
        self.elevation = trip.elevation
        // Extended metrics — derived from track points. Грубые и достроенные
        // точки в эти числа не идут (спека §2.4): у достройки скорость −1, и
        // счёт ниже записал бы тоннель в «стоянку».
        let measured = trip.measuredPoints
        if !measured.isEmpty {
            self.maxAltitude = measured.map(\.altitude).max()
            let split = TripSyncPayload.computeMovementSplit(measured)
            self.drivingTime = Int(split.driving)
            self.stoppedTime = Int(split.stopped)
        } else {
            self.maxAltitude = nil
            self.drivingTime = nil
            self.stoppedTime = nil
        }
        // Приватная зона у дома (0.8.2) — ЕДИНСТВЕННАЯ граница, где трек
        // режется. Стоит ЗДЕСЬ, ниже чисел выше: расстояние, время в пути и
        // высоты считаются по ПОЛНОМУ треку и не меняются от того, что
        // человек закрыл свой двор. Числа — про саму поездку, обрезка — про
        // то, что видно чужим.
        self.region = trip.region
        self.isPrivate = trip.isPrivate
        self.isTransfer = trip.isTransfer
        self.vehicleId = trip.vehicleId
        self.fuelCurrency = trip.fuelCurrency
        self.previewPolyline = Self.wirePreview(trip.previewPolyline, zone: zone)
        self.badgesJson = entity.badgesJSON
        self.xpEarned = Int(entity.xpEarned)
        self.conflictVersion = Int(entity.conflictVersion)
        self.lastModifiedAt = entity.lastModifiedAt ?? Date()
        self.serverCreatedAt = entity.serverCreatedAt
        // A manual trip imported as a summary has not downloaded its points
        // yet. Editing its title/privacy must not upload [] and erase the
        // server's full route. nil means "leave that field alone". When local
        // points exist, home privacy still trims them; a loaded track trimmed
        // to nothing sends the explicit empty array produced by wireTrack.
        if trip.source == .manual, entity.serverCreatedAt != nil, trip.trackPoints.isEmpty {
            self.trackPoints = nil
        } else {
            self.trackPoints = Self.wireTrack(trip.trackPoints, zone: zone)
        }
        self.recordingBreaks = trip.recordingBreaks
        self.photos = (entity.photos?.array as? [TripPhotoEntity])?.compactMap { pe in
            guard let pid = pe.id, let fn = pe.filename, let ts = pe.timestamp else { return nil }
            return TripPhotoMetadataPayload(
                id: pid, filename: fn, caption: pe.caption,
                timestamp: ts, sortOrder: Int(pe.sortOrder),
                capturedAt: pe.capturedAt,
                exifLatitude: Self.wireExif(pe.exifLatitude?.doubleValue,
                                            pe.exifLongitude?.doubleValue, zone: zone)?.latitude,
                exifLongitude: Self.wireExif(pe.exifLatitude?.doubleValue,
                                             pe.exifLongitude?.doubleValue, zone: zone)?.longitude)
        }
        self.checkpoints = trip.checkpoints.enumerated().map { index, c in
            TripCheckpointPayload(
                id: c.id, timestamp: c.timestamp,
                latitude: Self.wireCheckpoint(c.latitude, c.longitude, zone: zone)?.latitude,
                longitude: Self.wireCheckpoint(c.latitude, c.longitude, zone: zone)?.longitude,
                distanceFromStart: c.distanceFromStart, elapsedFromStart: c.elapsedFromStart,
                name: c.name, photoId: c.photoId, photoIds: c.photoIds, placeId: c.placeId, sortOrder: index)
        }
        self.segments = trip.segments.map {
            TripSegmentPayload(
                id: $0.id, fromCheckpointId: $0.fromCheckpointId,
                toCheckpointId: $0.toCheckpointId, name: $0.name)
        }
        self.source = trip.source
        // Ключ едет ВСЕГДА, и «Авто» тоже: иначе возврат на «Авто»
        // неотличим от молчания старого клиента — см. поле выше.
        self.energyMode = trip.energyMode.rawValue
    }

    /// Координата кадра внутри зоны с телефона НЕ уезжает.
    ///
    /// Снимок, сделанный во дворе, несёт точку дома точнее любого трека, а
    /// `TripPhotoPlacement` ставит по ней булавку прямо на публичной карте
    /// поездки. Поля опциональны в обе стороны с 0.6.5 — «нет координаты»
    /// это законный ответ, и снимок от этого не теряется: уезжают и файл, и
    /// подпись, и время.
    ///
    /// Убираются ОБЕ половины разом: одна широта без долготы это не «меньше
    /// данных», а сломанная пара.
    /// Координата ОТМЕТКИ внутри зоны с телефона не уезжает (0.8.3).
    ///
    /// Долг 0.8.2, названный в `home-privacy.md` словами: трек, превью и EXIF
    /// снимка там уже обрезаны, а отметка, поставленная во дворе, уезжала
    /// точной точкой — и уезжала ОСОЗНАННО, потому что широта и долгота были
    /// в проводе обязательными. Теперь они опциональны на обеих сторонах, и
    /// отметка уезжает без адреса, сохраняя имя и время.
    ///
    /// Убираются ОБЕ половины разом, как у EXIF: одна широта без долготы —
    /// это не «меньше данных», а сломанная пара.
    static func wireCheckpoint(_ latitude: Double, _ longitude: Double, zone: Zone?)
    -> (latitude: Double, longitude: Double)? {
        guard let zone else { return (latitude, longitude) }
        let point = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard !PrivacyZone.hides(point, centre: zone.centre, radius: zone.radius) else { return nil }
        return (latitude, longitude)
    }

    static func wireExif(_ latitude: Double?, _ longitude: Double?, zone: Zone?)
    -> (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        guard let zone else { return (latitude, longitude) }
        let point = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard !PrivacyZone.hides(point, centre: zone.centre, radius: zone.radius) else { return nil }
        return (latitude, longitude)
    }

    /// Зона в удобной форме: её читают оба носителя геометрии.
    typealias Zone = (centre: CLLocationCoordinate2D, radius: Double)

    /// Трек в проводе: полный, если зоны нет, обрезанный, если есть.
    ///
    /// **Обрезка НЕ спрашивает `isPrivate`**, хотя тумблер и назван «обрезать
    /// публичные». Правило версии — «режется то, что УХОДИТ С ТЕЛЕФОНА», а
    /// приватная поездка уходит на тот же сервер теми же байтами. Зависимость
    /// от приватности была бы вдобавок багом: `AuthService
    /// .unpublishAllPublicTrips` ставит `isPrivate = true` ПЕРЕД сборкой
    /// пейлоада, и на выходе из аккаунта уже обрезанный серверный трек
    /// заменился бы полным — ровно в тот момент, когда человек просил
    /// спрятать.
    ///
    /// Пустой список, а НЕ `nil`. `nil` в проводе — «ключа нет, локальное не
    /// трогать» (дисциплина `checkpoints`/`segments` 0.6.5/0.6.8), и поездка,
    /// уехавшая целиком ДО включения зоны, осталась бы на сервере целой
    /// навсегда: переотправка ничего бы не стёрла.
    static func wireTrack(_ points: [TrackPoint], zone: Zone?) -> [TrackPointPayload] {
        guard let zone else { return points.map(TrackPointPayload.init) }
        let left = PrivacyZone.trim(points: points, centre: zone.centre, radius: zone.radius)
        guard PrivacyZone.isDrawable(left.count) else { return [] }
        return left.map(TrackPointPayload.init)
    }

    /// Превью — ВТОРОЙ носитель геометрии, и режется тем же правилом.
    ///
    /// Его рисует карточка в чужой ленте, не поднимая трека вовсе: обрежь
    /// один трек — и двор всё равно виден в ленте. Поездка целиком внутри
    /// зоны уезжает без превью, а не с огрызком в одну точку.
    ///
    /// А локальное превью от этого НЕ страдает: пул возвращает наше же
    /// обрезанное превью эхом, и `applyRemoteTrip` перестал записывать его
    /// поверх своего, пока зона включена. Своя поездка на своём телефоне
    /// остаётся целой всегда.
    static func wirePreview(_ preview: Data?, zone: Zone?) -> String? {
        guard let preview else { return nil }
        guard let zone else { return preview.base64EncodedString() }
        let left = PrivacyZone.trim(coordinates: Trip.decodePolyline(preview),
                                    centre: zone.centre, radius: zone.radius)
        guard PrivacyZone.isDrawable(left.count) else { return nil }
        return Trip.encodePolyline(left).base64EncodedString()
    }

    /// Mirrors `Trip.movementSplit` — duplicated here (not called through the
    /// Trip getter) because `Trip.movementSplit` is private and we want to
    /// keep the computation locally side-effect-free, with no reliance on
    /// CoreData faulting behaviour at upload time.
    private static func computeMovementSplit(_ points: [TrackPoint]) -> (driving: TimeInterval, stopped: TimeInterval) {
        guard points.count >= 2 else { return (0, 0) }
        let idleSpeedKmh = 5.0
        let maxGap: TimeInterval = 60
        var drv: TimeInterval = 0
        var stp: TimeInterval = 0
        for i in 1..<points.count {
            guard points[i].recordingSegmentIndex == points[i - 1].recordingSegmentIndex else { continue }
            let dt = points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
            guard dt > 0, dt <= maxGap else { continue }
            let avgKmh = ((points[i].speed + points[i - 1].speed) / 2.0) * 3.6
            if avgKmh < idleSpeedKmh {
                stp += dt
            } else {
                drv += dt
            }
        }
        return (drv, stp)
    }
}
