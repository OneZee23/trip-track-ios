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

    /// True if the trip's wall-clock span touches the hour-of-day window
    /// [startHour, endHour). The window may wrap midnight (e.g. 22→5). Sampled
    /// every 5 minutes so a multi-hour window can't be missed; a span ≥24h always
    /// matches. Uses the trip's full [startDate, endDate] so an overnight drive
    /// that starts in the evening still counts toward night / early-morning badges.
    /// Hours-of-day [0,23] the trip's wall-clock span touches. A single 5-min walk
    /// (a span ≥24h returns all hours). Computed once per trip so the night/morning
    /// window checks share one pass instead of re-walking the span per window.
    private static func hoursTouched(by trip: Trip) -> Set<Int> {
        let cal = Calendar.current
        let start = trip.startDate
        let end = trip.endDate ?? start
        guard end > start else { return [cal.component(.hour, from: start)] }
        if end.timeIntervalSince(start) >= 24 * 3600 { return Set(0...23) }
        var hours: Set<Int> = []
        var t = start
        let step: TimeInterval = 300
        while t < end {
            hours.insert(cal.component(.hour, from: t))
            t = t.addingTimeInterval(step)
        }
        hours.insert(cal.component(.hour, from: end))
        return hours
    }

    /// True if any touched hour falls in the [startHour, endHour) window (wraps midnight).
    private static func windowOverlaps(_ hours: Set<Int>, _ startHour: Int, _ endHour: Int) -> Bool {
        hours.contains { h in startHour <= endHour ? (h >= startHour && h < endHour) : (h >= startHour || h < endHour) }
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
        // 0.5.5 secret-badges aggregates. `distinctMonthsThisYear` uses
        // calendar-year scoping — "Wrapped" rewards a full year of
        // driving, so a trip in Dec 2025 + Jan 2026 shouldn't count
        // toward the 2026 set.
        var hasAfterMidnight = false
        var monthsThisYear = Set<Int>()
        var vehicleCounts: [UUID: Int] = [:]
        var privateCount = 0
        let currentYear = Calendar.current.component(.year, from: Date())

        for trip in trips {
            totalDist += trip.distanceKm
            maxSpeed = max(maxSpeed, trip.maxSpeedKmh)
            totalDuration += trip.duration
            longestTrip = max(longestTrip, trip.distanceKm)
            longestTripDuration = max(longestTripDuration, trip.duration)

            if let r = trip.region { regions.insert(r) }

            if trip.distanceKm >= 42.195 { hasSingleMarathon = true }
            if trip.distanceKm >= 500 { hasSingleIronButt = true }

            // Overlap-based: award if ANY part of the trip falls in the window, so
            // an overnight drive that STARTS in the evening (e.g. 20:00→07:00) still
            // earns night badges — the previous start-hour-only check missed these.
            // One span walk per trip; flags short-circuit so later trips skip even that.
            let needsHourWindows = !hasNight || !hasLateNight || !hasEarlyMorning || !hasAfterMidnight
            let tripHours = needsHourWindows ? Self.hoursTouched(by: trip) : []
            if !hasNight, Self.windowOverlaps(tripHours, 22, 5) { hasNight = true }
            if !hasLateNight, Self.windowOverlaps(tripHours, 23, 4) { hasLateNight = true }
            if !hasEarlyMorning, Self.windowOverlaps(tripHours, 0, 6) { hasEarlyMorning = true }

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

            // Secret-badge aggregates
            if !hasAfterMidnight, Self.windowOverlaps(tripHours, 0, 4) { hasAfterMidnight = true }
            let year = Calendar.current.component(.year, from: trip.startDate)
            if year == currentYear { monthsThisYear.insert(month) }
            if let vid = trip.vehicleId { vehicleCounts[vid, default: 0] += 1 }
            if trip.isPrivate { privateCount += 1 }

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
            countriesCount: 0, // TODO: populate when country data source is available
            hasAfterMidnightTrip: hasAfterMidnight,
            distinctMonthsWithTrips: monthsThisYear.count,
            maxTripsOnSingleVehicle: vehicleCounts.values.max() ?? 0,
            privateTripCount: privateCount,
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

    // MARK: - Last Earned Dates

    static func lastEarnedDates(for badgeIds: [String], using tripManager: TripManager) -> [String: Date] {
        guard !badgeIds.isEmpty else { return [:] }
        let badgeSet = Set(badgeIds)
        var result: [String: Date] = [:]

        let trips = tripManager.fetchTrips()
        for trip in trips {
            for id in trip.earnedBadgeIds where badgeSet.contains(id) {
                if result[id] == nil || trip.startDate > result[id]! {
                    result[id] = trip.startDate
                }
            }
        }
        return result
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
