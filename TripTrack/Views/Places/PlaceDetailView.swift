import SwiftUI
import CoreLocation

/// Экран места (0.6.8, S3): карта с булавкой и нитками проездов, три плитки,
/// «обычно занимает» по направлениям, список проездов; «…» — переименовать,
/// удалить. Читает `PlaceDetailViewModel`; в `body` ни одного похода в базу.
struct PlaceDetailView: View {
    let placeId: UUID
    let onOpenTrip: (UUID, TripFocus) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @StateObject private var model: PlaceDetailViewModel
    @State private var showsMenu = false
    @State private var confirmingDelete = false
    @State private var renaming = false

    private static let dayMonthWeekday = LocalizedDateFormatter.templates("dMMMEEE")
    /// Время проезда — своим шаблоном, чтобы 12/24 часа решала локаль, а не мы.
    private static let clockTime = LocalizedDateFormatter.templates("jmm")
    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")
    private static let monthYear = LocalizedDateFormatter.templates("MMMyyyy")
    /// Внутренний отступ обеих плашек. Колонка текста начинается от него плюс
    /// `PassCourseGlyph.diameter` плюс `PassCourseGlyph.spacing` — одинаково в
    /// «Обычно занимает» и в каждой строке проезда.
    private static let cardInset: CGFloat = 14

    init(placeId: UUID, onOpenTrip: @escaping (UUID, TripFocus) -> Void) {
        self.placeId = placeId
        self.onOpenTrip = onOpenTrip
        _model = StateObject(wrappedValue: PlaceDetailViewModel(placeId: placeId))
    }

    var body: some View {
        // Вынесенной цепочкой, как у `TripDetailView.body`: закрытие экрана —
        // условие для экрана целиком, а не часть его содержимого.
        placeDetailBody
            .onChange(of: model.place == nil) { wasNil, isNil in
                // Место исчезло, пока экран был открыт (удалили на другом
                // пути; устаревший id в `.navigateToPlace`) — закрываемся
                // сами, а не показываем скелет «Без названия» без карты и с
                // плитками «0/—/—». Первичный `nil` — до `load()` — не в
                // счёт: экран ещё ни разу не показал место.
                if isNil && !wasNil { dismiss() }
            }
    }

