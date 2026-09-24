import Foundation

/// Одна дверь в мир (спека §3.2). Всё, что финиш делает с поездкой после
/// записи трека, — опыт и значки, одометр машины, коллекция дорог, очередь
/// синка, места и туман — живёт здесь. Зовут её финиш подтверждённой поездки
/// и «Моя» у черновика, и больше никто: «Моя», пришедшее через неделю, делает
/// ровно то же, что финиш неделю назад.
enum TripWorldEntry {
    enum Route: Equatable {
        /// < 500 м и < 2 мин — удалить молча (Review Focus 2).
        case discardJunk
        /// Черновик: итог без наград и вопрос «Твоя?».
        case awaitConfirmation
        /// Подтверждённая поездка входит в мир сразу.
        case enterWorld
    }

    /// Куда идёт только что законченная поездка. Мусор побеждает черновик:
    /// спрашивать про поездку по парковке нечего.
    static func route(for trip: Trip) -> Route {
        if trip.isJunk { return .discardJunk }
        return trip.isDraft ? .awaitConfirmation : .enterWorld
    }

    /// Награды, значки поездки, коллекция дорог и очередь синка.
    @MainActor
    static func rewards(for trip: Trip, tripManager: TripManager,
                        gamification: GamificationManager,
                        roads: RoadCollectionManager) -> TripCompletionData {
        // Use lightweight fetch (no track points for historical trips); the
        // finished trip itself carries its points.
        var allTrips = tripManager.fetchTrips()
        if let idx = allTrips.firstIndex(where: { $0.id == trip.id }) {
            allTrips[idx] = trip
        } else {
            allTrips.append(trip)
        }
        let data = gamification.processCompletedTrip(
            trip: trip,
            allTrips: allTrips,
            settingsEntity: gamification.fetchSettingsEntity(),
            vehicleEntity: gamification.fetchVehicleEntity(id: trip.vehicleId)
        )
        tripManager.saveBadgesJSON(tripId: trip.id, badgeIds: data.newBadges.map(\.id))
        var final = data
        final.roadCard = roads.processTrip(trip)
        // Очередь синка — здесь, а не в `stopTrip`: у черновика её нет до «Моя».
        SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: trip.id, action: .upload))
        return final
    }

    /// Места и туман — по окончательному треку. Отметки черновика ждали входа
    /// в мир без места (`PlaceManager.registerCheckpoint` их пропускал), и
    /// место у них заводится здесь; у подтверждённой поездки они уже с местом,
    /// и цикл ничего не делает.
    @MainActor
    @discardableResult
    static func placesAndReveal(trip: Trip) async -> RevealedLayerStore.IngestDelta {
        for checkpoint in trip.checkpoints where checkpoint.placeId == nil {
            PlaceManager.shared.registerCheckpoint(checkpoint, tripId: trip.id)
        }
        await PlaceManager.shared.process(tripId: trip.id)
        return await RevealedLayerStore.shared.ingest(tripId: trip.id)
    }
}
