import SwiftUI

/// Высота внутренней колонки листа — чтобы скролл её обнял, а не растянулся.
private struct AtlasSheetContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The period is a draft until Apply. Closing this sheet keeps the current map.
struct AtlasPeriodSheet: View {
    let onSelect: (AtlasPeriod) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AtlasPeriod
    @State private var start: Date
    @State private var end: Date
    @State private var inner: CGFloat = 0
    @State private var previousPreset: AtlasPeriod = .allTime

    init(period: AtlasPeriod, onSelect: @escaping (AtlasPeriod) -> Void) {
        self.onSelect = onSelect
        _draft = State(initialValue: period)
        if case let .custom(start, end) = period {
            let window = AtlasPeriodBounds.clamp(start: start, end: end)
            _start = State(initialValue: window.start)
            _end = State(initialValue: window.end)
        } else {
            let now = Date()
            _start = State(initialValue: Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now)
            _end = State(initialValue: now)
            _previousPreset = State(initialValue: period)
        }
    }

    private var isCustom: Bool {
        if case .custom = draft { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            AtlasControlsHeader(
                title: isCustom ? AppStrings.atlasCustomPeriod(lang.language) : AppStrings.atlasPeriod(lang.language),
                onBack: isCustom ? {
                    withAnimation { draft = previousPreset }
                } : nil
            )
            // Скролл ОБНИМАЕТ содержимое, а не забирает всю предложенную
            // высоту.
            //
            // `contentSizedSheet` меряет то, что ему дали, а `ScrollView` по
            // умолчанию отвечает «возьму сколько предложите» — и лист от
            // такой мерки становится полноэкранным, то есть ровно с той же
            // пустотой, из-за которой всё и затевалось. Поймано КАДРОМ
            // (`AtlasSheetHeightShotTests`), а не рассуждением: состоянием
            // высоту листа не спросить. Поэтому меряется внутренняя колонка,
            // и её высота становится потолком скролла: содержимое короче
            // экрана — лист по нему, длиннее — система зажмёт по экрану, а
            // скролл останется скроллом.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isCustom { customDates } else { presets }
                    Text(AppStrings.atlasPeriodHint(lang.language))
                        .font(.inter(14))
                        .foregroundStyle(AtlasTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                // СОБСТВЕННАЯ высота, а не предложенная, — и это не украшение,
                // а то, что размыкает петлю. Без `fixedSize` колонка сжимается
                // под маленькое предложение, измерение от этого становится
                // ещё меньше, следующий проход предлагает ещё меньше — и лист
                // схлопывается до шапки с кнопкой (репорт владельца 26 сен:
                // «тут просто кнопка показать и период»). На симуляторе первый
                // проход случайно ложился верно, на телефоне — нет; поэтому
                // высоту здесь держит не удачный порядок, а тип.
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: AtlasSheetContentHeight.self,
                                               value: geo.size.height)
                    }
                }
            }
            // Просто присваивание, без `max`: от схлопывания держит `fixedSize`
            // выше, а «только расти» сломало бы возврат со «своего периода» на
            // пресеты — лист остался бы высотой с календарь.
            .onPreferenceChange(AtlasSheetContentHeight.self) { inner = $0 }
            .frame(maxHeight: inner > 0 ? inner : nil)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { applyButton }
        .background(AtlasTheme.background)
        .presentationCornerRadius(AtlasTheme.sheetRadius)
        // Высота ПО СОДЕРЖИМОМУ. Стояло `.medium` — ровно полэкрана, сколько
        // бы строк внутри ни было, — а «Показать» приколота к низу листа:
        // между подсказкой и кнопкой зияло поле в треть телефона. Владелец
        // 26 сен: «зачем-то куча пустого места, это может так и надо?» — нет,
        // не надо, это не приём, а лист выше своего содержимого.
        //
        // Заодно ушла вся машинерия с `detent`: пресеты и свой период просто
        // разной высоты, и лист следует за ними сам. Высокое содержимое
        // система зажмёт по экрану, а внутри стоит `ScrollView`.
        .contentSizedSheet(background: AtlasTheme.background)
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlas_period_sheet")
    }

    private var presets: some View {
        VStack(spacing: 0) {
            periodRow(.allTime, title: AppStrings.atlasAllTime(lang.language), id: "all_time")
            separator
            periodRow(.thisYear, title: AppStrings.atlasThisYear(lang.language), id: "this_year")
            separator
            periodRow(.last30Days, title: AppStrings.atlasLast30Days(lang.language), id: "last_30_days")
            separator
            periodRow(.custom(start: start, end: end), title: AppStrings.atlasCustomPeriod(lang.language), id: "custom")
        }
        .padding(.horizontal, 16)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
    }

    private var separator: some View {
        Rectangle().fill(AtlasTheme.separator).frame(height: 0.5)
    }

    private func periodRow(_ period: AtlasPeriod, title: String, id: String) -> some View {
        let selected = period == draft || (id == "custom" && isCustom)
        return Button {
            Haptics.tap()
            withAnimation {
                if id == "custom" {
                    previousPreset = draft
                }
                draft = period
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(selected ? AtlasTheme.accent : AtlasTheme.secondary.opacity(0.5),
                                  lineWidth: selected ? 7 : 2)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.inter(16, weight: .semibold))
                    .foregroundStyle(AtlasTheme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if id == "custom" {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                        .foregroundStyle(AtlasTheme.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("atlas_period_\(id)")
    }

    /// Свой период — ТЕМ ЖЕ календарём, что фильтр истории на «Я».
    ///
    /// Просьба владельца 26 сен: «переиспользуй то, как мы сделали календарь
    /// в „Я“ и в ленте — там очень удобно». Удобство там в механике: один тап
    /// ставит начало, второй конец, тот же день дважды снимает выбор, день
    /// раньше начала меняет концы местами, а тап по готовому отрезку начинает
    /// заново. Прежний `DatePicker(.graphical)` требовал сперва выбрать, КАКУЮ
    /// из двух дат ты сейчас правишь, — два лишних решения на каждый период.
    ///
    /// Берётся сам компонент, а не копия его логики: две копии однажды
    /// разойдутся, и «удобно как в Я» перестанет быть правдой. Флагами гасится
    /// то, что здесь лишнее, — строка «сбросить» (над календарём и так стоит
    /// «Всё время») и свёрнутая неделя.
    private var customDates: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                dateChip(AppStrings.atlasFrom(lang.language), date: start)
                dateChip(AppStrings.atlasTo(lang.language), date: end)
            }
            ProfileHistoryCalendar(
                dateFrom: calendarFrom,
                dateTo: calendarTo,
                // Километров по дням у «Атласа» нет: тепловая заливка — это
                // про историю поездок на «Я», а здесь календарь выбирает
                // окно, а не показывает, сколько в нём наезжено.
                kmByDay: [:],
                maxKmDay: 0,
                filteredCount: 0,
                showsFilterRow: false,
                startsExpanded: true
            )
            .accessibilityIdentifier("atlas_period_calendar")
        }
    }

    /// Обе даты у «Атласа» неопциональны, а календарь говорит на `Date?`.
    ///
    /// Пустой конец — это «выбрано только начало», и до второго тапа окно
    /// считается одним днём: иначе «Показать» на полпути показал бы период,
    /// которого человек не задавал.
    private var calendarFrom: Binding<Date?> {
        Binding(get: { start }, set: { picked in
            guard let picked else { return }
            start = picked
            if end < picked { end = picked }
        })
    }

    private var calendarTo: Binding<Date?> {
        Binding(get: { end }, set: { picked in
            guard let picked else { end = start; return }
            end = picked
        })
    }

    /// Итог выбора словами — «С 28 авг.» / «По 26 сент.». Нажимать их больше
    /// не нужно: какую дату ставит тап, решает сам календарь.
    private func dateChip(_ title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.inter(12, weight: .semibold))
                .foregroundStyle(AtlasTheme.secondary)
            Text(date, format: .dateTime.day().month(.abbreviated).year().locale(lang.language.locale))
                .font(.inter(14, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(AtlasTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 12))
    }


    private var applyButton: some View {
        Button {
            Haptics.tap()
            onSelect(isCustom ? .custom(start: start, end: end) : draft)
            dismiss()
        } label: {
            Text(AppStrings.atlasShow(lang.language))
                .font(AppType.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(AtlasTheme.accent, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("atlas_period_apply")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AtlasTheme.background)
    }
}

/// These choices change the existing map immediately; no second map is created.
struct AtlasAppearanceSheet: View {
    @Binding var appearance: AtlasMapAppearance
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            AtlasControlsHeader(title: AppStrings.atlasMapStyle(lang.language))
            ScrollView {
                VStack(spacing: 16) {
                    // Три в ряд — как рисует макет A7. Сетка, а не `HStack`:
                    // у трёх плиток подписи разной длины, и колонки обязаны
                    // быть равными, а не по содержимому.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                             count: 3),
                              spacing: 8) {
                        styleCard(.fog, title: AppStrings.atlasFogStyle(lang.language))
                        styleCard(.night, title: AppStrings.atlasNightStyle(lang.language))
                        styleCard(.cells, title: AppStrings.atlasCellsStyle(lang.language))
                    }
                    layerToggles
                }
                .padding(16)
            }
        }
        .background(AtlasTheme.background)
        .presentationBackground(AtlasTheme.background)
        .presentationCornerRadius(AtlasTheme.sheetRadius)
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlas_appearance_sheet")
    }

    private var layerToggles: some View {
        VStack(spacing: 0) {
            // Подписи городов убраны вовсе (владелец, 26 сен): наш «Геленджик»
            // ложился поверх «Gelendzhik», который рисует сама Apple. Имена
            // городов знает карта, и знает лучше — на тринадцати языках и без
            // нашего слоя. Вместе с подписями ушёл и тумблер: выключателя у
            // того, чего нет, быть не может.
            Toggle(AppStrings.atlasShowPhotos(lang.language), isOn: $appearance.showsPhotos)
                .frame(minHeight: 56)
                .accessibilityIdentifier("atlas_photos_toggle")
        }
        .font(.inter(16, weight: .semibold))
        .foregroundStyle(AtlasTheme.ink)
        .tint(AtlasTheme.accent)
        .padding(.horizontal, 16)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
    }

    private func styleCard(_ style: AtlasMapAppearance.Style, title: String) -> some View {
        let selected = appearance.style == style
        return Button {
            Haptics.tap()
            appearance.style = style
        } label: {
            VStack(spacing: 8) {
                AtlasStylePreview(style: style)
                    .frame(height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 5) {
                    Text(title).font(.inter(14, weight: .bold))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(selected ? AtlasTheme.accent : AtlasTheme.ink)
                .frame(minHeight: 24)
            }
            .padding(5)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity)
            .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(selected ? AtlasTheme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("atlas_style_\(style.rawValue)")
    }
}

/// S8's explanations cover the metrics the app really computes. Stamps and
/// geometric city-boundary promises are intentionally not part of this sheet.
struct AtlasExplanationSheet: View {
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(spacing: 0) {
            AtlasControlsHeader(title: AppStrings.atlasHowWeCount(lang.language))
            ScrollView {
                VStack(spacing: 12) {
                    explanation(
                        symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        title: AppStrings.atlasNewRoads(lang.language),
                        body: AppStrings.atlasRoadsExplanation(lang.language))
                    explanation(
                        symbol: "arrow.triangle.2.circlepath",
                        title: AppStrings.atlasTotalTravelled(lang.language),
                        body: AppStrings.atlasTripsExplanation(lang.language))
                    explanation(
                        symbol: "calendar",
                        title: AppStrings.atlasPeriod(lang.language),
                        body: AppStrings.atlasPeriodRoadsExplanation(lang.language))
                }
                .padding(16)
            }
        }
        .background(AtlasTheme.background)
        .presentationBackground(AtlasTheme.background)
        .presentationCornerRadius(AtlasTheme.sheetRadius)
        .presentationDragIndicator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("atlas_explanation_sheet")
    }

    private func explanation(symbol: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AtlasTheme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppType.statCaption)
                    .tracking(AppType.statCaptionTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(AtlasTheme.ink)
            }
            Text(body)
                .font(.inter(15))
                .lineSpacing(3)
                .foregroundStyle(AtlasTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct AtlasControlsHeader: View {
    let title: String
    var onBack: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Capsule().fill(AtlasTheme.handle).frame(width: 36, height: 5)
                .accessibilityHidden(true)
            HStack(spacing: 12) {
                if let onBack {
                    Button { Haptics.tap(); onBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AtlasTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(AtlasTheme.card, in: Circle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel(AppStrings.back(lang.language))
                    .accessibilityIdentifier("atlas_period_back")
                }
                Text(title)
                    .font(AppType.sheetTitle)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(AtlasTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AtlasTheme.secondary)
                        .frame(width: 36, height: 36)
                        .background(AtlasTheme.searchBackground, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(AppStrings.close(lang.language))
                .accessibilityIdentifier("atlas_controls_close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// A small, code-native illustration of each real map appearance.
private struct AtlasStylePreview: View {
    let style: AtlasMapAppearance.Style

    var body: some View {
        Canvas { context, size in
            let night = style == .night
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(night
                ? Color(red: 0.11, green: 0.14, blue: 0.19)
                : Color(red: 0.90, green: 0.90, blue: 0.88)))
            let route = routePath(size)
            let openedColour = Color(red: 0.85, green: 0.82, blue: 0.69)
            if style == .cells {
                // У «Клеток» открытое — КЛЕТКИ, и превью обязано показывать
                // именно их: тайл, подписанный «Клетки», но нарисованный
                // мягким коридором, обещал бы не то, что человек увидит.
                context.fill(openedCells(route, size: size), with: .color(openedColour))
            } else {
                context.stroke(route, with: .color(night
                    ? Color(red: 0.20, green: 0.25, blue: 0.30)
                    : openedColour),
                    style: StrokeStyle(lineWidth: 28, lineCap: .round, lineJoin: .round))
            }
            var streets = Path()
            for x in stride(from: CGFloat(-20), through: size.width + 40, by: 26) {
                streets.move(to: CGPoint(x: x, y: 0))
                streets.addLine(to: CGPoint(x: x + 40, y: size.height))
            }
            context.stroke(streets, with: .color(.white.opacity(night ? 0.07 : 0.55)), lineWidth: 1)
            context.stroke(route, with: .color(.white.opacity(night ? 0.25 : 0.95)),
                           style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            context.stroke(route, with: .color(night
                ? Color(red: 1, green: 0.58, blue: 0.34)
                : Color(red: 0.78, green: 0.28, blue: 0.18)),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            for point in [CGPoint(x: size.width * 0.16, y: size.height * 0.75),
                          CGPoint(x: size.width * 0.78, y: size.height * 0.23)] {
                let dot = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(.white))
                context.stroke(dot, with: .color(.black.opacity(0.65)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    /// Клетки, которых коридор касается. Сторона взята «на глаз кадра», а не
    /// из `FogCellGrid`: превью это рисунок в восемьдесят точек, и настоящая
    /// сторона в точках карты здесь ничего не значит — значит только то, что
    /// открытое выглядит квадратами такого же порядка, как на карте.
    private func openedCells(_ route: Path, size: CGSize) -> Path {
        let side: CGFloat = 13
        let halo: CGFloat = 14
        let wide = route.strokedPath(StrokeStyle(lineWidth: halo * 2,
                                                 lineCap: .round, lineJoin: .round))
        var cells = Path()
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let cell = CGRect(x: x, y: y, width: side, height: side)
                if wide.contains(CGPoint(x: cell.midX, y: cell.midY)) {
                    cells.addRect(cell)
                }
                x += side
            }
            y += side
        }
        return cells
    }

    private func routePath(_ size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.75))
            path.addCurve(to: CGPoint(x: size.width * 0.78, y: size.height * 0.23),
                          control1: CGPoint(x: size.width * 0.59, y: size.height * 0.95),
                          control2: CGPoint(x: size.width * 0.42, y: size.height * 0.10))
        }
    }
}
