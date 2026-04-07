import SwiftUI
import Charts

struct StatsView: View {
    let tripManager: TripManager
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var allTrips: [Trip] = []
    @State private var currentMonth: MonthStats = .empty
    @State private var previousMonth: MonthStats = .empty
    @State private var weeklyData: [WeekData] = []
    @State private var dayOfWeekData: [DayOfWeekData] = []
    @State private var topPlaces: [PlaceStats] = []
    @State private var records: RecordStats = .empty
    @State private var kmByDayCache: [Date: Double] = [:]
    @State private var weekdaySymbolsCache: [String] = []
    @State private var monthGridCache: [Date?] = []

    private let calendar = Calendar.current

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // 1. Hero — This Month
                        heroSection(c, isRu: isRu)

                        // 2. Weekly Activity Chart
                        if !weeklyData.isEmpty {
                            weeklyChartSection(c, isRu: isRu)
                        }

                        // 3. Calendar Heatmap
                        calendarHeatmapCard(c)

                        // 4. When You Drive
                        if !dayOfWeekData.isEmpty {
                            dayOfWeekSection(c, isRu: isRu)
                        }

                        // 5. Top Places
                        if !topPlaces.isEmpty {
                            topPlacesSection(c, isRu: isRu)
                        }

                        // 6. Records
                        recordsSection(c, isRu: isRu)

                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            .background(c.bg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(AppStrings.stats(lang.language))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(c.text)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(c.textTertiary)
                    }
                }
            }
            .toolbarBackground(c.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear { calculateAll() }
    }

    // MARK: - 1. Hero Section

    private func heroSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 14) {
            // Month title
            Text(monthTitle(Date()))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(c.textSecondary)
                .textCase(.uppercase)
                .tracking(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Primary metrics
            HStack(spacing: 0) {
                heroMetric(
                    value: String(format: "%.0f", currentMonth.totalKm),
                    unit: isRu ? "км" : "km",
                    change: kmChange(),
                    c: c
                )
                heroMetric(
                    value: "\(currentMonth.tripCount)",
                    unit: isRu ? "поездок" : "trips",
                    change: tripChange(),
                    c: c
                )
            }

            // Secondary metrics
            HStack(spacing: 0) {
                miniMetric(icon: "clock.fill", value: currentMonth.formattedDuration, label: isRu ? "в пути" : "driving", color: AppTheme.blue, c: c)
                miniMetric(icon: "gauge.with.needle", value: String(format: "%.0f", currentMonth.avgSpeedKmh), label: isRu ? "км/ч ср." : "km/h avg", color: AppTheme.purple, c: c)
                miniMetric(icon: "speedometer", value: String(format: "%.0f", currentMonth.maxSpeedKmh), label: isRu ? "км/ч макс" : "km/h max", color: AppTheme.red, c: c)
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func heroMetric(value: String, unit: String, change: ChangeInfo?, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .heavy).monospacedDigit())
                    .foregroundStyle(c.text)
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }

            if let change {
                HStack(spacing: 3) {
                    Image(systemName: change.isPositive ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(change.text)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(change.isPositive ? AppTheme.green : AppTheme.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniMetric(icon: String, value: String, label: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(c.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2. Weekly Chart

    private func weeklyChartSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isRu ? "Активность" : "Activity")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)

            Chart(weeklyData) { item in
                BarMark(
                    x: .value("Week", item.label),
                    y: .value("km", item.km)
                )
                .foregroundStyle(item.isCurrent ? AppTheme.accent : AppTheme.accent.opacity(0.3))
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text(String(format: "%.0f", km))
                                .font(.system(size: 10))
                                .foregroundStyle(c.textTertiary)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(c.border)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(c.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - 3. Calendar Heatmap

    private func calendarHeatmapCard(_ c: AppTheme.Colors) -> some View {
        let kmByDay = kmByDayCache
        let maxKm = max(kmByDay.values.max() ?? 1, 1)
        let weekdays = weekdaySymbolsCache
        let gridDays = monthGridCache

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("\(AppStrings.calendar(lang.language)) — \(monthTitle(Date()))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
            }

            HStack(spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let km = kmByDay[calendar.startOfDay(for: date)] ?? 0
                        let opacity = heatmapOpacity(km: km, maxKm: maxKm)
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(km > 0 ? .white : c.textTertiary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(km > 0 ? AppTheme.accent.opacity(opacity) : c.cardAlt)
                            )
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - 4. Day of Week

    private func dayOfWeekSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        let maxTrips = dayOfWeekData.map(\.count).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            Text(isRu ? "Когда вы ездите" : "When you drive")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)

            ForEach(dayOfWeekData) { item in
                HStack(spacing: 10) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 28, alignment: .leading)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.clear)
                            .frame(height: 20)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppTheme.accent.opacity(item.isWeekend ? 0.7 : 0.4))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 20, maxHeight: 20
                            )
                            .scaleEffect(
                                x: max(0.02, Double(item.count) / Double(max(maxTrips, 1))),
                                anchor: .leading
                            )
                    }

                    Text("\(item.count)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - 5. Top Places

    private func topPlacesSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isRu ? "Частые маршруты" : "Frequent routes")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)

            ForEach(Array(topPlaces.prefix(5).enumerated()), id: \.element.name) { index, place in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(index == 0 ? AppTheme.accent : c.textTertiary, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        Text(String(format: isRu ? "%.0f км" : "%.0f km", place.totalKm))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                    }

                    Spacer()

                    Text("\(place.tripCount)")
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .foregroundStyle(c.text)
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - 6. Records

    private func recordsSection(_ c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isRu ? "Рекорды" : "Records")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)

            HStack(spacing: 10) {
                recordCard(
                    icon: "road.lanes",
                    value: String(format: "%.1f %@", records.longestTripKm, isRu ? "км" : "km"),
                    label: isRu ? "Самая длинная" : "Longest trip",
                    sublabel: records.longestTripDate,
                    color: AppTheme.green, c: c
                )
                recordCard(
                    icon: "speedometer",
                    value: String(format: "%.0f %@", records.maxSpeedKmh, isRu ? "км/ч" : "km/h"),
                    label: isRu ? "Макс. скорость" : "Top speed",
                    sublabel: records.maxSpeedDate,
                    color: AppTheme.red, c: c
                )
            }

            HStack(spacing: 10) {
                recordCard(
                    icon: "flame.fill",
                    value: String(format: "%.0f %@", records.mostActiveDay.km, isRu ? "км" : "km"),
                    label: isRu ? "Лучший день" : "Best day",
                    sublabel: records.mostActiveDay.date,
                    color: AppTheme.accent, c: c
                )
                recordCard(
                    icon: "car.fill",
                    value: "\(allTrips.count)",
                    label: isRu ? "Всего поездок" : "Total trips",
                    sublabel: String(format: "%.0f %@", allTrips.reduce(0) { $0 + $1.distanceKm }, isRu ? "км" : "km"),
                    color: AppTheme.blue, c: c
                )
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func recordCard(icon: String, value: String, label: String, sublabel: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(c.text)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(c.textSecondary)
            Text(sublabel)
                .font(.system(size: 10))
                .foregroundStyle(c.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Calculations

    private func calculateAll() {
        // Use StatsCache to avoid re-fetching when no trips changed
        let count = tripManager.fetchTripCount()
        let lastDate = tripManager.fetchLastTripDate()
        if let cached = StatsCache.tripsIfValid(currentCount: count, currentLastDate: lastDate) {
            allTrips = cached
        } else {
            allTrips = tripManager.fetchTrips()
            StatsCache.update(trips: allTrips, count: count, lastDate: lastDate)
        }

        let now = Date()
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!

        let thisMonthTrips = allTrips.filter { $0.startDate >= thisMonthStart }
        let lastMonthTrips = allTrips.filter { $0.startDate >= lastMonthStart && $0.startDate < thisMonthStart }

        currentMonth = computeMonthStats(thisMonthTrips)
        previousMonth = computeMonthStats(lastMonthTrips)

        // Weekly data — last 12 weeks
        weeklyData = computeWeeklyData()

        // Day of week
        dayOfWeekData = computeDayOfWeek()

        // Top places
        topPlaces = computeTopPlaces()

        // Records
        records = computeRecords()

        // Calendar caches
        kmByDayCache = computeKmByDay()
        weekdaySymbolsCache = weekdaySymbols()
        monthGridCache = monthGridDays(for: Date())
    }

    private func computeKmByDay() -> [Date: Double] {
        let now = Date()
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [:] }
        var byDay: [Date: Double] = [:]
        for trip in allTrips where trip.startDate >= monthStart && trip.startDate < monthEnd {
            let day = calendar.startOfDay(for: trip.startDate)
            byDay[day, default: 0] += trip.distanceKm
        }
        return byDay
    }

    private func computeMonthStats(_ trips: [Trip]) -> MonthStats {
        let count = trips.count
        let totalKm = trips.reduce(0.0) { $0 + $1.distanceKm }
        let totalDuration = trips.reduce(0.0) { $0 + $1.duration }
        let maxSpeed = trips.map(\.maxSpeedKmh).max() ?? 0
        let avgSpeed = count > 0 ? trips.reduce(0.0) { $0 + $1.averageSpeedKmh } / Double(count) : 0
        return MonthStats(tripCount: count, totalKm: totalKm, totalDuration: totalDuration, avgSpeedKmh: avgSpeed, maxSpeedKmh: maxSpeed)
    }

    private func computeWeeklyData() -> [WeekData] {
        let now = Date()
        let weekCount = 12
        var result: [WeekData] = []

        for i in (0..<weekCount).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -i, to: now),
                  let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)) else { continue }
            let nextMonday = calendar.date(byAdding: .weekOfYear, value: 1, to: monday)!

            let km = allTrips
                .filter { $0.startDate >= monday && $0.startDate < nextMonday }
                .reduce(0.0) { $0 + $1.distanceKm }

            let formatter = DateFormatter()
            formatter.dateFormat = "d/M"
            let label = formatter.string(from: monday)

            result.append(WeekData(label: label, km: km, isCurrent: i == 0))
        }
        return result
    }

    private func computeDayOfWeek() -> [DayOfWeekData] {
        let isRu = lang.language == .ru
        let dayNames = isRu
            ? ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        var counts = [Int](repeating: 0, count: 7)
        for trip in allTrips {
            let weekday = calendar.component(.weekday, from: trip.startDate)
            // Convert Sunday=1..Saturday=7 to Monday=0..Sunday=6
            let index = (weekday + 5) % 7
            counts[index] += 1
        }

        return (0..<7).map { i in
            DayOfWeekData(
                name: dayNames[i],
                count: counts[i],
                dayIndex: i,
                isWeekend: i >= 5
            )
        }
    }

    private func computeTopPlaces() -> [PlaceStats] {
        // 1. Extract city name for each trip
        var cityTrips: [String: (count: Int, km: Double)] = [:]
        var regionFallbacks: [(region: String, count: Int, km: Double)] = []

        for trip in allTrips {
            let city = extractCityName(from: trip)
            if let city {
                cityTrips[city, default: (0, 0)].count += 1
                cityTrips[city, default: (0, 0)].km += trip.distanceKm
            } else if let region = trip.region {
                // No city — accumulate by region to merge later
                regionFallbacks.append((region, 1, trip.distanceKm))
            }
        }

        // 2. Merge region-fallback trips into existing cities from same region
        // Build region→city mapping from trips that DO have cities
        var regionToCities: [String: String] = [:]
        for trip in allTrips {
            if let city = extractCityName(from: trip), let region = trip.region {
                regionToCities[region] = city
            }
        }

        for fallback in regionFallbacks {
            if let city = regionToCities[fallback.region] {
                // Merge into existing city
                cityTrips[city, default: (0, 0)].count += fallback.count
                cityTrips[city, default: (0, 0)].km += fallback.km
            } else {
                // No city found for this region — show region name
                cityTrips[fallback.region, default: (0, 0)].count += fallback.count
                cityTrips[fallback.region, default: (0, 0)].km += fallback.km
            }
        }

        return cityTrips
            .map { PlaceStats(name: $0.key, tripCount: $0.value.count, totalKm: $0.value.km) }
            .sorted { $0.tripCount > $1.tripCount }
    }

    private func extractCityName(from trip: Trip) -> String? {
        guard let title = trip.title, !title.isEmpty else { return nil }
        // Skip date-format titles
        if let first = title.first, first.isNumber { return nil }
        if title.contains(":") && title.count < 20 { return nil }
        // "Krasnodar → Sochi" → "Krasnodar"
        if let arrow = title.range(of: " → ") {
            return String(title[..<arrow.lowerBound])
        }
        return title
    }

    private func computeRecords() -> RecordStats {
        let formatter = DateFormatter()
        formatter.dateFormat = lang.language == .ru ? "d MMM" : "MMM d"
        formatter.locale = lang.language == .ru ? Locale(identifier: "ru_RU") : Locale(identifier: "en_US")

        let longest = allTrips.max(by: { $0.distanceKm < $1.distanceKm })
        let fastest = allTrips.max(by: { $0.maxSpeedKmh < $1.maxSpeedKmh })

        // Most active day
        var kmByDay: [Date: Double] = [:]
        for trip in allTrips {
            let day = calendar.startOfDay(for: trip.startDate)
            kmByDay[day, default: 0] += trip.distanceKm
        }
        let bestDay = kmByDay.max(by: { $0.value < $1.value })

        return RecordStats(
            longestTripKm: longest?.distanceKm ?? 0,
            longestTripDate: longest.map { formatter.string(from: $0.startDate) } ?? "-",
            maxSpeedKmh: fastest?.maxSpeedKmh ?? 0,
            maxSpeedDate: fastest.map { formatter.string(from: $0.startDate) } ?? "-",
            mostActiveDay: (km: bestDay?.value ?? 0, date: bestDay.map { formatter.string(from: $0.key) } ?? "-")
        )
    }

    // MARK: - Change Calculation

    private func kmChange() -> ChangeInfo? {
        guard previousMonth.totalKm > 0 else { return nil }
        let diff = currentMonth.totalKm - previousMonth.totalKm
        let pct = abs(diff / previousMonth.totalKm * 100)
        let isRu = lang.language == .ru
        return ChangeInfo(
            text: String(format: "%.0f%% %@", pct, isRu ? "vs прош." : "vs prev."),
            isPositive: diff >= 0
        )
    }

    private func tripChange() -> ChangeInfo? {
        guard previousMonth.tripCount > 0 else { return nil }
        let diff = currentMonth.tripCount - previousMonth.tripCount
        let isRu = lang.language == .ru
        if diff >= 0 {
            return ChangeInfo(text: isRu ? "+\(diff) больше" : "+\(diff) more", isPositive: true)
        } else {
            return ChangeInfo(text: isRu ? "\(diff) меньше" : "\(diff) fewer", isPositive: false)
        }
    }

    // MARK: - Calendar Helpers

    private func heatmapOpacity(km: Double, maxKm: Double) -> Double {
        guard km > 0 else { return 0 }
        let r = km / maxKm
        if r < 0.33 { return 0.2 }
        if r < 0.66 { return 0.5 }
        return 0.9
    }

    private func weekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = lang.language == .ru ? Locale(identifier: "ru_RU") : Locale(identifier: "en_US")
        let symbols = formatter.veryShortWeekdaySymbols ?? ["M","T","W","T","F","S","S"]
        return Array(symbols[1...]) + [symbols[0]]
    }

    private func monthGridDays(for month: Date) -> [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let offset = (firstWeekday + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                result.append(date)
            }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = lang.language == .ru ? Locale(identifier: "ru_RU") : Locale(identifier: "en_US")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }
}

