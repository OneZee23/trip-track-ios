import SwiftUI

/// The permanent sheet of «Моя карта» (canon: «Sheet постоянный: свёрнут =
/// сводка + шеринг; тап по объекту подменяет контент; потянуть вверх = полная
/// детализация; смахнуть вниз / ✕ = назад к сводке»).
///
/// Deliberately NOT a system `.sheet`: this screen owns a floating tab bar,
/// and the collapsed summary has to float *above* it (canon frame 1) while a
/// selected card covers it (frames 2–5). A presented sheet can do one or the
/// other, never both, and its detents fight the tab bar the whole way.
struct MyMapSheet: View {
    @ObservedObject var vm: MyMapViewModel
    /// Owned by the screen so it can hide the tab bar under the open panel.
    @Binding var isSummaryExpanded: Bool
    var onOpenTrip: (UUID) -> Void
    /// Тап по печати в журнале. Замыканием, а не `vm.select` прямо здесь:
    /// в волне 4 у находки появится своя карточка, и меняться должен один
    /// вызов на экране, а не строка внутри списка.
    var onOpenDiscovery: (UUID) -> Void
    var onShare: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit

    /// `CustomTabBar` caps its pill at 380; Figma draws the collapsed card
    /// 10 pt narrower than the bar, so the card caps 10 lower.
    static let summaryMaxWidth: CGFloat = 370

    /// Высота самой карточки: ручка (4 + 8 сверху), строка 32, отступы 8 и 12.
    static let collapsedCardHeight: CGFloat = 86

    /// Сколько низа экрана занимает свёрнутый лист вместе с зазором до
    /// плавающего таб-бара.
    ///
    /// Это же число карта отдаёт в `additionalSafeAreaInsets.bottom`: логотип
    /// Apple и ссылка «Legal» — сабвью `MKMapView`, и под непрозрачным туманом
    /// лист накрыл бы их насовсем. Прятать «Legal» нельзя (API нет, а попытка
    /// рискует ревью), поэтому её поднимают ровно на свёрнутый лист —
    /// развёрнутый не считается, он состояние на пару секунд.
    static func collapsedHeight(bottomInset: CGFloat) -> CGFloat {
        collapsedCardHeight + CustomTabBar.clearance(bottomInset: bottomInset) + 6
    }

    static var collapsedHeight: CGFloat {
        collapsedHeight(bottomInset: UIApplication.tt_safeAreaInsets?.bottom ?? 0)
    }

    /// Высота журнала под его содержимое: ручка с шапкой, затем три группы —
    /// строки регионов, ряды печатей по пять в ряду, строки загадок.
    ///
    /// Считается по числу строк, а не берётся константой: лист на 520 при трёх
    /// регионах был наполовину пустым, и это уже чинили однажды. Пустая группа
    /// не занимает ничего — кроме «Находок», у которых есть своя пустая
    /// строка.
    static func journalHeight(regions: Int, finds: Int, riddles: Int) -> CGFloat {
        let head: CGFloat = 50
        let opened = group(rows: max(regions, 1), rowHeight: 56)
        let sealRows = max(1, Int(ceil(Double(finds) / Double(sealsPerRow))))
        let found = group(rows: sealRows, rowHeight: 60)
        let near = riddles == 0 ? 0 : group(rows: riddles, rowHeight: 52)
        return head + opened + found + near + 24
    }

    /// Заголовок группы (22 сверху, 4 снизу, 15 строка) плюс её строки.
    private static func group(rows: Int, rowHeight: CGFloat) -> CGFloat {
        41 + CGFloat(rows) * rowHeight
    }

    /// Печатей в ряду. Пять по 44 pt с зазорами укладываются даже на самом
    /// узком экране (SE: 375 − 32 поля = 343).
    static let sealsPerRow = 5

