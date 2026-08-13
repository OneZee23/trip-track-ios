import SwiftUI
import Charts
import CoreLocation

// Shared building blocks of the 6.1.0 trip-detail «poster» redesign, used
// by both TripDetailView (own trip) and SocialTripDetailView (others').
// Poster chrome (scrims, circle buttons), section cards (charts, moving/
// stops bar, description, achievements), the publish-with-description
// sheet and the publish progress/error toasts live here so the two detail
// screens can't drift apart visually.

// MARK: - Formatting helpers

enum TripDetailFormat {
    /// «186 м · 14:05» — the touched altitude sample and when it was reached.
    /// Falls back to the bare value for a trip whose points carry no clock.
    static func chartAltitudeReadout(
        _ pt: DetailChartPoint,
        lang: LanguageManager.Language
    ) -> String {
        let value = "\(Int(pt.y.rounded())) \(AppStrings.m(lang))"
        guard let date = pt.date else { return value }
        return "\(value) · \(chartClock.string(from: date))"
    }

    /// «94 км/ч · 14:05».
    static func chartSpeedReadout(
        _ pt: DetailChartPoint,
        lang: LanguageManager.Language
    ) -> String {
        let value = "\(Int(pt.y.rounded())) \(AppStrings.kmh(lang))"
        guard let date = pt.date else { return value }
        return "\(value) · \(chartClock.string(from: date))"
    }

    private static let chartClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// «23.4» — one decimal, and a decimal comma where the language uses one.
    static func fuelVolume(_ litres: Double) -> String {
        Self.oneDecimal.string(from: NSNumber(value: litres)) ?? String(format: "%.1f", litres)
    }

    /// «1 310» — grouped, because a four-digit price without a separator reads
    /// as a number of metres.
    static func money(_ amount: Double) -> String {
        Self.grouped.string(from: NSNumber(value: amount.rounded())) ?? String(format: "%.0f", amount)
    }

    private static let oneDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        f.usesGroupingSeparator = false
        return f
    }()

    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        // A narrow no-break space is what the canon draws («1 310») and what
        // keeps the group from wrapping mid-number in a 159pt tile.
        f.groupingSeparator = "\u{202F}"
        return f
    }()

    /// ВРЕМЯ / В ДВИЖЕНИИ / СТОЯНКИ as the canon writes them — «4 ч 58 мин»,
    /// with the numbers coloured and the units small beside them.
    ///
    /// Never a clock reading: «0:46» is read as a time of day, and «3:40» does
    /// not say whether it means hours or minutes. Units say it outright.
    static func durationSegments(
        _ seconds: TimeInterval,
        lang: LanguageManager.Language
    ) -> [DetailStatCard.Segment] {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let ru = lang == .ru
        if h > 0 {
            let hourPart = DetailStatCard.Segment(value: "\(h)", unit: ru ? "ч" : "h")
            // «4 ч» alone, not «4 ч 0 мин» — a zero component is noise.
            guard m > 0 else { return [hourPart] }
            return [hourPart, DetailStatCard.Segment(value: "\(m)", unit: ru ? "мин" : "min")]
        }
        if m > 0 {
            return [DetailStatCard.Segment(value: "\(m)", unit: ru ? "мин" : "min")]
        }
        // Under a minute — seconds, so a two-minute test drive isn't «0 мин».
        return [DetailStatCard.Segment(value: "\(total)", unit: ru ? "сек" : "s")]
    }

    private static let posterDateFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMMM"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "MMMM d"
        return (ru, en)
    }()

    /// Pixel-font hero line — «14 АПРЕЛЯ · ТВЕРСКАЯ ОБЛ.» Region omitted
    /// when the trip has none (geocode pending / disabled).
    static func posterDateLine(date: Date, region: String?, lang: LanguageManager.Language) -> String {
        let f = lang == .ru ? posterDateFormatters.ru : posterDateFormatters.en
        var line = f.string(from: date).uppercased()
        // Region follows the APP language (stored raw geocoder string may
        // be in either) — same rule as the feed card meta line.
        if let region = RegionDisplay.localized(region, language: lang), !region.isEmpty {
            line += " · \(region.uppercased())"
        }
        return line
    }
}

