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
/// Ошибки маршрута стоят строкой под точками, а не диалогом: системных
/// модалок в приложении нет вовсе (CLAUDE.md, «Dialogs»), а «нет дороги» —
/// это состояние формы, а не вопрос к человеку.
struct ManualTripSheet: View {
    /// Кто пишет в базу. Приходит снаружи, а не берётся из синглтона: у
    /// `TripManager` его нет — экземпляр держит `MapViewModel`, и оба входа
    /// (лента и «Мои») до него дотягиваются.
    let tripManager: TripManager
    /// Поездка создана — id для «открыть» и для тоста. Лист закрывает себя сам.
    var onCreated: (UUID) -> Void = { _ in }

    @StateObject private var model = ManualTripModel()
    @State private var searchTarget: SearchTarget?
    @State private var isCreating = false

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

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
    }

    // MARK: - Шапка

    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.manualTripEntry(lang.language))
                .font(.system(size: 16, weight: .bold))
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
                        .font(.system(size: 16, weight: .medium))
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
            VStack(alignment: .leading, spacing: 18) {
                mapCard(c)
                subtitleLine(c)
                pointsCard(c)
                routeStatus(c)
                startCard(c)
                durationCard(c)
                vehicleCard(c)
                titleCard(c)
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    private func subtitleLine(_ c: AppTheme.Colors) -> some View {
        Text(AppStrings.manualTripSubtitle(lang.language))
            .font(.system(size: 12.5))
            .foregroundStyle(c.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func mapCard(_ c: AppTheme.Colors) -> some View {
        ManualTripMapView(
            points: orderedPoints,
            route: model.route?.coordinates ?? [],
            onTap: searchTarget == nil ? nil : { coordinate in
                Task { await pick(await model.point(at: coordinate)) }
            }
        )
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    // MARK: - Точки

    private func pointsCard(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            pointRow(label: AppStrings.manualTripFrom(lang.language),
                     point: model.from, target: .from, c: c)
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
                            .font(.system(size: 15, weight: .semibold))
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
        }
        .surfaceCard(cornerRadius: 16)
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
                model.updateSearch("")
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                        Text(displayName(point))
                            .font(.system(size: 15, weight: .semibold))
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

    // MARK: - Состояние маршрута

    @ViewBuilder
    private func routeStatus(_ c: AppTheme.Colors) -> some View {
        if model.isRouting {
            Text(AppStrings.manualTripRouting(lang.language))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
        } else if let error = model.routeError {
            Text(errorText(error))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_error")
        } else if let route = model.route {
            Text(Measure.distance(metres: routeDistance(route), unit: distanceUnit,
                                  lang: lang.language, style: .tenths))
                .font(.system(size: 15, weight: .heavy))
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

    // MARK: - Когда и сколько

    private func startCard(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.manualTripStart(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            DatePicker(
                "",
                selection: $model.startDate,
                in: model.startBounds,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .accessibilityIdentifier("manual_trip_start")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func durationCard(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.manualTripDuration(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)

            HStack(spacing: 14) {
                durationButton("minus", c: c) {
                    model.adjustDuration(by: -ManualTripModel.durationStep)
                }
                Text(durationText(model.duration))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("manual_trip_duration")
                durationButton("plus", c: c) {
                    model.adjustDuration(by: ManualTripModel.durationStep)
                }
            }

            if let suggested = model.suggestedDuration {
                Button {
                    Haptics.tap()
                    model.applySuggestedDuration()
                } label: {
                    Text(AppStrings.manualTripSuggestedTime(
                        lang.language, time: durationText(suggested)))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("manual_trip_suggested")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func durationButton(
        _ icon: String, c: AppTheme.Colors, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 38, height: 38)
                .background(c.cardAlt, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableCardStyle())
    }

    /// «2 ч 30 мин». Единиц расстояния тут нет — только часы и минуты, и обе
    /// подписи берутся у `AppStrings`, а не пишутся строкой.
    private func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let h = AppStrings.hoursUnitShort(lang.language)
        let m = AppStrings.minutesUnitShort(lang.language)
        if hours == 0 { return "\(minutes) \(m)" }
        if minutes == 0 { return "\(hours) \(h)" }
        return "\(hours) \(h) \(minutes) \(m)"
    }

    // MARK: - Машина

    private func vehicleCard(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.vehiclePickerTitle(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    vehicleChip(id: nil, title: AppStrings.noVehicle(lang.language), c: c)
                    // «На что можно писать сейчас» — тот же список, что у
                    // экрана записи: архивная и проданная машина не принимает
                    // новых поездок НИГДЕ (CLAUDE.md, 0.6.4).
                    ForEach(settings.recordableVehicles) { vehicle in
                        vehicleChip(id: vehicle.id, title: vehicle.name, c: c)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func vehicleChip(id: UUID?, title: String, c: AppTheme.Colors) -> some View {
        let selected = model.vehicleId == id
        return Button {
            Haptics.selection()
            model.vehicleId = id
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : c.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? AppTheme.accent : c.cardAlt, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Название

    private func titleCard(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.tripTitleLabel(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            TextField(AppStrings.tripTitlePlaceholder(lang.language), text: $model.title)
                .font(.system(size: 16))
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
            Text(AppStrings.manualTripCreate(lang.language))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
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

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        Task {
            let id = await model.create(using: tripManager)
            isCreating = false
            guard let id else { return }
            onCreated(id)
            dismiss()
        }
    }

    // MARK: - Вторая стадия: поиск

    private func searchStage(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 0) {
            mapCard(c)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            searchField(c)

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
            .font(.system(size: 16))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
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

    /// Точка выбрана — кладём её на место, закрываем стадию поиска и
    /// пересчитываем маршрут. Один путь для поиска и для тапа по карте.
    private func pick(_ point: ManualTripPoint) async {
        switch searchTarget {
        case .from: model.from = point
        case .to: model.to = point
        case .via(let index):
            guard index < model.via.count else { break }
            model.via[index] = point
        case nil: return
        }
        searchTarget = nil
        model.updateSearch("")
        model.recomputeRoute()
    }
}