    private var placeDetailBody: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        return VStack(spacing: 0) {
            CustomNavBar(title: model.place?.name ?? AppStrings.placeUnnamed(l)) {
                menuButton(c: c, l: l)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    mapCard(c: c, l: l)
                    tilesRow(c: c, l: l)
                    usualCard(c: c, l: l)
                    passesSection(c: c, l: l)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                // Бар спрятан — клиренс под таб-бар не нужен, но домашний
                // индикатор снизу всё равно нужно освободить.
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Пояс-и-подтяжки вдобавок к тому, что уже держит `CustomNavBar`, —
        // как у `VehicleDetailView`: не даёт системному бару мигнуть при
        // резком pop посреди анимации.
        .background(NavBarKiller())
        .ignoresSafeArea(edges: .bottom)
        .task {
            model.load()
            // Пришли по устаревшему id (`.navigateToPlace` на уже удалённое
            // место): `place` был `nil` и остался `nil`, перехода нет, и
            // `onChange` в `body` не сработает никогда — закрываемся здесь.
            if model.place == nil { dismiss() }
        }
        .sheet(isPresented: $renaming) {
            PlaceRenameSheet(name: model.place?.name) { model.rename($0) }
        }
        // Дом-диалог, не системный — см. «Dialogs» в CLAUDE.md. Корень экрана,
        // а не внутри ScrollView: иначе скрим был бы размером с секцию.
        .appConfirm(
            isPresented: $confirmingDelete,
            title: AppStrings.placeDeleteTitle(l),
            message: AppStrings.placeDeleteMessage(l),
            actions: [
                AppDialogAction(AppStrings.placeDelete(l), kind: .destructive) {
                    // Закрывает экран `onChange` выше (place станет nil) —
                    // путь один; звать `dismiss()` здесь же означало бы
                    // закрывать дважды.
                    model.delete()
                }
            ]
        )
        // `.contain`, не по умолчанию: без своего контейнера SwiftUI отдаёт
        // этот идентификатор вниз по немаркированным обёрткам `CustomNavBar`
        // и ПЕРЕТИРАЕТ им `place_menu` у кнопки «…» (проверено дампом дерева
        // доступности) — кнопки и текст внутри при этом остаются каждый сам
        // по себе, просто у экрана появляется собственный якорь.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place_detail")
    }

    // MARK: - «…»

    private func menuButton(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            showsMenu = true
        } label: {
            NavCircleIcon(systemImage: "ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.moreActions(l))
        .accessibilityIdentifier("place_menu")
        .popover(isPresented: $showsMenu, arrowEdge: .top) {
            ActionPopoverList(items: menuItems(l))
        }
    }

    /// Поповер закрывается ДО показа листа или диалога: тот же приём, что у
    /// `VehicleDetailView.vehicleActionItems` — представление, запрошенное в
    /// том же runloop, где ещё идёт закрытие поповера, гонку иногда проигрывает.
    private func menuItems(_ l: LanguageManager.Language) -> [ActionPopoverList.Item] {
        func run(_ action: @escaping () -> Void) {
            showsMenu = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                action()
            }
        }
        return [
            .init(title: AppStrings.placeRename(l), systemImage: "pencil",
                  accessibilityId: "place_action_rename") { run { renaming = true } },
            .init(title: AppStrings.placeDelete(l), systemImage: "trash", isDestructive: true,
                  accessibilityId: "place_action_delete") {
                run { confirmingDelete = true }
            },
        ]
    }

    // MARK: - Карта

    @ViewBuilder
    private func mapCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let place = model.place {
            VStack(alignment: .leading, spacing: 8) {
                PlacesMapView(pins: [PlacePin(id: placeId, coordinate: place.coordinate)],
                              routes: model.routes, selectedId: placeId, isInteractive: false)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(mapCaption(place, l))
                    .font(.system(size: 11, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(c.textTertiary)
                    // Длинное имя иначе даёт три строки и сдвигает плитки ниже.
                    .lineLimit(2)
            }
        }
    }

    /// «Джубга · 44.32, 38.71 · 11 проездов». Координата — не расстояние, ей
    /// не нужна `Measure`: широта и долгота одни и те же в любой единице.
    private func mapCaption(_ place: Place, _ l: LanguageManager.Language) -> String {
        let name = place.name ?? AppStrings.placeUnnamed(l)
        let coordinate = String(format: "%.2f, %.2f", place.latitude, place.longitude)
        let count = "\(AppStrings.formattedCount(model.stats.passCount, lang: l)) \(AppStrings.nounPasses(l, model.stats.passCount))"
        return "\(name) · \(coordinate) · \(count)"
    }

    // MARK: - Плитки

    /// Тот же `DetailStatCard`, что у путешествия (`JourneyDetailView.totals`)
    /// и поездки — общий компонент плитки, а не его копия. Держится это тем,
    /// что дата у него короткая (`tileDate`): полная дата с годом
    /// («Jun 18, 2026») в трети ширины плитки обрезалась в «Jun 18, 2…» даже
    /// с `minimumScaleFactor` — короткая («18 июн») в тот же 23pt влезает.
    private func tilesRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 10) {
            DetailStatCard(value: "\(model.stats.passCount)",
                           label: AppStrings.nounPasses(l, model.stats.passCount),
                           color: AppTheme.accent)
            DetailStatCard(value: model.stats.firstAt.map { Self.tileDate($0, lang: l) } ?? "—",
                           label: AppStrings.placeTileFirst(l),
                           color: AppTheme.accent)
            DetailStatCard(value: model.stats.lastAt.map { Self.tileDate($0, lang: l) } ?? "—",
                           label: AppStrings.placeTileLast(l),
                           color: AppTheme.accent)
        }
    }

