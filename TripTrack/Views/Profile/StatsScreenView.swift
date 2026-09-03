import SwiftUI
import CoreLocation

// MARK: - Статистика (Figma 580:316 / empty 580:416 / month-tap 1821:119 / year 1827:119)

/// Pushed from the Я stats strip (fork FK-3). Client-side aggregates only —
/// every number is computed from real CoreData trips, real `RoadEntity` rows
/// and the real atlas pass, or the surface hides. Nothing here is a placeholder:
/// a record with no data is dropped, not zeroed.
/// The old `StatsView` sheet (Feed) is untouched (fork FK-12).
struct StatsScreenView: View {
    let tripManager: TripManager
    /// Откуда брать поездки. `nil` — своя библиотека из CoreData (сегодняшнее
    /// поведение). Непустой источник делает экран ЧУЖИМ (0.6.3): те же секции,
    /// та же арифметика, другой массив на входе.
    var source: TripSource?
    /// Имя владельца профиля под заголовком. Только для чужого экрана —
    /// на своём и так понятно, чьи это числа.
    var ownerName: String?
    /// How a tapped trip opens. Set by a host that has a nav path of its own
    /// (`MeDest.trip`); when it is nil the app-wide `.openTripDetail` channel
    /// takes over, which lands on the Home tab instead of pushing in place.
    /// Defaulted so the existing `ProfileView` call site keeps compiling until
    /// it passes one.
    var onOpenTrip: ((UUID) -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var agg: MeAggregates?
    /// Atlas-derived lifetime counters behind «Всего: N городов · N регионов».
    /// Lands a beat after `agg` — the pass that produces it is the Моя карта
    /// build, and the line is below the fold anyway.
    @State private var places: StatsPlaces?
    @State private var range: StatsRange = .month
    /// Which month/year the stepper is parked on. Starts on the last month
    /// that actually holds a trip, not on `now`: opening a screen whose whole
    /// job is showing real numbers on a column of zeroes (because the user
    /// last drove in April and it is August) is the one thing it must not do.
    @State private var anchor = Date()
    /// Column the user tapped in the bar chart (0…11) — canon 1821:6866.
    @State private var pickedMonth: Int?

    /// Чужой экран. Две секции при нём отсутствуют, и обе по своей причине:
    ///  - «В этот день год назад» — личный крючок памяти, у постороннего он
    ///    бессмысленный;
    ///  - «Дорога-чемпион» и половина «Новых мест» про новые дороги —
    ///    `RoadEntity` живёт только локально, на сервере её нет вовсе, так что
    ///    у чужого `roads` всегда пуст.
    private var isRemote: Bool { source != nil }

    /// Чужая статистика не загрузилась. Пустой экран и отказ — разные вещи.
    @State private var remoteFailed = false
    /// Поколение загрузки: обе кнопки «Повторить» плодят независимые задачи, и
    /// без гейта обогнавшая старая перезаписала бы результат новой урезанным.
    @State private var loadGeneration = 0

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ScrollView {
            VStack(spacing: 10) {
                if agg == nil, isRemote {
                    // До двадцати последовательных страниц: пустой экран всё
                    // это время выглядит как сломанный. Карта показывает
                    // загрузку — статистика обязана тоже.
                    CarLoadingView()
                        .padding(.top, 80)
                } else if isRemote, remoteFailed, (agg?.tripCount ?? 0) == 0 {
                    remoteFailedState(c, l)
                } else if let agg {
                    // Частичная загрузка: числа ниже — правда, но НЕ вся.
                    // Молча показать их как полные значит соврать точной цифрой.
                    if isRemote, remoteFailed {
                        partialDataBanner(c, l)
                    }
                    // У чужого пустого экрана не может быть призыва «запиши
                    // первую поездку»: кнопка уводит на СВОЮ вкладку записи.
                    if agg.tripCount == 0, isRemote {
                        remoteEmptyState(c, l)
                    } else if agg.tripCount == 0 {
                        emptyState(c, l)
                    } else {
                        content(agg, c, l)
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

    @ViewBuilder
    private func content(
        _ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        let cal = Calendar.current
        let current = slice(agg, range: range, anchor: anchor, calendar: cal)
        let previous = previousSlice(agg, range: range, anchor: anchor, calendar: cal)

        if !isRemote, let trip = agg.yearAgoTrip {
            memoryCard(trip, c, l)
        }

        rangeSegment(c, l)

        if range != .all {
            periodStepper(agg, c, l, calendar: cal)
        }

        totalsCard(current, c, l)

        // Never «больше на 100%» against nothing: the line exists only when a
        // comparable period was actually driven. Its SLOT, though, is always
        // there — stepping through months used to shove the chart and both
        // sections up and down by this row's height on every tap.
        Group {
            if let previous, previous.km > 0 {
                compareLine(current: current, previous: previous, c: c, l: l)
            }
        }
        .frame(height: 18)
        .frame(maxWidth: .infinity, alignment: .leading)

        chartCard(agg, c, l, calendar: cal)

        newPlacesSection(agg, c, l, calendar: cal)

        hallOfFame(agg, c, l)

        // Архив считает фото и заметки, а `PublicTripDTO` не возит ни того, ни
        // другого — у чужого плашка всегда писала бы «фото и заметки в 0
        // поездках». Это утверждение о другом человеке, которого мы не
        // проверяли, поэтому её просто нет.
        if !isRemote {
            archiveCard(agg, c, l)
        }
    }

    /// Часть страниц не доехала. Полоска, а не пустой экран: то, что уже
    /// посчитано, — правда, просто неполная, и человек имеет право знать, что
    /// смотрит на нижнюю границу.
    private func partialDataBanner(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.accent)
            Text(AppStrings.publicDataPartial(l))
                .font(.system(size: 11.5))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { Task { await load() } } label: {
                Text(AppStrings.retry(l))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(AppTheme.accentBg, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("stats_partial_banner")
    }

    /// Отказ загрузки у чужого экрана. Отдельно от пустого состояния: писать
    /// «человек ничего не опубликовал», когда на самом деле отвалилась сеть, —
    /// это утверждение о другом человеке, которого мы не проверяли.
    private func remoteFailedState(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(c.textTertiary)
            Text(AppStrings.publicDataLoadFailed(l))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(c.text)
            Button { Task { await load() } } label: {
                Text(AppStrings.retry(l))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("stats_remote_failed")
    }

    /// Пусто у ЧУЖОГО экрана: человек либо ничего не опубликовал, либо
    /// спрятал статистику. Ни того, ни другого посторонний не исправит, так что
    /// никаких кнопок — только объяснение.
    private func remoteEmptyState(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(c.textTertiary)
            Text(AppStrings.publicMapEmptyTitle(l))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(c.text)
            Text(AppStrings.publicMapEmptyBody(l))
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("stats_remote_empty")
    }

    // MARK: - Nav row

    /// The app's own nav bar, not a local copy of one.
    ///
    /// Canon draws «Статистика» at 28 heavy inside the bar; `CustomNavBar`
    /// draws every pushed 0.6.0 screen's title at 18 bold and takes no font.
    /// Matching canon here would need an edit to the shared bar and would make
    /// this one screen the outlier among its siblings, so the house component
    /// wins — see its own note on why the artboard sizes were overridden.
    ///
    /// No `navBarInSheet`: Статистика is pushed onto the Я tab's
    /// NavigationStack (`MeDest.stats`), so there is no grabber above it — and
    /// sheet clearance on a pushed screen sinks the row 10pt too low.
    private func navRow(_ l: LanguageManager.Language) -> some View {
        // На чужом экране под заголовком стоит имя владельца: без него две
        // одинаковые «Статистики» — своя и чужая — неотличимы, а это ровно тот
        // разрыв, из которого вырос P0 «своё превью с чужими данными».
        CustomNavBar(title: AppStrings.stats(l), largeTitle: true, subtitle: ownerName)
            // The screenshot tour walks back out of Статистика by this id. The
            // back button is shared code now, so the id rides on the bar — it
            // is the only button in there.
            .accessibilityIdentifier("stats_back")
    }

    // MARK: - «Год назад в этот день» (canon 1764:135)

    private func memoryCard(
        _ trip: Trip, _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        Button {
            openTrip(trip.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.statsYearAgoToday(l))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(AppTheme.accent)

                HStack(spacing: 12) {
                    // Real tiles, not a flat plate: this card's whole claim is
                    // «you were HERE», and a decorative rectangle doesn't make it.
                    // The guard is house convention — with fewer than two points
                    // MapSnapshotPreview returns before it can mark itself
                    // failed, and shimmers forever.
                    if trip.previewCoordinates.count > 1 {
                        MapSnapshotPreview(
                            coordinates: trip.previewCoordinates,
                            tripId: trip.id,
                            height: 56, width: 80
                        )
                        .frame(width: 80, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        ZStack {
                            Rectangle().fill(c.cardAlt)
                            Image(systemName: "map.slash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(c.textTertiary)
                        }
                        .frame(width: 80, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tripName(trip, l))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        Text(memoryMeta(trip, l))
                            .font(.system(size: 12))
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stats_memory_card")
    }

    /// «118 км · 3 фото» — the photo half disappears on a trip without any.
    private func memoryMeta(_ trip: Trip, _ l: LanguageManager.Language) -> String {
        let km = "\(GarageFormat.odometer(trip.distanceKm)) \(AppStrings.km(l))"
        guard !trip.photos.isEmpty else { return km }
        return "\(km) · \(AppStrings.photosCount(l, n: trip.photos.count))"
    }

    // MARK: - Range segment (canon 1764:148)

    private func rangeSegment(
        _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        HStack(spacing: 8) {
            rangeChip(.month, AppStrings.statsRangeMonth(l), "stats_range_month", c)
            rangeChip(.year, AppStrings.statsRangeYear(l), "stats_range_year", c)
            rangeChip(.all, AppStrings.statsRangeAll(l), "stats_range_all", c)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func rangeChip(
        _ value: StatsRange, _ title: String, _ id: String, _ c: AppTheme.Colors
    ) -> some View {
        let isOn = range == value
        // `accentBg` is 8% — enough over the warm light background, invisible
        // over a dark one. Same correction the bar chart below already makes.
        let fill = scheme == .dark ? AppTheme.accent.opacity(0.18) : AppTheme.accentBg
        return Button {
            Haptics.tap()
            pickedMonth = nil
            range = value
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? AppTheme.accent : c.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? fill : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Period stepper (canon 1825:129)

    private func periodStepper(
        _ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language,
        calendar cal: Calendar
    ) -> some View {
        let canBack = step(-1, agg, calendar: cal) != nil
        let canForward = step(1, agg, calendar: cal) != nil

        return HStack(spacing: 18) {
            stepButton("chevron.left", enabled: canBack, c: c) {
                if let next = step(-1, agg, calendar: cal) { anchor = next }
            }
            Text(periodLabel(l, calendar: cal))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(c.text)
                // FIXED, not minimum: at `minWidth` the label grew for a long
                // month and shoved both chevrons outward, so the arrows moved
                // under your thumb between «Май» and «Сентябрь». The label
                // scales inside a constant slot instead.
                .frame(width: 170)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
            stepButton("chevron.right", enabled: canForward, c: c) {
                if let next = step(1, agg, calendar: cal) { anchor = next }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .animation(.easeOut(duration: 0.15), value: anchor)
    }

    private func stepButton(
        _ icon: String, enabled: Bool, c: AppTheme.Colors, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            pickedMonth = nil
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
    }

    /// One step in the current range, or nil when it would walk out of the
    /// recorded library (before the first trip) or into the future.
    private func step(_ delta: Int, _ agg: MeAggregates, calendar cal: Calendar) -> Date? {
        guard let first = agg.firstTripDate else { return nil }
        let unit: Calendar.Component = range == .year ? .year : .month
        guard let candidate = cal.date(byAdding: unit, value: delta, to: anchor) else { return nil }
        let lower = range == .year
            ? MeAggregates.yearKey(first, cal)
            : MeAggregates.monthKey(first, cal)
        let upper = range == .year
            ? MeAggregates.yearKey(Date(), cal)
            : MeAggregates.monthKey(Date(), cal)
        let value = range == .year
            ? MeAggregates.yearKey(candidate, cal)
            : MeAggregates.monthKey(candidate, cal)
        // `lower...upper` would trap if a trip carried a future date (clock
        // skew on import). Compare the bounds instead of building a range.
        return value >= lower && value <= upper ? candidate : nil
    }

    private func periodLabel(_ l: LanguageManager.Language, calendar cal: Calendar) -> String {
        range == .year
            ? String(cal.component(.year, from: anchor))
            : StatsPeriodFormat.monthYear(anchor, l)
    }

    // MARK: - Totals (canon 580:325)

    private func totalsCard(
        _ slice: StatsSlice, _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        HStack(spacing: 0) {
            totalsColumn(
                value: GarageFormat.odometer(slice.km),
                label: AppStrings.km(l),
                valueColor: AppTheme.accent, size: 26, c: c
            )
            totalsColumn(
                value: "\(slice.trips)",
                label: AppStrings.tripsGenitive(l, count: slice.trips),
                valueColor: c.text, size: 20, c: c, leadingBorder: true
            )
            totalsColumn(
                value: "\(Int(slice.hours.rounded()))",
                label: AppStrings.statsHoursOnRoad(l),
                valueColor: c.text, size: 20, c: c, leadingBorder: true
            )
        }
        .padding(.vertical, 16)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("stats_summary")
    }

    private func totalsColumn(
        value: String, label: String, valueColor: Color, size: CGFloat,
        c: AppTheme.Colors, leadingBorder: Bool = false
    ) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: size, weight: .heavy).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(c.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            if leadingBorder {
                Rectangle().fill(c.border).frame(width: 1)
            }
        }
    }

    // MARK: - Comparison line (canon 1765:119)

    private func compareLine(
        current: StatsSlice, previous: StatsSlice,
        c: AppTheme.Colors, l: LanguageManager.Language
    ) -> some View {
        // Strictly greater: two identical periods are not «больше».
        let more = current.km > previous.km
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: more ? "arrow.up" : "arrow.down")
                .font(.system(size: 11, weight: .bold))
                // Driving less isn't a failure — only «more» gets a colour.
                .foregroundStyle(more ? AppTheme.green : c.textTertiary)
            Text(AppStrings.statsVsLastPeriod(
                l, more: more,
                period: comparisonPeriod(l),
                current: GarageFormat.odometer(current.km),
                previous: GarageFormat.odometer(previous.km)
            ))
            .font(.system(size: 12))
            .foregroundStyle(c.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .accessibilityIdentifier("stats_compare")
    }

    /// `statsVsLastPeriod` wants the period already declined («в прошлом
    /// июне», «в прошлом году») and AppStrings ships no declension helper.
    /// Months come out of ICU (see `StatsPeriodFormat.monthPrepositional`);
    /// the year noun has no ICU source, so it is the one literal that has to
    /// live here. Reported for a follow-up move into `AppStrings`.
    private func comparisonPeriod(_ l: LanguageManager.Language) -> String {
        range == .year
            ? (AppStrings.statsYear(l))
            : StatsPeriodFormat.monthPrepositional(anchor, l)
    }

    // MARK: - Monthly chart (canon 580:335)

    private func chartCard(
        _ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language,
        calendar cal: Calendar
    ) -> some View {
        let model = chartModel(agg, l, calendar: cal)
        let maxKm = model.km.max() ?? 0
        // Dim bars need more alpha in dark or they vanish against the card.
        let dimFill = AppTheme.accent.opacity(scheme == .dark ? 0.22 : 0.12)
        let plotHeight: CGFloat = 130
        // Hoisted: inside the ForEach this would rebuild the symbol table
        // twelve times per render.
        let labels = StatsPeriodFormat.shortMonths(l)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppStrings.statsKmByMonth(l))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(c.text)
                Spacer()
                Text(model.badge)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(c.textSecondary)
            }

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(0..<12, id: \.self) { i in
                    let km = model.km[i]
                    let isOn = model.highlight == i
                    let h: CGFloat = maxKm > 0 && km > 0
                        ? max(4, CGFloat(km / maxKm) * plotHeight)
                        : 4
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isOn ? AppTheme.accent : dimFill)
                            .opacity(km > 0 ? 1 : 0.35)
                            .frame(height: h)
                        Text(labels[i])
                            .font(.system(size: 10, weight: isOn ? .heavy : .semibold))
                            .foregroundStyle(isOn ? AppTheme.accent : c.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.tap()
                        pickedMonth = pickedMonth == i ? nil : i
                    }
                    .overlay(alignment: popoverAlignment(i)) {
                        if pickedMonth == i {
                            monthPopover(index: i, model: model, c: c, l: l)
                        }
                    }
                }
            }
            .frame(height: plotHeight + 22)
            // A rule at last year's level for the same month — the one number
            // that says whether this bar is good or not.
            .overlay(alignment: .bottomLeading) {
                if let reference = model.reference, maxKm > 0, reference > 0 {
                    referenceRule(
                        value: reference, maxKm: maxKm, plotHeight: plotHeight,
                        label: model.referenceLabel, c: c
                    )
                }
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .animation(.easeOut(duration: 0.2), value: pickedMonth)
        .accessibilityIdentifier("stats_chart")
    }

    private func referenceRule(
        value: Double, maxKm: Double, plotHeight: CGFloat,
        label: String?, c: AppTheme.Colors
    ) -> some View {
        // 22pt of month labels sit under the plot, so the rule is lifted by
        // that much before it is raised to its own value.
        let y = plotHeight * CGFloat(min(1, value / maxKm))
        return VStack(alignment: .trailing, spacing: 2) {
            if let label {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(c.textTertiary)
            }
            Rectangle()
                .fill(c.textTertiary.opacity(0.75))
                .frame(height: 1.5)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .offset(y: -(22 + y))
        .allowsHitTesting(false)
    }

    /// Keeps the 128pt card inside the chart without measuring anything: the
    /// edge columns anchor by their own edge, everything between centres.
    private func popoverAlignment(_ i: Int) -> Alignment {
        if i <= 1 { return .topLeading }
        if i >= 10 { return .topTrailing }
        return .top
    }

    private func monthPopover(
        index: Int, model: ChartModel, c: AppTheme.Colors, l: LanguageManager.Language
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(StatsPeriodFormat.monthName(index, l))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.text)
            Text(popoverMeta(index: index, model: model, l: l))
                .font(.system(size: 11))
                .foregroundStyle(c.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(c.card)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        )
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        .allowsHitTesting(false)
    }

    /// «780 км · 11 поездок» — the tapped column, spelled out.
    private func popoverMeta(
        index: Int, model: ChartModel, l: LanguageManager.Language
    ) -> String {
        let km = "\(GarageFormat.odometer(model.km[index])) \(AppStrings.km(l))"
        return "\(km) · \(AppStrings.tripsCount(l, n: model.trips[index]))"
    }

    // MARK: - «Новые места» (canon 1766:128)

    @ViewBuilder
    private func newPlacesSection(
        _ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language,
        calendar cal: Calendar
    ) -> some View {
        let roads = newRoads(agg, calendar: cal)
        let totals = places
        if totals != nil || roads > 0 {
            sectionLabel(AppStrings.statsNewPlaces(l), c)
            VStack(alignment: .leading, spacing: 8) {
                // Reserved, not conditional: a month that opened no new road
                // used to collapse this line and pull the two sections below
                // the chart up with it.
                Group {
                    if roads > 0 {
                        Text(AppStrings.statsNewPlacesLine(
                            l, period: newPlacesPeriod(l, calendar: cal),
                            roads: roads, firstPlace: firstPlace(agg, l, calendar: cal)
                        ))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.text)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(minHeight: 17, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let totals {
                    Text(AppStrings.statsTotalsLine(
                        l, cities: totals.cities, regions: totals.regions
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .surfaceCard(cornerRadius: 16)
            .accessibilityIdentifier("stats_new_places")
        }
    }

    /// «За июнь» / «За 2024» / «За всё время» — accusative, which for RU month
    /// nouns and for a bare year is the nominative, so no declension is needed.
    private func newPlacesPeriod(_ l: LanguageManager.Language, calendar cal: Calendar) -> String {
        switch range {
        case .month: return StatsPeriodFormat.monthLower(anchor, l)
        case .year: return String(cal.component(.year, from: anchor))
        case .all: return AppStrings.statsRangeAll(l).lowercased(l)
        }
    }

    /// Region first seen inside the selected range.
    ///
    /// RU only ever gets nil: the copy reads «первый раз в …» and needs the
    /// prepositional case, while the geocoder stores nominative admin areas
    /// («Тульская область») that nothing on device can decline. A wrong case
    /// in the primary language is worse than a shorter line, so the clause is
    /// dropped there and kept in English, where the nominative is correct.
    private func firstPlace(
        _ agg: MeAggregates, _ l: LanguageManager.Language, calendar cal: Calendar
    ) -> String? {
        guard l != .ru else { return nil }
        return agg.regionFirstVisit
            .filter { contains($0.value, calendar: cal) }
            .max { $0.value < $1.value }?
            .key
    }

    private func newRoads(_ agg: MeAggregates, calendar cal: Calendar) -> Int {
        agg.roadFirstDriven.filter { contains($0, calendar: cal) }.count
    }

    // MARK: - «Доска почета» (canon 580:389)

    /// Lifetime records, not range-scoped — canon shows the identical five
    /// rows under «Июнь 2026» and under «Год · 2024».
    @ViewBuilder
    private func hallOfFame(
        _ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        let rows = records(agg, l)
        if !rows.isEmpty {
            sectionLabel(AppStrings.statsHallOfFame(l), c)
            ForEach(rows) { row in
                recordRow(row, c)
            }
        }
    }

    /// Every row that could be sourced. A record with no data is absent from
    /// the array — never a zero, never an em-dash.
    private func records(_ agg: MeAggregates, _ l: LanguageManager.Language) -> [RecordRow] {
        var rows: [RecordRow] = []

        if agg.longestTripKm > 0 {
            rows.append(RecordRow(
                id: "longest", icon: "arrow.up.right", tint: AppTheme.green,
                label: AppStrings.statsRecordLongest(l),
                subject: longestTripName(agg, l),
                value: "\(GarageFormat.odometer(agg.longestTripKm)) \(AppStrings.km(l))",
                tripId: agg.longestTripId
            ))
        }
        if agg.bestDayKm > 0, let date = agg.bestDayDate {
            rows.append(RecordRow(
                id: "bestDay", icon: "clock.fill", tint: AppTheme.accent,
                label: AppStrings.statsRecordBestDay(l),
                subject: StatsPeriodFormat.dayMonth(date, l),
                value: "\(GarageFormat.odometer(agg.bestDayKm)) \(AppStrings.km(l))",
                tripId: agg.bestDayTripId
            ))
        }
        if agg.photoPlaceCount > 0, let place = agg.photoPlace {
            rows.append(RecordRow(
                id: "photos", icon: "camera.fill", tint: AppTheme.red,
                label: AppStrings.statsRecordMostPhotos(l),
                subject: place,
                value: AppStrings.photosCount(l, n: agg.photoPlaceCount),
                tripId: nil
            ))
        }
        // A road driven once is not a champion — «47 раз» needs a repeat.
        if agg.championRoadDrives >= 2, let road = agg.championRoadName {
            rows.append(RecordRow(
                id: "road", icon: "arrow.triangle.2.circlepath", tint: AppTheme.green,
                label: AppStrings.statsRecordChampionRoad(l),
                subject: road,
                value: AppStrings.timesCount(l, n: agg.championRoadDrives),
                tripId: nil
            ))
        }
        if agg.farthestKm > 0, let place = agg.farthestPlace {
            rows.append(RecordRow(
                id: "farthest", icon: "mappin.and.ellipse", tint: AppTheme.green,
                label: AppStrings.statsRecordFarthest(l),
                subject: place,
                value: "\(GarageFormat.odometer(agg.farthestKm)) \(AppStrings.km(l))",
                tripId: agg.farthestTripId
            ))
        }
        return rows
    }

    private func recordRow(_ row: RecordRow, _ c: AppTheme.Colors) -> some View {
        let card = HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(row.tint.opacity(0.14))
                Image(systemName: row.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(row.tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.system(size: 10.5, weight: .semibold))
                                                            .foregroundStyle(c.textTertiary)
                Text(row.subject)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.value)
                .font(.system(size: 15, weight: .heavy).monospacedDigit())
                .foregroundStyle(AppTheme.accent)
                .lineLimit(1)

            if row.tripId != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .padding(13)
        .surfaceCard(cornerRadius: 16)

        return Group {
            // У чужого экрана строка НЕ тапабельна: `openTrip` шлёт
            // `.openTripDetail`, а тот ищет поездку в ЛОКАЛЬНОЙ базе. С чужим
            // UUID это прыжок на «Дом» и пустой экран вместо поездки.
            if let tripId = row.tripId, !isRemote {
                Button { openTrip(tripId) } label: { card.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
            } else {
                card
            }
        }
        // On the outside: a Button swallows identifiers set on its label, and
        // the UI test walks these rows by index.
        .accessibilityIdentifier("stats_record_row")
    }

    // MARK: - Archive plaque (canon 1767:140)

    @ViewBuilder
    private func archiveCard(
        _ agg: MeAggregates, _ c: AppTheme.Colors, _ l: LanguageManager.Language
    ) -> some View {
        if let first = agg.firstTripDate {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.statsWithTripTrackSince(
                    l, date: StatsPeriodFormat.monthYearInline(first, l)
                ))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.text)
                Text(AppStrings.statsMemoriesLine(
                    l,
                    km: GarageFormat.odometer(agg.totalKm),
                    // Trips that actually carry a photo or a note — the line
                    // says «фото и заметки в N поездках», and the total trip
                    // count answers a different question.
                    trips: agg.tripsWithMemories
                ))
                .font(.system(size: 12))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .surfaceCard(cornerRadius: 16)
            .padding(.top, 4)
            .accessibilityIdentifier("stats_archive")
        }
    }

    private func sectionLabel(_ text: String, _ c: AppTheme.Colors) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .tracking(0.26)
            .foregroundStyle(c.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .padding(.top, 6)
    }

    // MARK: - Empty state (canon 580:416)

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

    // MARK: - Range slicing (main actor, O(12) — the heavy pass already ran)

    private func slice(
        _ agg: MeAggregates, range: StatsRange, anchor: Date, calendar cal: Calendar
    ) -> StatsSlice {
        switch range {
        case .month:
            return agg.monthTotals[MeAggregates.monthKey(anchor, cal)] ?? StatsSlice()
        case .year:
            return sum(agg, year: cal.component(.year, from: anchor))
        case .all:
            return agg.monthTotals.values.reduce(into: StatsSlice()) { $0.add($1) }
        }
    }

    private func previousSlice(
        _ agg: MeAggregates, range: StatsRange, anchor: Date, calendar cal: Calendar
    ) -> StatsSlice? {
        switch range {
        case .month:
            // Same month a year earlier — what the chart's reference rule marks.
            return agg.monthTotals[MeAggregates.monthKey(anchor, cal) - 12]
        case .year:
            return sum(agg, year: cal.component(.year, from: anchor) - 1)
        case .all:
            return nil
        }
    }

    private func sum(_ agg: MeAggregates, year: Int) -> StatsSlice {
        var total = StatsSlice()
        for m in 0..<12 {
            if let bucket = agg.monthTotals[year * 12 + m] { total.add(bucket) }
        }
        return total
    }

    private func contains(_ date: Date, calendar cal: Calendar) -> Bool {
        switch range {
        case .month:
            return MeAggregates.monthKey(date, cal) == MeAggregates.monthKey(anchor, cal)
        case .year:
            return MeAggregates.yearKey(date, cal) == MeAggregates.yearKey(anchor, cal)
        case .all:
            return true
        }
    }

    private func chartModel(
        _ agg: MeAggregates, _ l: LanguageManager.Language, calendar cal: Calendar
    ) -> ChartModel {
        var model = ChartModel()
        let nowKey = MeAggregates.monthKey(Date(), cal)

        switch range {
        case .month, .year:
            let year = cal.component(.year, from: anchor)
            model.badge = String(year)
            for m in 0..<12 {
                let bucket = agg.monthTotals[year * 12 + m] ?? StatsSlice()
                model.km[m] = bucket.km
                model.trips[m] = bucket.trips
            }
            if range == .month {
                model.highlight = cal.component(.month, from: anchor) - 1
                // Only draw the rule when there is a real month behind it.
                let lastYear = agg.monthTotals[MeAggregates.monthKey(anchor, cal) - 12]
                if let lastYear, lastYear.km > 0 {
                    model.reference = lastYear.km
                    model.referenceLabel = StatsPeriodFormat.monthYearLower(
                        cal.date(byAdding: .year, value: -1, to: anchor) ?? anchor, l
                    )
                }
            } else if year == cal.component(.year, from: Date()) {
                model.highlight = cal.component(.month, from: Date()) - 1
            }
        case .all:
            // A column is «every June there has ever been» — the badge says so,
            // so nobody reads it as one particular year.
            model.badge = AppStrings.statsRangeAll(l)
            for (key, bucket) in agg.monthTotals {
                let m = ((key % 12) + 12) % 12
                model.km[m] += bucket.km
                model.trips[m] += bucket.trips
            }
            model.highlight = ((nowKey % 12) + 12) % 12
        }
        return model
    }

    // MARK: - Helpers

    private func openTrip(_ id: UUID) {
        Haptics.tap()
        if let onOpenTrip {
            onOpenTrip(id)
        } else {
            NotificationCenter.default.post(name: .openTripDetail, object: id)
        }
    }

    private func tripName(_ trip: Trip, _ l: LanguageManager.Language) -> String {
        if let t = trip.title, !t.isEmpty { return t }
        if let r = trip.region, !r.isEmpty { return r }
        return ProfileDateFormat.dayMonth(trip.startDate, lang: l)
    }

    private func longestTripName(_ agg: MeAggregates, _ l: LanguageManager.Language) -> String {
        if let t = agg.longestTripTitle, !t.isEmpty { return t }
        if let r = agg.longestTripRegion, !r.isEmpty { return r }
        if let d = agg.longestTripDate { return ProfileDateFormat.dayMonth(d, lang: l) }
        return "—"
    }

    // MARK: - Data

    private func load() async {
        // Fetch (cache-aware) on main, crunch off-main, publish on main.
        let count = tripManager.fetchTripCount()
        let lastDate = tripManager.fetchLastTripDate()
        let trips: [Trip]
        loadGeneration += 1
        let generation = loadGeneration
        if let source {
            // ЧУЖОЙ экран. `StatsCache` — кэш библиотеки ВЛАДЕЛЬЦА, ключ у него
            // «сколько поездок и когда последняя», и на чужом аккаунте он бы
            // совпал случайно и подсунул чужому профилю свои поездки. Ровно тот
            // класс ошибки, который аудит профиля занёс в P0, поэтому здесь
            // кэша нет вовсе.
            let result = await source.load()
            guard generation == loadGeneration else { return }
            trips = result.trips
            remoteFailed = result.failed
        } else if let cached = StatsCache.tripsIfValid(currentCount: count, currentLastDate: lastDate) {
            trips = cached
        } else {
            trips = tripManager.fetchTrips()
            StatsCache.update(trips: trips, count: count, lastDate: lastDate)
        }
        // Small table, main-actor viewContext — the same way RouteMapView
        // reads territory. Crossing into the detached pass as plain values.
        // У чужого экрана дорог нет и быть не может: RoadEntity локальная.
        let roads = isRemote ? [] : RoadCollectionManager().fetchRoads()

        let computed = await Task.detached(priority: .userInitiated) {
            MeAggregates.compute(
                trips: trips, roads: roads, includeFarthestPoint: true,
                now: Date(), calendar: Calendar.current
            )
        }.value
        guard !Task.isCancelled, generation == loadGeneration else { return }
        agg = computed
        // Park on the newest month that holds a trip, not on an empty «now».
        if let last = computed.lastTripDate { anchor = last }

        await loadPlaces(trips: trips, count: count, lastDate: lastDate, generation: generation)
    }

    /// «Всего: N городов · N регионов». Cities exist only as atlas coverage —
    /// `TripEntity.region` is the geocoder's admin area, so the count has to
    /// come from the same build Моя карта uses, or the two screens would
    /// disagree. Cached against the library fingerprint: this is the slowest
    /// thing on the screen and it does not move between range changes.
    private func loadPlaces(trips: [Trip], count: Int, lastDate: Date?, generation: Int) async {
        if !isRemote, let cached = StatsPlacesCache.value(count: count, lastDate: lastDate) {
            places = cached
            return
        }
        guard !trips.isEmpty else { return }
        await RegionAtlas.shared.loadIfNeeded()
        // Таблица владельца читается здесь (main-actor viewContext), а вот
        // ЧУЖОЙ туман считается уже в detached: у человека с сотнями публичных
        // поездок это сотни декодов полилиний плюс геохеш на каждые 300 м
        // пути — на главном акторе это многосекундная заморозка. `MyMapViewModel`
        // делает ровно то же внутри detached, и расхождение было случайным.
        let ownHashes = isRemote ? nil : TerritoryManager().visitedGeohashes
        let remote = isRemote
        let atlas = RegionAtlas.shared
        let built = await Task.detached(priority: .utility) { () -> StatsPlaces in
            let hashes = remote
                ? TerritoryManager.geohashes(
                    fromTrips: trips.map { $0.previewCoordinates }, precision: 6)
                : (ownHashes ?? [])
            let exploration = MapExploration.build(
                trips: trips, visitedHashes: hashes, atlas: atlas
            )
            return StatsPlaces(
                cities: exploration.regions.reduce(0) { $0 + $1.visitedCityCount },
                regions: exploration.regions.count
            )
        }.value
        // Тот же гейт, что у `agg`: обогнавший старый прогон иначе накрыл бы
        // свежие города и регионы урезанными.
        guard !Task.isCancelled, generation == loadGeneration else { return }
        if !isRemote { StatsPlacesCache.store(built, count: count, lastDate: lastDate) }
        places = built
    }
}

// MARK: - Screen-local models

extension StatsScreenView {
    enum StatsRange {
        case month
        case year
        case all
    }

    /// One record card's finished content — assembled where the language is,
    /// so the aggregate stays raw numbers.
    struct RecordRow: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let label: String
        let subject: String
        let value: String
        /// Where the row goes on tap; nil rows carry no chevron and no gesture
        /// (a region or a road is not one trip).
        let tripId: UUID?
    }

    struct ChartModel {
        var km = [Double](repeating: 0, count: 12)
        var trips = [Int](repeating: 0, count: 12)
        var badge = ""
        var highlight: Int?
        var reference: Double?
        var referenceLabel: String?
    }

    struct StatsPlaces {
        let cities: Int
        let regions: Int
    }
}

/// Lives beside `StatsCache` in spirit but not in file: it caches the atlas
/// pass, not the trips, and only this screen asks for it.
private enum StatsPlacesCache {
    private static var cached: StatsScreenView.StatsPlaces?
    private static var cachedCount = -1
    private static var cachedLastDate: Date?

    static func value(count: Int, lastDate: Date?) -> StatsScreenView.StatsPlaces? {
        guard cachedCount == count, cachedLastDate == lastDate else { return nil }
        return cached
    }

    static func store(_ value: StatsScreenView.StatsPlaces, count: Int, lastDate: Date?) {
        cached = value
        cachedCount = count
        cachedLastDate = lastDate
    }
}

// MARK: - Period formatting

/// Everything the screen needs from a date, in both languages, without a
/// single month name written out in Swift — ICU owns the words, this owns the
/// case transforms. RU prepositional is derived from the genitive form ICU
/// gives for `MMMM` («июня» → «июне»), which is regular for all twelve.
enum StatsPeriodFormat {
    // House pattern (see `ProfileDateFormat`): one formatter per pattern per
    // language, built once. These run inside `body` — the stepper label
    // re-renders on every tap — and constructing a `DateFormatter` each time
    // is the expensive half of the call.
    private static let standaloneMonths = LocalizedDateFormatter.patterns("LLLL")
    private static let genitiveMonths = LocalizedDateFormatter.patterns("MMMM")
    private static let monthYearInlineFmt = LocalizedDateFormatter.templates("MMMMyyyy")
    private static let dayMonthFmt = LocalizedDateFormatter.templates("dMMMM")
    private static let ruLocale = LanguageManager.Language.ru.locale

    /// ICU's standalone (nominative) month — «Июнь», "June".
    private static func standalone(_ date: Date, _ l: LanguageManager.Language) -> String {
        standaloneMonths[l]?.string(from: date) ?? ""
    }

    private static func yearText(_ date: Date) -> String {
        String(Calendar.current.component(.year, from: date))
    }

    /// «Июнь 2026» / "June 2026" — the stepper label.
    static func monthYear(_ date: Date, _ l: LanguageManager.Language) -> String {
        "\(standalone(date, l).capitalized) \(yearText(date))"
    }

    /// «марта 2024» / "March 2024" — mid-sentence, so RU takes the genitive
    /// form ICU gives `MMMM` in a format context.
    static func monthYearInline(_ date: Date, _ l: LanguageManager.Language) -> String {
        monthYearInlineFmt[l]?.string(from: date) ?? ""
    }

    /// «июнь 2025» / "June 2025" — the chart's reference-rule label.
    static func monthYearLower(_ date: Date, _ l: LanguageManager.Language) -> String {
        "\(monthLower(date, l)) \(yearText(date))"
    }

    /// «июнь» / "June" — reads after «За …», where the RU accusative of every
    /// month noun is identical to its nominative.
    static func monthLower(_ date: Date, _ l: LanguageManager.Language) -> String {
        let name = standalone(date, l)
        return l == .ru ? name.lowercased(with: ruLocale) : name.capitalized
    }

    /// «июне» / "June" — reads after «в прошлом …».
    static func monthPrepositional(_ date: Date, _ l: LanguageManager.Language) -> String {
        guard l == .ru else { return standalone(date, l).capitalized }
        // Genitive → prepositional: «января» → «январе», «мая» → «мае». The
        // final -а/-я becomes -е for all twelve, so the case comes out of ICU
        // plus one rule instead of a table of month names written in Swift.
        let genitive = (genitiveMonths[.ru]?.string(from: date) ?? "").lowercased(with: ruLocale)
        guard let last = genitive.last, last == "а" || last == "я" else { return genitive }
        return String(genitive.dropLast()) + "е"
    }

    /// «12 октября» / "October 12" — the best-day record's subject.
    static func dayMonth(_ date: Date, _ l: LanguageManager.Language) -> String {
        dayMonthFmt[l]?.string(from: date) ?? ""
    }

    /// «Сентябрь» / "September" for a bare 0-based column index.
    static func monthName(_ index: Int, _ l: LanguageManager.Language) -> String {
        let symbols = standaloneMonths[l]?.standaloneMonthSymbols ?? []
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index].capitalized
    }

    /// «Янв…Дек» / "Jan…Dec" axis labels. Sliced off the standalone names
    /// rather than read from `shortMonthSymbols`: ICU's abbreviated RU list is
    /// the FORMAT variant («мая», genitive) and carries trailing periods,
    /// neither of which belongs on an axis. The first three letters of the
    /// nominative name are the canon spelling in both languages.
    static func shortMonths(_ l: LanguageManager.Language) -> [String] {
        let symbols = standaloneMonths[l]?.standaloneMonthSymbols ?? []
        guard symbols.count == 12 else {
            return ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        }
        return symbols.map { String($0.prefix(3)).capitalized }
    }
}

// MARK: - Me-tab aggregates (§3 — client-side only, every number real)

/// Pure aggregate over `[Trip]` shared by the Я canon (strip regions, hero
/// gating, moments, history) and the Статистика screen. `compute` is a pure
/// function — safe to run inside `Task.detached` and trivially unit-testable.
struct MeAggregates {
    // All-time
    var tripCount = 0
    /// Trips that carry a photo or a note — what «фото и заметки в N поездках»
    /// is actually counting. The total trip count answers a different question
    /// and made the archive plaque claim every drive was documented.
    var tripsWithMemories = 0
    var totalKm = 0.0
    var totalHours = 0.0
    var regionsAllTime = 0
    var longestTripKm = 0.0
    var longestTripTitle: String?
    var longestTripRegion: String?
    var longestTripDate: Date?
    var longestTripId: UUID?
    /// Max Σ duration over any single calendar day (all-time).
    var maxDayDuration: TimeInterval = 0
    var firstTripDate: Date?
    var lastTripDate: Date?

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

    // MARK: Статистика (every calendar month the library touches)

    /// Σ km / trips / hours per calendar month, keyed by `monthKey`. Every
    /// range the screen can ask for — one month, one year, all time, and the
    /// period before each — is a lookup or a 12-term sum over this, so the
    /// segment and the stepper never trigger a second pass over the library.
    var monthTotals: [Int: StatsSlice] = [:]
    /// When each region was first driven — feeds «первый раз в …».
    var regionFirstVisit: [String: Date] = [:]
    /// First-drive dates of collected roads — feeds «+2 новые дороги».
    var roadFirstDriven: [Date] = []

    // MARK: Доска почета (lifetime records, raw — the view formats them)

    var bestDayKm = 0.0
    var bestDayDate: Date?
    /// The biggest single trip of that day, so the row has somewhere to go.
    var bestDayTripId: UUID?
    /// Region (or, with no region on file, trip name) holding the most photos.
    var photoPlace: String?
    var photoPlaceCount = 0
    var championRoadName: String?
    var championRoadDrives = 0
    var farthestPlace: String?
    var farthestKm = 0.0
    var farthestTripId: UUID?

    /// `year * 12 + (month - 1)` — orderable, so «the month before» is `-1`
    /// and «the same month last year» is `-12`, across year boundaries.
    static func monthKey(_ date: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.year, .month], from: date)
        return (c.year ?? 0) * 12 + ((c.month ?? 1) - 1)
    }

    static func yearKey(_ date: Date, _ cal: Calendar) -> Int {
        cal.component(.year, from: date)
    }

    /// - Parameters:
    ///   - roads: collected `RoadEntity` rows, for «Дорога-чемпион» and the
    ///     new-roads counter. Defaulted so the Я tab's call site is unchanged.
    ///   - includeFarthestPoint: also walk every trip's preview polyline to
    ///     find the point furthest from home. Off by default because it is the
    ///     only part of this function that decodes geometry, and the Я tab —
    ///     which runs this on every appearance — has no use for it.
    static func compute(
        trips: [Trip],
        roads: [RoadCard] = [],
        includeFarthestPoint: Bool = false,
        now: Date,
        calendar cal: Calendar
    ) -> MeAggregates {
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
        var kmByDayAll: [Date: Double] = [:]
        var bestTripOfDay: [Date: (km: Double, id: UUID)] = [:]
        var photosByPlace: [String: Int] = [:]
        var longest: Trip?
        for t in trips {
            a.totalKm += t.distanceKm
            if !t.photos.isEmpty || (t.tripDescription?.isEmpty == false) {
                a.tripsWithMemories += 1
            }
            a.totalHours += t.duration / 3600
            if let r = t.region, !r.isEmpty { regionsAll.insert(r) }
            let day = cal.startOfDay(for: t.startDate)
            durationByDay[day, default: 0] += t.duration
            kmByDayAll[day, default: 0] += t.distanceKm
            if t.distanceKm > (bestTripOfDay[day]?.km ?? -1) {
                bestTripOfDay[day] = (t.distanceKm, t.id)
            }
            if t.distanceKm > (longest?.distanceKm ?? -1) { longest = t }

            a.monthTotals[monthKey(t.startDate, cal), default: StatsSlice()]
                .add(km: t.distanceKm, hours: t.duration / 3600)

            if a.firstTripDate == nil || t.startDate < (a.firstTripDate ?? t.startDate) {
                a.firstTripDate = t.startDate
            }
            if a.lastTripDate == nil || t.startDate > (a.lastTripDate ?? t.startDate) {
                a.lastTripDate = t.startDate
            }
            if let r = t.region, !r.isEmpty {
                if let seen = a.regionFirstVisit[r] {
                    a.regionFirstVisit[r] = min(seen, t.startDate)
                } else {
                    a.regionFirstVisit[r] = t.startDate
                }
            }
            // Photos are grouped by place, per canon («Карелия · 14 фото»);
            // a trip with no region still counts, under its own name.
            if !t.photos.isEmpty {
                let place = (t.region?.isEmpty == false ? t.region : t.title) ?? ""
                if !place.isEmpty { photosByPlace[place, default: 0] += t.photos.count }
            }
        }
        a.regionsAllTime = regionsAll.count
        a.maxDayDuration = durationByDay.values.max() ?? 0
        if let longest {
            a.longestTripKm = longest.distanceKm
            a.longestTripTitle = longest.title
            a.longestTripRegion = longest.region
            a.longestTripDate = longest.startDate
            a.longestTripId = longest.id
        }

        // Best day by km, all-time. Deterministic: km first, then the earlier
        // day, so two identical days always resolve the same way.
        if let best = kmByDayAll.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }) {
            a.bestDayKm = best.value
            a.bestDayDate = best.key
            a.bestDayTripId = bestTripOfDay[best.key]?.id
        }

        if let best = photosByPlace.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }) {
            a.photoPlace = best.key
            a.photoPlaceCount = best.value
        }

        a.roadFirstDriven = roads.map(\.firstDriven)
        if let champion = roads.max(by: { lhs, rhs in
            lhs.timesDriven == rhs.timesDriven
                ? lhs.name > rhs.name
                : lhs.timesDriven < rhs.timesDriven
        }) {
            a.championRoadName = champion.name
            a.championRoadDrives = champion.timesDriven
        }

        if includeFarthestPoint { a.computeFarthestPoint(trips: trips) }

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
        // The window is deliberate and locked by
        // `MeAggregatesTests.testYearAgoTripPicksBestWithinThreeDayWindow`:
        // an exact-day match almost never has a trip behind it, and a card
        // that never appears is worth less than one that is three days loose.
        if let target = cal.date(byAdding: .year, value: -1, to: now) {
            a.yearAgoTrip = trips
                .filter { abs($0.startDate.timeIntervalSince(target)) < 3 * 86_400 }
                .max { $0.distanceKm < $1.distanceKm }
        }

        // «Новый регион» — the most recent first-visit that happened this
        // year; suppressed when the user has ever seen fewer than 2 regions.
        if regionsAll.count >= 2 {
            a.newRegion = a.regionFirstVisit
                .filter { $0.value >= yearStart }
                .max { $0.value < $1.value }?
                .key
        }

        a.recentTrips = Array(trips.sorted { $0.startDate > $1.startDate }.prefix(10))
        return a
    }

    /// «Самая дальняя точка»: the furthest any route ever got from home.
    ///
    /// Home is not stored anywhere, so it is inferred — the ~5 km cell that
    /// starts the most trips. That is the only anchor the library actually
    /// supports; measuring from a trip's own start would answer a different
    /// question (how far that one drive reached) and would tie the record to
    /// whichever trip happened to be longest.
    private mutating func computeFarthestPoint(trips: [Trip]) {
        var startCells: [String: (count: Int, lat: Double, lon: Double)] = [:]
        for t in trips {
            guard let start = t.previewCoordinates.first else { continue }
            let key = Self.cellKey(start)
            var cell = startCells[key] ?? (count: 0, lat: 0, lon: 0)
            cell.count += 1
            cell.lat += start.latitude
            cell.lon += start.longitude
            startCells[key] = cell
        }
        guard let home = startCells.max(by: { lhs, rhs in
            lhs.value.count == rhs.value.count ? lhs.key > rhs.key : lhs.value.count < rhs.value.count
        })?.value, home.count > 0 else { return }
        let origin = CLLocationCoordinate2D(
            latitude: home.lat / Double(home.count),
            longitude: home.lon / Double(home.count)
        )

        for t in trips {
            for coord in t.previewCoordinates {
                let km = Self.haversineKm(origin, coord)
                guard km > farthestKm else { continue }
                farthestKm = km
                farthestTripId = t.id
                // `Trip.region` is where the trip STARTED — naming it here made
                // the record read «Краснодарский край» for a run that ended at
                // Elbrus, i.e. it named the one place the farthest point is
                // guaranteed not to be. Nothing in the model stores a place for
                // an arbitrary coordinate, so the honest label is the trip
                // itself; the distance beside it is the fact this row is about.
                farthestPlace = (t.title?.isEmpty == false ? t.title : t.region)
            }
        }
        if farthestPlace?.isEmpty != false {
            farthestKm = 0
            farthestTripId = nil
            farthestPlace = nil
        }
    }

    /// ~0.05° cells — about 5 km across at Russian latitudes, which is one
    /// "home" without merging the next town over.
    private static func cellKey(_ c: CLLocationCoordinate2D) -> String {
        "\(Int((c.latitude * 20).rounded(.down)))_\(Int((c.longitude * 20).rounded(.down)))"
    }

    private static func haversineKm(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        let earthKm = 6371.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * earthKm * asin(min(1, sqrt(h)))
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

/// One period's three numbers. Both a monthly bucket and any sum of them —
/// the range slicing is just `reduce`, so nothing about a period is special.
struct StatsSlice {
    var km = 0.0
    var trips = 0
    var hours = 0.0

    mutating func add(km: Double, hours: Double) {
        self.km += km
        self.hours += hours
        trips += 1
    }

    mutating func add(_ other: StatsSlice) {
        km += other.km
        hours += other.hours
        trips += other.trips
    }
}
