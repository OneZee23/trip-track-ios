import SwiftUI

/// Список черновиков — ЕДИНСТВЕННЫЙ новый экран этой переделки (спека §3).
///
/// Экран поездки не меняется: его карточка «Это твоя поездка?» и есть
/// подтверждение. Здесь то же самое действие называется тем же словом —
/// «Моя», — и идёт той же дверью: `DraftDecisionQueue`, которую разбирает
/// `MapViewModel.applyDraftDecisions`. Второго кода подтверждения быть не
/// должно: у «Моя» побочных эффектов на полэкрана (награды, одометр, туман,
/// места, очередь синка), и разойдись два пути, разница нашлась бы не сразу.
///
/// Удаление ВСЕГДА через диалог, подтверждение — без него: отмены в
/// приложении нет, а подтверждённую поездку можно удалить из Ленты.
struct DraftsListView: View {
    let onOpenTrip: (UUID) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [Trip] = []
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var pendingDelete: [UUID] = []
    @State private var showDelete = false

    private var layout: DraftsLayout {
        let metrics = WindowLayoutMetrics.shared
        let size = metrics.size ?? CGSize(width: 390, height: 844)
        let insets = metrics.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        return DraftsLayout(height: size.height, safeTop: insets.top,
                            safeBottom: insets.bottom, width: size.width)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack(alignment: .top) {
            c.bg.ignoresSafeArea()
            if drafts.isEmpty { empty } else { list }
            header
            if !drafts.isEmpty { bottomBar }
        }
        .toolbar(.hidden, for: .navigationBar)
        .appConfirm(
            isPresented: $showDelete,
            title: AppStrings.draftsDeleteTitle(lang.language, count: pendingDelete.count),
            message: AppStrings.draftsDeleteBody(lang.language),
            actions: [
                AppDialogAction(AppStrings.delete(lang.language), kind: .destructive) {
                    discard(pendingDelete)
                }
            ]
        )
        .onAppear {
            reload()
            // Список открыли — точка у вкладки «Я» уходит (спека, состояние 12).
            DraftsBadge.shared.markSeen()
        }
        .onReceive(NotificationCenter.default.publisher(for: .draftTripResolved)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .tripDeleted)) { _ in reload() }
    }

    // MARK: Шапка

    /// Стекло с обводкой снизу, низ = зона + 46. Формулой, не координатой.
    private var header: some View {
        let l = lang.language
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if selecting {
                    headerButton(AppStrings.draftsSelectAll(l), id: "drafts_select_all") {
                        selected = selected.count == drafts.count ? [] : Set(drafts.map(\.id))
                    }
                } else {
                    backButton
                }
                Spacer(minLength: 8)
                Text(selecting
                     ? AppStrings.draftsSelectedCount(l, count: selected.count)
                     : AppStrings.draftsTitle(l))
                    .font(AppType.navTitle)
                    .foregroundStyle(AtlasTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selecting {
                    headerButton(AppStrings.done(l), id: "drafts_done") {
                        selecting = false
                        selected = []
                    }
                } else if !drafts.isEmpty {
                    headerButton(AppStrings.draftsSelect(l), id: "drafts_select") {
                        selecting = true
                    }
                } else {
                    // Пустой экран «Выбрать» не показывает: выбирать нечего.
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
        }
        .frame(maxWidth: .infinity)
        // Стекло уходит ПОД часы, сама строка — нет. Ровно так: строка
        // остаётся внутри безопасной зоны и её низ равен `зона + 46`, а
        // `ignoresSafeArea` висит на ФОНЕ. Повесь его на всю шапку — и
        // содержимое встанет под часы, где до «Выбрать» пальцем не
        // дотянуться (поймано первым же кадром на симуляторе).
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) { AtlasTheme.separator.frame(height: 1) }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var backButton: some View {
        Button { Haptics.tap(); dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AtlasTheme.ink)
                .frame(width: 36, height: 36)
                .background(AtlasTheme.chip, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(AppStrings.back(lang.language))
        .accessibilityIdentifier("drafts_back")
    }

    private func headerButton(_ title: String, id: String,
                              action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); withAnimation(.snappy(duration: 0.22)) { action() } } label: {
            Text(title)
                .font(AppType.action)
                .foregroundStyle(AtlasTheme.accent)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: Список

    /// Строка списка: заголовок группы или черновик.
    ///
    /// Плоским списком, а не `Section`, нарочно: у `.plain` заголовки секций
    /// ПРИЛИПАЮТ к верху, и под стеклянной шапкой их набралось бы три штуки
    /// друг на друге. Здесь заголовок — обычная строка без фона и без свайпов,
    /// он уезжает вместе со списком.
    private enum Item: Identifiable {
        case header(DraftsGrouping.Bucket)
        case row(Trip, CardEdge)

        var id: String {
            switch self {
            case .header(let bucket): return "h-" + bucket.rawValue
            case .row(let trip, _): return trip.id.uuidString
            }
        }
    }

    /// Где строка стоит в карточке группы: от этого зависят скруглённые углы
    /// её подложки и нужна ли разделительная линия сверху.
    private struct CardEdge {
        let isFirst: Bool
        let isLast: Bool
    }

    private var items: [Item] {
        var out: [Item] = []
        for group in DraftsGrouping.build(drafts) {
            out.append(.header(group.bucket))
            for (index, trip) in group.trips.enumerated() {
                out.append(.row(trip, CardEdge(isFirst: index == 0,
                                               isLast: index == group.trips.count - 1)))
            }
        }
        return out
    }

    /// `List`, а не `ScrollView`: свайпы по спеке системные, а `swipeActions`
    /// вне списка молча не работают — строка просто не сдвигается, и заметить
    /// это можно только пальцем.
    private var list: some View {
        List {
            ForEach(items) { item in
                switch item {
                case .header(let bucket):
                    Text(title(for: bucket))
                        .atlasSectionStyle()
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                case .row(let trip, let edge):
                    row(trip, edge: edge)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollIndicators(.hidden)
        .contentMargins(.top, layout.headerBottom + 4, for: .scrollContent)
        .contentMargins(.bottom, layout.listBottomInset, for: .scrollContent)
        // Боковые поля — у СОДЕРЖИМОГО скролла, а не у строки. `listRowInsets`
        // сдвигает только содержимое строки, а действие свайпа по-прежнему
        // считает себя от края ЭКРАНА: красная плашка вылезала из карточки и
        // срезала ей угол (поймано кадром, а не сборкой).
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    private func title(for bucket: DraftsGrouping.Bucket) -> String {
        let l = lang.language
        switch bucket {
        case .today: return AppStrings.today(l)
        case .yesterday: return AppStrings.yesterday(l)
        case .earlier: return AppStrings.earlier(l)
        }
    }

    /// Строка 72 pt. В режиме выбора она НЕ открывает экран поездки — только
    /// переключает кружок: иначе выбор нескольких требовал бы попадания мимо
    /// всей строки.
    private func row(_ trip: Trip, edge: CardEdge) -> some View {
        Button {
            Haptics.tap()
            if selecting {
                withAnimation(.snappy(duration: 0.18)) { toggle(trip.id) }
            } else {
                onOpenTrip(trip.id)
            }
        } label: {
            VStack(spacing: 0) {
                if !edge.isFirst {
                    AtlasTheme.separator.frame(height: 1).padding(.leading, 84)
                }
                HStack(spacing: 12) {
                    if selecting { selectionCircle(trip.id) }
                    DraftRouteThumb(route: trip.previewCoordinates)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TripAutoTitle.localized(trip.title, startDate: trip.startDate,
                                                     language: lang.language)
                             ?? AppStrings.tripTitle(lang.language))
                            .font(AppType.itemTitle)
                            .foregroundStyle(AtlasTheme.ink)
                            .lineLimit(1)
                        Text(subtitle(trip))
                            .font(AppType.meta)
                            .foregroundStyle(AtlasTheme.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !selecting {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AtlasTheme.secondary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 72)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("draft_row")
        .accessibilityLabel(voiceOverLabel(trip))
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(
            UnevenRoundedRectangle(
                topLeadingRadius: edge.isFirst ? 16 : 0,
                bottomLeadingRadius: edge.isLast ? 16 : 0,
                bottomTrailingRadius: edge.isLast ? 16 : 0,
                topTrailingRadius: edge.isFirst ? 16 : 0,
                style: .continuous
            )
            .fill(AtlasTheme.card)
        )
        // Свайпы — те же два действия, что и везде: вправо «Моя» без
        // диалога, влево «Удалить» через диалог.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { confirm([trip.id]) } label: {
                swipeLabel(AppStrings.draftConfirm(lang.language), icon: "checkmark")
            }
            .tint(AppTheme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { askDelete([trip.id]) } label: {
                swipeLabel(AppStrings.delete(lang.language), icon: "trash")
            }
        }
    }

    /// Строка читается одной фразой (спека §9): имя, расстояние, время,
    /// старт, «черновик». Последнее слово — единственное место, где статус
    /// назван словами: глазу его говорит сам экран, а голосу сказать нечем.
    private func voiceOverLabel(_ trip: Trip) -> String {
        let l = lang.language
        let name = TripAutoTitle.localized(trip.title, startDate: trip.startDate,
                                           language: l)
            ?? AppStrings.tripTitle(l)
        let parts = subtitle(trip).replacingOccurrences(of: " · ", with: ", ")
        return name + ", " + parts + ", " + AppStrings.nounDrafts(l, 1)
    }

    /// СЛОВО, а не значок, и это отступление от доски со своей причиной.
    ///
    /// Доски DR-05/DR-06 рисуют значок и подпись вместе, но спека сама же
    /// требует СИСТЕМНЫЕ `swipeActions` (§7), а те на ширине действия ~74 pt
    /// показывают либо одно, либо другое: `Label` с картинкой отдаёт только
    /// значок (проверено кадром, в том числе с жёсткой рамкой 96 — её система
    /// игнорирует), голый `Text` — только слово. Из двух выбрано слово:
    /// одно из действий необратимо, и корзина без подписи заставляет
    /// угадывать. Галочка «Моя» без подписи не объясняет вообще ничего.
    private func swipeLabel(_ title: String, icon: String) -> some View {
        Text(title).font(.inter(13, weight: .semibold))
    }

    private func selectionCircle(_ id: UUID) -> some View {
        let on = selected.contains(id)
        return ZStack {
            Circle()
                .fill(on ? AtlasTheme.accent : .clear)
                .overlay(Circle().strokeBorder(on ? .clear : AtlasTheme.handle, lineWidth: 1.5))
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private func subtitle(_ trip: Trip) -> String {
        let l = lang.language
        let km = Measure.distance(metres: trip.distance, unit: DistanceUnit.current,
                                  lang: l, style: .tenths)
        let time = CheckpointReading.clock(trip.duration, lang: l)
        let clock = Self.clock[l]?.string(from: trip.startDate) ?? ""
        return [km, time, clock].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static let clock = LocalizedDateFormatter.templates("Hmm")

    // MARK: Низ

    /// Кнопка на `верх таб-бара − 64`, и список уходит ПОД неё.
    private var bottomBar: some View {
        let l = lang.language
        return VStack(spacing: 0) {
            if selecting {
                HStack(spacing: 8) {
                    wideButton(AppStrings.delete(l), id: "drafts_delete_selected",
                               tint: AppTheme.red, fill: AtlasTheme.chip,
                               width: layout.deleteButtonWidth) {
                        askDelete(Array(selected))
                    }
                    wideButton(AppStrings.draftsMineCount(l, count: selected.count),
                               id: "drafts_mine_selected",
                               tint: .white, fill: AtlasTheme.accent, width: nil) {
                        confirm(Array(selected))
                    }
                }
                .opacity(selected.isEmpty ? 0.4 : 1)
                .allowsHitTesting(!selected.isEmpty)
            } else {
                wideButton(drafts.count == 1
                           ? AppStrings.draftConfirm(l)
                           : AppStrings.draftsAllMine(l, count: drafts.count),
                           id: "drafts_all_mine",
                           tint: .white, fill: AtlasTheme.accent, width: nil) {
                    confirm(drafts.map(\.id))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: layout.buttonTop - layout.safeTop)
    }

    /// `width == nil` — кнопка занимает всё, что осталось. Иначе ровно
    /// столько точек, сколько сказано: две кнопки режима выбора обязаны
    /// вместе закрывать ту же ширину, что одна кнопка обычного вида, — иначе
    /// левый край у них разъезжается между состояниями.
    private func wideButton(_ title: String, id: String, tint: Color, fill: Color,
                            width: CGFloat?, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Text(title)
                .font(AppType.button)
                .foregroundStyle(tint)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .padding(.horizontal, 12)
                .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .frame(width: width)
        .shadow(color: .black.opacity(0.16), radius: 28, y: 8)
        .accessibilityIdentifier(id)
    }

    // MARK: Пусто

    private var empty: some View {
        let l = lang.language
        return VStack(spacing: 10) {
            ZStack {
                Circle().fill(AtlasTheme.chip).frame(width: 56, height: 56)
                Image(systemName: "tray")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AtlasTheme.secondary)
            }
            Text(AppStrings.draftsEmptyTitle(l))
                .font(AppType.itemTitle)
                .foregroundStyle(AtlasTheme.ink)
            Text(AppStrings.draftsEmptyBody(l))
                .font(AppType.body)
                .foregroundStyle(AtlasTheme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, layout.emptyTop - layout.safeTop)
        .padding(.horizontal, 24)
        .accessibilityIdentifier("drafts_empty")
    }

    // MARK: Действия

    private func reload() {
        drafts = mapVM.tripManager.fetchDraftTrips()
        selected = selected.intersection(Set(drafts.map(\.id)))
        if drafts.isEmpty { selecting = false }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Подтверждение идёт ТОЙ ЖЕ дверью, что «Моя» на экране поездки, и
    /// экрана поездки для этого не требует: очередь разбирает
    /// `MapViewModel.applyDraftDecisions`, подписанный на это уведомление.
    private func confirm(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { DraftDecisionQueue.shared.enqueue(id, .confirm) }
        NotificationCenter.default.post(name: .draftTripDecisionQueued, object: nil)
        withAnimation(.snappy(duration: 0.25)) {
            drafts.removeAll { ids.contains($0.id) }
            selected.subtract(ids)
            if drafts.isEmpty { selecting = false }
        }
    }

    private func askDelete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        pendingDelete = ids
        showDelete = true
    }

    private func discard(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { DraftDecisionQueue.shared.enqueue(id, .discard) }
        NotificationCenter.default.post(name: .draftTripDecisionQueued, object: nil)
        withAnimation(.snappy(duration: 0.25)) {
            drafts.removeAll { ids.contains($0.id) }
            selected.subtract(ids)
            if drafts.isEmpty { selecting = false }
        }
        pendingDelete = []
    }
}
