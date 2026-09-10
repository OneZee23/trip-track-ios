import SwiftUI
import MapKit

/// Экран путешествия: карта всех плеч, итог четырьмя числами, лента по дням.
///
/// Живёт по `id`, а не по значению `Journey`: правка дат из листа меняет запись
/// в базе, и экран, державший копию, показывал бы прежнее окно с прежними
/// плечами. Пропало путешествие (удалили здесь же или синком) — экран
/// закрывается сам: пустая шапка без единого способа уйти уже была в гараже.
///
/// Тело разрезано на методы с первой строки, а не когда компилятор начнёт
/// падать по таймауту: `TripDetailView` этот предел уже нашёл.
struct JourneyDetailView: View {
    let journeyId: UUID

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = JourneyManager.shared

    @State private var trips: [Trip] = []
    @State private var aggregate = JourneyAggregate.build(trips: [])
    /// Склейка `previewPolyline` плеч. Карта режет её по разрывам больше
    /// километра сама, так что каждое плечо выходит своей ниткой.
    @State private var coordinates: [CLLocationCoordinate2D] = []
    /// Имена мест из кэша геокодера, посчитанные один раз на загрузку: ходить
    /// в CoreData из `body` — значит ходить туда на каждый кадр прокрутки.
    /// Отметки всех плеч кружками. Без миниатюр: снимок грузится с диска, а
    /// кружок на обзорной карте его всё равно не показывает — на герое стоит
    /// `.compact`.
    @State private var checkpointMarkers: [CheckpointMarker] = []
    @State private var startName: String?
    @State private var farthestName: String?
    /// Обложка, выбранная руками, — снимок из плеч. Считается на загрузке, а не
    /// в `body`: `body` перебирал бы фотографии всех плеч на каждый кадр
    /// прокрутки. Снимок, уехавший вместе с плечом, молча возвращает карту.
    @State private var coverPhoto: TripPhoto?
    /// Имя стоянки по id ПЕРВОЙ её поездки, а не по номеру дня: в одном дне
    /// стоянок бывает две (город → трасса → город), и номер дня склеил бы их.
    @State private var localNames: [UUID: String] = [:]

    @State private var showEdit = false
    @State private var showActions = false
    @State private var confirmDelete = false
    /// Плечо, которое просят убрать. Спрашиваем ДО правки: из ленты пропадает
    /// целый день дороги, и молча такое не делается. Вернуть плечо есть чем —
    /// полка «Убранные поездки» в листе правки, — но вопрос всё равно задаём:
    /// возврат живёт на другом экране, и знать о нём в момент нажатия человек
    /// не обязан.
    @State private var legToRemove: Trip?
    @State private var isMapFullscreen = false
    @State private var openTripId: UUID?
    @State private var heroProgress: Double = 0
    /// Плечи ещё не читались. Без этого флага экран на первом кадре показывает
    /// «Пока пусто» и через мгновение подменяет его лентой — мигание, которое
    /// читается как поломка.
    @State private var loaded = false

    private var colors: AppTheme.Colors { AppTheme.colors(for: scheme) }
    private var journey: Journey? { manager.journeys.first { $0.id == journeyId } }

    private static let heroHeight: CGFloat = 300

    var body: some View {
        stage
            .fullScreenCover(isPresented: $isMapFullscreen) { fullscreenMap }
            .sheet(isPresented: $showEdit) { editSheet }
            .navigationDestination(item: $openTripId) { id in
                TripDetailView(tripId: id, viewModel: TripsViewModel(tripManager: mapVM.tripManager))
            }
            .appConfirm(
                isPresented: $confirmDelete,
                title: AppStrings.journeyDelete(lang.language),
                message: AppStrings.journeyDeleteHint(lang.language),
                actions: [
                    AppDialogAction(AppStrings.delete(lang.language), kind: .destructive,
                                    identifier: "journey_delete_confirm") {
                        manager.delete(id: journeyId)
                    }
                ]
            )
            // На КОРНЕ экрана, а не внутри ленты: накладка размером с секцию
            // уезжала бы вместе с прокруткой (см. `AppConfirmDialog`). Поездка
            // приходит аргументом замыкания — читать её из состояния после
            // закрытия диалога нельзя, он гасит себя первым.
            .appConfirm(
                item: $legToRemove,
                title: { _ in AppStrings.journeyRemoveLeg(lang.language) },
                message: { _ in AppStrings.journeyRemoveLegHint(lang.language) },
                actions: { trip in
                    [AppDialogAction(AppStrings.journeyRemoveLeg(lang.language),
                                     kind: .destructive,
                                     identifier: "journey_remove_leg_confirm") {
                        removeLeg(trip)
                    }]
                }
            )
    }