// MARK: - Poster chrome

enum PosterPalette {
    /// Theme-invariant poster navy (#141828) — the hero is deliberately
    /// dark-on-fixed-poster in both light and dark themes.
    static let navy = Color(red: 0x14/255, green: 0x18/255, blue: 0x28/255)
    static let ctaText = Color(red: 0x16/255, green: 0x1B/255, blue: 0x2C/255)
}

/// Legibility gradient over the poster canvas: darkens the top (status bar /
/// buttons) and the bottom (date + title + CTA) while keeping the route
/// bright in the middle band.
struct PosterLegibilityOverlay: View {
    var topOpacity: Double = 0.4
    var clearFrom: Double = 0.30
    var clearTo: Double = 0.55
    var bottomOpacity: Double = 0.85

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: PosterPalette.navy.opacity(topOpacity), location: 0),
                .init(color: PosterPalette.navy.opacity(0), location: clearFrom),
                .init(color: PosterPalette.navy.opacity(0), location: clearTo),
                .init(color: PosterPalette.navy.opacity(bottomOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

/// Status-bar scrim — 96pt black fade pinned to the top of the poster.
struct PosterTopScrim: View {
    var body: some View {
        LinearGradient(
            colors: [.black.opacity(0.45), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 96)
        .allowsHitTesting(false)
    }
}

/// 34pt circular glass button used on the poster (back / share / more).
struct PosterCircleButton: View {
    let systemImage: String
    var accessibilityLabelText: String? = nil
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        let button = Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.4), in: Circle())
        }
        // Only override when the caller provides a localized label — the
        // old `?? systemImage` fallback made VoiceOver announce raw SF
        // names ("chevron.left"). Without an override, SF Symbols supply
        // their own localized description.
        if let accessibilityLabelText {
            button.accessibilityLabel(accessibilityLabelText)
        } else {
            button
        }
    }
}

// MARK: - Section header + chips

/// Unified section header — Inter ExtraBold 17 (Figma: «Детали»,
/// «Профиль высоты», «Описание», «Фото · 4», …).
struct DetailSectionHeader: View {
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(AppTheme.colors(for: scheme).text)
    }
}

/// White pill chip of the top-of-body row («12:30 – 17:28» · «Honda Civic»
/// · «Видна всем»). Content-agnostic so callers can mix text, emoji and
/// small icons while the surface stays identical.
struct DetailChipSurface<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        HStack(spacing: 5) { content }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(c.textSecondary)
            .padding(.leading, 11)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(c.card)
                    .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
            }
    }
}

// MARK: - Charts

struct DetailChartPoint: Identifiable {
    let id: Int
    /// Cumulative distance from the start, km.
    let x: Double
    /// Altitude (m) or speed (km/h) depending on the series — the MEAN over
    /// this slice of the route.
    let y: Double
    /// When this sample was recorded. Carried so a touch on the chart can
    /// answer «where on the drive was this?» in the trip's own clock, the way
    /// the canon's tooltip does («186 м · 14:05 / 212-й км»). Nil for trips
    /// that arrived without timestamps.
    var date: Date?
    /// Lowest and highest value inside the slice. On a ten-hour drive one
    /// pixel of chart covers minutes of driving, and a mean alone would erase
    /// every burst and every stop; the band drawn between these two is what
    /// keeps the shape of the drive honest at that scale.
    var yMin: Double = .nan
    var yMax: Double = .nan

    var hasBand: Bool { !yMin.isNaN && !yMax.isNaN && yMax - yMin > 0.5 }
}

