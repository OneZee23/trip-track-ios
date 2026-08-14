import SwiftUI

// MARK: - Статистика (Figma 122:799 / empty 123:834)

/// Pushed from the Я stats strip (fork FK-3). Client-side aggregates only —
/// every number is computed from real CoreData trips or the surface hides.
/// The old `StatsView` sheet (Feed) is untouched (fork FK-12).
struct StatsScreenView: View {
    let tripManager: TripManager

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @State private var agg: MeAggregates?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ScrollView {
            VStack(spacing: 10) {
                if let agg {
                    if agg.tripCount == 0 {
                        emptyState(c, l)
                    } else {
                        summaryCard(agg, c, l)
                        chartCard(agg, c, l)
                        recordsSection(agg, c, l)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hideAppTabBar()
        .safeAreaInset(edge: .top, spacing: 0) {
            navRow(l)
        }
        .task {
            await load()
        }
        .accessibilityIdentifier("stats_screen")
    }

    // MARK: - Nav row

    /// The app's own nav bar, not a local copy of one.
    ///
    /// This row was hand-built: a 34pt `GarageCircleNavButton` (15pt glyph,
    /// fainter shadow, no 44pt hit area) inset 16pt from the edge, opposite a
    /// `Color.clear` spacer that existed only to keep the title centred. On a
    /// 393–440pt phone that control reads as a small circle floating in a thin
    /// bar. `CustomNavBar` carries `NavCircleIcon` at 40pt with the canon
    /// insets and centres the title in a ZStack over the full width, so the
    /// balancing spacer goes with it.
    ///
    /// No `navBarInSheet`: Статистика is pushed onto the Я tab's
    /// NavigationStack (`MeDest.stats`), so there is no grabber above it — and
    /// sheet clearance on a pushed screen sinks the row 10pt too low.
    private func navRow(_ l: LanguageManager.Language) -> some View {
        CustomNavBar(title: AppStrings.stats(l))
            // The screenshot tour walks back out of Статистика by this id. The
            // back button is shared code now, so the id rides on the bar — it
            // is the only button in there.
            .accessibilityIdentifier("stats_back")
    }

    // MARK: - Summary card

    private func summaryCard(_ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack(spacing: 0) {
            summaryColumn(
                value: GarageFormat.odometer(agg.totalKm),
                label: AppStrings.statsKmTotal(l),
                valueColor: AppTheme.accent, c: c
            )
            summaryColumn(
                value: "\(agg.tripCount)",
                label: AppStrings.trips(l),
                valueColor: c.text, c: c, leadingBorder: true
            )
            summaryColumn(
                value: "\(Int(agg.totalHours.rounded()))",
                label: AppStrings.statsHours(l),
                valueColor: c.text, c: c, leadingBorder: true
            )
        }
        .padding(.vertical, 16)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("stats_summary")
    }

    private func summaryColumn(
        value: String, label: String, valueColor: Color,
        c: AppTheme.Colors, leadingBorder: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            if leadingBorder {
                Rectangle().fill(c.border).frame(width: 1)
            }
        }
    }

    // MARK: - Monthly chart

    private func chartCard(_ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let maxKm = agg.monthlyKm.max() ?? 0
        let maxIdx = maxKm > 0 ? (agg.monthlyKm.firstIndex(of: maxKm) ?? -1) : -1
        let labels = Self.monthLabels(l)
        // Dim bars need more alpha in dark or they vanish against the card.
        let dimFill = AppTheme.accent.opacity(scheme == .dark ? 0.22 : 0.12)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppStrings.statsKmByMonth(l))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(c.text)
                Spacer()
                Text(String(agg.year))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(c.cardAlt, in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<12, id: \.self) { i in
                    let km = agg.monthlyKm[i]
                    let h: CGFloat = maxKm > 0 && km > 0
                        ? max(4, CGFloat(km / maxKm) * 130)
                        : 4
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == maxIdx ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(dimFill))
                            .opacity(km > 0 ? 1 : 0.35)
                            .frame(height: h)
                        Text(labels[i])
                            .font(.system(size: 10, weight: i == maxIdx ? .heavy : .semibold))
                            .foregroundStyle(i == maxIdx ? AppTheme.accent : c.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 130 + 22)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("stats_chart")
    }

    private static func monthLabels(_ l: LanguageManager.Language) -> [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: l == .ru ? "ru_RU" : "en_US")
        let symbols = f.shortMonthSymbols ?? []
        guard symbols.count == 12 else {
            return ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        }
        return symbols.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).capitalized }
    }

    // MARK: - Records

    private func recordsSection(_ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.statsRecords(l))
                .font(.system(size: 13, weight: .bold))
                .tracking(0.26)
                .foregroundStyle(c.textSecondary)
                .padding(.leading, 2)
                .padding(.top, 6)

            recordRow(
                icon: "arrow.up.right",
                iconColor: AppTheme.green,
                iconBg: AppTheme.green.opacity(0.14),
                title: AppStrings.recordLongest(l),
                subtitle: longestTripName(agg, l),
                value: "\(GarageFormat.odometer(agg.longestTripKm)) \(AppStrings.km(l))",
                valueColor: AppTheme.green, c: c
            )
            .accessibilityIdentifier("stats_record_row_0")

            recordRow(
                icon: "clock.fill",
                iconColor: AppTheme.accent,
                iconBg: AppTheme.accent.opacity(0.14),
                title: AppStrings.recordLongestDay(l),
                subtitle: AppStrings.recordPerDay(l),
                value: Self.hoursMinutes(agg.maxDayDuration),
                valueColor: AppTheme.accent, c: c
            )
            .accessibilityIdentifier("stats_record_row_1")

            recordRow(
                icon: "flame.fill",
                iconColor: AppTheme.red,
                iconBg: AppTheme.red.opacity(0.14),
                title: AppStrings.recordStreak(l),
                subtitle: AppStrings.recordStreakSub(l),
                value: AppStrings.daysCount(l, n: settings.bestStreak),
                valueColor: AppTheme.accent, c: c
            )
            .accessibilityIdentifier("stats_record_row_2")
        }
    }

    private func longestTripName(_ agg: MeAggregates, _ l: LanguageManager.Language) -> String {
        if let t = agg.longestTripTitle, !t.isEmpty { return t }
        if let r = agg.longestTripRegion, !r.isEmpty { return r }
        if let d = agg.longestTripDate { return ProfileDateFormat.dayMonth(d, lang: l) }
        return "—"
    }

    private static func hoursMinutes(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        return "\(h):" + String(format: "%02d", m)
    }

    private func recordRow(
        icon: String, iconColor: Color, iconBg: Color,
        title: String, subtitle: String,
        value: String, valueColor: Color, c: AppTheme.Colors
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(iconBg)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.system(size: 15, weight: .heavy).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .padding(13)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Empty state (Figma 123:834)

    private func emptyState(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            IdleRing()
            Spacer().frame(height: 22)
            Text(AppStrings.statsEmptyTitle(l))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
            Spacer().frame(height: 8)
            Text(AppStrings.statsEmptyBody(l))
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 18)
            Button {
                Haptics.action()
                dismiss()
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 17, weight: .semibold))
                    Text(AppStrings.recordTripCta(l))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(AppTheme.accent)
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 3, y: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stats_empty_cta")
        }
        .padding(.horizontal, 40)
        .padding(.top, 120)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func load() async {
        // Fetch (cache-aware) on main, crunch off-main, publish on main.
        let count = tripManager.fetchTripCount()
        let lastDate = tripManager.fetchLastTripDate()
        let trips: [Trip]
        if let cached = StatsCache.tripsIfValid(currentCount: count, currentLastDate: lastDate) {
            trips = cached
        } else {
            trips = tripManager.fetchTrips()
            StatsCache.update(trips: trips, count: count, lastDate: lastDate)
        }
        let computed = await Task.detached(priority: .userInitiated) {
            MeAggregates.compute(trips: trips, now: Date(), calendar: Calendar.current)
        }.value
        guard !Task.isCancelled else { return }
        agg = computed
    }
}

