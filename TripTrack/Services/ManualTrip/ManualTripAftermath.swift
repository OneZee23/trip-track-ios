import Foundation

/// Что происходит с вписанной поездкой СРАЗУ после того, как она легла в базу.
///
/// Ровно две вещи из цепочки финиша — места и слой открытого, — и живут они
/// здесь, а не в листе, потому что вызывающих у них двое: настоящий экран
/// (`ManualTripModel.create`) и отладочный сид (`DebugMapSeed`). Пока сид звал
/// только `createManualTrip`, его поездка отличалась от настоящей молча: карта
/// её не открывала, места её не видели, а по снимку с симулятора этого не
/// отличить. Одна дверь — и разойтись им больше нечем.
///
/// Чего здесь НЕТ и не будет: `PostTripTrackProcessor` (чинить у линии
/// `MKDirections` нечего, а его пересчёт переписал бы километры),
/// `GamificationManager`, `BadgeManager`, `DiscoveryProcessor` — награды
/// вписанная поездка не даёт. Одометр машины при этом взводит сам
/// `TripManager.createManualTrip`: он — часть записи в базу, а не то, что
/// досчитывается после.
@MainActor
enum ManualTripAftermath {
    static func settle(tripId: UUID) async {
        await PlaceManager.shared.process(tripId: tripId)
        await RevealedLayerStore.shared.ingest(tripId: tripId)
    }
}
