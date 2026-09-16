import Foundation

struct SyncPullResponse: Codable {
    struct TripsSection: Codable {
        let upserted: [TripSyncPayload]
        let deleted: [UUID]
    }
    struct VehiclesSection: Codable {
        let upserted: [VehicleSyncPayload]
        let deleted: [UUID]
    }
    struct PhotosSection: Codable {
        let upserted: [PhotoSyncPayload]
        let deleted: [UUID]
    }
    struct JourneysSection: Codable {
        let upserted: [JourneySyncPayload]
        let deleted: [UUID]
    }
    /// Находки (0.7.0) — то, что нашёл ВТОРОЙ телефон этого же человека.
    ///
    /// `deleted` в контракте есть и разбирается, но пустой всегда: находку не
    /// снимают поштучно. Поле остаётся, потому что форма секции общая для всех
    /// типов, и сервер, который однажды начнёт его наполнять, не должен ронять
    /// разбор пула.
    ///
    /// **`[String]`, а не `[UUID]`,** — и это не вкусовщина: ключ находки это
    /// id секрета из каталога или `"<type>:<geohash7>"` загадки
    /// (`"pass:ubcr4xk"`), то есть строка, которая UUID не является никогда.
    /// Пока список пуст, `[]` декодируется любым типом; в день, когда сервер
    /// положит в него первую строку, `[UUID]` уронил бы не секцию находок, а
    /// ВЕСЬ `/sync/pull`.
    struct DiscoveriesSection: Codable {
        let upserted: [DiscoverySyncPayload]
        let deleted: [String]?
    }

    /// Count of non-deleted entities the server currently holds for this
    /// account. Client compares against local `synced` count to detect
    /// server-side data loss and trigger reconciliation via `/sync/manifest`.
    /// Optional for backwards compatibility with older backends.
    struct OwnedCounts: Codable {
        let trips: Int
        let vehicles: Int
        let photos: Int
        /// Not wired into reconciliation yet (0.6.6) — the manifest/heal path
        /// stays trips/vehicles/photos only. Decoded so the struct doesn't
        /// choke on a server that starts sending it.
        let journeys: Int?
    }

    let trips: TripsSection
    let vehicles: VehiclesSection
    let photos: PhotosSection
    let settings: SettingsSyncPayload?
    let serverTime: String
    let ownedCounts: OwnedCounts?
    /// Optional: сервер до 0.6.6 секции не знает.
    let journeys: JourneysSection?
    /// Optional: сервер до 0.7.0 секции не знает, и отсутствие ключа — это
    /// «старый сервер», а не «находок нет». Та же дисциплина ключа, что у
    /// `checkpoints`/`segments` внутри поездки.
    let discoveries: DiscoveriesSection?
}

/// Находка на проводе.
///
/// Координата у строки ЕСТЬ, но не у каждой: фикс-волна волны 3 научила сервер
/// отдавать `latitude`/`longitude` (центр первой ячейки заявки) **только для
/// подтверждённых** находок — у неподтверждённой сервер своего трека не видел
/// и ручаться за место не может. Отсюда и разбор: пара пришла целиком —
/// секрет со второго телефона встаёт печатью здесь; не пришла — прежний вывод
/// по ключу (загадка) или «дописать, но не заводить» (секрет). Что с этим
/// делает клиент — см. `PullApplier.remote(from:)`.
struct DiscoverySyncPayload: Codable {
    /// Ключ находки: id секрета из каталога или `"<type>:<geohash7>"` загадки.
    let secretId: String
    let kind: String
    let symbol: String?
    let foundAt: Date
    let verified: Bool?
    let tripId: UUID?
    /// Центр первой ячейки заявки. `nil` у неподтверждённой находки и у
    /// сервера до фикс-волны волны 3 — обе половины обязаны прийти вместе,
    /// одна без другой не значит ничего.
    let latitude: Double?
    let longitude: Double?
    let title: String?
    let story: String?
}

/// Full list of entity UUIDs the server currently owns. Fetched only when
/// `ownedCounts` disagrees with local state — used to identify specifically
/// which local-synced entities the server has lost so they can be re-uploaded.
///
/// `truncated` is set when the server's per-type cap was hit — the ID list
/// is incomplete and MUST NOT drive reconciliation, otherwise client would
/// flag legit server-owned entities as "missing" and re-upload them.
struct SyncManifestResponse: Codable {
    let trips: [UUID]
    let vehicles: [UUID]
    let photos: [UUID]
    let truncated: Bool?
}