    /// «18 июн» внутри текущего календарного года просмотра, иначе
    /// «июн 2024» — без года место, которое не видели три года, читалось бы
    /// как «в этом году». Чистая функция (`now`/`calendar` параметрами, не
    /// `Date()`/`.current` внутри тела) — год решает тест, а не то, в каком
    /// году открыли экран.
    static func tileDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                          lang: LanguageManager.Language) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let templates = sameYear ? dayMonth : monthYear
        return templates[lang]?.string(from: date) ?? ""
    }

    // MARK: - «Обычно занимает»

    @ViewBuilder
    private func usualCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if !model.stats.directions.isEmpty {
            usualShell(c: c, l: l) {
                VStack(spacing: 12) {
                    ForEach(Array(model.stats.directions.enumerated()), id: \.offset) { _, direction in
                        directionRow(direction, c: c, l: l)
                    }
                }
            }
        } else if let median = model.stats.medianElapsed {
            // Проезды есть, но ни один не нёс курса — сгруппировать по
            // направлению нечем, а факт «обычно занимает» всё равно есть.
            usualShell(c: c, l: l) {
                usualRow(course: PlacePass.unknownCourse,
                         median: median,
                         second: PlaceUsuallyLine.compose(count: model.stats.passCount,
                                                          best: median, worst: median, lang: l),
                         // Не «в сторону …», а «Без направления»: точка вместо
                         // стрелки иначе выглядела бы недорисованной.
                         towards: AppStrings.placeNoDirection(l), c: c)
            }
        }
    }

    /// Шапка карточки: заголовок и ПОД ним подпись, от чего отсчитаны минуты.
    /// Одной строкой через точку-разделитель («Обычно занимает · от старта
    /// поездки») она читалась как продолжение заголовка и заставляла
    /// перечитывать — замечание владельца 16 сентября.
    private func usualShell<Content: View>(
        c: AppTheme.Colors, l: LanguageManager.Language,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.placeUsuallyTitle(l))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(c.text)
                Text(AppStrings.placeUsuallyCaption(l))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            content()
        }
        .padding(.horizontal, Self.cardInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 16)
    }

    private func directionRow(_ direction: PlaceStats.Direction, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        usualRow(
            course: direction.course,
            median: direction.median,
            second: PlaceUsuallyLine.compose(count: direction.count, best: direction.best,
                                             worst: direction.worst, lang: l),
            towards: model.directionLabels[direction.latestTripId].map { AppStrings.placeTowards(l, name: $0) },
            c: c)
    }

    /// Ровно та же геометрия, что у строки проезда: `PassCourseGlyph` (40 pt),
    /// зазор `PassCourseGlyph.spacing`, две строки текста. Иначе колонки двух
    /// плашек стоят на разном отступе, и одно и то же «1 ч 19 мин» в них не
    /// совпадает — ровно это и было видно на экране до фикса.
    private func usualRow(course: Double, median: TimeInterval, second: String,
                          towards: String?, c: AppTheme.Colors) -> some View {
        HStack(spacing: PassCourseGlyph.spacing) {
            PassCourseGlyph(course: course)
            VStack(alignment: .leading, spacing: 2) {
                Text(CheckpointReading.clock(median, lang: lang.language))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(c.text)
                Text(second)
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
            }
            Spacer(minLength: 8)
            if let towards {
                Text(towards)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Проезды

    @ViewBuilder
    private func passesSection(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if !model.passes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.placePassesSection(l))
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(c.textTertiary)
                LazyVStack(spacing: 10) {
                    ForEach(model.passes) { pass in
                        passRow(pass, c: c, l: l)
                    }
                }
            }
        }
    }

    private func passRow(_ pass: PlacePass, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            onOpenTrip(pass.tripId, model.focus(forPassOf: pass.tripId))
        } label: {
            HStack(spacing: PassCourseGlyph.spacing) {
                PassCourseGlyph(course: pass.course)
                VStack(alignment: .leading, spacing: 2) {
                    Text(passTitle(pass, l))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(c.text)
                    Text(passSubtitle(pass, l))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, Self.cardInset)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("place_pass_row")
    }

    /// «Вс, 6 сент. · 12:40» — дата и час проезда одной строкой. Час нужен
    /// потому, что «туда и обратно» в один день дают две строки с одной датой,
    /// и различить их по ней нельзя.
    private func passTitle(_ pass: PlacePass, _ l: LanguageManager.Language) -> String {
        let date = Self.dayMonthWeekday[l]?.string(from: pass.timestamp) ?? ""
        guard let time = Self.clockTime[l]?.string(from: pass.timestamp), !time.isEmpty else { return date }
        return date.isEmpty ? time : "\(date) · \(time)"
    }

    /// «1 ч 30 мин · 128 км · от старта» — то же чтение, что у «Моментов»
    /// (`TripMomentsTimeline`), только подпись идёт ПОСЛЕ числа: список
    /// проездов — не лента одной поездки, и без слов «от старта» здесь не
    /// сразу ясно, что означают эти два числа. Со строчной и своим ключом —
    /// это хвост фразы, а не её начало.
    private func passSubtitle(_ pass: PlacePass, _ l: LanguageManager.Language) -> String {
        let reading = CheckpointReading.text(elapsed: pass.elapsedFromStart, metres: pass.distanceFromStart,
                                              unit: distanceUnit, lang: l)
        return "\(reading) · \(AppStrings.placeFromStartInline(l))"
    }
}