// MARK: - Data Models

private struct MonthStats {
    var tripCount: Int = 0
    var totalKm: Double = 0
    var totalDuration: TimeInterval = 0
    var avgSpeedKmh: Double = 0
    var maxSpeedKmh: Double = 0
    static let empty = MonthStats()

    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

private struct WeekData: Identifiable {
    var id: String { label }
    let label: String
    let km: Double
    let isCurrent: Bool
}

private struct DayOfWeekData: Identifiable {
    var id: Int { dayIndex }
    let name: String
    let count: Int
    let dayIndex: Int
    let isWeekend: Bool
}

private struct PlaceStats {
    let name: String
    let tripCount: Int
    let totalKm: Double
}

private struct RecordStats {
    var longestTripKm: Double = 0
    var longestTripDate: String = "-"
    var maxSpeedKmh: Double = 0
    var maxSpeedDate: String = "-"
    var mostActiveDay: (km: Double, date: String) = (0, "-")
    static let empty = RecordStats()
}

private struct ChangeInfo {
    let text: String
    let isPositive: Bool
}

// MARK: - Fuel Calculator Card

private struct FuelCalculatorCard: View {
    let totalKm: Double
    let language: LanguageManager.Language
    let onFocus: () -> Void

    @AppStorage("fuelConsumption") private var fuelConsumption: String = "7.8"
    @AppStorage("fuelPrice") private var fuelPrice: String = "56"
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool

