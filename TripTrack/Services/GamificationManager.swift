import Foundation
import CoreData

final class GamificationManager {
    private let persistenceController: PersistenceController
    /// Internal, not private: `BackfillLatchTests` asserts on it directly —
    /// the latch closing at the wrong moment is the whole failure mode.
    static let backfillKey = "gamification_backfill_done"

    private let defaults: UserDefaults

    init(persistenceController: PersistenceController = .shared,
         defaults: UserDefaults = .standard) {
        self.persistenceController = persistenceController
        self.defaults = defaults
    }

    // MARK: - XP Calculation

    func calculateXP(for trip: Trip, allTrips: [Trip]) -> XPBreakdown {
        var breakdown = XPBreakdown()

        // Base: 1 XP per km
        breakdown.base = max(1, Int(trip.distanceKm))

        // Long trip bonus: x2 for 200+ km (adds extra base amount)
        if trip.distanceKm >= 200 {
            breakdown.longTripBonus = breakdown.base
        }

        // First trip of day bonus
        let calendar = Calendar.current
        let tripDay = calendar.startOfDay(for: trip.startDate)
        let hasTripToday = allTrips.contains { t in
            t.id != trip.id &&
            calendar.startOfDay(for: t.startDate) == tripDay
        }
        if !hasTripToday {
            breakdown.firstTripOfDay = 20
        }

        // New region bonus
        if let region = trip.region {
            let existingRegions = Set(allTrips.filter { $0.id != trip.id }.compactMap(\.region))
            if !existingRegions.contains(region) {
                // +50 XP for discovering a new region
                breakdown.regionDiscovery = 50
                // x1.5 on base distance (add 0.5x extra)
                breakdown.newRegionBonus = breakdown.base / 2
            }
        }

        return breakdown
    }

    // MARK: - Process Completed Trip

