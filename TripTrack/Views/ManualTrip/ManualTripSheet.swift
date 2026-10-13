import SwiftUI
import MapKit

/// «Вписать поездку» — единственный вход в ручную поездку (0.8.0, PRO).
///
/// Редизайн 13 окт 2026 (вариант A, решение владельца: «рекомендации — топ,
/// их и делаем»). Прежний лист был формой настроек: точки строками с
/// шевронами, облака чипов, пустая карта на 40 % экрана, серая кнопка почти
/// до самого конца и мелкая приписка под ней. Платная функция выглядела
/// тестовой. Теперь у листа ДВЕ стадии, и обе — одна и та же поездка:
///
/// 1. **Куда.** Строка «Откуда → Куда» и клавиатура сразу. Под ней — дом,
///    частые места и концы недавних поездок (`ManualTripSuggestions`), а с
///    первой буквы — поиск Apple. Выбрал «Откуда» — фокус сам уходит в «Куда».
/// 2. **Поездка.** Лист становится её будущей страницей: карта с маршрутом,
///    пиксельная строка даты, заголовок «Дом → Джубга», чипы времени и машины,
///    плитки. Время и машина уже подставлены, правятся здесь же.
///
/// Второго листа поверх первого нет — ни у поиска, ни у времени (тот увёл бы
/// первый вниз вместе с набранным); пейвол — законное исключение, см. ниже.
/// Ошибки маршрута стоят строкой под заголовком, а не диалогом: системных
/// модалок в приложении нет вовсе (CLAUDE.md, «Dialogs»).
struct ManualTripSheet: View {
    /// Покупка НЕ записывает поездку сама — «Сохранить» человек нажимает сам.
    ///
    /// Константой, потому что это решение, а не деталь: автозапись после
    /// покупки означала бы, что человек, зашедший на пейвол из листа,
    /// получает поездку одним нажатием, которого он не делал. Держит
    /// `ManualTripPaywallReturnTests`.
    static let recordsAutomaticallyAfterPurchase = false

    /// Кто пишет в базу. Приходит снаружи, а не берётся из синглтона: у
    /// `TripManager` его нет — экземпляр держит `MapViewModel`.
    let tripManager: TripManager
    /// Готовый лист — дата с календаря, зеркало «обратной дороги». `nil` —
    /// пустой лист.
    var preset: ManualTripPreset?
    /// Поездка создана — для подсветки в «Истории» и «Обратно». Лист
    /// закрывает себя сам.
    var onCreated: (ManualTripCreationResult) -> Void = { _ in }

    @StateObject private var model: ManualTripModel
    @State private var stage: Stage = .places
    @State private var field: Field = .from
    @FocusState private var queryFocused: Bool
    @State private var isCreating = false
    @State private var showsTime = false
    @State private var showsVehicles = false
    @State private var showsTitleField = false
    @FocusState private var titleFocused: Bool
    @State private var suggestions: [ManualTripSuggestions.Item] = []
    /// Точку ставят пальцем по карте, а не выбирают из списка.
    @State private var pickingOnMap = false
    /// Пейвол открыт ПОВЕРХ этого листа (состояние 36б): `@StateObject model`
    /// остаётся жив, и набранное сохраняется само (§12.2 спеки).
    @State private var paywallOverSheet = false

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    init(
        tripManager: TripManager, preset: ManualTripPreset? = nil,
        onCreated: @escaping (ManualTripCreationResult) -> Void = { _ in }
    ) {
        self.tripManager = tripManager
        self.preset = preset
        self.onCreated = onCreated
        let vehicle = SettingsManager.shared.activeRecordableVehicleId
        _model = StateObject(wrappedValue: preset.map {
            ManualTripModel(preset: $0, defaultVehicleId: vehicle)
        } ?? ManualTripModel(vehicleId: vehicle))
        // Обратная дорога приходит с обоими концами — сразу страница поездки.
        let ready = preset?.from != nil && preset?.to != nil
        _stage = State(initialValue: ready ? .trip : .places)
    }

