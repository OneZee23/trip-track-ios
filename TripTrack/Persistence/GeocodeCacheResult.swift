import Foundation

/// Ответ кэша геокодера по координате: имя населённого пункта и региона.
///
/// Раньше жил приватной структурой в `TripManager` — единственном, кто ходил
/// в `GeocodeCacheEntity`. С 0.6.8 кэш читает и экран места (через
/// `TripRepository`), а вью-модели и тесту нужен тип без `TripManager`;
/// правило «один тип — один файл» не даёт держать его внутри протокола.
struct GeocodeCacheResult {
    let locality: String?
    let region: String?

    /// TTL записи кэша — 90 дней, один источник на оба пути чтения:
    /// синхронный `CoreDataTripRepository.cachedGeocode` и пакетный фоновый
    /// `TripManager.cachedLocalities`. Раньше то же число стояло в обоих
    /// файлах по отдельности и могло разъехаться при правке одного из них.
    static let ttl: TimeInterval = 90 * 24 * 3600
}
