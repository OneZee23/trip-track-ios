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
    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")
    private static let monthYear = LocalizedDateFormatter.templates("MMMyyyy")

    init(placeId: UUID, onOpenTrip: @escaping (UUID, TripFocus) -> Void) {
        self.placeId = placeId
        self.onOpenTrip = onOpenTrip
        _model = StateObject(wrappedValue: PlaceDetailViewModel(placeId: placeId))
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        VStack(spacing: 0) {
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
        .task { model.load() }
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
                    model.delete()
                    dismiss()
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
            VStack(alignment: .leading, spacing: 12) {
                Text(AppStrings.placeUsuallyTitle(l))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.text)
                VStack(spacing: 12) {
                    ForEach(Array(model.stats.directions.enumerated()), id: \.offset) { _, direction in
                        directionRow(direction, c: c, l: l)
                    }
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        } else if let median = model.stats.medianElapsed {
            // Проезды есть, но ни один не нёс курса — сгруппировать по
            // направлению нечем, а факт «обычно занимает» всё равно есть.
            VStack(alignment: .leading, spacing: 12) {
                Text(AppStrings.placeUsuallyTitle(l))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.text)
                HStack {
                    Text(AppStrings.placeNoDirection(l))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                    Spacer(minLength: 8)
                    Text(CheckpointReading.clock(median, lang: l))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(c.text)
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func directionRow(_ direction: PlaceStats.Direction, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(AppTheme.accentBg).frame(width: 32, height: 32)
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .rotationEffect(.degrees(direction.course))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(directionPrimaryLine(direction, l))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.text)
                Text(directionSecondaryLine(direction, l))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// «1:30 · к морю» — без подписи направления (кэш геокодера промолчал)
    /// остаётся только время.
    private func directionPrimaryLine(_ direction: PlaceStats.Direction, _ l: LanguageManager.Language) -> String {
        let time = CheckpointReading.clock(direction.median, lang: l)
        guard let label = model.directionLabels[direction.latestTripId] else { return time }
        return "\(time) · \(label)"
    }

    private func directionSecondaryLine(_ direction: PlaceStats.Direction, _ l: LanguageManager.Language) -> String {
        let best = CheckpointReading.clock(direction.best, lang: l)
        let worst = CheckpointReading.clock(direction.worst, lang: l)
        let count = "\(AppStrings.formattedCount(direction.count, lang: l)) \(AppStrings.nounPasses(l, direction.count))"
        return "\(best) · \(worst) · \(count)"
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
            HStack(spacing: 12) {
                Group {
                    if pass.hasCourse {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.accent)
                            .rotationEffect(.degrees(pass.course))
                    } else {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(c.textTertiary)
                    }
                }
                .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(passTitle(pass, l))
                        .font(.system(size: 14, weight: .semibold))
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
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("place_pass_row")
    }

    private func passTitle(_ pass: PlacePass, _ l: LanguageManager.Language) -> String {
        Self.dayMonthWeekday[l]?.string(from: pass.timestamp) ?? ""
    }

    /// «1:30 · 128 км · От старта» — то же чтение, что у «Моментов»
    /// (`TripMomentsTimeline`), только подпись идёт ПОСЛЕ числа: список
    /// проездов — не лента одной поездки, и без слов «от старта» здесь не
    /// сразу ясно, что означают эти два числа.
    private func passSubtitle(_ pass: PlacePass, _ l: LanguageManager.Language) -> String {
        let reading = CheckpointReading.text(elapsed: pass.elapsedFromStart, metres: pass.distanceFromStart,
                                              unit: distanceUnit, lang: l)
        return "\(reading) · \(AppStrings.checkpointFromStart(l))"
    }
}
