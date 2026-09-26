import SwiftUI
import MapKit

/// «Вписать поездку» — единственный вход в ручную поездку (0.8.0, «Плюс»).
///
/// Один лист на всё: точки, дата, длительность, машина, название. Второго
/// листа поверх него нет ни у поиска места, ни у машины — тот увёл бы первый
/// вниз вместе с набранным, ровно как это разобрано у отрезков («Отрезок до…»
/// переключает ТОТ ЖЕ лист во вторую стадию). Поиск здесь — вторая стадия,
/// машина — ряд фишек.
///
/// Редизайн 20 сен 2026 (решения владельца, все четыре — «рекомендованный»
/// вариант): карта — герой, порядок «маршрут → когда → машина → Записать»;
/// точки ставятся чипами («Дом», частые места, тап по карте) не только
/// поиском; длительность подстраивается под маршрут сама, пока её не тронули
/// рукой; лист умеет открыться уже заполненным — `preset`.
///
/// Ошибки маршрута стоят строкой под картой, а не диалогом: системных
/// модалок в приложении нет вовсе (CLAUDE.md, «Dialogs»), а «нет дороги» —
/// это состояние формы, а не вопрос к человеку.
struct ManualTripSheet: View {
    /// Кто пишет в базу. Приходит снаружи, а не берётся из синглтона: у
    /// `TripManager` его нет — экземпляр держит `MapViewModel`, и оба входа
    /// (лента и «Мои») до него дотягиваются.
    let tripManager: TripManager
    /// Готовый лист — дата с календаря, зеркало «обратной дороги». `nil` —
    /// пустая форма, как раньше.
    var preset: ManualTripPreset?
    /// Поездка создана — точки/машина/id для «Открыть»/«Обратно» и для тоста.
    /// Лист закрывает себя сам.
    var onCreated: (ManualTripCreationResult) -> Void = { _ in }

    @StateObject private var model: ManualTripModel
    @State private var searchTarget: SearchTarget?
    @State private var isCreating = false
    /// «Точка на карте» взведена — следующий тап по герою листа ставит точку
    /// в активное поле (`ManualTripActiveField`), как и в поиске.
    @State private var mapTapArmed = false
    @State private var frequentPlaces: [Place] = []

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    init(
        tripManager: TripManager, preset: ManualTripPreset? = nil,
        onCreated: @escaping (ManualTripCreationResult) -> Void = { _ in }
    ) {
        self.tripManager = tripManager
        self.preset = preset
        self.onCreated = onCreated
        _model = StateObject(wrappedValue: preset.map(ManualTripModel.init(preset:)) ?? ManualTripModel())
    }

