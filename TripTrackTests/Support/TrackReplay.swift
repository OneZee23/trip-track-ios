import Foundation
import CoreData
import CoreLocation
@testable import TripTrack

/// Стенд (спека §2.7): сырые фиксы → шлюз → запись → пост-обработка →
/// (если дали маршрутизатор) дорога. `recordingLimit` = 65 воспроизводит
/// старый конвейер.
@MainActor
enum TrackReplay {
    struct Result {
        /// Дыры в ЗАПИСАННОМ (до достройки).
        let recordedGaps: Int
        /// Дыры, которые остались незакрытыми после финиша.
        let openGaps: Int
        let coarsePoints: Int
        let filledPoints: Int
        /// Сколько кусков достройки легло — подряд идущие достроенные точки.
        let fillRuns: Int
        let distance: Double
    }

    static func run(_ fixes: [CLLocation], recordingLimit: Double = FixGate.recordingAccuracyLimit,
                    router: RoadRouter? = nil) async -> Result {
        let pc = PersistenceController(inMemory: true)
        let manager = TripManager(locationManager: LocationManager(), persistenceController: pc)
        manager.startTrip(vehicleId: nil)
        for fix in fixes where FixGate.decide(horizontalAccuracy: fix.horizontalAccuracy, ageSeconds: 0,
                                              speedMS: fix.speed, isRecording: true,
                                              recordingLimit: recordingLimit) == .accept {
            manager.handleNewLocation(fix)
        }
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        guard let entity = try? pc.container.viewContext.fetch(request).first, let id = entity.id else {
            return Result(recordedGaps: 0, openGaps: 0, coarsePoints: 0, filledPoints: 0, fillRuns: 0, distance: 0)
        }
        let recorded = PostTripTrackProcessor.liveTrackPoints(of: entity).compactMap(PostTripTrackProcessor.gapPoint)

        // Финиш без `stopTrip`: тот зовёт геокодер и очередь синка, а стенду
        // нужен только трек. Конец поездки — последний фикс.
        entity.endDate = fixes.last?.timestamp
        pc.save()
        await PostTripTrackProcessor(persistenceController: pc).processTrip(id)
        if let router {
            _ = await RoadGapFiller(router: router, persistence: pc, isAllowedToRun: { true },
                                    pause: { _ in }, reveal: { _ in }).fill(tripId: id)
            // `fill` с раунда 1 задачи 5 пишет на СВОИХ фоновых контекстах, а
            // не на `viewContext`; автослияние в `viewContext` асинхронное, и
            // стенд не вправе зависеть от того, когда именно оно случится —
            // обновляем объект явно вместо ожидания гонки с слиянием.
            pc.container.viewContext.refreshAllObjects()
        }

        let points = PostTripTrackProcessor.liveTrackPoints(of: entity)
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        var fillRuns = 0
        var inRun = false
        for p in points {
            if p.isInterpolated, !inRun { fillRuns += 1 }
            inRun = p.isInterpolated
        }
        return Result(
            recordedGaps: TrackGapFinder.openGaps(in: recorded).count,
            openGaps: TrackGapFinder.openGaps(in: points.compactMap(PostTripTrackProcessor.gapPoint)).count,
            coarsePoints: points.filter {
                !$0.isInterpolated && $0.horizontalAccuracy > TripDistanceGate.odometerAccuracyLimit
            }.count,
            filledPoints: points.filter(\.isInterpolated).count,
            fillRuns: fillRuns,
            distance: entity.distance
        )
    }
}