/// Turns a whole track into a fixed number of evenly spaced samples along the
/// route — the only shape that survives both a five-minute hop and a ten-hour
/// drive.
///
/// Buckets are cut by DISTANCE, not by sample index. Index buckets look right
/// until the first traffic jam: standing still for half an hour is a thousand
/// GPS points at the same kilometre, which under index sampling swallow most of
/// the budget and draw a vertical wall on the chart, while the motorway either
/// side of it gets a handful of points.
enum ChartSeriesBuilder {
    /// Enough for one sample every couple of points across a phone-width card,
    /// and few enough that Swift Charts stays smooth while a finger drags over
    /// it.
    static let bucketCount = 200

    struct Sample {
        let km: Double
        let mean: Double
        let low: Double
        let high: Double
        let date: Date?
    }

    /// - Parameters:
    ///   - cumulativeKm: distance from the start for each track point.
    ///   - values: the quantity being charted, one per track point.
    static func buckets(
        cumulativeKm: [Double],
        values: [Double],
        dates: [Date],
        totalKm: Double
    ) -> [Sample] {
        guard cumulativeKm.count == values.count, cumulativeKm.count > 1, totalKm > 0.05 else {
            return []
        }
        let n = min(bucketCount, cumulativeKm.count)
        let width = totalKm / Double(n)
        guard width > 0 else { return [] }

        var sum = [Double](repeating: 0, count: n)
        var count = [Int](repeating: 0, count: n)
        var low = [Double](repeating: .infinity, count: n)
        var high = [Double](repeating: -.infinity, count: n)
        var firstDate = [Date?](repeating: nil, count: n)

        for i in 0..<cumulativeKm.count {
            let idx = min(n - 1, max(0, Int(cumulativeKm[i] / width)))
            let v = values[i]
            sum[idx] += v
            count[idx] += 1
            low[idx] = Swift.min(low[idx], v)
            high[idx] = Swift.max(high[idx], v)
            if firstDate[idx] == nil, i < dates.count { firstDate[idx] = dates[i] }
        }

        var out: [Sample] = []
        out.reserveCapacity(n)
        for i in 0..<n where count[i] > 0 {
            out.append(
                Sample(
                    // Middle of the slice: the sample stands for the whole of
                    // it, not for its left edge.
                    km: (Double(i) + 0.5) * width,
                    mean: sum[i] / Double(count[i]),
                    low: low[i],
                    high: high[i],
                    date: firstDate[i]
                )
            )
        }
        return out
    }
}

// MARK: - Chart scrubbing

/// The value under the finger: which sample, and where to draw the bubble.
private struct ChartScrubSelection: Equatable {
    let point: DetailChartPoint
    /// x in the chart's own coordinate space, for positioning the tooltip.
    let plotX: CGFloat
    /// y of the sample itself, so the bubble can sit clear of the dot.
    let plotY: CGFloat

    /// Sample identity is enough — two selections of the same point at the
    /// same place are the same selection, and that is what keeps the haptic
    /// from firing on every pixel of a drag.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.point.id == rhs.point.id && lhs.plotX == rhs.plotX
    }
}

/// Dark bubble over the touched sample — value and time on top, the kilometre
/// underneath (Figma 465:…).
private struct ChartScrubTooltip: View {
    let primary: String
    let secondary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(primary)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text(secondary)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 28/255, green: 28/255, blue: 30/255))
        )
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .fixedSize()
        // The bubble follows the finger; it must never eat the touches that
        // are moving it.
        .allowsHitTesting(false)
    }
}

private extension Array where Element == DetailChartPoint {
    /// Sample nearest to a distance along the route.
    func nearest(toKm km: Double) -> DetailChartPoint? {
        self.min { abs($0.x - km) < abs($1.x - km) }
    }
}

