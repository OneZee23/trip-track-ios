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
    /// Покупка НЕ записывает поездку сама — «Записать» человек нажимает сам.
    ///
    /// Константой, потому что это решение, а не деталь: автозапись после
    /// покупки означала бы, что человек, зашедший на пейвол из листа,
    /// получает поездку одним нажатием, которого он не делал. Держит
    /// `ManualTripPaywallReturnTests`.
    static let recordsAutomaticallyAfterPurchase = false

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
    @FocusState private var searchFocused: Bool
    @State private var isCreating = false
    /// «Точка на карте» взведена — следующий тап по герою листа ставит точку
    /// в активное поле (`ManualTripActiveField`), как и в поиске.
    @State private var mapTapArmed = false
    @State private var frequentPlaces: [Place] = []
    /// Геометрия платной части — числом, а не измерением (правило проекта).
    /// Карта-герой 40 % высоты экрана: прежние 260 pt были одинаковы у SE и
    /// у Pro Max, то есть на первом занимали полэкрана, а на втором — треть.
    private var layout: ProLayout {
        let metrics = WindowLayoutMetrics.shared
        return ProLayout(height: metrics.size?.height ?? 844,
                         safeTop: metrics.safeAreaInsets?.top ?? 47,
                         safeBottom: metrics.safeAreaInsets?.bottom ?? 34)
    }

    /// Пейвол открыт ПОВЕРХ этого листа (состояние 36б).
    ///
    /// Именно поверх, а не подменой содержимого хоста: `@StateObject model`
    /// остаётся жив, и набранное — точки, остановки, время, машина —
    /// сохраняется САМО, без отдельного кода восстановления. Подменить
    /// содержимое значило бы уничтожить модель вместе с ним (§12.2 спеки).
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
        // Второй лист ПОВЕРХ первого — законный случай: он не «вместо», а
        // «над», и первый под ним не закрывается. Запрет на две презентации
        // подряд (CLAUDE.md) про другое — про «закрыть одну и открыть другую
        // в одном нажатии», чего здесь не происходит.
        .sheet(isPresented: $paywallOverSheet) {
            PlusPaywallSheet(feature: .manualTrip, origin: .manualTrip)
        }
    }

    // MARK: - Шапка

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 16) {
            if !dynamicTypeSize.isAccessibilitySize { formTitle(c) }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                if searchTarget != nil { cancelSearch() } else { dismiss() }
            } label: {
                Text(AppStrings.cancel(lang.language))
                    .font(.interScaled(16, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("manual_trip_cancel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func formTitle(_ c: AppTheme.Colors) -> some View {
        Text(AppStrings.manualTripEntry(lang.language))
            .font(.interScaled(18, weight: .bold, relativeTo: .headline))
            .foregroundStyle(c.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Форма

    private func formStage(_ c: AppTheme.Colors) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // The large heading scrolls; cancel and save stay reachable
                    // even on a 375 × 667 phone at the largest text setting.
                    if dynamicTypeSize.isAccessibilitySize { formTitle(c) }
                    pointsCard(c)
                    ManualTripQuickPointsRow(
                        home: settings.homeLocation,
                        frequentPlaces: frequentPlaces,
                        isMapTapArmed: mapTapArmed,
                        onPick: quickPick,
                        onArmMapTap: { mapTapArmed = true }
                    )
                    mapCard(c, height: layout.manualMap)
                    routeStatus(c)
                    ManualTripWhenVehicleCard(model: model, vehicles: settings.recordableVehicles)
                    titleCard(c)
                    if dynamicTypeSize.isAccessibilitySize {
                        footerDetails(c).id("manual_footer_details")
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.createError) { _, error in
                if dynamicTypeSize.isAccessibilitySize, error != nil {
                    proxy.scrollTo("manual_footer_details", anchor: .bottom)
                }
            }
        }
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

    /// Выход из второй стадии. Заготовка промежуточной точки, ради которой
    /// поиск и открывали, живёт в `model.via` с координатой (0, 0) — и, не
    /// убери её здесь, оставалась бы в форме пустой строкой «Через», которую
    /// снимает только кнопка «минус», о которой человек не думал. Маршруту она
    /// не мешала (и `recomputeRoute`, и карта её отфильтровывают), поэтому
    /// молчала.
    private func cancelSearch() {
        searchFocused = false
        if case .via(let index) = searchTarget {
            model.discardPlaceholderVia(at: index)
        }
        searchTarget = nil
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
        HStack(spacing: 8) {
            Rectangle().fill(c.border).frame(height: 1)
            Button {
                Haptics.tap()
                swapPoints()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(c.cardAlt, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(AppStrings.manualTripSwapPoints(lang.language))
            .accessibilityIdentifier("manual_trip_swap")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
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
                    .font(.interScaled(15, weight: .semibold))
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
                            .font(.interScaled(13, weight: .semibold, relativeTo: .caption))
                            .foregroundStyle(c.textSecondary)
                        Text(displayName(point))
                            .font(.interScaled(15, weight: .semibold))
                            .foregroundStyle(point == nil ? c.textSecondary : c.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
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
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 44, height: 44)
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
                .font(.interScaled(13))
                .foregroundStyle(c.textSecondary)
        } else if model.isRouteTooLong {
            // Кнопка выключена, и рядом написано почему. Молча выключенная
            // кнопка — та самая мёртвая, которую запрещает CLAUDE.md.
            Text(AppStrings.manualTripErrorTooLong(lang.language))
                .font(.interScaled(13, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_too_long")
        } else if model.endsLater {
            // Тот же случай, что `isRouteTooLong`: кнопка выключена, и рядом
            // написано почему.
            Text(AppStrings.manualTripErrorEndsLater(lang.language))
                .font(.interScaled(13, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_ends_later")
        } else if let error = model.routeError {
            Text(errorText(error))
                .font(.interScaled(13, weight: .semibold))
                .foregroundStyle(AppTheme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_error")
        } else if let route = model.route {
            Text(Measure.distance(metres: routeDistance(route), unit: distanceUnit,
                                  lang: lang.language, style: .tenths))
                .font(.interScaled(15, weight: .bold))
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
                .font(.interScaled(13, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(c.textSecondary)
            TextField(AppStrings.tripTitlePlaceholder(lang.language), text: $model.title)
                .font(.interScaled(16))
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
        VStack(spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize { footerDetails(c) }
            createButton(c)
        }
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(c.bg)
    }

    /// At accessibility sizes details scroll with the form, leaving the
    /// explicit save action reachable without covering all editable fields.
    private func footerDetails(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 8) {
            if let error = model.createError { refusalCard(error, c) }
            if let summary = routeSummary ?? ((model.from == nil || model.to == nil)
                ? AppStrings.manualTripNeedPoints(lang.language) : nil) {
                Text(summary)
                    .font(.interScaled(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manual_trip_summary")
            }
            Text(AppStrings.manualHonesty(lang.language))
                .font(.interScaled(12, relativeTo: .caption))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manual_trip_honesty")
        }
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : 16)
    }

    /// Карточка отказа записи — состояния 36а и 36в.
    ///
    /// Карточка, а не строка: у отказа есть ПРИЧИНА и есть ДЕЙСТВИЕ, и у двух
    /// случаев они разные. Общее «не удалось» заставило бы человека с
    /// кончившейся подпиской жать «Повторить», пока не устанет, а человека с
    /// отказом базы — идти покупать то, что у него и так есть.
    private func refusalCard(
        _ error: ManualTripCreateError, _ c: AppTheme.Colors
    ) -> some View {
        let l = lang.language
        return VStack(alignment: .leading, spacing: 4) {
            Text(refusalTitle(error, l))
                .font(.interScaled(17, weight: .semibold))
                .foregroundStyle(c.text)
            Text(refusalText(error, l))
                .font(.interScaled(15))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.action()
                switch error.action {
                case .renew:
                    // Пейвол — ВТОРОЙ лист ПОВЕРХ этого, а не подмена
                    // содержимого хоста. Модель под ним остаётся жива, и
                    // точки, остановки, время и машина сохраняются САМИ;
                    // подмена уничтожила бы `@StateObject` вместе с
                    // набранным (§12.2 спеки).
                    model.clearCreateError()
                    paywallOverSheet = true
                case .retry:
                    create()
                }
            } label: {
                Text(refusalAction(error, l))
                    .font(.interScaled(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accent)
                    )
            }
            .buttonStyle(PressableCardStyle())
            .padding(.top, 8)
            .accessibilityIdentifier("manual_trip_refusal_action")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(c.border, lineWidth: 1)
        )
        .accessibilityIdentifier("manual_trip_create_error")
    }

    private func refusalTitle(
        _ error: ManualTripCreateError, _ l: LanguageManager.Language
    ) -> String {
        switch error {
        case .noAccess: return AppStrings.manualFailedProTitle(l)
        case .notSaved: return AppStrings.manualFailedDbTitle(l)
        }
    }

    private func refusalText(
        _ error: ManualTripCreateError, _ l: LanguageManager.Language
    ) -> String {
        switch error {
        case .noAccess: return AppStrings.manualFailedProText(l)
        case .notSaved: return AppStrings.manualFailedDbText(l)
        }
    }

    private func refusalAction(
        _ error: ManualTripCreateError, _ l: LanguageManager.Language
    ) -> String {
        switch error.action {
        case .renew: return AppStrings.proCtxRenew(l)
        case .retry: return AppStrings.retry(l)
        }
    }

    private func createButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.action()
            create()
        } label: {
            Text(AppStrings.manualTripSave(lang.language))
                .font(.interScaled(16, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
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
        .accessibilityIdentifier("manual_trip_create")
    }

    /// The result summary is separate from the action: numbers never replace
    /// the verb on a button, regardless of route length or language.
    private var routeSummary: String? {
        guard let route = model.route else { return nil }
        return ManualTripSummaryLine.compose(
            distance: Measure.distance(metres: routeDistance(route), unit: distanceUnit,
                                       lang: lang.language, style: .tenths),
            duration: ManualTripDurationText.string(model.duration, lang: lang.language),
            when: RelativeTripDate.string(from: model.startDate, language: lang.language)
        )
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
            if !searchFocused {
                mapCard(c, height: dynamicTypeSize.isAccessibilitySize ? 120 : 190)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            searchField(c)

            if !searchFocused {
                ManualTripQuickPointsRow(
                    home: settings.homeLocation,
                    frequentPlaces: frequentPlaces,
                    isMapTapArmed: mapTapArmed,
                    onPick: quickPick,
                    onArmMapTap: { mapTapArmed = true }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Список сам по себе скроллится — `LazyVStack` внутри `ScrollView`
            // по правилу проекта для списков длиннее двадцати строк.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.completions.enumerated()), id: \.offset) { _, item in
                        completionRow(item, c: c)
                    }
                }
                // Пустой список — это «ищем», «не нашлось» или «ещё ничего не
                // набрано», и до 0.8.4 экран отвечал на все три одинаковым
                // белым местом. Форму этого состояния дорисует дизайнер; пока
                // здесь стоит честный минимум.
                if model.completions.isEmpty && !model.isSearching
                    && model.query.trimmingCharacters(in: .whitespacesAndNewlines).count > 1 {
                    Text(AppStrings.noResults(lang.language))
                        .font(.interScaled(14))
                        .foregroundStyle(c.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .accessibilityIdentifier("manual_trip_no_results")
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func searchField(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            TextField(
                AppStrings.manualTripSearchHint(lang.language),
                text: Binding(get: { model.query }, set: { model.updateSearch($0) }),
                prompt: Text(AppStrings.manualTripSearchHint(lang.language))
                    .foregroundStyle(c.textSecondary)
            )
            .font(.interScaled(16))
            .foregroundStyle(c.text)
            .autocorrectionDisabled()
            .focused($searchFocused)
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
                    .font(.interScaled(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.interScaled(12))
                        .foregroundStyle(c.textSecondary)
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
        searchFocused = false
        searchTarget = nil
        mapTapArmed = false
        model.updateSearch("")
        model.recomputeRoute()
    }
}
