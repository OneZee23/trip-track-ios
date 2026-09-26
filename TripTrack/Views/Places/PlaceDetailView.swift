import SwiftUI
import CoreLocation

/// Экран места (макет «Места» 0.8.1, S4).
///
/// Карта — ФОН экрана, а не карточка внутри него: место это точка на земле, и
/// первое, что о нём надо знать, — где она. Поверх карты едет бумажный лист со
/// скруглённым верхом; он и есть содержимое, и он же уносит карту вверх, когда
/// его тянут. До 0.8.1 карта была плашкой 220 pt в общем скролле и читалась
/// иллюстрацией к тексту.
///
/// Читает `PlaceDetailViewModel`; в `body` ни одного похода в базу.
struct PlaceDetailView: View {
    let placeId: UUID
    let onOpenTrip: (UUID, TripFocus) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lang: LanguageManager
    @StateObject private var model: PlaceDetailViewModel
    @State private var confirmingDelete = false
    @State private var renaming = false
    /// 0 — лист внизу и видна карта, 1 — лист под шапкой. Квантуется до 1/20
    /// ДО записи в состояние: на полной точности каждый пройденный пункт
    /// перерисовывает тело, в котором живёт `MKMapView`.
    @State private var headerProgress: CGFloat = 0

    private static let dayMonthWeekday = LocalizedDateFormatter.templates("dMMMEEE")
    private static let dayNumber = LocalizedDateFormatter.templates("d")
    private static let monthShort = LocalizedDateFormatter.templates("MMM")
    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")
    private static let monthYear = LocalizedDateFormatter.templates("MMMyyyy")
    private static let scrollSpace = "place.detail.scroll"

    /// Сколько карты видно до листа. Число из макета; лист начинается ниже
    /// середины экрана, чтобы имя и «Здесь N раз» попадали в первый экран без
    /// прокрутки.
    private static let mapHeight: CGFloat = 322
    /// Высота шапки со скролла — под ней лист и прячется.
    private static let headerHeight: CGFloat = 96

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
        let l = lang.language
        return stage
            .background(AtlasTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // Пояс-и-подтяжки вдобавок к `CustomNavBar` — как у
            // `VehicleDetailView`: не даёт системному бару мигнуть при резком
            // pop посреди анимации.
            .background(NavBarKiller())
            .ignoresSafeArea(.container, edges: .top)
            .task {
                model.load()
                // Пришли по устаревшему id (`.navigateToPlace` на уже
                // удалённое место): `place` был `nil` и остался `nil`,
                // перехода нет, и `onChange` в `body` не сработает никогда —
                // закрываемся здесь.
                if model.place == nil { dismiss() }
            }
            .sheet(isPresented: $renaming) {
                PlaceRenameSheet(name: model.place?.name, address: model.geocodedName) { model.rename($0) }
            }
            // Дом-диалог, не системный — см. «Dialogs» в CLAUDE.md. Корень
            // экрана, а не внутри ScrollView: иначе скрим был бы размером с
            // секцию.
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
            // `.contain`, не по умолчанию: без своего контейнера SwiftUI
            // отдаёт этот идентификатор вниз по немаркированным обёрткам и
            // перетирает им идентификаторы кнопок внутри (проверено дампом
            // дерева доступности).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("place_detail")
    }