    private var stage: some View {
        scroll
            .background(colors.bg)
            // Экран уходит под статус-бар (`.ignoresSafeArea` ниже), и на
            // светлой карте-склейке часы со связью пропадали. Накладка — под
            // шапкой: её кнопки остаются чёткими.
            .edgeScrims(top: true)
            .overlay(alignment: .top) { topBar }
            .navigationBarHidden(true)
            .hideAppTabBar()
            .ignoresSafeArea(.container, edges: .top)
            .task(id: journeyId) { reload() }
            // Поездку удаляют с ЕЁ экрана, открытого отсюда же. Без этой
            // строки плечо остаётся строкой ленты и километрами в итоге, а
            // нажатие на него уводит в `TripDetailView` без поездки — а там
            // без поездки нет ни шапки, ни кружка «Назад»: экран без выхода.
            // Тот же случай и то же лечение, что в `ProfileView`.
            .onReceive(NotificationCenter.default.publisher(for: .tripDeleted)) { _ in reload() }
            // Возврат с экрана плеча. Там же его переименовывают, добавляют
            // снимки и ставят отметки — всё это лента дня показывает своими
            // строками, миниатюрами и кружками на карте.
            .onChange(of: openTripId) { _, new in if new == nil { reload() } }
            // Удаление (своё или прилетевшее синком) не оставляет экрана,
            // которому нечего показать.
            //
            // Сравниваются СВОИ записи из старого и нового списка, а не списки
            // целиком: `journeys` меняется от любой чужой правки и от каждого
            // пула, а `reload()` перечитывает поездки окна и пересчитывает
            // итог. Без этой проверки экран одного путешествия перебирал бы
            // базу всякий раз, когда меняется соседнее.
            .onChange(of: manager.journeys) { old, new in
                let before = old.first { $0.id == journeyId }
                let after = new.first { $0.id == journeyId }
                if after == nil { dismiss() } else if before != after { reload() }
            }
    }

    // MARK: - Полотно

