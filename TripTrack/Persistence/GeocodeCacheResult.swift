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
}
