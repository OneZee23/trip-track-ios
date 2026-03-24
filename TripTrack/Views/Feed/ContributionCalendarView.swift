import SwiftUI

struct ContributionCalendarView: View {
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    let language: LanguageManager.Language
    let maxKmDay: Double
    let kmByDay: (Date) -> [Date: Double]

    @State private var isExpanded = false
    @State private var displayedMonth = Date()
    @Environment(\.colorScheme) private var scheme

    private let calendar = Calendar.current

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            if isExpanded {
                expandedView(c)
            } else {
                collapsedView(c)
            }
        }
        .surfaceCard(cornerRadius: 12)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
    }

    // MARK: - Selection Logic

    @State private var bouncedDay: Date?

    private func handleDayTap(_ date: Date) {
        Haptics.tap()
        // Visual bounce
        bouncedDay = date
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if bouncedDay == date { bouncedDay = nil }
        }
        let tappedDay = calendar.startOfDay(for: date)

        if dateFrom == nil {
            // Nothing selected → set start
            dateFrom = tappedDay
            dateTo = nil
        } else if dateTo == nil {
            // Start selected, no end yet
            let start = calendar.startOfDay(for: dateFrom!)
            if calendar.isDate(tappedDay, inSameDayAs: start) {
                // Same day tapped twice → clear filter entirely
                dateFrom = nil
                dateTo = nil
            } else if tappedDay < start {
                // Tapped before start → swap
                dateTo = start
                dateFrom = tappedDay
            } else {
                // Normal: tapped after start
                dateTo = tappedDay
            }
        } else {
            // Range already selected → reset, start new
            dateFrom = tappedDay
            dateTo = nil
        }
    }

    private func isInRange(_ date: Date) -> Bool {
        guard let from = dateFrom else { return false }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: from)

        if let to = dateTo {
            let end = calendar.startOfDay(for: to)
            return day >= start && day <= end
        }
        // Only start selected
        return calendar.isDate(day, inSameDayAs: start)
    }

    private func isRangeStart(_ date: Date) -> Bool {
        guard let from = dateFrom else { return false }
        return calendar.isDate(calendar.startOfDay(for: date), inSameDayAs: calendar.startOfDay(for: from))
    }

    private func isRangeEnd(_ date: Date) -> Bool {
        guard let to = dateTo else { return false }
        return calendar.isDate(calendar.startOfDay(for: date), inSameDayAs: calendar.startOfDay(for: to))
    }

    // MARK: - Collapsed (current week)

    private func collapsedView(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.thisWeek(language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { isExpanded = true }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 28, height: 28)
                }
            }

            HStack {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 4) {
                let days = currentWeekDays()
                let monthData = kmByDay(displayedMonth)
                ForEach(days, id: \.self) { date in
                    dayCell(date: date, km: monthData[calendar.startOfDay(for: date)] ?? 0, c: c)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Expanded (full month)

    private func expandedView(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 8) {
            // Month header
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 32, height: 32)
                }

                Spacer()

                Text(monthYearTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 32, height: 32)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { isExpanded = false }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 28, height: 28)
                }
            }

            // Weekday labels
            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, sym in
                    Text(sym)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            let monthData = kmByDay(displayedMonth)
            let gridDays = monthGridDays()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(gridDays.indices, id: \.self) { index in
                    let day = gridDays[index]
                    if let date = day {
                        dayCell(date: date, km: monthData[calendar.startOfDay(for: date)] ?? 0, c: c)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(12)
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < -50 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                        }
                    } else if value.translation.width > 50 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                        }
                    }
                }
        )
    }

    // MARK: - Day Cell

    private func dayCell(date: Date, km: Double, c: AppTheme.Colors) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()
        let inRange = isInRange(date)
        let isStart = isRangeStart(date)
        let isEnd = isRangeEnd(date)
        let hasTrips = km > 0
        let day = calendar.component(.day, from: date)
        let isCurrentWeek = isInCurrentWeek(date)

        return Button {
            guard !isFuture else { return }
            handleDayTap(date)
        } label: {
            Text("\(day)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    isFuture ? c.textTertiary.opacity(0.3) :
                    inRange ? .white :
                    hasTrips ? c.text : c.textTertiary
                )
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(dayCellBackground(km: km, isFuture: isFuture, inRange: inRange, isStart: isStart, isEnd: isEnd, isCurrentWeek: isCurrentWeek, c: c))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isToday && !inRange ? c.textTertiary.opacity(0.4) : .clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .scaleEffect(bouncedDay.map { calendar.isDate($0, inSameDayAs: date) } == true ? 1.15 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bouncedDay)
    }

    private func dayCellBackground(km: Double, isFuture: Bool, inRange: Bool, isStart: Bool, isEnd: Bool, isCurrentWeek: Bool, c: AppTheme.Colors) -> Color {
        guard !isFuture else { return c.cardAlt.opacity(0.3) }

        // Selected range
        if inRange {
            if isStart || isEnd {
                return AppTheme.accent
            }
            return AppTheme.accent.opacity(0.5)
        }

        // Trip intensity
        guard km > 0, maxKmDay > 0 else {
            // Current week subtle highlight (only in expanded view)
            if isCurrentWeek && isExpanded {
                return c.cardAlt.opacity(0.8)
            }
            return c.cardAlt
        }

        let ratio = km / maxKmDay
        if ratio < 0.33 {
            return AppTheme.accent.opacity(0.15)
        } else if ratio < 0.66 {
            return AppTheme.accent.opacity(0.40)
        } else {
            return AppTheme.accent.opacity(0.80)
        }
    }

    // MARK: - Data Helpers

    private func isInCurrentWeek(_ date: Date) -> Bool {
        let today = Date()
        let todayWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let dateWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return todayWeek.yearForWeekOfYear == dateWeek.yearForWeekOfYear && todayWeek.weekOfYear == dateWeek.weekOfYear
    }

    private static let weekdaySymbolsRu: [String] = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU")
        let s = f.veryShortWeekdaySymbols ?? ["П","В","С","Ч","П","С","В"]
        return Array(s[1...]) + [s[0]]
    }()
    private static let weekdaySymbolsEn: [String] = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US")
        let s = f.veryShortWeekdaySymbols ?? ["M","T","W","T","F","S","S"]
        return Array(s[1...]) + [s[0]]
    }()
    private var weekdaySymbols: [String] {
        language == .ru ? Self.weekdaySymbolsRu : Self.weekdaySymbolsEn
    }

    private func currentWeekDays() -> [Date] {
        let today = Date()
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2 // Monday
        guard let monday = calendar.date(from: comps) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func monthGridDays() -> [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let offset = (firstWeekday + 5) % 7

        var result: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                result.append(date)
            }
        }
        while result.count % 7 != 0 {
            result.append(nil)
        }
        return result
    }

    private static let monthYearRu: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "LLLL yyyy"; return f
    }()
    private static let monthYearEn: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US"); f.dateFormat = "LLLL yyyy"; return f
    }()
    private var monthYearTitle: String {
        let f = language == .ru ? Self.monthYearRu : Self.monthYearEn
        return f.string(from: displayedMonth).capitalized
    }
}