    private var scroll: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                    .background(alignment: .top) { scrollProbe }
                pageBody(colors)
            }
        }
        .coordinateSpace(name: Self.scrollSpace)
        .scrollIndicators(.hidden)
        .onPreferenceChange(JourneyScrollOffsetKey.self) { minY in
            // Квантуется ДО состояния: на полной точности каждый пройденный
            // пункт перерисовывает тело, в котором живёт MKMapView.
            let span = max(1, Self.heroHeight - 60)
            let raw = min(max(-minY / span, 0), 1)
            let stepped = (raw * 20).rounded() / 20
            if stepped != heroProgress { heroProgress = stepped }
        }
    }

    private var scrollProbe: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: JourneyScrollOffsetKey.self,
                value: proxy.frame(in: .named(Self.scrollSpace)).minY
            )
        }
    }

    @ViewBuilder
    private func pageBody(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if trips.isEmpty {
                if loaded { emptyCard(c) }
            } else {
                totals(c)
                JourneyDaysList(
                    aggregate: aggregate,
                    language: lang.language,
                    localNames: localNames,
                    onOpenTrip: { openTripId = $0.id },
                    // Лента только сообщает, о чём попросили: вопрос задаёт
                    // экран, на его корне.
                    onRemoveLeg: { legToRemove = $0 }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 40)
    }

    // MARK: - Герой

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            heroMap
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 150)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            heroCaption
        }
        .frame(height: Self.heroHeight)
        .clipped()
        .overlay(alignment: .bottomTrailing) { expandButton }
    }

    @ViewBuilder
    private var heroMap: some View {
        if let photo = coverPhoto {
            // Выбранная обложка — вместо карты, под тем же градиентом: имя и
            // даты обязаны читаться и на светлом снимке. Кнопка «во весь
            // экран» при этом остаётся: маршрут никуда не делся, и это
            // единственный способ его посмотреть.
            AsyncThumbnailView(filename: photo.filename, maxSize: 1_200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityIdentifier("journey_hero_cover")
        } else if coordinates.count > 1 {
            // Не интерактивная нарочно: панорама живёт на полном экране, а
            // жест по карте внутри прокрутки съедает саму прокрутку.
            RouteMapView(
                coordinates: coordinates,
                isInteractive: false,
                checkpointMarkers: checkpointMarkers,
                checkpointMarkerStyle: .compact,
                showsFog: false
            )
        } else {
            Color.black.opacity(0.88)
                .overlay {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.35))
                }
        }
    }

    private var heroCaption: some View {
        let caption = captionText
        return VStack(alignment: .leading, spacing: 6) {
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            Text(titleText)
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.trailing, 52)
    }

    @ViewBuilder
    private var expandButton: some View {
        if coordinates.count > 1 {
            MapChromeButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                accessibilityLabelText: AppStrings.openRouteMapA11y(lang.language)
            ) {
                Haptics.tap()
                isMapFullscreen = true
            }
            .accessibilityIdentifier("journey_map_expand")
            .padding(.trailing, 6)
            .padding(.bottom, 4)
        }
    }

    private var topBar: some View {
        TripDetailTopBar(
            progress: heroProgress,
            topInset: safeAreaTop,
            title: titleText,
            language: lang.language,
            // Поделиться путешествием пока нечем: у него нет ни своей
            // страницы на сервере, ни постера. Кнопка, которая ничего не
            // делает, хуже её отсутствия.
            showShare: false,
            shareDisabled: true,
            showActions: true,
            actionsPresented: $showActions,
            onBack: { dismiss() },
            onShare: {},
            pill: { EmptyView() },
            popover: { ActionPopoverList(items: actions) }
        )
    }

    private var actions: [ActionPopoverList.Item] {
        // Поповер закрывается ДО показа листа: UIKit роняет sheet, запрошенный,
        // пока поповер ещё на экране (тот же приём, что в `ownerActions`).
        func present(_ work: @escaping @MainActor () -> Void) {
            showActions = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                work()
            }
        }
        return [
            .init(title: AppStrings.journeyEdit(lang.language), systemImage: "pencil",
                  accessibilityId: "journey_action_edit") { present { showEdit = true } },
            .init(title: AppStrings.journeyDelete(lang.language), systemImage: "trash",
                  isDestructive: true, accessibilityId: "journey_action_delete") {
                present { confirmDelete = true }
            },
        ]
    }

    // MARK: - Итог

    private func totals(_ c: AppTheme.Colors) -> some View {
        let l = lang.language
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            DetailStatCard(
                value: "\(aggregate.calendarDays)",
                unit: AppStrings.nounDays(l, aggregate.calendarDays),
                label: AppStrings.journeyDurationLabel(l),
                color: AppTheme.accent, staggerIndex: 0
            )
            DetailStatCard(
                value: journeyDistance(l).value,
                unit: journeyDistance(l).unit,
                label: AppStrings.journeyDistanceLabel(l),
                color: AppTheme.green, staggerIndex: 1
            )
            DetailStatCard(
                value: "\(aggregate.legCount)",
                unit: AppStrings.nounTrips(l, aggregate.legCount),
                label: AppStrings.journeyLegsLabel(l),
                color: AppTheme.blue, staggerIndex: 2
            )
            DetailStatCard(
                segments: TripDetailFormat.durationSegments(aggregate.drivingSeconds, lang: l),
                label: AppStrings.journeyDrivingLabel(l),
                color: AppTheme.accent, staggerIndex: 3
            )
        }
    }

    /// Окно без единой поездки — законное состояние, а не поломка: даты можно
    /// сдвинуть куда угодно, и путешествие переживёт удаление своих плеч.
    ///
    /// Карточка НАЖИМАЕТСЯ и ведёт в лист правки. Раньше она печатала
    /// «Добавить поездку» обычным текстом внутри мёртвой рамки: кнопки «+» на
    /// экране путешествия нет и не будет — плечи набираются датами, потому что
    /// членство это окно, — и человек тыкал в надпись, которая ничего не
    /// делала. Обещать действие и не давать его — ровно то, чего не велит
    /// CLAUDE.md («если нажатие что-то открывает — это видно; если не
    /// открывает — не притворяемся»).
    private func emptyCard(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            showEdit = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.journeyEmptyTitle(lang.language))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(c.text)
                HStack(spacing: 6) {
                    // Ведём туда, где правят окно, и называем это тем же
                    // словом, что стоит на самом листе.
                    Text(AppStrings.journeyEdit(lang.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(c.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("journey_empty")
    }

    // MARK: - Листы

    /// Лист правки. `.contentSizedSheet` — СНАРУЖИ `if let`, а не внутри.
    ///
    /// Модификатор меряет содержимое и держит замер в своём `@State`. Внутри
    /// ветки он пропадает вместе с ней: в тот момент, когда путешествие
    /// исчезает из списка (удалили прямо из листа), детент теряется, и лист
    /// на прощание раздувается во весь экран. Снаружи он переживает пустую
    /// ветку и закрывается той высотой, которой стоял.
    private var editSheet: some View {
        Group {
            if let journey {
                JourneyEditSheet(journey: journey, photos: trips.flatMap(\.photos))
                    .environmentObject(lang)
            }
        }
        .contentSizedSheet(background: colors.bg)
    }

    /// Полная карта — та же склейка и без реплея: реплей живёт у поездки, где
    /// есть время каждой точки.
    private var fullscreenMap: some View {
        FullscreenMapSheet(
            coordinates: coordinates,
            distanceMeters: aggregate.totalMetres,
            checkpointMarkers: checkpointMarkers,
            showsFog: false,
            language: lang.language,
            // Проигрывать нечего: склейка плеч — не маршрут, и машинка пошла
            // бы напрямик через пустоту между городами.
            allowsPlayback: false
        )
        .environmentObject(lang)
    }

    // MARK: - Загрузка

    private func reload() {
        guard let journey else { return }
        let legs = manager.trips(in: journey)
        let agg = JourneyAggregate.build(trips: legs)
        trips = legs
        aggregate = agg
        // Через `previewCoordinates`, а не `decodePolyline` напрямую: те же
        // байты уже разобраны для карточки в «Моих» и лежат в `NSCache`.
        coordinates = legs.flatMap(\.previewCoordinates)
        checkpointMarkers = legs.flatMap(markers(of:))
        coverPhoto = journey.coverPhotoId.flatMap { id in
            legs.lazy.flatMap(\.photos).first { $0.id == id }
        }
        loaded = true
        loadLocalityNames(agg: agg)
    }

    /// Имена мест — отдельным шагом, после того как остальное уже нарисовано.
    /// `cachedLocalities` берёт ВСЮ пачку координат одним фоновым запросом; по
    /// одной синхронной `cachedLocality` на шапку и на каждую стоянку экран
    /// ходил бы в CoreData на главном потоке столько раз, сколько у путешествия
    /// стоянок. Экран показывает карту и ленту сразу, а подписи мест
    /// проступают, когда придёт ответ.
    private func loadLocalityNames(agg: JourneyAggregate) {
        var anchorByKey: [UUID: CLLocationCoordinate2D] = [:]
        for day in agg.days {
            for item in day.items {
                guard case .local(let group, let anchor, _) = item, let key = group.first?.id else { continue }
                anchorByKey[key] = anchor
            }
        }
        var coords: [CLLocationCoordinate2D] = []
        if let start = agg.firstStart { coords.append(start) }
        if let farthest = agg.farthestEnd { coords.append(farthest) }
        coords.append(contentsOf: anchorByKey.values)
        guard !coords.isEmpty else { return }

        // Кэш геокодера живёт у `TripManager`, а тот — один на приложение и
        // лежит в `MapViewModel`: своего заводить нельзя, у него внутри
        // очередь записи поездки.
        let geocoder = mapVM.tripManager
        Task { @MainActor in
            let names = await geocoder.cachedLocalities(for: coords)
            startName = agg.firstStart.flatMap { names[TripManager.geocodeCacheKey(for: $0)] }
            farthestName = agg.farthestEnd.flatMap { names[TripManager.geocodeCacheKey(for: $0)] }
            localNames = anchorByKey.compactMapValues { names[TripManager.geocodeCacheKey(for: $0)] }
        }
    }

    /// «Убрать из путешествия»: поездка выходит из окна, но остаётся в
    /// истории — обёртка правится, запись о дороге не трогается вовсе.
    ///
    /// Зовётся только из подтверждения (`legToRemove`). Обратный ход — полка
    /// «Убранные поездки» в листе правки: она и есть единственное место, где
    /// `excludedTripIds` уменьшается.
    ///
    /// Пишется именно исключение, а не сдвиг дат: сосед может лежать в
    /// середине окна, и подвинуть границу так, чтобы он выпал, значило бы
    /// выкинуть заодно всё, что стоит за ним.
    private func removeLeg(_ trip: Trip) {
        guard var updated = journey, !updated.excludedTripIds.contains(trip.id) else { return }
        updated.excludedTripIds.append(trip.id)
        // Даты не двигаются — пересечься с соседним окном нечем, и `.overlaps`
        // здесь недостижим. Молчим о нём вместо того, чтобы показывать ошибку,
        // которой не бывает.
        try? manager.update(updated)
        reload()
    }

    /// Отметки одного плеча в том виде, в каком их рисует карта. Номера
    /// считаются ВНУТРИ плеча — как на экране самой поездки: «вторая отметка
    /// на дороге к морю», а не «седьмая отметка путешествия».
    /// Километры путешествия — число и подпись из одних рук.
    private func journeyDistance(_ l: LanguageManager.Language) -> Measure.Parts {
        Measure.distanceParts(
            metres: aggregate.totalMetres, unit: distanceUnit, lang: l, style: .grouped)
    }

    private func markers(of trip: Trip) -> [CheckpointMarker] {
        trip.checkpoints.enumerated().map { index, checkpoint in
            CheckpointMarker(
                id: checkpoint.id,
                latitude: checkpoint.latitude, longitude: checkpoint.longitude,
                number: index + 1,
                name: checkpoint.name ?? AppStrings.checkpointDefaultName(lang.language, number: index + 1),
                reading: CheckpointReading.text(
                    elapsed: checkpoint.elapsedFromStart,
                    metres: checkpoint.distanceFromStart,
                    unit: distanceUnit,
                    lang: lang.language),
                image: nil,
                timestamp: checkpoint.timestamp)
        }
    }

    // MARK: - Строки

    /// Имя человека, иначе «Краснодар — Тбилиси», иначе даты — общая лестница
    /// с карточкой в «Моих» (`JourneyTitle`). Ни одного из трёх не бывает
    /// пусто: даты у окна есть всегда.
    private var titleText: String {
        guard let journey else { return dateRangeText }
        return JourneyTitle.text(journey, aggregate: aggregate,
                                 startName: startName, farthestName: farthestName,
                                 dateRange: dateRangeText)
    }

    /// «12–17 сен · Краснодарский край, Северная Осетия».
    ///
    /// Даты уходят из подписи, когда заголовок САМ стал датами (имени взять
    /// неоткуда) — но только они: регионы остаются. Сравнение было по всей
    /// строке, и подпись целиком считалась не совпавшей, стоило появиться
    /// хоть одному региону, — «12–17 СЕН · КРАСНОДАРСКИЙ КРАЙ» над заголовком
    /// «12–17 сен».
    private var captionText: String {
        var parts: [String] = []
        if titleText != dateRangeText { parts.append(dateRangeText) }
        let regions = aggregate.regions
            .compactMap { RegionDisplay.localized($0, language: lang.language) }
            .filter { !$0.isEmpty }
        if !regions.isEmpty { parts.append(regions.joined(separator: ", ")) }
        return parts.joined(separator: " · ").uppercased(lang.language)
    }

    private var dateRangeText: String {
        guard let journey else { return "" }
        let end = journey.endDate ?? trips.last?.endDate ?? journey.startDate
        return JourneyFormat.dateRange(from: journey.startDate, to: end, language: lang.language)
    }

    private var safeAreaTop: CGFloat { UIApplication.tt_safeAreaInsets?.top ?? 59 }

    private static let scrollSpace = "journeyScroll"
}

/// Насколько уехал герой — своим ключом, а не общим с экраном поездки: два
/// экрана в одном стеке навигации, и общий ключ однажды сложил бы их вместе.
private struct JourneyScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