// MARK: - Me-tab aggregates (§3 — client-side only, every number real)

/// Pure aggregate over `[Trip]` shared by the Я canon (strip regions, hero
/// gating, moments, history) and the Статистика screen. `compute` is a pure
/// function — safe to run inside `Task.detached` and trivially unit-testable.
struct MeAggregates {
    // All-time
    var tripCount = 0
    var totalKm = 0.0
    var totalHours = 0.0
    var regionsAllTime = 0
    var longestTripKm = 0.0
    var longestTripTitle: String?
    var longestTripRegion: String?
    var longestTripDate: Date?
    /// Max Σ duration over any single calendar day (all-time).
    var maxDayDuration: TimeInterval = 0

    // Current year
    var year = 0
    var yearTripCount = 0
    var yearKm = 0.0
    var yearHours = 0.0
    var yearRegions = 0
    var yearPhotoCount = 0
    /// 12 buckets (Jan…Dec) of Σ km for the current year.
    var monthlyKm = [Double](repeating: 0, count: 12)
    /// Longest run of consecutive trip-days inside the current year.
    var yearStreak = 0
    /// Best single day of the current year, Σ km.
    var maxDayKm = 0.0
    var topRegion: String?

    // Moments
    var yearAgoTrip: Trip?
    var longestYearTrip: Trip?
    /// Region first visited this year — only when ≥2 all-time regions exist
    /// (a lone-region user's only region isn't "new").
    var newRegion: String?