/// Makes a chart answer a finger: touch or drag anywhere along it and the
/// nearest sample is marked and read out.
///
/// Both charts plot distance on x, so the whole interaction is "which kilometre
/// is under the finger" — the mapping back from a screen point comes from the
/// chart proxy, so it stays correct whatever the card's width or the trip's
/// length.
private struct ChartScrub<Tooltip: View>: ViewModifier {
    let series: [DetailChartPoint]
    @Binding var selection: ChartScrubSelection?
    @ViewBuilder let tooltip: (DetailChartPoint) -> Tooltip

    /// Measured, because the bubble is centred on the sample and then kept
    /// inside the card — both need its width. Seeded with a plausible value so
    /// the first frame is not wildly off before the measurement lands.
    @State private var tooltipWidth: CGFloat = 150

    func body(content: Content) -> some View {
        content.chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] }
                // Put a finger down and slide — no hold, no aiming. The
                // surface hands the touch back to the page the moment the
                // movement turns out to be vertical, so scrolling past the
                // chart still works exactly as it did.
                HorizontalScrubSurface { location in
                    scrub(to: location, proxy: proxy, plot: plot)
                }
                    // Lifting the finger keeps the readout on screen: the
                    // number is the reason you touched the chart, and a bubble
                    // that vanishes with the touch can only be read while your
                    // own thumb is over it.
                    .overlay {
                        if let sel = selection, let plot {
                            tooltip(sel.point)
                                .background(
                                    GeometryReader { t in
                                        Color.clear.preference(
                                            key: TooltipWidthKey.self,
                                            value: t.size.width
                                        )
                                    }
                                )
                                .onPreferenceChange(TooltipWidthKey.self) { w in
                                    guard w > 0 else { return }
                                    tooltipWidth = w
                                }
                                // `.position` places a view by its CENTRE,
                                // which is exactly how a callout relates to the
                                // point it describes — and unlike an alignment
                                // guide it survives being wrapped in padding.
                                .position(
                                    x: centreX(for: sel, in: plot),
                                    y: centreY(for: sel, in: plot)
                                )
                                // The bubble itself opts out of hit testing,
                                // but the measuring backdrop wrapped around it
                                // here does not — and `Color.clear` takes
                                // touches in SwiftUI. Left alone it parked a
                                // dead patch of chart wherever the readout had
                                // last landed, so the chart stopped answering
                                // exactly where you had just touched it.
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    /// Move the readout to whatever sample sits under this point.
    private func scrub(to location: CGPoint, proxy: ChartProxy, plot: CGRect?) {
        guard let plot else { return }
        let x = location.x - plot.minX
        guard let km: Double = proxy.value(atX: x),
              let point = series.nearest(toKm: km),
              let px = proxy.position(forX: point.x)
        else { return }
        let py = proxy.position(forY: point.y) ?? 0
        let new = ChartScrubSelection(
            point: point,
            plotX: px + plot.minX,
            plotY: py + plot.minY
        )
        guard selection != new else { return }
        Haptics.selection()
        selection = new
    }

    /// Centred on the sample, then pulled back so neither edge leaves the card.
    private func centreX(for sel: ChartScrubSelection, in plot: CGRect) -> CGFloat {
        let half = tooltipWidth / 2
        let lo = plot.minX + half
        let hi = plot.maxX - half
        guard hi > lo else { return plot.midX }
        return min(max(sel.plotX, lo), hi)
    }

    /// Above the sample where there is room, below it when the sample is near
    /// the top — the dot is half the answer, and a bubble parked on top of it
    /// hides the very thing it is pointing at.
    private func centreY(for sel: ChartScrubSelection, in plot: CGRect) -> CGFloat {
        let gap: CGFloat = 30
        let above = sel.plotY - gap
        return above >= plot.minY + 18 ? above : sel.plotY + gap
    }

}

/// Top level, not nested: a generic type cannot hold the static storage a
/// `PreferenceKey` needs.
private struct TooltipWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func chartScrub<Tooltip: View>(
        series: [DetailChartPoint],
        selection: Binding<ChartScrubSelection?>,
        @ViewBuilder tooltip: @escaping (DetailChartPoint) -> Tooltip
    ) -> some View {
        modifier(ChartScrub(series: series, selection: selection, tooltip: tooltip))
    }
}

