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

    let tripManager: TripManager
    var language: LanguageManager.Language = .ru
    private(set) var allTrips: [Trip] = []
    private var filteredTrips: [Trip] = []
    private let pageSize = 20
    private var currentPage = 0
    private var hasMorePages = true

    // Cached calendar data — invalidated on loadTrips()
    private(set) var cachedMaxKmDay: Double = 1
    private var kmByDayCache: [Date: [Date: Double]] = [:]
    private(set) var cachedUniqueRegions: [String] = []
    /// tripId → vehicleId lookup rebuilt on every load. FeedView's own-trip
    /// social cards need the vehicle for a trip id DURING body evaluation —
    /// hitting `tripManager.tripDetail(id:)` there materialized the FULL
    /// track-point set synchronously on the main thread per visible row
    /// (thousands of objects for long trips → scroll hitches). This map is
    /// built from the already-fetched light `allTrips` (no track points) and
    /// makes the body read a plain dictionary lookup.
    private(set) var vehicleIdByTripId: [UUID: UUID] = [:]

    private var cancellables = Set<AnyCancellable>()

    // Cached DateFormatters for section titles — one per language and format,
    // built once (a DateFormatter is expensive and these run per section).
    private static let sectionMonth = monthFormatters(pattern: "LLLL")
    private static let sectionMonthYear = monthFormatters(pattern: "LLLL yyyy")

    private static func monthFormatters(pattern: String) -> [LanguageManager.Language: DateFormatter] {
        var map: [LanguageManager.Language: DateFormatter] = [:]
        for lang in LanguageManager.Language.allCases {
            let f = DateFormatter()
            f.locale = lang.locale
            f.dateFormat = pattern
            map[lang] = f
        }
        return map
    }

    /// App-scoped instance. The 5-tab skeleton destroys FeedView on every
    /// tab switch — a view-owned @StateObject would rebuild from scratch
    /// and silently drop the user's filters/calendar range each hop (the
    /// same remount hazard MyMapViewModel.shared solves for the Maps tab).
    private static var sharedInstance: FeedViewModel?

    static func shared(tripManager: TripManager) -> FeedViewModel {
        if let s = sharedInstance { return s }
        let vm = FeedViewModel(tripManager: tripManager)
        sharedInstance = vm
        return vm
    }

    init(tripManager: TripManager) {
        self.tripManager = tripManager

        // Reload on any event that can change Mine-tab content:
        //  • .tripRecordingEnded — a trip recorded/auto-stopped in the background
        //  • .syncPullCompleted  — a server pull delivered updated data
        //  • .tripPhotosChanged  — a photo added/removed (card indicator/thumb)
        //  • .tripPrivacyChanged — privacy flip (the "Только Вы" pill)
        //  • .tripDeleted        — delete from the trip-detail «…» menu. The
        //    detail screen dismisses back onto the Mine list, and without a
        //    reload the deleted trip's card stayed put (tapping it landed on
        //    the no-back-button skeleton). FeedView's .onAppear does NOT
        //    re-fire on pop-back (it's attached to the NavigationStack), so
        //    the reload must come from here.
        //
        // These can arrive in BURSTS: when Cloud Sync drains, every uploaded
        // photo posts .tripPhotosChanged and every pull posts .syncPullCompleted.
        // The old code ran the SYNCHRONOUS loadTrips() once per event, faulting
        // the whole library on the main thread each time — the dominant cause of
        // the sync-time jank. Merge + THROTTLE caps reloads to ≤1 per window
        // (throttle, not debounce, so a long continuous drain still refreshes
        // periodically instead of starving until it quiesces), and
        // loadTripsAsync() runs the fetch on a background context (hopping back
        // to the main actor for the @Published mutations).
        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: .tripRecordingEnded),
            NotificationCenter.default.publisher(for: .syncPullCompleted),
            NotificationCenter.default.publisher(for: .tripPhotosChanged),
            NotificationCenter.default.publisher(for: .tripPrivacyChanged),
            NotificationCenter.default.publisher(for: .tripDeleted)
        )
        .throttle(for: .milliseconds(800), scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] _ in
            Task { [weak self] in await self?.loadTripsAsync() }
        }
        .store(in: &cancellables)
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
        rebuildCalendarCaches()
        applyFilters()
    }

    /// Async pull-to-refresh entry point. Runs the CoreData fetch on a
    /// background context (see `CoreDataTripRepository.fetchAllTripsAsync`)
    /// so the main thread stays free for the SwiftUI `.refreshable` spinner
    /// animation. Without this, the synchronous viewContext fetch caused a
    /// visible ~200ms freeze on iPhone 12 / 70+ trip libraries.
    func loadTripsAsync() async {
        let fetched = await tripManager.fetchTripsAsync()
        // Hop back to the main actor for EVERY @Published / cache mutation.
        // FeedViewModel is not @MainActor and fetchTripsAsync() is a nonisolated
        // async method, so this continuation resumes on the cooperative pool
        // (SE-0338). Writing allTrips / @Published trips+sections, and mutating
        // kmByDayCache off-main would trip "Publishing changes from background
        // threads" and race the main-thread calendar reads (kmByDay) — a crash
        // risk that the debounced sync-burst reloads would hit far more often
        // than the rare pull-to-refresh that shared this method before.
        await MainActor.run {
            allTrips = fetched
            rebuildCalendarCaches()
            applyFilters()
        }
    }

    func retryGeocodingIfNeeded() {
        tripManager.retryGeocodingForUntitledTrips()
    }

    // NOTE: the soft-delete/undo subsystem (softDeleteTrip / undoDelete /
    // commitPendingDelete / deleteTimer / pendingDeleteTrip filtering) was
    // removed as dead code — its only entry point was FeedView's swipe-to-
    // delete, retired in v0.6. The sole remaining delete flow is the trip
    // detail «…» menu (immediate, confirm-gated), which posts `.tripDeleted`;
    // this VM reloads on that notification (see init).

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

        // tripId → vehicleId (own-trip social cards, see property doc)
        vehicleIdByTripId = allTrips.reduce(into: [:]) { map, trip in
            if let vid = trip.vehicleId { map[trip.id] = vid }
        }

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
        let lng = language

        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return AppStrings.feedViewModelThisMonth(lng)
        }

        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        if calendar.isDate(date, equalTo: lastMonth, toGranularity: .month) {
            return AppStrings.feedViewModelLastMonth(lng)
        }

        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let table = sameYear ? Self.sectionMonth : Self.sectionMonthYear
        return (table[lng]?.string(from: date) ?? "").capitalized
    }
}