    // History
    /// Last 10 trips, newest first.
    var recentTrips: [Trip] = []

    static func compute(trips: [Trip], now: Date, calendar cal: Calendar) -> MeAggregates {
        var a = MeAggregates()

        // Year window: [Jan 1 of current year, Jan 1 of next year). Derived
        // from `now` at compute time — rolls over automatically (§5).
        guard let yearStart = cal.date(from: cal.dateComponents([.year], from: now)),
              let nextYearStart = cal.date(byAdding: .year, value: 1, to: yearStart) else {
            return a
        }
        a.year = cal.component(.year, from: now)

        a.tripCount = trips.count
        guard !trips.isEmpty else { return a }

        var regionsAll = Set<String>()
        var durationByDay: [Date: TimeInterval] = [:]
        var longest: Trip?
        for t in trips {
            a.totalKm += t.distanceKm
            a.totalHours += t.duration / 3600
            if let r = t.region, !r.isEmpty { regionsAll.insert(r) }
            durationByDay[cal.startOfDay(for: t.startDate), default: 0] += t.duration
            if t.distanceKm > (longest?.distanceKm ?? -1) { longest = t }
        }
        a.regionsAllTime = regionsAll.count
        a.maxDayDuration = durationByDay.values.max() ?? 0
        if let longest {
            a.longestTripKm = longest.distanceKm
            a.longestTripTitle = longest.title
            a.longestTripRegion = longest.region
            a.longestTripDate = longest.startDate
        }

        // Year scope
        let yearTrips = trips.filter { $0.startDate >= yearStart && $0.startDate < nextYearStart }
        a.yearTripCount = yearTrips.count

        var kmByDay: [Date: Double] = [:]
        var yearRegionSet = Set<String>()
        var regionCounts: [String: Int] = [:]
        for t in yearTrips {
            a.yearKm += t.distanceKm
            a.yearHours += t.duration / 3600
            a.yearPhotoCount += t.photos.count
            let month = cal.component(.month, from: t.startDate)
            if (1...12).contains(month) {
                a.monthlyKm[month - 1] += t.distanceKm
            }
            kmByDay[cal.startOfDay(for: t.startDate), default: 0] += t.distanceKm
            if let r = t.region, !r.isEmpty {
                yearRegionSet.insert(r)
                regionCounts[r, default: 0] += 1
            }
        }
        a.yearRegions = yearRegionSet.count
        a.maxDayKm = kmByDay.values.max() ?? 0
        // Deterministic max: highest count wins, name breaks ties.
        a.topRegion = regionCounts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }?.key
        a.yearStreak = Self.longestStreak(days: Set(kmByDay.keys), calendar: cal)
        a.longestYearTrip = yearTrips.max { $0.distanceKm < $1.distanceKm }

        // «Год назад в этот день» — best trip within ±3 days of now − 1y.
        if let target = cal.date(byAdding: .year, value: -1, to: now) {
            a.yearAgoTrip = trips
                .filter { abs($0.startDate.timeIntervalSince(target)) < 3 * 86_400 }
                .max { $0.distanceKm < $1.distanceKm }
        }

        // «Новый регион» — the most recent first-visit that happened this
        // year; suppressed when the user has ever seen fewer than 2 regions.
        if regionsAll.count >= 2 {
            let firstVisit = Dictionary(
                trips.compactMap { t in t.region.flatMap { $0.isEmpty ? nil : ($0, t.startDate) } },
                uniquingKeysWith: min
            )
            a.newRegion = firstVisit
                .filter { $0.value >= yearStart }
                .max { $0.value < $1.value }?
                .key
        }

        a.recentTrips = Array(trips.sorted { $0.startDate > $1.startDate }.prefix(10))
        return a
    }

    /// Longest run of consecutive calendar days — walks the sorted day set
    /// chaining `+1 day` steps.
    static func longestStreak(days: Set<Date>, calendar cal: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var best = 1
        var run = 1
        for i in 1..<sorted.count {
            if let next = cal.date(byAdding: .day, value: 1, to: sorted[i - 1]),
               cal.isDate(next, inSameDayAs: sorted[i]) {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }
}