    private enum Stage { case places, trip }
    /// Какую точку сейчас выбирают. `via` хранит индекс: промежуточную можно
    /// удалить, пока открыт выбор.
    private enum Field: Equatable {
        case from, to
        case via(Int)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Group {
            if pickingOnMap {
                mapPickStage(c)
            } else {
                switch stage {
                case .places: placesStage(c)
                case .trip: tripStage(c)
                }
            }
        }
        .background(c.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Набранное не теряется от случайного свайпа: закрывает лист только ×.
        .interactiveDismissDisabled(model.from != nil || model.to != nil)
        .task { reloadSuggestions() }
        // Второй лист ПОВЕРХ первого — законный случай: он не «вместо», а
        // «над», и первый под ним не закрывается.
        .sheet(isPresented: $paywallOverSheet) {
            PlusPaywallSheet(feature: .manualTrip, origin: .manualTrip)
        }
    }

    // MARK: - Стадия 1: куда

    private func placesStage(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            topBar(c, eyebrow: AppStrings.manualTripEntry(lang.language))
            pointsLine(c)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 14)
            Divider().overlay(c.border)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if trimmedQuery.count > 1 {
                        ForEach(Array(model.completions.enumerated()), id: \.offset) { _, item in
                            completionRow(item, c: c)
                        }
                        if model.completions.isEmpty && !model.isSearching {
                            Text(AppStrings.noResults(lang.language))
                                .font(.interScaled(15))
                                .foregroundStyle(c.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 28)
                                .accessibilityIdentifier("manual_trip_no_results")
                        }
                    } else {
                        ForEach(suggestions) { item in suggestionRow(item, c: c) }
                        mapPickRow(c)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focusQuery() }
    }

