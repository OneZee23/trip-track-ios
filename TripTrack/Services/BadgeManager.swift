import Foundation
import CoreData

enum BadgeManager {
    private static let unlockedKey = "unlockedBadgeIds"
    private static let earnCountsKey = "badgeEarnCounts"

    // MARK: - Earn Counts (for repeatable badges)

    static func earnCount(for badgeId: String) -> Int {
        allEarnCounts()[badgeId] ?? 0
    }

    static func allEarnCounts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: earnCountsKey) as? [String: Int] ?? [:]
    }

    static func incrementEarnCount(for badgeId: String) -> Int {
        var counts = allEarnCounts()
        let newCount = (counts[badgeId] ?? 0) + 1
        counts[badgeId] = newCount
        UserDefaults.standard.set(counts, forKey: earnCountsKey)
        return newCount
    }

    static func computeStats(from trips: [Trip]) -> BadgeStats {
        var totalDist: Double = 0
        var maxSpeed: Double = 0
        var totalDuration: Double = 0
        var longestTrip: Double = 0
        var regions = Set<String>()
        var hasNight = false
        var hasLateNight = false
        var hasEarlyMorning = false
        var maxAltitude: Double = 0
        var maxLatitude: Double = 0
        var maxElevationGain: Double = 0
        var hasSingleMarathon = false
        var hasSingleIronButt = false
        var longestTripDuration: TimeInterval = 0
        var hasSunday = false
        var hasSeaLevel = false
        var hasWinterMountain = false

        for trip in trips {
            totalDist += trip.distanceKm
            maxSpeed = max(maxSpeed, trip.maxSpeedKmh)
            totalDuration += trip.duration
            longestTrip = max(longestTrip, trip.distanceKm)
            longestTripDuration = max(longestTripDuration, trip.duration)

            if let r = trip.region { regions.insert(r) }

            if trip.distanceKm >= 42.195 { hasSingleMarathon = true }
            if trip.distanceKm >= 500 { hasSingleIronButt = true }

            let hour = Calendar.current.component(.hour, from: trip.startDate)
            if hour >= 22 || hour < 5 { hasNight = true }
            if hour >= 23 || hour < 4 { hasLateNight = true }
            if hour < 6 { hasEarlyMorning = true }

            let weekday = Calendar.current.component(.weekday, from: trip.startDate)
            if weekday == 1 { hasSunday = true } // Sunday = 1

            // Elevation gain from trip
            if trip.elevation >= 1000 {
                maxElevationGain = max(maxElevationGain, trip.elevation)
            }

            // Winter mountain check (Dec-Feb with elevation)
            let month = Calendar.current.component(.month, from: trip.startDate)
            if (month == 12 || month == 1 || month == 2) && trip.elevation >= 200 {
                hasWinterMountain = true
            }

            // Track points analysis
            for point in trip.trackPoints {
                maxAltitude = max(maxAltitude, point.altitude)
                maxLatitude = max(maxLatitude, abs(point.latitude))
            }

            // Sea level check: mostly at low altitude, decent distance
            if trip.distanceKm >= 20 && !trip.trackPoints.isEmpty {
                let lowPoints = trip.trackPoints.filter { $0.altitude < 10 && $0.altitude >= 0 }
                if Double(lowPoints.count) / Double(trip.trackPoints.count) > 0.8 {
                    hasSeaLevel = true
                }
            }
        }

        // Weekend warrior: 4 consecutive weekends with trips
        let hasWeekendWarrior = checkWeekendWarrior(trips: trips)

        // Streak info from UserDefaults (stored by GamificationManager)
        let currentStreak = Int(fetchStreakFromSettings()?.currentStreak ?? 0)
        let bestStreak = Int(fetchStreakFromSettings()?.bestStreak ?? 0)

        return BadgeStats(
            totalTrips: trips.count,
            totalDistanceKm: totalDist,
            maxSpeedKmh: maxSpeed,
            totalDurationHours: totalDuration / 3600,
            uniqueRegions: regions.count,
            longestTripKm: longestTrip,
            hasNightTrip: hasNight,
            hasEarlyMorningTrip: hasEarlyMorning,
            hasLateNightTrip: hasLateNight,
            maxAltitude: maxAltitude,
            maxLatitude: maxLatitude,
            maxElevationGainSingleTrip: maxElevationGain,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            hasSingleTripMarathon: hasSingleMarathon,
            hasSingleTripIronButt: hasSingleIronButt,
            longestSingleTripDuration: longestTripDuration,
            hasSundayTrip: hasSunday,
            hasWeekendWarrior: hasWeekendWarrior,
            hasWinterMountainTrip: hasWinterMountain,
            hasSeaLevelTrip: hasSeaLevel,
            countriesCount: 0 // TODO: populate when country data source is available
        )
    }

    static func unlockedBadges(for stats: BadgeStats) -> [Badge] {
        Badge.all.filter { $0.checkUnlocked(stats) }
    }

    static func checkNewBadges(stats: BadgeStats) -> [Badge] {
        let currentlyUnlocked = Set(unlockedBadges(for: stats).map(\.id))
        let previouslyUnlocked = Set(UserDefaults.standard.stringArray(forKey: unlockedKey) ?? [])
        let newIds = currentlyUnlocked.subtracting(previouslyUnlocked)

        UserDefaults.standard.set(Array(currentlyUnlocked), forKey: unlockedKey)

        return Badge.all.filter { newIds.contains($0.id) }
    }

    // MARK: - Per-Trip Badge Evaluation

    struct BadgeEvalResult {
        let allEarned: [Badge]                    // all badges earned on this trip
        let repeatedBadgeCounts: [String: Int]    // badge ID → global earn count (for repeatable)
    }

    static func evaluateBadgesForTrip(_ trip: Trip, allTrips: [Trip]) -> BadgeEvalResult {
        // 1. Milestone badges: compute stats from ALL trips, diff with stored unlocked set
        let globalStats = computeStats(from: allTrips)
        let currentlyUnlocked = Set(unlockedBadges(for: globalStats).map(\.id))
        let previouslyUnlocked = Set(UserDefaults.standard.stringArray(forKey: unlockedKey) ?? [])
        let newMilestoneIds = currentlyUnlocked.subtracting(previouslyUnlocked)

        // Update stored unlocked set
        UserDefaults.standard.set(Array(currentlyUnlocked), forKey: unlockedKey)

        let newMilestones = Badge.all.filter { !$0.isRepeatable && newMilestoneIds.contains($0.id) }

        // 2. Repeatable badges: compute stats from just this trip
        let singleTripStats = computeStats(from: [trip])
        let repeatableBadges = Badge.all.filter { $0.isRepeatable && $0.checkUnlocked(singleTripStats) }

        // Increment earn counts for each repeatable badge earned
        var counts: [String: Int] = [:]
        for badge in repeatableBadges {
            counts[badge.id] = incrementEarnCount(for: badge.id)
        }

        let allEarned = newMilestones + repeatableBadges
        return BadgeEvalResult(allEarned: allEarned, repeatedBadgeCounts: counts)
    }

    // MARK: - Weekend Warrior Check

    private static func checkWeekendWarrior(trips: [Trip]) -> Bool {
        let calendar = Calendar.current

        // Get unique weekend week-start dates (Monday of each week with a weekend trip)
        var weekStarts = Set<Date>()
        for trip in trips {
            let weekday = calendar.component(.weekday, from: trip.startDate)
            if weekday == 1 || weekday == 7 { // Sunday or Saturday
                // Get the Monday of this week
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: trip.startDate)
                if let monday = calendar.date(from: components) {
                    weekStarts.insert(monday)
                }
            }
        }

        guard weekStarts.count >= 4 else { return false }

        // Sort and check for 4 consecutive weeks (7 days apart)
        let sorted = weekStarts.sorted()
        var consecutive = 1
        for i in 1..<sorted.count {
            let daysBetween = calendar.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day ?? 0
            if daysBetween == 7 {
                consecutive += 1
                if consecutive >= 4 { return true }
            } else if daysBetween > 7 {
                consecutive = 1
            }
            // daysBetween == 0 means same week, skip
        }

        return false
    }

    // MARK: - Fetch Streak from Settings

    private static func fetchStreakFromSettings() -> UserSettingsEntity? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
