import Foundation
import Combine

struct TripSection: Identifiable, Equatable {
    let id: String // "2026-03" format
    let title: String
    let trips: [Trip]
}

final class FeedViewModel: ObservableObject {
    @Published var trips: [Trip] = []
    @Published var sections: [TripSection] = []
    @Published var filters = TripFilters.empty
    @Published var showFilters = false
    @Published var toastItem: ToastItem?

    let tripManager: TripManager
    var language: LanguageManager.Language = .ru
    private(set) var allTrips: [Trip] = []
    private var filteredTrips: [Trip] = []
    private let pageSize = 20
    private var currentPage = 0
    private var hasMorePages = true
    private var pendingDeleteTrip: Trip?
    private var deleteTimer: Timer?

    // Cached calendar data — invalidated on loadTrips()
    private(set) var cachedMaxKmDay: Double = 1
    private var kmByDayCache: [Date: [Date: Double]] = [:]
    private(set) var cachedUniqueRegions: [String] = []

    // Cached DateFormatters for section titles (separate per locale+format for thread safety)
    private static let sectionMonthRu: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "LLLL"; return f
    }()
    private static let sectionMonthEn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "LLLL"; return f
    }()
    private static let sectionMonthYearRu: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "LLLL yyyy"; return f
    }()
    private static let sectionMonthYearEn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "LLLL yyyy"; return f
    }()

    init(tripManager: TripManager) {
        self.tripManager = tripManager
    }

    deinit {
        deleteTimer?.invalidate()
    }

    // MARK: - Computed stats (from all filtered trips, not just loaded page)

    var totalTripCount: Int { filteredTrips.count }

    var totalKm: Double {
        filteredTrips.reduce(0) { $0 + $1.distanceKm }
    }

    var totalDuration: TimeInterval {
        filteredTrips.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalTime: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var uniqueRegions: [String] { cachedUniqueRegions }

    // MARK: - Actions

    func loadTrips() {
        allTrips = tripManager.fetchTrips()
        // Retry geocoding deferred to avoid blocking current runloop cycle
        DispatchQueue.main.async { [weak self] in
            self?.tripManager.retryGeocodingForUntitledTrips()
        }
        rebuildCalendarCaches()
        applyFilters()
    }

    /// Soft-delete: hides from UI, shows undo toast, commits after delay
    func softDeleteTrip(_ trip: Trip) {
        // Cancel any pending delete
        cancelPendingDelete()

        pendingDeleteTrip = trip
        // Remove from both lists to prevent reappearing on pull-to-refresh
        allTrips.removeAll { $0.id == trip.id }
        trips.removeAll { $0.id == trip.id }
        rebuildSections()

        toastItem = ToastItem(
            type: .undo,
            message: AppStrings.tripDeleted(language),
            undoLabel: AppStrings.undo(language),
            undoAction: { [weak self] in
                self?.undoDelete()
            }
        )

        deleteTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.commitPendingDelete()
        }
    }

    private func undoDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        guard pendingDeleteTrip != nil else { return }
        pendingDeleteTrip = nil
        // Reload from CoreData to restore the trip (it was only removed from local arrays)
        loadTrips()
    }

    private func commitPendingDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        guard let trip = pendingDeleteTrip else { return }
        pendingDeleteTrip = nil
        tripManager.deleteTrip(id: trip.id)
        allTrips.removeAll { $0.id == trip.id }
        rebuildCalendarCaches()
    }

    func cancelPendingDelete() {
        if pendingDeleteTrip != nil {
            commitPendingDelete()
        }
    }

    func tripDetail(id: UUID) -> Trip? {
        tripManager.tripDetail(id: id)
    }

    func applyFilters() {
        let cal = Calendar.current
        var result = allTrips

        if let region = filters.region {
            result = result.filter { trip in
                guard let tripRegion = trip.region else { return false }
                return tripRegion.localizedCaseInsensitiveContains(region)
                    || region.localizedCaseInsensitiveContains(tripRegion)
            }
        }
        if let from = filters.dateFrom {
            let start = cal.startOfDay(for: from)
            if let to = filters.dateTo {
                let end = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: to) ?? to)
                result = result.filter { $0.startDate >= start && $0.startDate < end }
            } else {
                // Single day
                let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
                result = result.filter { $0.startDate >= start && $0.startDate < end }
            }
        }

        filteredTrips = result
        currentPage = 0
        hasMorePages = true
        loadPage()
    }

    func resetFilters() {
        filters = .empty
        applyFilters()
    }

    /// Resets only region filter; keeps date range (set from calendar).
    func resetSecondaryFilters() {
        filters.region = nil
        applyFilters()
    }

    func setRegionFilter(_ region: String?) {
        filters.region = region
        applyFilters()
    }

    func setDateRange(from: Date?, to: Date?) {
        filters.dateFrom = from
        filters.dateTo = to
        applyFilters()
    }

    // MARK: - Calendar Data (cached)

    private func rebuildCalendarCaches() {
        let cal = Calendar.current

        // maxKmDay
        var dayTotals: [Date: Double] = [:]
        for trip in allTrips {
            let day = cal.startOfDay(for: trip.startDate)
            dayTotals[day, default: 0] += trip.distanceKm
        }
        cachedMaxKmDay = dayTotals.values.max() ?? 1

        // uniqueRegions
        cachedUniqueRegions = Array(Set(allTrips.compactMap { $0.region })).sorted()

        // clear kmByDay cache
        kmByDayCache.removeAll()
    }

    /// Returns total km driven per day for a given month (cached)
    func kmByDay(for month: Date) -> [Date: Double] {
        let cal = Calendar.current
        let monthKey = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month

        if let cached = kmByDayCache[monthKey] {
            return cached
        }

        guard let _ = cal.range(of: .day, in: .month, for: month),
              let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: month)) else {
            return [:]
        }
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart

        var result: [Date: Double] = [:]
        for trip in allTrips {
            guard trip.startDate >= monthStart && trip.startDate < monthEnd else { continue }
            let day = cal.startOfDay(for: trip.startDate)
            result[day, default: 0] += trip.distanceKm
        }

        kmByDayCache[monthKey] = result
        return result
    }

    /// Max km in any single day across all trips (for relative intensity)
    var maxKmDay: Double { cachedMaxKmDay }

    // MARK: - Pagination

    func loadMoreIfNeeded(currentTrip: Trip) {
        guard hasMorePages else { return }
        // Load next page when reaching the last 5 items — only search tail
        let threshold = max(0, trips.count - 5)
        guard trips[threshold...].contains(where: { $0.id == currentTrip.id }) else { return }
        loadNextPage()
    }

    private func loadPage() {
        let end = min(pageSize, filteredTrips.count)
        trips = Array(filteredTrips.prefix(end))
        currentPage = 1
        hasMorePages = end < filteredTrips.count
        rebuildSections()
    }

    private func loadNextPage() {
        let start = currentPage * pageSize
        guard start < filteredTrips.count else {
            hasMorePages = false
            return
        }
        let end = min(start + pageSize, filteredTrips.count)
        trips.append(contentsOf: filteredTrips[start..<end])
        currentPage += 1
        hasMorePages = end < filteredTrips.count
        rebuildSections()
    }

    // MARK: - Grouping

    private func rebuildSections() {
        let calendar = Calendar.current
        let now = Date()
        let grouped = Dictionary(grouping: trips) { trip in
            calendar.dateComponents([.year, .month], from: trip.startDate)
        }

        sections = grouped
            .sorted { lhs, rhs in
                let lDate = calendar.date(from: lhs.key) ?? .distantPast
                let rDate = calendar.date(from: rhs.key) ?? .distantPast
                return lDate > rDate
            }
            .map { components, trips in
                let date = calendar.date(from: components) ?? Date()
                let title = sectionTitle(for: date, now: now, calendar: calendar)
                let id = "\(components.year ?? 0)-\(components.month ?? 0)"
                return TripSection(id: id, title: title, trips: trips)
            }
    }

    private func sectionTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        let isRu = language == .ru

        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return isRu ? "Этот месяц" : "This month"
        }

        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        if calendar.isDate(date, equalTo: lastMonth, toGranularity: .month) {
            return isRu ? "Прошлый месяц" : "Last month"
        }

        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter: DateFormatter
        switch (isRu, sameYear) {
        case (true, true):   formatter = Self.sectionMonthRu
        case (true, false):  formatter = Self.sectionMonthYearRu
        case (false, true):  formatter = Self.sectionMonthEn
        case (false, false): formatter = Self.sectionMonthYearEn
        }
        return formatter.string(from: date).capitalized
    }
}