    /// Строка «Откуда → Куда»: выбранная точка — словом, та, что выбирают, —
    /// полем с курсором, ещё не выбранная — бледным словом. Тап по любой
    /// возвращает выбор к ней.
    private func pointsLine(_ c: AppTheme.Colors) -> some View {
        let l = lang.language
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return VStack(alignment: .leading, spacing: 10) {
            layout {
                pointSlot(.from, point: model.from, placeholder: AppStrings.manualTripFrom(l), c: c)
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(model.from == nil ? c.textTertiary : c.text)
                    .accessibilityHidden(true)
                pointSlot(.to, point: model.to, placeholder: AppStrings.manualTripTo(l), c: c)
            }
            ForEach(Array(model.via.enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: 8) {
                    Text(AppStrings.manualTripVia(l))
                        .font(.interScaled(13, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                    pointSlot(.via(index), point: stop.isPlaceholder ? nil : stop,
                              placeholder: AppStrings.manualTripSearchHint(l), c: c, small: true)
                    Spacer(minLength: 0)
                    Button {
                        Haptics.tap()
                        removeVia(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(c.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.delete(l))
                    .accessibilityIdentifier("manual_trip_remove_via_\(index)")
                }
            }
        }
        // По левому краю, как заголовок на странице поездки: поле теперь по
        // ширине текста, и без этого строка вставала посередине листа.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pointSlot(
        _ slot: Field, point: ManualTripPoint?, placeholder: String,
        c: AppTheme.Colors, small: Bool = false
    ) -> some View {
        let size: CGFloat = small ? 17 : 24
        if field == slot {
            TextField(placeholder, text: Binding(get: { model.query }, set: { model.updateSearch($0) }),
                      prompt: Text(placeholder).foregroundStyle(c.textTertiary))
                .font(.interScaled(size, weight: .bold, relativeTo: .title2))
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($queryFocused)
                .onSubmit(submitQuery)
                // По тексту, а не во всю строку: иначе «→ Куда» уезжает к
                // правому краю и строка перестаёт читаться как маршрут.
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .accessibilityIdentifier("manual_trip_search")
        } else {
            Button {
                Haptics.tap()
                select(slot)
            } label: {
                Text(point.map(name) ?? placeholder)
                    .font(.interScaled(size, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(point == nil ? c.textTertiary : c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier(identifier(for: slot))
        }
    }

    private func suggestionRow(_ item: ManualTripSuggestions.Item, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            Task { await pick(item.point) }
        } label: {
            HStack(spacing: 14) {
                suggestionIcon(item.kind, c: c)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.point.name)
                        .font(.interScaled(16, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.interScaled(13))
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("manual_trip_suggestion")
    }

    /// Последняя строка подсказок — точка пальцем: то, у чего нет адреса
    /// (поворот на трассе, дача без улицы). Пейвол обещает её словами
    /// («Поставьте точки на карте»), и лист обязан её держать.
    private func mapPickRow(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            queryFocused = false
            withAnimation(.easeOut(duration: 0.2)) { pickingOnMap = true }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "hand.tap")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                Text(AppStrings.manualTripPointOnMap(lang.language))
                    .font(.interScaled(16, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("manual_trip_map_pick")
    }

    /// Выбор точки пальцем: карта на весь лист, подсказка сверху, тап ставит
    /// точку в то поле, которое сейчас выбирают.
    private func mapPickStage(_ c: AppTheme.Colors) -> some View {
        ZStack(alignment: .top) {
            ManualTripMapView(points: orderedPoints, route: model.route?.coordinates ?? [],
                              onTap: { coordinate in
                Task {
                    let point = await model.point(at: coordinate)
                    pickingOnMap = false
                    await pick(point)
                }
            })
            .ignoresSafeArea(edges: .bottom)
            .accessibilityIdentifier("manual_trip_map")
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    withAnimation(.easeOut(duration: 0.2)) { pickingOnMap = false }
                    focusQuery()
                } label: {
                    NavCircleIcon(systemImage: "chevron.left", glyphSize: 15)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.back(lang.language))
                .accessibilityIdentifier("manual_trip_map_back")
                Text(AppStrings.manualTripTapMapHint(lang.language))
                    .font(.interScaled(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(c.card, in: Capsule())
                    .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.08), radius: 5, y: 2)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private func suggestionIcon(_ kind: ManualTripSuggestions.Item.Kind, c: AppTheme.Colors) -> some View {
        let symbol: String
        let fg: Color
        let bg: Color
        switch kind {
        case .home: symbol = "house.fill"; fg = c.card; bg = c.text
        case .place: symbol = "mappin"; fg = AppTheme.accent; bg = AppTheme.accentBg
        case .recent: symbol = "clock.arrow.circlepath"; fg = c.textSecondary; bg = c.cardAlt
        }
        return Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(fg)
            .frame(width: 36, height: 36)
            .background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    private func completionRow(_ item: MKLocalSearchCompletion, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            Task {
                guard let point = await model.resolve(item) else { return }
                await pick(point)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.interScaled(16, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.interScaled(13))
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("manual_trip_result")
    }

    // MARK: - Стадия 2: поездка

    private func tripStage(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(c)
                    VStack(alignment: .leading, spacing: 18) {
                        titleBlock(c)
                        chips(c)
                        if showsTime { timeEditor(c) }
                        if showsVehicles { vehicleChooser(c) }
                        routeState(c)
                        tiles(c)
                        if let error = model.createError { refusalCard(error, c) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            saveButton(c)
        }
    }

    private func hero(_ c: AppTheme.Colors) -> some View {
        ManualTripMapView(points: orderedPoints, route: model.route?.coordinates ?? [])
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 200 : 300)
            .overlay(alignment: .topTrailing) {
                closeButton(c).padding(12)
            }
            .accessibilityIdentifier("manual_trip_map")
    }

    /// Пиксельная строка и заголовок — та же пара, что на странице поездки
    /// (`TripDetailView.titleBlock`): лист показывает то, что сохранится.
    private func titleBlock(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TripDetailFormat.posterDateLine(date: model.startDate, region: nil, lang: lang.language))
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if showsTitleField {
                TextField(model.displayTitle ?? AppStrings.tripTitlePlaceholder(lang.language),
                          text: $model.title)
                    .font(.interScaled(26, weight: .bold, relativeTo: .title))
                    .tracking(-0.52)
                    .foregroundStyle(c.text)
                    .tint(AppTheme.accent)
                    .submitLabel(.done)
                    .focused($titleFocused)
                    .onSubmit { showsTitleField = false }
                    .accessibilityIdentifier("manual_trip_title")
            } else {
                Button {
                    Haptics.tap()
                    showsTitleField = true
                    titleFocused = true
                } label: {
                    Text(model.displayTitle ?? AppStrings.tripTitlePlaceholder(lang.language))
                        .font(.interScaled(26, weight: .bold, relativeTo: .title))
                        .tracking(-0.52)
                        .foregroundStyle(c.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityHint(AppStrings.tripTitleLabel(lang.language))
                .accessibilityIdentifier("manual_trip_title")
            }
        }
    }

    /// Три факта под заголовком, как на странице поездки: время, машина и
    /// «+ точка». Время и машина открываются на месте, под чипами.
    private func chips(_ c: AppTheme.Colors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(selected: showsTime, identifier: "manual_trip_time") {
                    showsTime.toggle()
                    showsVehicles = false
                } label: {
                    Text(timeRangeText).monospacedDigit()
                }
                chip(selected: showsVehicles, identifier: "manual_trip_vehicle") {
                    showsVehicles.toggle()
                    showsTime = false
                } label: {
                    if let v = selectedVehicle {
                        Text(v.displayEmoji).font(.inter(12))
                        Text(v.name).lineLimit(1)
                    } else {
                        Image(systemName: "car").font(.system(size: 11, weight: .medium))
                        Text(AppStrings.noVehicle(lang.language))
                    }
                }
                // Потолок достигнут — кнопки нет вовсе: нажатие, которое
                // ничего не делает, хуже отсутствующего.
                if model.via.count < ManualTripRouter.maxViaPoints {
                    chip(selected: false, identifier: "manual_trip_add_via", disclosure: false) {
                        addVia()
                    } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        Text(AppStrings.manualTripVia(lang.language))
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip<Label: View>(
        selected: Bool, identifier: String, disclosure: Bool = true,
        action: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { action() }
        } label: {
            DetailChipSurface {
                label()
                if disclosure {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.5)
                        .rotationEffect(.degrees(selected ? 180 : 0))
                }
            }
            .overlay {
                if selected {
                    Capsule().strokeBorder(AppTheme.colors(for: scheme).text, lineWidth: 1.5)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier(identifier)
    }

    /// Время — на месте, под чипом: день, выезд и длительность. Длительность
    /// сама следует за маршрутом, пока её не тронули (`ManualTripDurationPolicy`).
    private func timeEditor(_ c: AppTheme.Colors) -> some View {
        let l = lang.language
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let onToday = calendar.isDate(model.startDate, inSameDayAs: Date())
        let onYesterday = calendar.isDate(model.startDate, inSameDayAs: yesterday)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                dayButton(AppStrings.today(l), selected: onToday) { model.setStartDay(Date()) }
                dayButton(AppStrings.yesterday(l), selected: onYesterday) { model.setStartDay(yesterday) }
                DatePicker(AppStrings.manualTripStart(l),
                           selection: Binding(get: { model.startDate }, set: { model.setStart($0) }),
                           in: model.startBounds, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .accessibilityIdentifier("manual_trip_start")
            }
            .padding(3)
            .background(c.cardAlt, in: Capsule())
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.manualTripStart(l))
                        .font(.interScaled(11, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                    DatePicker(AppStrings.manualTripStart(l),
                               selection: Binding(get: { model.startDate }, set: { model.setStart($0) }),
                               in: model.startBounds, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .accessibilityIdentifier("manual_trip_start_time")
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(AppStrings.manualTripDuration(l))
                        .font(.interScaled(11, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                    HStack(spacing: 4) {
                        stepButton("minus") { model.adjustDuration(by: -ManualTripModel.durationStep) }
                        Text(ManualTripDurationText.string(model.duration, lang: l))
                            .font(.interScaled(15, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(c.text)
                            .frame(minWidth: 64)
                            .accessibilityIdentifier("manual_trip_duration")
                        stepButton("plus") { model.adjustDuration(by: ManualTripModel.durationStep) }
                    }
                }
            }
            if model.durationTouched, let suggested = model.suggestedDuration {
                Button {
                    Haptics.tap()
                    model.applySuggestedDuration()
                } label: {
                    Text(AppStrings.manualTripSuggestedTime(
                        l, time: ManualTripDurationText.string(suggested, lang: l)))
                        .font(.interScaled(13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("manual_trip_suggested")
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func dayButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.interScaled(13, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background {
                    if selected {
                        Capsule().fill(c.card)
                            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.08), radius: 2, y: 1)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        let c = AppTheme.colors(for: scheme)
        return Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 30, height: 30)
                .background(c.cardAlt, in: Circle())
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(icon == "plus" ? "+" : "−") \(ManualTripDurationText.string(ManualTripModel.durationStep, lang: lang.language))")
        .accessibilityValue(ManualTripDurationText.string(model.duration, lang: lang.language))
        .accessibilityIdentifier("manual_trip_duration_\(icon)")
    }

    private func vehicleChooser(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            vehicleRow(id: nil, emoji: nil, title: AppStrings.noVehicle(lang.language), c: c)
            ForEach(settings.recordableVehicles) { vehicle in
                Divider().overlay(c.border).padding(.leading, 16)
                vehicleRow(id: vehicle.id, emoji: vehicle.displayEmoji, title: vehicle.name, c: c)
            }
        }
        .surfaceCard(cornerRadius: 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func vehicleRow(id: UUID?, emoji: String?, title: String, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.selection()
            model.vehicleId = id
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showsVehicles = false }
        } label: {
            HStack(spacing: 10) {
                if let emoji {
                    Text(emoji).font(.inter(16))
                } else {
                    Image(systemName: "car").font(.system(size: 14)).foregroundStyle(c.textSecondary)
                }
                Text(title)
                    .font(.interScaled(16, weight: .medium))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if model.vehicleId == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(model.vehicleId == id ? .isSelected : [])
    }

    /// «Строим маршрут…» и ошибки — строкой, на месте плиток. Красного на
    /// верном вводе больше нет: время, которое не успело закончиться, лист
    /// сдвигает сам, пока его не тронули (`ManualTripDateDefaults.untouchedStart`).
    @ViewBuilder
    private func routeState(_ c: AppTheme.Colors) -> some View {
        if model.isRouting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(AppStrings.manualTripRouting(lang.language))
                    .font(.interScaled(14))
                    .foregroundStyle(c.textSecondary)
            }
        } else if let text = problemText {
            Text(text)
                .font(.interScaled(14, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_error")
        }
    }

    private var problemText: String? {
        let l = lang.language
        if model.isRouteTooLong { return AppStrings.manualTripErrorTooLong(l) }
        if model.route != nil, model.endsLater { return AppStrings.manualTripErrorEndsLater(l) }
        guard let error = model.routeError else { return nil }
        switch error {
        case .noRoute: return AppStrings.manualTripErrorNoRoute(l)
        case .offline: return AppStrings.manualTripErrorOffline(l)
        case .tooManyStops, .failed: return AppStrings.manualTripErrorFailed(l)
        }
    }

    /// Плитки — те же, что на странице поездки (`DetailStatCard`): дистанция
    /// зелёным, время чернилами.
    @ViewBuilder
    private func tiles(_ c: AppTheme.Colors) -> some View {
        if let route = model.route {
            let l = lang.language
            let distance = Measure.distanceParts(
                metres: routeDistance(route), unit: distanceUnit, lang: l, style: .tenths)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                DetailStatCard(value: distance.value, unit: distance.unit,
                               label: AppStrings.distance(l), color: c.distance)
                    .accessibilityIdentifier("manual_trip_distance")
                DetailStatCard(segments: TripDetailFormat.durationSegments(model.duration, lang: l),
                               label: AppStrings.duration(l), color: c.text)
            }
        }
    }

    /// То же число, что ляжет в базу: `TripDistanceGate` по тем же точкам с
    /// тем же временем. `MKRoute.distance` показал бы одно, а сохранилось бы
    /// другое.
    private func routeDistance(_ route: ManualTripRouter.Route) -> Double {
        let stamps = ManualTripBuilder.timestamps(
            count: route.coordinates.count, startDate: model.startDate, duration: model.duration)
        return TripDistanceGate.totalDistance(
            zip(route.coordinates, stamps).map {
                TripDistanceGate.Sample(latitude: $0.0.latitude,
                                        longitude: $0.0.longitude, timestamp: $0.1)
            }
        )
    }

    /// Карточка отказа записи — состояния 36а и 36в: у отказа есть причина и
    /// действие, и у двух случаев они разные.
    private func refusalCard(_ error: ManualTripCreateError, _ c: AppTheme.Colors) -> some View {
        let l = lang.language
        return VStack(alignment: .leading, spacing: 4) {
            Text(error == .noAccess ? AppStrings.manualFailedProTitle(l) : AppStrings.manualFailedDbTitle(l))
                .font(.interScaled(17, weight: .semibold))
                .foregroundStyle(c.text)
            Text(error == .noAccess ? AppStrings.manualFailedProText(l) : AppStrings.manualFailedDbText(l))
                .font(.interScaled(15))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.action()
                switch error.action {
                case .renew:
                    model.clearCreateError()
                    paywallOverSheet = true
                case .retry:
                    create()
                }
            } label: {
                Text(error.action == .renew ? AppStrings.proCtxRenew(l) : AppStrings.retry(l))
                    .font(.interScaled(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.accent))
            }
            .buttonStyle(PressableCardStyle())
            .padding(.top, 8)
            .accessibilityIdentifier("manual_trip_refusal_action")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("manual_trip_create_error")
    }

    private func saveButton(_ c: AppTheme.Colors) -> some View {
        let ready = model.canCreate && !isCreating
        return Button {
            Haptics.action()
            create()
        } label: {
            HStack(spacing: 8) {
                if isCreating || model.isRouting {
                    ProgressView().tint(.white).controlSize(.small)
                }
                Text(AppStrings.manualTripSave(lang.language))
                    .font(.interScaled(17, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(AppTheme.accent.opacity(ready ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!ready)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(c.bg)
        .accessibilityIdentifier("manual_trip_create")
    }

    // MARK: - Общее

    private func topBar(_ c: AppTheme.Colors, eyebrow: String) -> some View {
        HStack(spacing: 12) {
            Text(eyebrow.uppercased(lang.language))
                .font(.custom("PressStart2P-Regular", size: 9))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            closeButton(c)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 12)
    }

    /// Один выход на обеих стадиях — тот же круг, что у страницы поездки.
    private func closeButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            NavCircleIcon(systemImage: "xmark", glyphSize: 15)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.cancel(lang.language))
        .accessibilityIdentifier("manual_trip_cancel")
    }

    private var trimmedQuery: String {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var timeRangeText: String {
        let start = Self.timeFormatter.string(from: model.startDate)
        let end = model.startDate.addingTimeInterval(model.duration)
        return "\(start) – \(Self.timeFormatter.string(from: end))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var selectedVehicle: Vehicle? {
        guard let id = model.vehicleId else { return nil }
        return settings.vehicles.first { $0.id == id }
    }

    /// Пустая заготовка промежуточной точки на карту не идёт: координата
    /// (0, 0) — точка в Гвинейском заливе.
    private var orderedPoints: [ManualTripPoint] {
        var all: [ManualTripPoint] = []
        if let from = model.from { all.append(from) }
        all.append(contentsOf: model.via.filter { !$0.isPlaceholder })
        if let to = model.to { all.append(to) }
        return all
    }

    private func name(_ point: ManualTripPoint) -> String {
        point.name.isEmpty ? AppStrings.manualTripSearchHint(lang.language) : point.name
    }

    private func identifier(for slot: Field) -> String {
        switch slot {
        case .from: "manual_trip_point_from"
        case .to: "manual_trip_point_to"
        case .via(let index): "manual_trip_point_via_\(index)"
        }
    }

    private func focusQuery() {
        // Поле появляется вместе со стадией; фокус ставится следующим витком,
        // иначе клавиатура не приезжает (та же ловушка, что у поиска «Мест»).
        Task { @MainActor in queryFocused = true }
    }

    private func select(_ slot: Field) {
        field = slot
        model.updateSearch("")
        reloadSuggestions()
        if stage != .places { withAnimation(.easeOut(duration: 0.2)) { stage = .places } }
        focusQuery()
    }

    private func removeVia(at index: Int) {
        guard index < model.via.count else { return }
        model.via.remove(at: index)
        model.recomputeRoute()
        if case .via = field {
            field = model.to == nil ? .to : .from
            if model.from != nil && model.to != nil {
                queryFocused = false
                withAnimation(.easeOut(duration: 0.25)) { stage = .trip }
                return
            }
        }
        reloadSuggestions()
    }

    private func addVia() {
        model.via.append(ManualTripPoint(name: "", coordinate: CLLocationCoordinate2D()))
        select(.via(model.via.count - 1))
    }

    /// Точка выбрана: кладём на место, фокус — в следующее пустое поле, а
    /// когда пустых нет — страница поездки.
    private func pick(_ point: ManualTripPoint) async {
        switch field {
        case .from: model.from = point
        case .to: model.to = point
        case .via(let index):
            if index < model.via.count { model.via[index] = point }
        }
        model.updateSearch("")
        model.recomputeRoute()
        if model.from == nil {
            field = .from
        } else if model.to == nil {
            field = .to
        } else {
            queryFocused = false
            withAnimation(.easeOut(duration: 0.25)) { stage = .trip }
            return
        }
        reloadSuggestions()
        focusQuery()
    }

    /// «Найти» на клавиатуре — первая строка списка: поиск Apple, когда
    /// что-то набрано, иначе первая подсказка.
    private func submitQuery() {
        if trimmedQuery.count > 1 {
            guard let first = model.completions.first else { return focusQuery() }
            Task {
                guard let point = await model.resolve(first) else { return focusQuery() }
                await pick(point)
            }
        } else if let first = suggestions.first {
            Task { await pick(first.point) }
        } else {
            focusQuery()
        }
    }

    private func reloadSuggestions() {
        let l = lang.language
        let repository = tripManager.repository
        let home = settings.homeLocation.map {
            ManualTripPoint(name: AppStrings.manualTripChipHome(l), coordinate: $0,
                            locality: repository.cachedLocality(for: $0))
        }
        let places = ManualTripFrequentPlaces.top(
            PlaceManager.shared.places, passCount: { PlaceManager.shared.passCount(for: $0) }
        ).map {
            ManualTripPoint(name: ($0.name?.isEmpty == false ? $0.name : nil) ?? AppStrings.placeUnnamed(l),
                            coordinate: $0.coordinate,
                            locality: repository.cachedLocality(for: $0.coordinate))
        }
        let taken: CLLocationCoordinate2D? = {
            switch field {
            case .from: return model.to?.coordinate
            case .to: return model.from?.coordinate
            case .via: return nil
            }
        }()
        suggestions = ManualTripSuggestions.build(
            home: home, places: places, recent: recentEnds(), excluding: taken)
    }

    /// Концы последних поездок — их имена из кэша геокодера (своего запроса
    /// лист не делает), подпись — когда это было.
    private func recentEnds() -> [ManualTripSuggestions.RecentEnd] {
        let l = lang.language
        var ends: [ManualTripSuggestions.RecentEnd] = []
        for trip in tripManager.fetchTrips(limit: 8, offset: 0) {
            guard let polyline = trip.previewPolyline else { continue }
            let coords = Trip.decodePolyline(polyline)
            let when = RelativeTripDate.string(from: trip.startDate, language: l)
            for coordinate in [coords.last, coords.first].compactMap({ $0 }) {
                guard let name = tripManager.repository.cachedLocality(for: coordinate) else { continue }
                ends.append(.init(name: name, coordinate: coordinate, detail: when))
            }
        }
        return ends
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        if model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let shown = model.displayTitle {
            // Сохраняется то имя, которое человек видел в заголовке листа, —
            // а не то, что геокодер подберёт потом.
            model.title = shown
        }
        Task {
            let result = await model.create(using: tripManager)
            isCreating = false
            guard let result else { return }
            onCreated(result)
            dismiss()
        }
    }
}