    @State private var isExpanded = false
    @State private var showAllTrips = false
    /// Находка, чья карточка открыта НАД журналом. Печать, а не id: сетка
    /// журнала уже держит готовые находки, и второй поход за ней в `vm` в
    /// момент показа ничего бы не уточнил.
    @State private var cardDiscovery: Discovery?
    /// Карточка НЕрешённой загадки из группы «Загадки рядом» — та же, что
    /// открывает тап по кругу на карте. Строка, которая ничего не открывает,
    /// была бы обещанием без содержания (канон «нажатие обязано отвечать»).
    @State private var cardRiddle: RiddleHintCardModel?
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if vm.selection == nil {
                    if isSummaryExpanded {
                        journalPanel(maxHeight: geo.size.height, safeBottom: geo.safeAreaInsets.bottom)
                            .transition(.move(edge: .bottom))
                    } else {
                        summaryCard
                            .padding(.horizontal, 16)
                            // Уйти из-под плавающего бара: клиренс + 6 = прежние 14 pt зазора над
                            // пилюлей (тот же приём, что у `RecordingBanner` в ленте).
                            .padding(.bottom, CustomTabBar.clearance + 6)
                            .transition(.opacity)
                    }
                } else {
                    detailPanel(maxHeight: geo.size.height, safeBottom: geo.safeAreaInsets.bottom)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.snappy(duration: 0.28), value: vm.selection)
        .animation(.snappy(duration: 0.28), value: isExpanded)
        .animation(.snappy(duration: 0.28), value: isSummaryExpanded)
        .onChange(of: vm.selection) { _, _ in
            isExpanded = false
            isSummaryExpanded = false
            showAllTrips = false
        }
        .sheet(item: $cardDiscovery) { find in
            DiscoveryCardSheet(discovery: find, showsOnMap: true) {
                // Сначала убрать карточку, потом вести камеру: `focusDiscovery`
                // выбирает печать, а выбор схлопывает журнал под листом — и
                // лист остался бы висеть над уже закрытым журналом.
                cardDiscovery = nil
                onOpenDiscovery(find.id)
            }
            .padding(.bottom, 20)
            .contentSizedSheet(background: AppTheme.colors(for: scheme).bg)
        }
        .sheet(item: $cardRiddle) { model in
            RiddleHintCard(model: model)
                .padding(.bottom, 20)
                .contentSizedSheet(background: AppTheme.colors(for: scheme).bg)
        }
    }

    // MARK: - Summary, pulled up

    /// «Журнал первооткрывателя» (спека §5): три группы — что открыто, что
    /// найдено, какие загадки рядом.
    ///
    /// The collapsed summary carries a grabber in the canon frame, and a
    /// grabber that does nothing is a lie. Pulling it up opens the journal —
    /// the same «полная детализация» rule the object cards follow, applied to
    /// the summary's own subject.
    ///
    /// Процентов, колец покрытия и «закрытых» регионов здесь больше нет:
    /// журнал отвечает на вопрос «что я открыл и нашёл», а не «сколько
    /// процентов края мне осталось закрасить» — карта территорий, из-за
    /// которой экран читался как Risk, ушла вместе с ними.
    ///
    /// Всё, что печатают эти строки, посчитано вне `body` — в
    /// `MyMapViewModel.journal`.
    private func journalPanel(maxHeight: CGFloat, safeBottom: CGFloat) -> some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            grabber(c)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .updating($drag) { value, state, _ in
                            state = min(value.translation.height, 0)
                        }
                        .onEnded { value in
                            if value.translation.height > 60 {
                                Haptics.tap()
                                isSummaryExpanded = false
                            }
                        }
                )

            HStack(spacing: 8) {
                Text(openedSummary)
                .font(.inter(15, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    openedGroup(c)
                    // Находки отложены до после 1.0.0 (`DiscoveriesAvailability`)
                    // — вся группа (шапка, пустая строка, сетка печатей) не
                    // рисуется вовсе, а не показывается пустой.
                    if DiscoveriesAvailability.isActive {
                        findsGroup(c)
                    }
                    riddlesGroup(c)
                }
                .padding(.bottom, 20 + safeBottom)
            }
        }
        .frame(maxWidth: .infinity)
        // Sized to what is in it. A fixed 520 meant three regions floated at
        // the top of a panel that was mostly empty white.
        .frame(height: max(180, min(Self.journalHeight(regions: vm.journal.regions.count,
                                                       finds: vm.journal.finds.count,
                                                       riddles: vm.journal.riddles.count) + safeBottom,
                                    min(560, maxHeight * 0.74) + safeBottom) - drag))
        .background(c.bg, in: UnevenRoundedRectangle(
            topLeadingRadius: 22, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous
        ))
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                isSummaryExpanded = false
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .padding(.top, 14)
            .accessibilityIdentifier("mymap_close")
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: -4)
        .accessibilityElement(children: .contain)
        // Имя осталось прежним нарочно: по нему панель находит обход
        // `MyMapTourTests`, а первая его кнопка — по-прежнему строка региона.
        .accessibilityIdentifier("mymap_region_list")
    }

    // MARK: - Журнал · Открыто

    /// Первая группа: сколько открыто и где. Итог печатает шапка панели —
    /// второй раз число не повторяется.
    @ViewBuilder
    private func openedGroup(_ c: AppTheme.Colors) -> some View {
        sectionTitle(AppStrings.journalOpenedSection(lang.language), c)
        ForEach(vm.journal.regions) { region in
            Button {
                Haptics.tap()
                vm.select(.region(region.id))
            } label: {
                regionRow(region, c)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Журнал · Находки

    /// Вторая группа: печати сеткой, свежая первая.
    ///
    /// Группа показывается ВСЕГДА, и пустая тоже: находки — половина замысла
    /// версии, и человек, у которого их ещё нет, обязан узнать, что они
    /// бывают. Загадки ниже так себя не ведут — «рядом» без единого круга это
    /// не обещание, а пустое место.
    @ViewBuilder
    private func findsGroup(_ c: AppTheme.Colors) -> some View {
        sectionTitle(
            AppStrings.journalFindsSection(lang.language, count: vm.journal.finds.count), c)

        if vm.journal.finds.isEmpty {
            Text(AppStrings.journalNoFindsYet(lang.language))
                .font(.inter(13))
                .foregroundStyle(c.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                               count: Self.sealsPerRow),
                spacing: 10
            ) {
                ForEach(vm.journal.finds) { find in
                    Button {
                        Haptics.tap()
                        // Карточка ложится ЛИСТОМ ПОВЕРХ журнала, а не
                        // подменяет его: человек разглядывает сетку печатей, и
                        // закрытая карточка обязана вернуть его в ту же сетку,
                        // а не на карту. На карту уводит кнопка внутри
                        // карточки — то есть по его решению.
                        cardDiscovery = find
                    } label: {
                        // Картинка кэширована по (вид, символ, масштаб) —
                        // `SealPainter` рисует её один раз на всё приложение.
                        Image(uiImage: SealPainter.image(
                            kind: find.kind, symbol: find.symbol, size: 44, scale: 3))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel(DiscoveryCopy.accessibility(for: find, lang.language))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Журнал · Загадки рядом

    /// Третья группа: те же три круга, что стоят на карте, — строкой про то,
    /// что ищется, и расстоянием до края круга.
    @ViewBuilder
    private func riddlesGroup(_ c: AppTheme.Colors) -> some View {
        if !vm.journal.riddles.isEmpty {
            sectionTitle(AppStrings.journalRiddlesSection(lang.language), c)
            ForEach(vm.journal.riddles) { riddle in
                riddleRow(riddle, c)
            }
        }
    }

    private func riddleRow(_ riddle: Journal.NearbyRiddle, _ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            cardRiddle = RiddleHintCardModel.make(
                riddle: riddle, unit: distanceUnit, lang: lang.language)
        } label: {
            riddleRowLabel(riddle, c)
        }
        .buttonStyle(PressableCardStyle())
    }

    private func riddleRowLabel(
        _ riddle: Journal.NearbyRiddle, _ c: AppTheme.Colors
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("?")
                .font(.inter(15, weight: .heavy))
                .foregroundStyle(Color(SealPainter.ring(for: .riddle)))
                .frame(width: 22, height: 22)
                .background(Color(SealPainter.ring(for: .riddle)).opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(RiddleCopy.line(for: riddle.type, lang.language))
                    .font(.inter(14, weight: .semibold))
                    .foregroundStyle(c.text)
                    .fixedSize(horizontal: false, vertical: true)
                // Внутри круга расстояния нет: «0 км до круга» — это не ответ,
                // а след формулы.
                if riddle.metresToEdge > 0 {
                    Text(AppStrings.journalRiddleDistance(
                        lang.language,
                        distance: Measure.distance(
                            metres: riddle.metresToEdge, unit: distanceUnit,
                            lang: lang.language)))
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func regionRow(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Text(RegionAtlas.flag(for: region.countryCode))
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(region.localizedName(lang.language))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                // Дата уже посчитана `MapExploration.build` вне главного
                // актёра: строка только печатает её.
                if let since = region.firstVisited {
                    Text(AppStrings.mapRegionSince(lang.language, date: since))
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Measure.distance(
                km: region.openedKm, unit: distanceUnit, lang: lang.language))
                .font(.inter(12, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    /// Одна строка итога, та же на карточке и над списком: «1 910 км открыто ·
    /// 4 региона». Километры — из слоя открытого, а не из суммы поездок.
    /// Одно расстояние, уже с единицей: число-герой свёрнутой карточки.
    private var openedDistance: String {
        Measure.distance(km: vm.revealed.openedKm, unit: distanceUnit, lang: lang.language)
    }

    /// «2 региона» — хвост под числом.
    private var openedRegions: String {
        let count = vm.exploration.regionCount
        return "\(AppStrings.groupedNumber(count, lang.language)) "
            + AppStrings.regionsGenitive(lang.language, count: count)
    }

    private var openedSummary: String {
        AppStrings.mapOpenedSummary(
            lang.language,
            distance: Measure.distance(
                km: vm.revealed.openedKm, unit: distanceUnit, lang: lang.language),
            regions: vm.exploration.regionCount
        )
    }

    // MARK: - Collapsed summary

    /// Figma `sheet-collapsed` (1114:250): 328 wide inside a 360 frame, 64
    /// tall, grabber centred on the CARD, text and share button on one row
    /// below it.
    ///
    /// Two things were off. The grabber sat in a column with the text, so it
    /// was centred over the text rather than the card and read as nudged left.
    /// And the card had no width cap while the tab bar has one at 380 — on a
    /// Pro Max that made the card 408 against the bar's 380, so the thing meant
    /// to be 10 pt NARROWER than the bar came out 28 pt wider. Hence the cap
    /// below: 370 keeps the Figma relationship at every screen size.
    private var summaryCard: some View {
        let c = AppTheme.colors(for: scheme)
        return VStack(spacing: 0) {
            // Ручка и шеврон — ОДИН знак «тяни вверх», собранный в одном
            // месте. До 23 сентября шеврон стоял в середине фразы, между
            // числом и кнопкой, и читался как знак препинания, а не как
            // управление: «дизайн этой плашки не нравится» — владелец.
            VStack(spacing: 3) {
                Capsule()
                    .fill(c.textTertiary.opacity(0.4))
                    .frame(width: 36, height: 4)
                if !vm.isEmpty {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(c.textTertiary.opacity(0.6))
                }
            }
            .padding(.top, 8)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    // Подпись над числом, а не вокруг него: «Открыто» — это
                    // заголовок величины, и в нём нет ни склонения, ни
                    // согласования с числом ни на одном из тринадцати языков.
                    Text(AppStrings.mapOpenedLabel(lang.language).uppercased(lang.language))
                        .font(.inter(10, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(c.textTertiary)

                    // Число — герой карточки: за ним сюда и приходят, а до
                    // 23 сентября оно было набрано тем же кеглем, что слово
                    // «Открыто» и счёт регионов.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(openedDistance)
                            .font(.inter(20, weight: .heavy))
                            .foregroundStyle(vm.isEmpty ? c.textTertiary : c.text)
                        if !vm.isEmpty {
                            Text("· " + openedRegions)
                                .font(.inter(13, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                if !vm.isEmpty {
                    Button {
                        Haptics.tap()
                        onShare()
                    } label: {
                        // The iOS share glyph, not a bare arrow: nothing about
                        // «↑» said what the button did until you pressed it.
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.accent.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.share(lang.language))
                    .accessibilityIdentifier("mymap_share")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: Self.summaryMaxWidth)
        .background(c.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { expandSummary() }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in if value.translation.height < -40 { expandSummary() } }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mymap_summary")
    }

    /// Nothing to open when you have not driven anywhere yet — the empty
    /// state already says so on the map itself.
    ///
    /// Прежнего обхода «один регион — сразу его карточка» здесь больше нет:
    /// он был верен, пока лист был СПИСКОМ РЕГИОНОВ и при одном регионе
    /// повторял строку, по которой только что нажали. Журнал при одном
    /// регионе несёт ещё находки и загадки, и увести человека мимо них было
    /// бы потерей, а не сокращением.
    private func expandSummary() {
        guard !vm.journal.isEmpty else { return }
        Haptics.selection()
        isSummaryExpanded = true
    }

    // MARK: - Selected object

    private func detailPanel(maxHeight: CGFloat, safeBottom: CGFloat) -> some View {
        let c = AppTheme.colors(for: scheme)
        let target = (isExpanded ? min(expandedHeight, maxHeight * 0.86) : baseHeight) + safeBottom
        return VStack(spacing: 0) {
            grabber(c).gesture(dragGesture)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let trip = vm.selectedTrip {
                        tripCard(trip, c)
                    } else if let discovery = vm.selectedDiscovery {
                        DiscoveryCardSheet(discovery: discovery)
                    } else if let road = vm.selectedRoad {
                        roadCard(road, c)
                    } else if let region = vm.selectedRegion {
                        regionCard(region, c)
                    }
                }
                .padding(.bottom, 20 + safeBottom)
            }
            .scrollDisabled(!isExpanded)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(120, target - drag))
        .background(c.bg, in: UnevenRoundedRectangle(
            topLeadingRadius: 22, bottomLeadingRadius: 0,
            bottomTrailingRadius: 0, topTrailingRadius: 22, style: .continuous
        ))
        .overlay(alignment: .topTrailing) { closeButton(c) }
        .shadow(color: .black.opacity(0.25), radius: 18, y: -4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(panelIdentifier)
    }

    /// The drag handle, and the ONLY thing that drags.
    ///
    /// The gesture used to sit on the whole panel, where it swallowed the
    /// scroll of the list underneath: a region with forty-four trips opened a
    /// card whose contents could not be reached at all. A grabber-only handle
    /// is also what every sheet on iOS does.
    private func grabber(_ c: AppTheme.Colors) -> some View {
        Capsule()
            .fill(c.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .accessibilityIdentifier("mymap_grabber")
    }

    /// Lets the UI tour assert which card is up without reading its copy.
    private var panelIdentifier: String {
        if vm.selectedTrip != nil { return "mymap_trip_card" }
        if vm.selectedDiscovery != nil { return "mymap_discovery_card" }
        if vm.selectedRoad != nil { return "mymap_road_card" }
        return "mymap_region_card"
    }

    private var baseHeight: CGFloat {
        if vm.selectedTrip != nil { return 176 }
        // Карточка находки: медальон, имя, дата — и, у секрета, история; у
        // загадки — мини-карта с кругом. «На карте» здесь нет, мы уже на
        // карте (`DiscoveryCardSheet.showsOnMap`).
        if vm.selectedDiscovery != nil { return 300 }
        // Header plus three rows — enough to read as a list worth pulling up.
        if vm.selectedRoad != nil { return 260 }
        return 214
    }

    /// Карточки, под которыми есть ещё что-то: список поездок региона, список
    /// поездок дороги — и история секрета, которая бывает в несколько абзацев.
    private var canExpand: Bool {
        vm.selectedRegion != nil || vm.selectedRoad != nil || vm.selectedDiscovery != nil
    }

    private var expandedHeight: CGFloat { canExpand ? 560 : baseHeight }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($drag) { value, state, _ in
                // Rubber-band past the ends instead of tearing the panel off.
                let raw = -value.translation.height
                if isExpanded { state = min(raw, 0) * 0.6 } else { state = max(raw, 0) * 0.6 }
                state = -state
            }
            .onEnded { value in
                let dy = value.translation.height
                if dy < -50, canExpand, !isExpanded {
                    Haptics.selection()
                    isExpanded = true
                } else if dy > 60 {
                    Haptics.tap()
                    if isExpanded { isExpanded = false } else { vm.select(nil) }
                }
            }
    }

    private func closeButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            vm.select(nil)
        } label: {
            NavCircleIcon(systemImage: "xmark")
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.top, 14)
        .accessibilityIdentifier("mymap_close")
        .accessibilityLabel(AppStrings.closeSheet(lang.language))
    }

    // MARK: - Region

    @ViewBuilder
    private func regionCard(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        regionHeader(region, c)

        // Крайние плитки прижаты к полям карточки, средняя по центру: до
        // 23 сентября все три стояли по центрам равных третей, и числа висели
        // сами по себе — левое в двух сантиметрах от флага с названием, правое
        // не доходя до края. «Вёрстка кривая» — владелец про этот экран.
        HStack(spacing: 8) {
            statColumn(Measure.distanceValue(km: region.km, unit: distanceUnit,
                                             lang: lang.language, style: .grouped),
                       AppStrings.mapKmDriven(lang.language, unit: distanceUnit), c,
                       alignment: .leading)
            statColumn("\(region.tripCount)",
                       AppStrings.tripsGenitive(lang.language, count: region.tripCount), c,
                       alignment: .center)
            statColumn(region.totalCities > 0
                       ? AppStrings.mapCitiesOfTotal(lang.language,
                                                     opened: region.visitedCityCount,
                                                     total: region.totalCities)
                       : "—",
                       AppStrings.citiesGenitive(lang.language, count: region.totalCities), c,
                       alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)

        if isExpanded {
            tripsSection(region, c)
        } else {
            Text(AppStrings.mapPullHint(lang.language))
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
        }
    }

    /// 17, not 19: the panel swaps this header in place for the road and the
    /// locked card, so all three follow the one canon size (1117:229). The flag
    /// stays on `.system` — Inter carries no emoji.
    private func regionHeader(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(RegionAtlas.flag(for: region.countryCode))
                .font(.system(size: 17))
            Text(region.localizedName(lang.language))
                .font(.inter(17, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    /// The value drew in SF while the label right under it drew in Inter — two
    /// typefaces stacked inside one card, and at heavy weight the digits gave
    /// it away. Canon: 18 ExtraBold over 10 SemiBold (1117:230/231).
    private func statColumn(
        _ value: String, _ label: String, _ c: AppTheme.Colors,
        alignment: HorizontalAlignment = .center
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(value)
                .font(.inter(18, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.inter(10, weight: .semibold))
                .foregroundStyle(c.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
    }

    // MARK: - Region · expanded

    // Списка городов с кольцами покрытия здесь больше нет (0.7.0, спека §5).
    // Кольцо отвечало на вопрос «сколько процентов города закрашено», то есть
    // предлагало закрашивать; туман спрашивает другое — где ты был. Вместе с
    // ним ушли `percentText` и `CoverageRing`.

    @ViewBuilder
    private func tripsSection(_ region: MapRegionStat, _ c: AppTheme.Colors) -> some View {
        let trips = region.tripIds.compactMap { vm.exploration.trip(id: $0) }
            .sorted { $0.startDate > $1.startDate }

        // «Все N» rides the section heading rather than sitting under the
        // last row: at the bottom of a scrolling card it was below the fold
        // and nobody saw it. Beside the heading it is where the eye already
        // is when it reads «ПОЕЗДКИ ЗДЕСЬ · 60».
        sectionTitle(
            AppStrings.mapTripsSection(lang.language, count: trips.count), c,
            action: trips.count > 4 && !showAllTrips
                ? (AppStrings.mapSeeAll(lang.language, count: trips.count), { showAllTrips = true })
                : nil
        )

        ForEach(showAllTrips ? trips : Array(trips.prefix(4))) { trip in
            Button {
                Haptics.tap()
                vm.select(.trip(trip.id))
            } label: {
                tripRow(trip, c)
            }
            .buttonStyle(.plain)
        }
    }

    private func tripRow(_ trip: MapTripPin, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            MapTripThumb(trip: trip, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language)
                     ?? (AppStrings.tripTitle(lang.language)))
                    .font(.inter(15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Text(tripSubtitle(trip))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func tripSubtitle(_ trip: MapTripPin) -> String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = Measure.distance(
            metres: trip.distance, unit: distanceUnit, lang: lang.language, style: .tenths)
        return "\(when) · \(km)"
    }

    private func sectionTitle(
        _ text: String,
        _ c: AppTheme.Colors,
        action: (title: String, run: () -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.inter(11, weight: .bold))
                .foregroundStyle(c.textTertiary)
            Spacer(minLength: 8)
            if let action {
                Button {
                    Haptics.tap()
                    action.run()
                } label: {
                    HStack(spacing: 3) {
                        Text(action.title)
                            .font(.inter(13, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    // A comfortable target without pushing the heading around.
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mymap_see_all")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    // MARK: - Road

    /// Tap a road you drive every day and you should get every trip that used
    /// it, not whichever one happened to be nearest. Without this the map felt
    /// like it held four trips: the photo-pins, and nothing else reachable.
    @ViewBuilder
    private func roadCard(_ trips: [MapTripPin], _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(AppStrings.mapRoadTrips(lang.language, count: trips.count))
                .font(.inter(17, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)

        ForEach(isExpanded ? trips : Array(trips.prefix(2))) { trip in
            Button {
                Haptics.tap()
                vm.select(.trip(trip.id))
            } label: {
                tripRow(trip, c)
            }
            .buttonStyle(.plain)
        }

        if !isExpanded, trips.count > 2 {
            Text(AppStrings.mapRoadPullHint(lang.language))
                .font(.inter(12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
        }
    }

    // MARK: - Trip

    @ViewBuilder
    private func tripCard(_ trip: MapTripPin, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            MapTripThumb(trip: trip, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language)
                     ?? (AppStrings.tripTitle(lang.language)))
                    .font(.inter(16, weight: .bold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Text(tripHeadline(trip))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                Text(tripSpeeds(trip))
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)

        Button {
            Haptics.action()
            onOpenTrip(trip.id)
        } label: {
            Text(AppStrings.mapOpenTrip(lang.language))
                .font(.inter(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .accessibilityIdentifier("mymap_open_trip")
    }

    private func tripHeadline(_ trip: MapTripPin) -> String {
        let when = RelativeTripDate.string(from: trip.startDate, language: lang.language)
        let km = Measure.distance(
            metres: trip.distance, unit: distanceUnit, lang: lang.language, style: .grouped)
        let time = Trip.formattedTimeHuman(trip.duration, lang: lang.language)
        return "\(when) · \(km) · \(time)"
    }

    private func tripSpeeds(_ trip: MapTripPin) -> String {
        let avg = AppStrings.myMapAvg(lang.language)
        let max = AppStrings.myMapMax(lang.language)
        let a = Measure.speed(ms: trip.avgSpeedMS, unit: distanceUnit, lang: lang.language)
        let m = Measure.speed(ms: trip.maxSpeedMS, unit: distanceUnit, lang: lang.language)
        return "\(avg) \(a) · \(max) \(m)"
    }
}

// MARK: - Pieces

/// Trip thumbnail: the photo if there is one, otherwise the route drawn from
/// the trip's own preview polyline — never a generic icon, since the shape of
/// the road is the thing you actually recognise.
struct MapTripThumb: View {
    let trip: MapTripPin
    var size: CGFloat = 40

    @Environment(\.colorScheme) private var scheme
    @State private var photo: UIImage?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(c.cardAlt)
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else if trip.route.count > 1 {
                    GeometryReader { geo in
                        SharePosterRoute(
                            points: SharePosterView.project(trip.route, in: geo.size, inset: 8),
                            lineWidth: size * 0.075
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .frame(width: size, height: size)
            .task(id: trip.photoFilename) {
                guard let filename = trip.photoFilename else { return }
                photo = await PhotoStorageService.loadThumbnail(filename: filename, maxSize: size * 3)
            }
    }
}