/// «Профиль высоты» — green area chart over cumulative distance.
struct ElevationChartCard: View {
    let series: [DetailChartPoint]
    let language: LanguageManager.Language
    /// e.g. «макс 248 м · ↑ 640 м»
    let summary: String
    /// Left footer label (trip region — Figma shows the start locality,
    /// which we don't store; region is the closest honest value).
    let leftLabel: String
    /// Right footer label — total distance («316 км»).
    let rightLabel: String
    @Environment(\.colorScheme) private var scheme
    @State private var selection: ChartScrubSelection?

    private var yDomain: ClosedRange<Double> {
        // Spans the BAND, not just the means — otherwise the extremes the band
        // exists to show are the first thing clipped off the chart.
        let lows = series.map { $0.hasBand ? $0.yMin : $0.y }
        let highs = series.map { $0.hasBand ? $0.yMax : $0.y }
        let lo = lows.min() ?? 0
        let hi = highs.max() ?? 1
        let pad = max((hi - lo) * 0.1, 1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppStrings.chartAltitudeLabel(language))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(c.textTertiary)
                Spacer()
                Text(summary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }

            Chart(series) { pt in
                AreaMark(
                    x: .value("km", pt.x),
                    yStart: .value("base", yDomain.lowerBound),
                    yEnd: .value("m", pt.y)
                )
                .foregroundStyle(AppTheme.green.opacity(0.18))
                .interpolationMethod(.monotone)

                // Highest and lowest metre inside each slice of the route. On a
                // short hop the band is invisible (one sample per slice); on a
                // mountain pass it is the shape of the pass.
                if pt.hasBand {
                    AreaMark(
                        x: .value("km", pt.x),
                        yStart: .value("min", pt.yMin),
                        yEnd: .value("max", pt.yMax)
                    )
                    .foregroundStyle(AppTheme.green.opacity(0.22))
                    .interpolationMethod(.monotone)
                }

                LineMark(x: .value("km", pt.x), y: .value("m", pt.y))
                    .foregroundStyle(AppTheme.green)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                if let sel = selection {
                    RuleMark(x: .value("km", sel.point.x))
                        .foregroundStyle(AppTheme.accent.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(
                        x: .value("km", sel.point.x),
                        y: .value("m", sel.point.y)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .symbolSize(60)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain)
            .frame(height: 92)
            .chartScrub(series: series, selection: $selection) { pt in
                ChartScrubTooltip(
                    primary: TripDetailFormat.chartAltitudeReadout(pt, lang: language),
                    secondary: AppStrings.chartKmMark(language, km: pt.x)
                )
            }
            .accessibilityIdentifier("elevation_chart")

            HStack(alignment: .firstTextBaseline) {
                Text(leftLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                Spacer()
                // 14pt vs the 9pt left label is a Figma inconsistency —
                // shipped verbatim per spec caveat 4.
                Text(rightLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
    }
}

/// «Скорость» — line chart colored by the same speed→color scale as the
/// route polyline (gradient stops at each sample).
struct SpeedChartCard: View {
    let series: [DetailChartPoint]
    let language: LanguageManager.Language
    /// e.g. «макс 132 · ср 64»
    let summary: String
    @Environment(\.colorScheme) private var scheme
    @State private var selection: ChartScrubSelection?

    private var yDomain: ClosedRange<Double> {
        let hi = max(series.map { $0.hasBand ? $0.yMax : $0.y }.max() ?? 1, 10)
        return 0...(hi * 1.1)
    }

    /// Horizontal gradient tracing the speed zones along the distance axis.
    private var speedGradient: Gradient {
        guard let first = series.first, let last = series.last, last.x > first.x else {
            return Gradient(colors: [AppTheme.green])
        }
        let span = last.x - first.x
        let stops = series.map { pt in
            Gradient.Stop(
                color: SpeedColorScale.bands[SpeedColorScale.zone(forSpeedMS: pt.y / 3.6)].color,
                location: (pt.x - first.x) / span
            )
        }
        return Gradient(stops: stops)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppStrings.chartSpeedLabel(language))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(c.textTertiary)
                Spacer()
                Text(summary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }

            Chart(series) { pt in
                // Slowest and fastest inside each slice. Over ten hours one
                // slice is minutes of driving, and the line alone — a mean —
                // would quietly turn a 130 burst and a standstill into a calm
                // 60. The band says both happened.
                if pt.hasBand {
                    AreaMark(
                        x: .value("km", pt.x),
                        yStart: .value("min", pt.yMin),
                        yEnd: .value("max", pt.yMax)
                    )
                    .foregroundStyle(c.textTertiary.opacity(0.22))
                    .interpolationMethod(.monotone)
                }

                LineMark(x: .value("km", pt.x), y: .value("kmh", pt.y))
                    .foregroundStyle(.linearGradient(
                        speedGradient, startPoint: .leading, endPoint: .trailing
                    ))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                if let sel = selection {
                    RuleMark(x: .value("km", sel.point.x))
                        .foregroundStyle(AppTheme.accent.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(
                        x: .value("km", sel.point.x),
                        y: .value("kmh", sel.point.y)
                    )
                    .foregroundStyle(AppTheme.accent)
                    .symbolSize(60)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain)
            .frame(height: 80)
            .chartScrub(series: series, selection: $selection) { pt in
                ChartScrubTooltip(
                    primary: TripDetailFormat.chartSpeedReadout(pt, lang: language),
                    secondary: AppStrings.chartKmMark(language, km: pt.x)
                )
            }
            .accessibilityIdentifier("speed_chart")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
    }
}

// MARK: - Moving / stops proportion bar

/// «В движении и стоянки» — orange/gray proportion bar with dot labels.
struct MovingStopsCard: View {
    let movingSeconds: TimeInterval
    let stoppedSeconds: TimeInterval
    let language: LanguageManager.Language
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let total = movingSeconds + stoppedSeconds
        let fraction = total > 0 ? movingSeconds / total : 0
        let grayBar = scheme == .dark
            ? Color.white.opacity(0.18)
            : Color(red: 0xD6/255, green: 0xD6/255, blue: 0xDB/255)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppStrings.movingDot(language, Trip.formattedTimeHuman(movingSeconds, lang: language)))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(AppStrings.stopsDot(language, Trip.formattedTimeHuman(stoppedSeconds, lang: language)))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            GeometryReader { geo in
                let available = max(geo.size.width - 2, 0)
                let movingW = max(min(available * fraction, available - 6), 6)
                HStack(spacing: 2) {
                    Capsule().fill(AppTheme.accent).frame(width: movingW)
                    Capsule().fill(grayBar)
                }
            }
            .frame(height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
    }
}

// MARK: - Description card

/// «Описание» — plain white card with the trip notes text.
struct DetailDescriptionCard: View {
    let text: String
    /// Owner view keeps a subtle pencil so the (tappable) card still reads
    /// as editable — Figma shows no affordance, discoverability wins.
    var showsEditHint: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let bodyColor = scheme == .dark
            ? Color.white.opacity(0.78)
            : Color(red: 0x45/255, green: 0x45/255, blue: 0x4D/255)

        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(4.5)
                .foregroundStyle(bodyColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if showsEditHint {
                Spacer(minLength: 0)
                Image(systemName: "pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Trip achievements

/// «Достижения поездки» — 3-up cards: tinted icon circle + badge name.
/// Figma shows emoji; badges in the app are SF-symbol + color, so the
/// cards use the badge's own icon/tint (consistent with the badge system).
struct TripAchievementsGrid: View {
    let badges: [Badge]
    let language: LanguageManager.Language
    let onTap: (Badge) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(badges) { badge in
                Button {
                    Haptics.tap()
                    onTap(badge)
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(badge.color.opacity(0.14))
                                .frame(width: 40, height: 40)
                            Image(systemName: badge.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(badge.color)
                        }
                        Text(badge.title(language))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(c.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(height: 28, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(c.card)
                            .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Reaction chips

/// Drawn-icon + count pill used by the reactions cards (Figma
/// ReactionPills 114:141: capsule 10×5, icon 14, count Bold 12; active =
/// accent-tinted fill icon on 12% accent + 1.5 accent border). `.breakdown`
/// is the owner-side read-only chip; `.unselected` / `.mine` are the
/// interactive social-side variants.
struct ReactionCountChip: View {
    enum Style {
        case breakdown
        case unselected
        case mine
    }

    let emoji: String
    let count: Int
    var style: Style = .breakdown
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let bg: Color
        let countColor: Color
        switch style {
        case .breakdown:
            bg = c.cardAlt
            countColor = c.text
        case .unselected:
            bg = scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
            countColor = c.textSecondary
        case .mine:
            bg = AppTheme.orangeDim
            countColor = AppTheme.accent
        }

        return HStack(spacing: 4) {
            ReactionIconView(
                emoji: emoji,
                size: 14,
                filled: style == .mine,
                tint: style == .mine ? AppTheme.accent : c.text
            )
            Text("\(count)")
                .font(.inter(12, weight: .bold).monospacedDigit())
                .foregroundStyle(countColor)
                // Rolls up as the reaction lands, down as it's taken back —
                // mirrors `ReactionTallyPill` in the feed.
                .contentTransition(.numericText(countsDown: style != .mine))
                .animation(.snappy(duration: 0.26), value: count)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(bg, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(style == .mine ? AppTheme.accent : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.22), value: style)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: style == .mine) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(style == .mine ? 1.16 : 0.88, duration: 0.13, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.3, spring: .bouncy)
            }
        }
    }
}

// MARK: - Publish-with-description sheet (Figma 533:119)

/// Stage-1 publish confirmation with an optional description field.
/// Replaces the old plain alert: same commit semantics (privacy flip),
/// plus the description is saved through the notes path when filled.
struct PublishTripSheet: View {
    let language: LanguageManager.Language
    /// Confirmation body incl. the cloud-sync-off appendix the parent
    /// already computes.
    let message: String
    @State var descriptionText: String
    let onPublish: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var descFocused: Bool

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.publishTripTitle(language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)

            Text(message)
                .font(.system(size: 14))
                .lineSpacing(3.5)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.publishOptionalDescLabel(language))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(c.textTertiary)
                .padding(.top, 4)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $descriptionText)
                    .font(.system(size: 15))
                    .foregroundStyle(c.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .focused($descFocused)
                if descriptionText.isEmpty {
                    Text(AppStrings.publishDescPlaceholder(language))
                        .font(.system(size: 15))
                        .foregroundStyle(c.textTertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 80)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Text(AppStrings.cancel(language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 15)
                        .background(c.cardAlt, in: Capsule())
                }
                Button {
                    Haptics.action()
                    let text = descriptionText
                    dismiss()
                    onPublish(text)
                } label: {
                    Text(AppStrings.publishAction(language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.accent, in: Capsule())
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        // Below the drag indicator, not against it: 16 put the title so close
        // to the sheet's top edge that the grabber sat almost on the type.
        .padding(.top, 30)
        .padding(.bottom, 20)
        .background(c.card)
        // Was `.medium` at the call site with a Spacer holding the slack: on a
        // short confirmation that left half a screen of empty card under the
        // buttons.
        .contentSizedSheet()
    }
}

// MARK: - Publish progress / error toasts (Figma 522:119 / 524:119)

/// Floating publish-status surface. Watches SyncQueue for the trip's
/// upload op: pending → indeterminate «Публикуется…», parked in the
/// failed queue (or stuck pending past the timeout — offline) → error
/// card with «Повторить», which re-drives the SAME enqueued publish op
/// via `retryFailedNow`. Deactivates itself once the op clears.
struct PublishStatusOverlay: View {
    let tripId: UUID
    @Binding var isActive: Bool
    let language: LanguageManager.Language
    @ObservedObject private var queue = SyncQueue.shared
    @State private var timedOut = false
    @Environment(\.colorScheme) private var scheme

    private var isPendingUpload: Bool {
        if queue.pending.contains(where: { $0.entityType == .trip && $0.entityId == tripId }) {
            return true
        }
        if let op = queue.currentOperation, op.entityType == .trip, op.entityId == tripId {
            return true
        }
        return false
    }

    private var hasFailed: Bool {
        queue.failed.contains { $0.entityType == .trip && $0.entityId == tripId }
    }

    var body: some View {
        Group {
            if isActive {
                if hasFailed || timedOut {
                    errorCard
                        // The op can still drain on its own (connectivity
                        // returns → SyncQueue auto-retries the pending op).
                        // Without this watcher the card would keep claiming
                        // failure after the trip successfully published.
                        .task(id: isPendingUpload) {
                            guard !isPendingUpload, !hasFailed else { return }
                            try? await Task.sleep(for: .milliseconds(900))
                            if isActive, !isPendingUpload, !hasFailed {
                                timedOut = false
                                isActive = false
                            }
                        }
                } else {
                    // Pill shows through the whole non-failed window — also
                    // while the op briefly isn't in the queue yet (enqueue
                    // races body by a tick) or has just cleared (short grace
                    // before dismissing so a fast publish still reads).
                    publishingPill
                        .task(id: isPendingUpload) {
                            if isPendingUpload {
                                // Ops don't fail while offline — they just
                                // sit in the queue. Surface the error card
                                // after a grace window so the user isn't
                                // stared at by an endless spinner.
                                try? await Task.sleep(for: .seconds(20))
                                if isActive, isPendingUpload { timedOut = true }
                            } else {
                                try? await Task.sleep(for: .milliseconds(900))
                                if isActive, !isPendingUpload, !hasFailed {
                                    timedOut = false
                                    isActive = false
                                }
                            }
                        }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isActive)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hasFailed)
    }

    private var publishingPill: some View {
        let c = AppTheme.colors(for: scheme)
        return HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.accent)
            Text(AppStrings.publishing(language))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(c.card)
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.accent.opacity(0.25), lineWidth: 1)
        )
        // Pure status — never swallow taps meant for content below.
        .allowsHitTesting(false)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var errorCard: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.red)
                Text(AppStrings.publishFailed(language))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    timedOut = false
                    isActive = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
            Text(AppStrings.publishFailedBody(language))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.action()
                timedOut = false
                Task { await SyncQueue.shared.retryFailedNow() }
            } label: {
                Text(AppStrings.retry(language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(AppTheme.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.card)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Social load-error state (Figma 519:158)

/// Full-screen «Не удалось загрузить поездку» with retry — used by
/// SocialTripDetailView when a stub trip (no route geometry) also fails
/// its remote loads, leaving nothing renderable.
struct TripLoadErrorView: View {
    let language: LanguageManager.Language
    let onRetry: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(c.textTertiary.opacity(0.35), lineWidth: 5)
                    .frame(width: 100, height: 100)
                Circle()
                    .stroke(c.textTertiary.opacity(0.2), lineWidth: 5)
                    .frame(width: 72, height: 72)
            }
            .padding(.bottom, 4)

            Text(AppStrings.tripLoadFailed(language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(AppStrings.tripLoadFailedBody(language))
                .font(.system(size: 14))
                .lineSpacing(3.5)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button {
                Haptics.tap()
                onRetry()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                    Text(AppStrings.tryAgain(language))
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
