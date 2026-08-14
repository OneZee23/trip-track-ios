import SwiftUI
import UIKit  // Color(UIColor { … }) — the heat ramp needs a per-scheme twin

// MARK: - History calendar (Figma 1866:7759)

/// The date-range filter that sits above «История» on the Я tab. Collapsed it
/// shows the current week; the month label and its chevron expand it to the
/// full month grid.
///
/// The range logic is the shipped Feed calendar's, unchanged: a tap sets the
/// start, a second tap sets the end, the same day twice clears, a day before
/// the start swaps the ends, and a tap while a full range is up starts over.
/// What the profile changes is the styling (canon 39pt cells + a km heat ramp)
/// and the «сбросить» row — without it a tap can leave the history nearly
/// empty with nothing on screen explaining why.
struct ProfileHistoryCalendar: View {
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    /// Σ km per calendar day, keyed by `Calendar.startOfDay`.
    let kmByDay: [Date: Double]
    let maxKmDay: Double
    /// How many trips the current range matches — drives the «сбросить» row.
    let filteredCount: Int

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var isExpanded = false
    @State private var displayedMonth = Date()
    @State private var bouncedDay: Date?

    /// Monday-first no matter the device locale: the canon header runs Пн…Вс,
    /// and `Calendar.current` is Sunday-first under en_US — which used to push
    /// "the current week" a week into the future every Sunday.
    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }()

    /// Canon geometry (Figma 1866:7759): seven 39pt squares across a 300pt row,
    /// i.e. 4.5pt between them. The gap is what's literal here — the squares
    /// themselves scale with the row so the grid keeps that proportion on a
    /// 393pt phone instead of leaving 10pt trenches between 39pt cells.
    private static let cellGap: CGFloat = 4.5

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 10) {
            if isExpanded {
                expandedHeader(c)
            } else {
                collapsedHeader(c)
            }

            weekdayHeader(c)

            // Resolved once per pass: every cell needs the same denominator,
            // and computing it per cell rebuilt the whole month array 42 times.
            let scale = visibleMaxKm

            if isExpanded {
                monthGrid(c, scale: scale)
            } else {
                weekRow(c, scale: scale)
            }

            if dateFrom != nil {
                filterRow(c)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .surfaceCard(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .animation(.easeInOut(duration: 0.18), value: dateFrom)
        .animation(.easeInOut(duration: 0.18), value: dateTo)
        .accessibilityIdentifier("profile_calendar")
    }

    // MARK: - Headers

    private func collapsedHeader(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(AppStrings.thisWeek(lang.language))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                // Open where the filter already lives, so a March range is not
                // five taps of paging away; with no filter that is this month.
                displayedMonth = dateFrom ?? Date()
                isExpanded = true
            } label: {
                HStack(spacing: 4) {
                    // Today's month, not `displayedMonth`: collapsed always
                    // shows the current week, so any other name would lie.
                    Text(ProfileDateFormat.monthName(Date(), lang: lang.language))
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(c.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func expandedHeader(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            monthStepButton("chevron.left", months: -1, c: c)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                isExpanded = false
            } label: {
                HStack(spacing: 4) {
                    Text(expandedTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            monthStepButton("chevron.right", months: 1, c: c)
        }
    }

    private func monthStepButton(_ systemName: String, months: Int, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.2)) {
                displayedMonth = calendar.date(byAdding: .month, value: months, to: displayedMonth) ?? displayedMonth
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedTitle: String {
        let name = ProfileDateFormat.monthName(displayedMonth, lang: lang.language)
        let year = calendar.component(.year, from: displayedMonth)
        // The year is noise while you are still inside the current one; it
        // earns its place only once you have paged out of it.
        guard year != calendar.component(.year, from: Date()) else { return name }
        return "\(name) \(year)"
    }

    // MARK: - Grids

    private func weekdayHeader(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: Self.cellGap) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekRow(_ c: AppTheme.Colors, scale: Double) -> some View {
        HStack(spacing: Self.cellGap) {
            ForEach(currentWeekDays(), id: \.self) { date in
                dayCell(date: date, c: c, scale: scale)
            }
        }
    }

    /// Six rows at most and all of them on screen at once, so a `LazyVGrid`
    /// would only add bookkeeping — plain rows also keep the cell geometry
    /// identical to the collapsed week.
    private func monthGrid(_ c: AppTheme.Colors, scale: Double) -> some View {
        let weeks = monthWeeks()
        return VStack(spacing: 4) {
            ForEach(weeks.indices, id: \.self) { row in
                HStack(spacing: Self.cellGap) {
                    ForEach(weeks[row].indices, id: \.self) { column in
                        if let date = weeks[row][column] {
                            dayCell(date: date, c: c, scale: scale)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    // Horizontal dominance only, or the card steals the
                    // profile's vertical scroll on a sloppy swipe.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        let months = value.translation.width < 0 ? 1 : -1
                        displayedMonth = calendar.date(byAdding: .month, value: months, to: displayedMonth) ?? displayedMonth
                    }
                }
        )
    }

    // MARK: - Day cell

    private func dayCell(date: Date, c: AppTheme.Colors, scale: Double) -> some View {
        let day = calendar.startOfDay(for: date)
        let km = kmByDay[day] ?? 0
        let isFuture = day > calendar.startOfDay(for: Date())
        let inRange = isInRange(date)
        let isEndpoint = isRangeStart(date) || isRangeEnd(date)
        let isBounced = bouncedDay.map { calendar.isDate($0, inSameDayAs: day) } == true

        return Button {
            handleDayTap(date)
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(dayFill(km: km, scale: scale, isFuture: isFuture, inRange: inRange, isEndpoint: isEndpoint, c: c))
                .overlay {
                    if calendar.isDateInToday(date) {
                        // strokeBorder, not stroke: a 2pt stroke straddles the
                        // edge and bleeds a hairline past the square. Inside a
                        // selected endpoint the ring flips to the card colour
                        // so «сегодня» survives on the inverted fill.
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isEndpoint ? c.card : c.text, lineWidth: 2)
                    }
                }
                .overlay {
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(dayNumberColor(km: km, scale: scale, isFuture: isFuture, inRange: inRange, isEndpoint: isEndpoint, c: c))
                }
                // Square, but sized by the row rather than pinned to canon's
                // 39pt. Canon draws 39pt cells with 4.5pt gaps on a 360pt
                // artboard; holding 39 on a 393pt phone keeps the squares and
                // doubles the gaps instead, which reads as a sparser, smaller
                // calendar than the one that was drawn. Scaling the cell keeps
                // the proportion the design actually specifies.
                .aspectRatio(1, contentMode: .fit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .scaleEffect(isBounced ? 1.15 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bouncedDay)
    }

    private func dayFill(km: Double, scale: Double, isFuture: Bool, inRange: Bool, isEndpoint: Bool, c: AppTheme.Colors) -> Color {
        guard !isFuture else { return c.cardAlt.opacity(0.4) }
        // Selection is inverted rather than tinted: every heat step is a warm
        // orange, so an accent-filled day would read as "a lot of km here".
        if isEndpoint { return c.text }
        if inRange { return c.text.opacity(0.16) }
        guard let step = heatStep(km, scale: scale) else { return Self.heatEmpty }
        return Self.heatRamp[step]
    }

    private func dayNumberColor(km: Double, scale: Double, isFuture: Bool, inRange: Bool, isEndpoint: Bool, c: AppTheme.Colors) -> Color {
        guard !isFuture else { return c.textTertiary.opacity(0.35) }
        if isEndpoint { return c.card }
        if inRange { return c.text }
        guard let step = heatStep(km, scale: scale) else { return c.textTertiary }
        // Canon 1866:7782: the palest step keeps the near-black numeral, every
        // warmer one flips to white. White on #FAA86B measures 1.9:1 and on
        // #F27333 2.5:1, which is under any contrast floor — flagged to the
        // author, who chose the drawn values. One line to reverse if it reads
        // badly on device: `step == 3 ? .white : c.text`.
        return step == 0 ? c.text : .white
    }

    /// 0…3 by quartile of the day's Σ km against the busiest day ON SCREEN.
    ///
    /// Deliberately not the all-time busiest day: one 1 200 km run to Elbrus
    /// would put every ordinary week five buckets below it and flatten the
    /// whole ramp to its palest step forever. The window is what the eye is
    /// comparing, so the window sets the scale.
    private func heatStep(_ km: Double, scale: Double) -> Int? {
        guard km > 0 else { return nil }
        // Nothing else on screen to compare against — a lone driven day is the
        // busiest day of its own window, not an empty one.
        guard scale > 0 else { return 3 }
        let ratio = min(km / scale, 1)
        if ratio <= 0.25 { return 0 }
        if ratio <= 0.5 { return 1 }
        if ratio <= 0.75 { return 2 }
        return 3
    }

    /// Busiest day among the ones currently drawn, capped by the all-time max
    /// the host measured so the scale can never exceed reality.
    private var visibleMaxKm: Double {
        let days: [Date] = isExpanded
            ? monthWeeks().flatMap { $0.compactMap { $0 } }
            : currentWeekDays()
        let peak = days
            .map { kmByDay[calendar.startOfDay(for: $0)] ?? 0 }
            .max() ?? 0
        return maxKmDay > 0 ? min(peak, maxKmDay) : peak
    }

    // MARK: - Heat ramp (Figma 1866:7782)

    // The canon hexes are light-mode tints painted on a white card; on the dark
    // card they glow and swallow the numerals, so each step carries a dark twin
    // blended from the same hue toward the dark card fill — the adaptive
    // treatment AppTheme.goldBg uses.
    /// A day with no trips. Canon #EBE8E5 — a touch warmer and darker than
    /// `cardAlt`, which is what makes the empty cells read as a grid rather
    /// than as holes in the card.
    private static let heatEmpty = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 44/255, green: 42/255, blue: 40/255, alpha: 1)
            : UIColor(red: 235/255, green: 232/255, blue: 229/255, alpha: 1)   // #EBE8E5
    })
    private static let heatLowest = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 66/255, green: 60/255, blue: 56/255, alpha: 1)
            : UIColor(red: 252/255, green: 219/255, blue: 184/255, alpha: 1)   // #FCDBB8
    })
    private static let heatLowMid = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 105/255, green: 77/255, blue: 58/255, alpha: 1)
            : UIColor(red: 250/255, green: 168/255, blue: 107/255, alpha: 1)   // #FAA86B
    })
    private static let heatHighMid = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 157/255, green: 81/255, blue: 43/255, alpha: 1)
            : UIColor(red: 242/255, green: 115/255, blue: 51/255, alpha: 1)    // #F27333
    })
    private static let heatHighest = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 196/255, green: 64/255, blue: 33/255, alpha: 1)
            : UIColor(red: 219/255, green: 69/255, blue: 33/255, alpha: 1)     // #DB4521
    })
    private static let heatRamp: [Color] = [heatLowest, heatLowMid, heatHighMid, heatHighest]

    // MARK: - Filter escape hatch

    private func filterRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(AppStrings.calendarFilterActive(lang.language, count: filteredCount))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                dateFrom = nil
                dateTo = nil
            } label: {
                Text(AppStrings.calendarClearFilter(lang.language))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_calendar_clear")
        }
    }

    // MARK: - Range selection

    private func handleDayTap(_ date: Date) {
        Haptics.tap()
        let tappedDay = calendar.startOfDay(for: date)

        // The bounce confirms the tap landed even when the fill barely moves —
        // an already-heat-filled day joining an existing range, say.
        bouncedDay = tappedDay
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if let bounced = bouncedDay, calendar.isDate(bounced, inSameDayAs: tappedDay) {
                bouncedDay = nil
            }
        }

        guard let from = dateFrom else {
            // Nothing selected → this day becomes the start
            dateFrom = tappedDay
            dateTo = nil
            return
        }
        guard dateTo == nil else {
            // A full range is already up → restart from this day
            dateFrom = tappedDay
            dateTo = nil
            return
        }

        let start = calendar.startOfDay(for: from)
        if calendar.isDate(tappedDay, inSameDayAs: start) {
            // Same day twice → clear the filter entirely
            dateFrom = nil
            dateTo = nil
        } else if tappedDay < start {
            // Tapped before the start → swap the ends
            dateFrom = tappedDay
            dateTo = start
        } else {
            dateTo = tappedDay
        }
    }

    private func isInRange(_ date: Date) -> Bool {
        guard let from = dateFrom else { return false }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: from)
        guard let to = dateTo else { return calendar.isDate(day, inSameDayAs: start) }
        return day >= start && day <= calendar.startOfDay(for: to)
    }

    private func isRangeStart(_ date: Date) -> Bool {
        guard let from = dateFrom else { return false }
        return calendar.isDate(calendar.startOfDay(for: date), inSameDayAs: calendar.startOfDay(for: from))
    }

    private func isRangeEnd(_ date: Date) -> Bool {
        guard let to = dateTo else { return false }
        return calendar.isDate(calendar.startOfDay(for: date), inSameDayAs: calendar.startOfDay(for: to))
    }

    // MARK: - Date helpers

    private static let weekdaySymbolsRu = rotatedShortWeekdays(
        "ru_RU", fallback: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    )
    private static let weekdaySymbolsEn = rotatedShortWeekdays(
        "en_US", fallback: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    )

    /// ICU hands the symbols back Sunday-first, so the head rotates to the tail
    /// to line up with the Monday-first grid. RU ships them lowercase («пн»).
    private static func rotatedShortWeekdays(_ localeID: String, fallback: [String]) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeID)
        guard let symbols = formatter.shortWeekdaySymbols, symbols.count == 7 else { return fallback }
        return (Array(symbols[1...]) + [symbols[0]]).map { $0.capitalized }
    }

    private var weekdaySymbols: [String] {
        lang.language == .ru ? Self.weekdaySymbolsRu : Self.weekdaySymbolsEn
    }

    private func currentWeekDays() -> [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// The displayed month padded with `nil` so every row holds seven slots.
    private func monthWeeks() -> [[Date?]] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        // Calendar.weekday is absolute (1 = Sunday) whatever firstWeekday says,
        // so +5 mod 7 turns it into the Monday-first leading offset.
        let offset = (calendar.component(.weekday, from: monthStart) + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            days.append(calendar.date(byAdding: .day, value: day - 1, to: monthStart))
        }
        while days.count % 7 != 0 { days.append(nil) }

        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0 ..< $0 + 7]) }
    }
}