    func processCompletedTrip(
        trip: Trip,
        allTrips: [Trip],
        settingsEntity: UserSettingsEntity?,
        vehicleEntity: VehicleEntity?
    ) -> TripCompletionData {
        let xpBreakdown = calculateXP(for: trip, allTrips: allTrips)

        // Previous state
        let previousXP = Int(settingsEntity?.profileXP ?? 0)
        let previousLevel = Int(settingsEntity?.profileLevel ?? 1)
        let previousRank = DriverRank.from(level: previousLevel)

        // Update XP and level
        let newXP = previousXP + xpBreakdown.total
        let newLevel = LevelSystem.level(for: newXP)
        let newRank = DriverRank.from(level: newLevel)

        settingsEntity?.profileXP = Int64(newXP)
        settingsEntity?.profileLevel = Int32(newLevel)

        // Update streak
        let currentStreak = updateStreak(
            settingsEntity: settingsEntity,
            tripDate: trip.startDate
        )

        // Vehicle progress
        let vehicleOdometerBefore = vehicleEntity?.odometerKm ?? 0
        let vehicleLevelBefore = Int(vehicleEntity?.vehicleLevel ?? 1)

        if let vehicle = vehicleEntity {
            let newOdometer = vehicleOdometerBefore + trip.distanceKm
            vehicle.odometerKm = newOdometer
            let newVehicleLevel = VehicleLevelSystem.level(for: newOdometer)
            vehicle.vehicleLevel = Int32(newVehicleLevel)

        }

        let vehicleOdometerAfter = vehicleEntity?.odometerKm ?? vehicleOdometerBefore
        let vehicleLevelAfter = Int(vehicleEntity?.vehicleLevel ?? Int32(vehicleLevelBefore))

        // Save XP on trip entity
        saveTripXP(tripId: trip.id, xp: xpBreakdown.total)

        persistenceController.save()

        // Enqueue sync for updated trip and settings
        let tripId = trip.id
        Task { @MainActor in
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .update))
        }
        SettingsManager.shared.scheduleSettingsSync()

        // Badge evaluation: milestones + repeatable badges
        let badgeResult = BadgeManager.evaluateBadgesForTrip(trip, allTrips: allTrips)

        return TripCompletionData(
            xpEarned: xpBreakdown.total,
            xpBreakdown: xpBreakdown,
            previousLevel: previousLevel,
            newLevel: newLevel,
            previousXP: previousXP,
            newXP: newXP,
            previousRank: previousRank,
            newRank: newRank,
            vehicleOdometerBefore: vehicleOdometerBefore,
            vehicleOdometerAfter: vehicleOdometerAfter,
            vehicleLevelBefore: vehicleLevelBefore,
            vehicleLevelAfter: vehicleLevelAfter,
            newBadges: badgeResult.allEarned,
            repeatedBadgeCounts: badgeResult.repeatedBadgeCounts,
            currentStreak: currentStreak,
            roadCard: nil // Set by RoadCollectionManager later
        )
    }

    // MARK: - Streak

    private func updateStreak(settingsEntity: UserSettingsEntity?, tripDate: Date) -> Int {
        guard let entity = settingsEntity else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: tripDate)

        if let lastDate = entity.lastTripDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysBetween = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0

            // Backdated / out-of-order trip (auto-trip recovery rewinds
            // startDate, manual edit, async sync replay, etc.) — leave
            // streak untouched and DON'T overwrite `lastTripDate` with an
            // older value. Without this, recording a real trip after a
            // backdated import would compute negative `daysBetween`,
            // hit the "broken" branch, and reset the streak to 1.
            if daysBetween < 0 {
                return Int(entity.currentStreak)
            }

            if daysBetween == 0 {
                // Same day, no change
                return Int(entity.currentStreak)
            } else if daysBetween == 1 {
                // Consecutive day
                entity.currentStreak += 1
            } else {
                // Streak broken, restart
                entity.currentStreak = 1
            }
        } else {
            entity.currentStreak = 1
        }

        entity.lastTripDate = tripDate
        if entity.currentStreak > entity.bestStreak {
            entity.bestStreak = entity.currentStreak
        }

        return Int(entity.currentStreak)
    }

    // Начисление стикеров выключено в 0.6.4.
    //
    // Показывать их было негде: раздел на экране машины убран, а больше их не
    // рисовал никто — начисление писало в базу состояние, которое не читала ни
    // одна строчка кода. Само поле `stickersJSON` и `VehicleSticker` оставлены:
    // они уходят в синк, и выкидывать их значило бы менять схему ради уборки.
    // Если стикеры когда-нибудь станут настоящей фичей, начисление вернётся
    // сюда же — вместе с местом, где их видно.

    private func decodeStickers(_ json: String?) -> [VehicleSticker] {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids.compactMap { VehicleSticker(rawValue: $0) }
    }

    private func encodeStickers(_ stickers: [VehicleSticker]) -> String {
        let ids = stickers.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(ids),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    // MARK: - Save XP on Trip

    private func saveTripXP(tripId: UUID, xp: Int) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)
        if let entity = try? context.fetch(request).first {
            entity.xpEarned = Int32(xp)
        }
    }

    // MARK: - Backfill

    func backfillIfNeeded(trips: [Trip], settingsEntity: UserSettingsEntity?) {
        guard !defaults.bool(forKey: Self.backfillKey),
              let entity = settingsEntity else { return }

        // Only back-fill a profile that has no XP yet — and DO NOT latch when
        // there is nothing to count.
        //
        // Latching on "I found nothing" records an accident as a decision. On
        // the launch that lost a real user's library all three back-fills ran
        // against zero rows, concluded there was nothing to do, and wrote their
        // flags. Even once his trips came home, level, badges and fog would
        // have stayed at zero permanently: the flags said the work was
        // finished and nothing ever reconsiders.
        guard entity.profileXP == 0, !trips.isEmpty else { return }

        var totalXP = 0
        let sortedTrips = trips.sorted { $0.startDate < $1.startDate }
        var seenRegions = Set<String>()

        for trip in sortedTrips {
            // Base XP
            var tripXP = max(1, Int(trip.distanceKm))

            // Long trip bonus
            if trip.distanceKm >= 200 {
                tripXP += max(1, Int(trip.distanceKm))
            }

            // Region discovery
            if let region = trip.region, !seenRegions.contains(region) {
                seenRegions.insert(region)
                tripXP += 50 + max(1, Int(trip.distanceKm)) / 2
            }

            totalXP += tripXP
        }

        entity.profileXP = Int64(totalXP)
        entity.profileLevel = Int32(LevelSystem.level(for: totalXP))

        // Backfill vehicle odometers
        backfillVehicleOdometers(trips: sortedTrips)

        persistenceController.save()
        // Latch only after real work — this is the line the guard above used
        // to reach without doing any.
        defaults.set(true, forKey: Self.backfillKey)
    }

    private func backfillVehicleOdometers(trips: [Trip]) {
        let context = persistenceController.container.viewContext
        // Правило «что считать» живёт в `VehicleOdometer` и покрыто тестами:
        // трансферы сюда не попадают.
        let odometerMap = VehicleOdometer.trackedByVehicle(from: trips)

        for (vehicleId, km) in odometerMap {
            let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", vehicleId as CVarArg)
            if let entity = try? context.fetch(request).first {
                entity.odometerKm = km
                entity.vehicleLevel = Int32(VehicleLevelSystem.level(for: km))
            }
        }
    }

    // MARK: - Backfill Per-Trip Badges

    func backfillBadgesIfNeeded(trips: [Trip]) {
        let key = "badges_backfill_done"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let context = persistenceController.container.viewContext
        let sortedTrips = trips.sorted { $0.startDate < $1.startDate }
        guard !sortedTrips.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        // Pre-fetch all entities into a lookup dictionary (avoids N individual fetches)
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        guard let allEntities = try? context.fetch(request) else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        let entityMap = Dictionary(uniqueKeysWithValues: allEntities.compactMap { e in
            e.id.map { ($0, e) }
        })

        // Reset earn counts to avoid double-counting on partial backfill crash
        UserDefaults.standard.removeObject(forKey: "badgeEarnCounts")

        let repeatableBadges = Badge.all.filter(\.isRepeatable)
        let milestoneBadges = Badge.all.filter { !$0.isRepeatable }

        // Track milestone unlocks incrementally (O(N) instead of O(N²))
        var previousMilestoneIds = Set<String>()

        for trip in sortedTrips {
            var earnedIds: [String] = []

            // Repeatable badges: evaluate from single trip
            let singleStats = BadgeManager.computeStats(from: [trip])
            for badge in repeatableBadges where badge.checkUnlocked(singleStats) {
                _ = BadgeManager.incrementEarnCount(for: badge.id)
                earnedIds.append(badge.id)
            }

            // Milestone badges: compute cumulative stats up to this trip
            // Use the full stats computed by the caller (allTrips up to this point)
            let cumulativeIndex = sortedTrips.firstIndex(where: { $0.id == trip.id })
            if let idx = cumulativeIndex {
                let cumulativeTrips = Array(sortedTrips[...idx])
                let stats = BadgeManager.computeStats(from: cumulativeTrips)
                let currentMilestoneIds = Set(milestoneBadges.filter { $0.checkUnlocked(stats) }.map(\.id))
                let newMilestoneIds = currentMilestoneIds.subtracting(previousMilestoneIds)
                earnedIds.append(contentsOf: newMilestoneIds)
                previousMilestoneIds = currentMilestoneIds
            }

            // Save to entity
            guard !earnedIds.isEmpty, let entity = entityMap[trip.id] else { continue }
            if let data = try? JSONEncoder().encode(earnedIds),
               let json = String(data: data, encoding: .utf8) {
                entity.badgesJSON = json
            }
        }

        persistenceController.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Helpers

    func fetchSettingsEntity() -> UserSettingsEntity? {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func fetchVehicleEntity(id: UUID?) -> VehicleEntity? {
        guard let id else { return nil }
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }
}