    private var stage: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                mapBackdrop
                scroll(height: geo.size.height)
                mapControls
                    // Кружок «Назад» и пилюля живут НА КАРТЕ и уходят вместе с
                    // ней: под шапкой их место занимает та же кнопка и имя.
                    .opacity(Double(1 - min(1, headerProgress * 2)))
                floatingHeader
            }
        }
    }

    // MARK: - Карта

    @ViewBuilder
    private var mapBackdrop: some View {
        if let place = model.place {
            PlacesMapView(pins: [PlacePin(id: placeId, coordinate: place.coordinate, name: place.name)],
                          routes: model.routes, selectedId: placeId, isInteractive: false)
                .frame(height: Self.mapHeight + AtlasTheme.sheetRadius)
                .frame(maxWidth: .infinity, alignment: .top)
                .clipped()
                .allowsHitTesting(false)
        } else {
            AtlasTheme.background.frame(height: Self.mapHeight)
        }
    }

    /// Кружок «Назад» и пилюля «23 проезда» — поверх карты.
    private var mapControls: some View {
        let l = lang.language
        return VStack(spacing: 0) {
            HStack(alignment: .center) {
                NavBackButton()
                Spacer(minLength: 12)
                if model.stats.passCount > 0 {
                    passesPill(l)
                }
            }
            .padding(.horizontal, AtlasTheme.sideInset)
            .padding(.top, 9)
            Spacer(minLength: 0)
        }
        .padding(.top, WindowLayoutMetrics.shared.safeAreaInsets?.top ?? 47)
    }

    /// «— 23 проезда»: штрих цвета нитки и счёт. Нитки на карте без подписи
    /// читались чужим маршрутом, а не проездами этого места.
    private func passesPill(_ l: LanguageManager.Language) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(AtlasTheme.accent).frame(width: 18, height: 3)
            Text("\(AppStrings.formattedCount(model.stats.passCount, lang: l)) \(AppStrings.nounPasses(l, model.stats.passCount))")
                .font(AppType.meta)
                .foregroundStyle(AtlasTheme.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(AtlasTheme.control.opacity(0.94), in: Capsule())
        .shadow(color: .black.opacity(scheme == .dark ? 0.32 : 0.12), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("place_passes_pill")
    }

    /// Шапка со скролла: та же кнопка «Назад» и имя места по центру.
    private var floatingHeader: some View {
        let l = lang.language
        return HStack(spacing: 8) {
            NavBackButton()
            Text(model.place?.name ?? AppStrings.placeUnnamed(l))
                .font(AppType.headerTitle)
                .foregroundStyle(AtlasTheme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            // Симметричный противовес кнопке: без него имя стоит не по центру.
            Color.clear.frame(width: NavCircleIcon.diameter, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, (WindowLayoutMetrics.shared.safeAreaInsets?.top ?? 47) + 3)
        .background {
            AtlasTheme.background.opacity(0.92)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    AtlasTheme.separator.frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        }
        .opacity(Double(headerProgress))
        // Пока шапка прозрачна, её кнопка перехватывала бы тапы по карте.
        .allowsHitTesting(headerProgress > 0.5)
    }

    // MARK: - Лист

    private func scroll(height: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Прозрачное окно в карту. Тянут за него так же, как за лист:
                // жест скролла обязан ловиться на всём экране.
                Color.clear
                    .frame(height: Self.mapHeight)
                    .background(alignment: .top) { scrollProbe }
                sheet
                    .frame(minHeight: max(0, height - Self.mapHeight))
            }
        }
        .coordinateSpace(name: Self.scrollSpace)
        .scrollIndicators(.hidden)
        .onPreferenceChange(PlaceScrollOffsetKey.self) { minY in
            let span = max(1, Self.mapHeight - Self.headerHeight)
            let raw = min(max(-minY / span, 0), 1)
            let stepped = (raw * 20).rounded() / 20
            if stepped != headerProgress { headerProgress = stepped }
        }
    }

    private var scrollProbe: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: PlaceScrollOffsetKey.self,
                                   value: proxy.frame(in: .named(Self.scrollSpace)).minY)
        }
    }

    private var sheet: some View {
        let l = lang.language
        return VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(AtlasTheme.handle)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
            titleRow(l)
            hereRow(l)
            usualCard(l)
            recentSection(l)
            passesSection(l)
            deleteBlock(l)
        }
        .padding(.horizontal, AtlasTheme.sideInset)
        .padding(.top, 8)
        .padding(.bottom, CustomTabBar.clearanceAboveSafeArea)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: AtlasTheme.sheetRadius,
                                   topTrailingRadius: AtlasTheme.sheetRadius,
                                   style: .continuous)
                .fill(AtlasTheme.background)
                .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.16), radius: 14, y: -8)
        }
    }

    /// Имя, город под ним и кружок «Переименовать».
    ///
    /// Переименование — кнопка, а не пункт «…»: действий у места ровно два, и
    /// пряча оба за многоточием, экран прятал от человека всё, что он тут
    /// может. Удаление стоит внизу, под всем содержимым: оно необратимо, и
    /// соседство с именем звало бы промахнуться.
    private func titleRow(_ l: LanguageManager.Language) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.place?.name ?? AppStrings.placeUnnamed(l))
                    .font(AppType.title)
                    .foregroundStyle(AtlasTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let address = model.address {
                    Text(address)
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                renaming = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AtlasTheme.ink)
                    .frame(width: AtlasTheme.controlSize, height: AtlasTheme.controlSize)
                    .background(AtlasTheme.searchBackground, in: Circle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(AppStrings.placeRename(l))
            .accessibilityIdentifier("place_action_rename")
        }
    }

    /// «Здесь 23 раза» — ЕДИНСТВЕННОЕ крупное число экрана, и единственная
    /// терракота на нём. Рядом — тот же нейтральный чип, что в списке:
    /// «частый гость» это подпись, а не награда (правило 0.6.8).
    private func hereRow(_ l: LanguageManager.Language) -> some View {
        let count = model.stats.passCount
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(hereText(l, count: count))
                .foregroundStyle(AtlasTheme.secondary)
            Spacer(minLength: 0)
            if model.stats.isFrequentGuest {
                PlaceChipLabel(text: AppStrings.placeChipFrequent(l))
            } else if model.stats.isFirstTime {
                PlaceChipLabel(text: AppStrings.placeChipFirst(l))
            }
        }
        .accessibilityIdentifier("place_here_row")
    }

    /// «Здесь 23 раза» одной строкой, но число — крупно и акцентом.
    ///
    /// Строка приходит из перевода ЦЕЛИКОМ и разбирать её на слова нельзя:
    /// порядок «здесь / число / раза» свой в каждом из тринадцати языков.
    /// Поэтому подсвечивается ровно тот диапазон, который мы сами же и
    /// напечатали (`formattedCount`), — а не найденный по цифрам: разряды
    /// бывают с неразрывным пробелом, и «1 248» цифрами не ищется.
    private func hereText(_ l: LanguageManager.Language, count: Int) -> AttributedString {
        var text = AttributedString(AppStrings.placeHereTimes(l, count: count))
        text.font = AppType.unit
        let number = AppStrings.formattedCount(count, lang: l)
        if let range = text.range(of: number) {
            text[range].font = AppType.display(34)
            text[range].foregroundColor = AtlasTheme.accent
        }
        return text
    }

    // MARK: - «Обычно занимает»

    @ViewBuilder
    private func usualCard(_ l: LanguageManager.Language) -> some View {
        if !model.stats.directions.isEmpty {
            paperCard {
                cardHeader(AppStrings.placeUsuallyTitle(l), caption: AppStrings.placeUsuallyCaption(l))
                ForEach(Array(model.stats.directions.enumerated()), id: \.offset) { index, direction in
                    if index > 0 { rowSeparator }
                    directionRow(direction, l)
                }
            }
        } else if let median = model.stats.medianElapsed {
            // Проезды есть, но ни один не нёс курса — сгруппировать по
            // направлению нечем, а факт «обычно занимает» всё равно есть.
            paperCard {
                cardHeader(AppStrings.placeUsuallyTitle(l), caption: AppStrings.placeUsuallyCaption(l))
                usualRow(course: PlacePass.unknownCourse,
                         // Не «в сторону …», а «Без направления»: точка вместо
                         // стрелки иначе выглядела бы недорисованной.
                         label: AppStrings.placeNoDirection(l),
                         detail: PlaceUsuallyLine.compose(count: model.stats.passCount, best: median,
                                                          worst: median, lang: l),
                         median: median, l: l)
            }
        }
    }

    private func directionRow(_ direction: PlaceStats.Direction, _ l: LanguageManager.Language) -> some View {
        usualRow(
            course: direction.course,
            label: model.directionLabels[direction.latestTripId].map { AppStrings.placeTowards(l, name: $0) },
            detail: PlaceUsuallyLine.compose(count: direction.count, best: direction.best,
                                             worst: direction.worst, lang: l),
            median: direction.median, l: l)
    }

    /// Слева — куда едут, справа — сколько это занимает.
    ///
    /// Стрелка компаса рисуется только там, где имени НЕТ: пока она стояла
    /// рядом с «в сторону Краснодара», направление было сказано дважды, а в
    /// строке без имени левая колонка оставалась пустой.
    private func usualRow(course: Double, label: String?, detail: String,
                          median: TimeInterval, l: LanguageManager.Language) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if label == nil { PassCourseGlyph(course: course) }
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label)
                        .font(AppType.body)
                        .foregroundStyle(AtlasTheme.ink)
                        .lineLimit(2)
                }
                Text(detail)
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(CheckpointReading.clock(median, lang: l))
                .font(AppType.itemValue)
                .foregroundStyle(AtlasTheme.ink)
                .lineLimit(1)
        }
        .frame(minHeight: 40)
    }

    // MARK: - Плитки дней

    @ViewBuilder
    private func recentSection(_ l: LanguageManager.Language) -> some View {
        if !model.tiles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.placeRecentPasses(l)).atlasSectionStyle()
                HStack(spacing: 6) {
                    ForEach(model.tiles) { tile in
                        dateTile(tile, l)
                    }
                }
            }
        }
    }

    /// День, месяц и — только когда проездов больше одного — «2 раза».
    ///
    /// Год не пишется НИКОГДА: полная дата не влезает в пятую долю ширины
    /// даже с `minimumScaleFactor`, а пять последних проездов по определению
    /// лежат рядом во времени (правило плиток дат 0.6.8).
    private func dateTile(_ tile: PlaceScreen.DateTile, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            Text(Self.dayNumber[l]?.string(from: tile.day) ?? "")
                .font(AppType.itemTitle)
                .foregroundStyle(AtlasTheme.ink)
            Text(Self.monthShort[l]?.string(from: tile.day) ?? "")
                .font(AppType.meta)
                .foregroundStyle(AtlasTheme.secondary)
            if tile.count > 1 {
                Text("\(AppStrings.formattedCount(tile.count, lang: l)) \(AppStrings.nounTimes(l, tile.count))")
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Проезды

    @ViewBuilder
    private func passesSection(_ l: LanguageManager.Language) -> some View {
        if !model.passes.isEmpty {
            let shown = model.showsAllPasses
                ? model.passes
                : Array(model.passes.prefix(PlaceScreen.visiblePasses))
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(AppStrings.placePassesSection(l)).atlasSectionStyle()
                    Spacer(minLength: 0)
                    // «от старта поездки» стоит ОДИН раз, над списком, а не
                    // хвостом в каждой из двадцати трёх строк.
                    Text(AppStrings.placeUsuallyCaption(l))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                }
                paperCard(spacing: 0, insets: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16)) {
                    // Ленивым столбцом: у зрелого места проездов сотни, и
                    // «Все N» разворачивает их все разом.
                    LazyVStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, pass in
                            if index > 0 { rowSeparator }
                            passRow(pass, l)
                        }
                        if shown.count < model.passes.count {
                            rowSeparator
                            showAllRow(l)
                        }
                    }
                }
            }
        }
    }

    private func passRow(_ pass: PlacePass, _ l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            onOpenTrip(pass.tripId, model.focus(forPassOf: pass.tripId))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(passTitle(pass, l))
                        .font(AppType.itemTitle)
                        .foregroundStyle(AtlasTheme.ink)
                        .lineLimit(1)
                    Text(passSubtitle(pass, l))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AtlasTheme.secondary.opacity(0.7))
            }
            .padding(.vertical, 7)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("place_pass_row")
    }

    private func showAllRow(_ l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            model.showsAllPasses = true
        } label: {
            HStack(spacing: 8) {
                Text(AppStrings.placeShowAllPasses(
                    l, passes: "\(AppStrings.formattedCount(model.passes.count, lang: l)) \(AppStrings.nounPasses(l, model.passes.count))"))
                    .font(AppType.itemTitle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AtlasTheme.accent)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("place_show_all_passes")
    }

    /// «Краснодар → Горячий Ключ», а нет имён в кэше геокодера — дата и час.
    /// Час нужен потому, что «туда и обратно» в один день дают две строки с
    /// одной датой, и различить их по ней нельзя.
    private func passTitle(_ pass: PlacePass, _ l: LanguageManager.Language) -> String {
        if let route = model.routeNames[pass.tripId] { return route }
        return Self.dayMonthWeekday[l]?.string(from: pass.timestamp) ?? ""
    }

    /// «20 сент., вс · 54 мин · 68 км».
    private func passSubtitle(_ pass: PlacePass, _ l: LanguageManager.Language) -> String {
        let reading = CheckpointReading.text(elapsed: pass.elapsedFromStart, metres: pass.distanceFromStart,
                                             unit: distanceUnit, lang: l)
        guard model.routeNames[pass.tripId] != nil,
              let date = Self.dayMonthWeekday[l]?.string(from: pass.timestamp), !date.isEmpty else {
            return reading
        }
        return "\(date) · \(reading)"
    }

    // MARK: - Удаление

    private func deleteBlock(_ l: LanguageManager.Language) -> some View {
        VStack(spacing: 6) {
            Button {
                Haptics.tap()
                confirmingDelete = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
                    Text(AppStrings.placeDelete(l)).font(AppType.button)
                }
                .foregroundStyle(AppTheme.red)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.statRadius, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("place_action_delete")
            Text(AppStrings.placeDeleteHint(l))
                .font(AppType.meta)
                .foregroundStyle(AtlasTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 4)
    }

    // MARK: - Общее

    /// Белая плашка макета: один радиус и одни поля на «Обычно занимает» и на
    /// список проездов — до 0.8.1 их задавали два разных места, и колонки
    /// текста в двух карточках стояли на разном отступе.
    private func paperCard<Content: View>(
        spacing: CGFloat = 2,
        insets: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16),
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
    }

    private func cardHeader(_ title: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).atlasSectionStyle()
            Spacer(minLength: 0)
            Text(caption)
                .font(AppType.meta)
                .foregroundStyle(AtlasTheme.secondary)
                .lineLimit(1)
        }
    }

    private var rowSeparator: some View {
        AtlasTheme.separator.frame(height: 1)
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
}

private struct PlaceScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