    private var liters: Double {
        let cons = Double(fuelConsumption.replacingOccurrences(of: ",", with: ".")) ?? 7.8
        return totalKm / 100 * cons
    }

    private var cost: Double {
        let price = Double(fuelPrice.replacingOccurrences(of: ",", with: ".")) ?? 56
        return liters * price
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(language == .ru ? "Расход топлива" : "Fuel consumption")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.consumption(language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                    TextField("7.8", text: $fuelConsumption)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15))
                        .foregroundStyle(c.text)
                        .padding(12)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                        .focused($focused)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppStrings.pricePerLiter(language))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                    TextField("56", text: $fuelPrice)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15))
                        .foregroundStyle(c.text)
                        .padding(12)
                        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                        .focused($focused)
                }
            }

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", totalKm))
                        .font(.system(size: 18, weight: .heavy).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                    Text(AppStrings.km(language))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", liters))
                        .font(.system(size: 18, weight: .heavy).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                    Text(language == .ru ? "л" : "L")
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", cost))
                        .font(.system(size: 18, weight: .heavy).monospacedDigit())
                        .foregroundStyle(AppTheme.accent)
                    Text(FuelCurrency.current)
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(language == .ru ? "Готово" : "Done") {
                    focused = false
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            }
        }
        .onChange(of: focused) { isFocused in
            if isFocused { onFocus() }
        }
    }
}