    /// Какую из точек сейчас ищут. `via` хранит индекс, а не сам объект:
    /// промежуточную можно удалить, пока открыт поиск.
    private enum SearchTarget: Equatable {
        case from
        case to
        case via(Int)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            header(c)
            Divider().overlay(c.border)
            if searchTarget != nil {
                searchStage(c)
            } else {
                formStage(c)
                footer(c)
            }
        }
        .background(c.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            frequentPlaces = ManualTripFrequentPlaces.top(
                PlaceManager.shared.places, passCount: { PlaceManager.shared.passCount(for: $0) }
            )
        }
    }

    // MARK: - Шапка

    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.manualTripEntry(lang.language))
                .font(.inter(16, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 84)

            HStack {
                Button {
                    Haptics.tap()
                    // Из поиска «Отмена» возвращает в форму, а не закрывает
                    // лист: закрыть форму, потеряв набранное, из второй стадии
                    // человек не просил.
                    if searchTarget != nil { searchTarget = nil } else { dismiss() }
                } label: {
                    Text(AppStrings.cancel(lang.language))
                        .font(.inter(16, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("manual_trip_cancel")

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Форма

    private func formStage(_ c: AppTheme.Colors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pointsCard(c)
                ManualTripQuickPointsRow(
                    home: settings.homeLocation,
                    frequentPlaces: frequentPlaces,
                    isMapTapArmed: mapTapArmed,
                    onPick: quickPick,
                    onArmMapTap: { mapTapArmed = true }
                )
                mapCard(c, height: 260)
                routeStatus(c)
                ManualTripWhenVehicleCard(model: model, vehicles: settings.recordableVehicles)
                titleCard(c)
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private func mapCard(_ c: AppTheme.Colors, height: CGFloat) -> some View {
        ManualTripMapView(
            points: orderedPoints,
            route: model.route?.coordinates ?? [],
            onTap: effectiveTarget == nil ? nil : { coordinate in
                Task {
                    let point = await model.point(at: coordinate)
                    await pick(point)
                }
            }
        )
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            // Взведённая «Точка на карте» — единственный признак того, что
            // следующий тап по герою сработает: без рамки это было бы
            // нажатие, эффект которого не виден (CLAUDE.md, «Нажатие обязано
            // отвечать»).
            if mapTapArmed && searchTarget == nil {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.accent, lineWidth: 2)
            }
        }
        .accessibilityIdentifier("manual_trip_map")
    }

    /// Пустая заготовка промежуточной точки на карту не идёт: у неё
    /// координата (0, 0) — точка в Гвинейском заливе, и булавка уехала бы
    /// туда вместе с рамкой карты.
    private var orderedPoints: [ManualTripPoint] {
        var all: [ManualTripPoint] = []
        if let from = model.from { all.append(from) }
        all.append(contentsOf: model.via.filter { !$0.isPlaceholder })
        if let to = model.to { all.append(to) }
        return all
    }

    /// Куда идёт следующий тап по карте — явная цель поиска, а пока её нет,
    /// взведённая чипом «Точка на карте» активная точка формы
    /// (`ManualTripActiveField`). `nil` — тап по карте ничего не делает.
    private var effectiveTarget: SearchTarget? {
        if let searchTarget { return searchTarget }
        guard mapTapArmed else { return nil }
        switch ManualTripActiveField.resolve(from: model.from, to: model.to) {
        case .from: return .from
        case .to: return .to
        }
    }

    // MARK: - Точки

    private func pointsCard(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            pointRow(label: AppStrings.manualTripFrom(lang.language),
                     point: model.from, target: .from, c: c)
            swapRow(c)
            ForEach(Array(model.via.enumerated()), id: \.element.id) { index, stop in
                Divider().overlay(c.border).padding(.leading, 16)
                pointRow(label: AppStrings.manualTripVia(lang.language),
                         point: stop, target: .via(index), c: c, removable: true)
            }
            Divider().overlay(c.border).padding(.leading, 16)
            pointRow(label: AppStrings.manualTripTo(lang.language),
                     point: model.to, target: .to, c: c)

            // Потолка достигли — кнопки нет вовсе: нажатие, которое ничего не
            // делает, хуже отсутствующего (то же правило, что у «Отрезок до…»).
            if model.via.count < ManualTripRouter.maxViaPoints {
                Divider().overlay(c.border).padding(.leading, 16)
                addViaButton(c)
            }
        }
        .surfaceCard(cornerRadius: 16)
    }

    /// Тонкая строка со знаком «поменять местами» поверх границы: точки, а не
    /// маршрут, — via остаётся в прежнем порядке, но едет в обратную сторону
    /// вместе с концами.
    private func swapRow(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Divider().overlay(c.border).padding(.leading, 16)
        }
        .frame(height: 1)
        .overlay(alignment: .trailing) {
            Button {
                Haptics.tap()
                swapPoints()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(c.card, in: Circle())
                    .overlay(Circle().strokeBorder(c.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("manual_trip_swap")
            .padding(.trailing, 12)
        }
    }

    private func swapPoints() {
        let oldFrom = model.from
        model.from = model.to
        model.to = oldFrom
        model.via.reverse()
        model.recomputeRoute()
    }

    private func addViaButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            model.via.append(ManualTripPoint(name: "", coordinate: CLLocationCoordinate2D()))
            searchTarget = .via(model.via.count - 1)
            model.updateSearch("")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(AppStrings.manualTripAddVia(lang.language))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("manual_trip_add_via")
    }

    @ViewBuilder
    private func pointRow(
        label: String, point: ManualTripPoint?, target: SearchTarget,
        c: AppTheme.Colors, removable: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                searchTarget = target
                mapTapArmed = false
                model.updateSearch("")
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.inter(11, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                        Text(displayName(point))
                            .font(.inter(15, weight: .semibold))
                            .foregroundStyle(point == nil ? c.textTertiary : c.text)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier(identifier(for: target))

            if removable, case .via(let index) = target {
                Button {
                    Haptics.tap()
                    guard index < model.via.count else { return }
                    model.via.remove(at: index)
                    model.recomputeRoute()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
    }

    /// Строки точек различаются только подписью, а подпись переводится —
    /// поэтому у каждой свой идентификатор: снимки и озвучка ищут строку, а не
    /// слово «Откуда».
    private func identifier(for target: SearchTarget) -> String {
        switch target {
        case .from: "manual_trip_point_from"
        case .to: "manual_trip_point_to"
        case .via(let index): "manual_trip_point_via_\(index)"
        }
    }

    private func displayName(_ point: ManualTripPoint?) -> String {
        guard let point, !point.name.isEmpty else {
            return AppStrings.manualTripSearchHint(lang.language)
        }
        return point.name
    }

    /// Чип («Дом», частое место) в стадии поиска идёт в цель поиска, в форме —
    /// в первое пустое поле (`ManualTripModel.assignQuickPoint`).
    private func quickPick(_ point: ManualTripPoint) {
        if searchTarget != nil {
            Task { await pick(point) }
        } else {
            model.assignQuickPoint(point)
        }
    }

    // MARK: - Состояние маршрута

    @ViewBuilder
    private func routeStatus(_ c: AppTheme.Colors) -> some View {
        if model.isRouting {
            Text(AppStrings.manualTripRouting(lang.language))
                .font(.inter(13))
                .foregroundStyle(c.textSecondary)
        } else if model.isRouteTooLong {
            // Кнопка выключена, и рядом написано почему. Молча выключенная
            // кнопка — та самая мёртвая, которую запрещает CLAUDE.md.
            Text(AppStrings.manualTripErrorTooLong(lang.language))
                .font(.inter(13, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_too_long")
        } else if let error = model.routeError {
            Text(errorText(error))
                .font(.inter(13, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_error")
        } else if let route = model.route {
            Text(Measure.distance(metres: routeDistance(route), unit: distanceUnit,
                                  lang: lang.language, style: .tenths))
                .font(.inter(15, weight: .bold))
                .foregroundStyle(c.text)
                .accessibilityIdentifier("manual_trip_distance")
        }
    }

    /// То же число, что ляжет в базу: `TripDistanceGate` по тем же точкам с
    /// тем же временем. Брать `MKRoute.distance` здесь значило бы показать
    /// одно, а сохранить другое.
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

    private func errorText(_ error: ManualTripRouteError) -> String {
        switch error {
        case .noRoute: AppStrings.manualTripErrorNoRoute(lang.language)
        case .offline: AppStrings.manualTripErrorOffline(lang.language)
        case .tooManyStops, .failed: AppStrings.manualTripErrorFailed(lang.language)
        }
    }

    // MARK: - Название

    private func titleCard(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.tripTitleLabel(lang.language))
                .font(.inter(11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            TextField(AppStrings.tripTitlePlaceholder(lang.language), text: $model.title)
                .font(.inter(16))
                .foregroundStyle(c.text)
                .submitLabel(.done)
                .accessibilityIdentifier("manual_trip_title")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Кнопка

    private func footer(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.action()
            create()
        } label: {
            Text(footerLabel)
                .font(.inter(16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    (model.canCreate && !isCreating) ? AppTheme.accent : c.textTertiary,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!model.canCreate || isCreating)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(c.bg)
        .accessibilityIdentifier("manual_trip_create")
    }

    /// «420 км · 5 ч 30 мин · вчера 09:00», как только маршрут готов; иначе —
    /// подсказка, чего не хватает. Молча выключенная кнопка запрещена тем же
    /// правилом, что держит строку у «слишком длинного» маршрута.
    private var footerLabel: String {
        if let route = model.route, model.canCreate {
            return ManualTripSummaryLine.compose(
                distance: Measure.distance(metres: routeDistance(route), unit: distanceUnit,
                                           lang: lang.language, style: .tenths),
                duration: ManualTripDurationText.string(model.duration, lang: lang.language),
                when: RelativeTripDate.string(from: model.startDate, language: lang.language)
            )
        }
        if model.from == nil || model.to == nil {
            return AppStrings.manualTripNeedPoints(lang.language)
        }
        return AppStrings.manualTripCreate(lang.language)
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        Task {
            let result = await model.create(using: tripManager)
            isCreating = false
            guard let result else { return }
            onCreated(result)
            dismiss()
        }
    }

    // MARK: - Вторая стадия: поиск

    private func searchStage(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            mapCard(c, height: 190)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            searchField(c)

            ManualTripQuickPointsRow(
                home: settings.homeLocation,
                frequentPlaces: frequentPlaces,
                isMapTapArmed: mapTapArmed,
                onPick: quickPick,
                onArmMapTap: { mapTapArmed = true }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Список сам по себе скроллится — `LazyVStack` внутри `ScrollView`
            // по правилу проекта для списков длиннее двадцати строк.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.completions.enumerated()), id: \.offset) { _, item in
                        completionRow(item, c: c)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func searchField(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            TextField(
                AppStrings.manualTripSearchHint(lang.language),
                text: Binding(get: { model.query }, set: { model.updateSearch($0) })
            )
            .font(.inter(16))
            .foregroundStyle(c.text)
            .autocorrectionDisabled()
            .accessibilityIdentifier("manual_trip_search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(16)
    }

    private func completionRow(_ item: MKLocalSearchCompletion, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            Task {
                guard let point = await model.resolve(item) else { return }
                await pick(point)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("manual_trip_result")
    }

    /// Точка выбрана — кладём её на место цели (поиск ИЛИ взведённый тап по
    /// карте), закрываем стадию поиска и пересчитываем маршрут.
    private func pick(_ point: ManualTripPoint) async {
        switch effectiveTarget {
        case .from: model.from = point
        case .to: model.to = point
        case .via(let index):
            guard index < model.via.count else { break }
            model.via[index] = point
        case nil: return
        }
        searchTarget = nil
        mapTapArmed = false
        model.updateSearch("")
        model.recomputeRoute()
    }
}
