import SwiftUI

/// «Собрать путешествие»: из каких поездок сложить одну историю.
///
/// Лист открывается двумя входами — «…» на экране поездки и долгое нажатие на
/// карточку в «Моих», — и оба приносят одну опорную поездку. Соседей за ±7
/// дней достаёт `JourneyManager.neighbours`, но **отмечена по умолчанию
/// только цепочка** (`JourneySuggester.chainAround`): поездки, у которых конец
/// одной там же, где начало следующей, и между ними не больше полутора суток.
///
/// Так было не всегда. До 0.6.6 лист отмечал ВСЁ окно и просил «снять лишние»
/// — и владелец, открыв его на девятикилометровом куске дороги домой, сказал
/// «не понимаю, что происходит»: экран показал ему десяток городских поездок с
/// галочками и работу по их снятию, вместо ответа на вопрос, с которым он
/// пришёл. Отмеченная цепочка — это готовый ответ, который можно поправить;
/// отмеченное окно — это заготовка чужой работы.
///
/// Опорная поездка особенной при этом не становится: у неё есть рамка и
/// подпись «Эта поездка», но галочку можно снять и с неё. Человек пришёл с
/// экрана одной поездки, а собирает историю — запрет «эту нельзя» был бы
/// правилом, которого он не просил.
///
/// Третий вход — подсказка «Похоже на путешествие» — приносит готовый список
/// (`preselected`). Он уже собран правилом целиком, и досыпать ему соседей
/// значит переспросить о том, на что человек только что ответил.
struct JourneyComposerSheet: View {
    let anchor: Trip
    /// Готовый список — подсказка «Похоже на путешествие» (0.6.6).
    var preselected: [Trip]? = nil
    let onCreated: (Journey) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    /// Не `@ObservedObject`: у менеджера лист спрашивает соседей ОДИН раз в
    /// `.task` и создаёт путешествие по кнопке. Ни одного `@Published` он не
    /// читает, а наблюдение за ним перерисовывало бы лист на каждую чужую
    /// правку — и на ту, которую делает он сам, прямо перед закрытием.
    private let manager = JourneyManager.shared
    @State private var candidates: [Trip]
    @State private var selected: Set<UUID>
    @State private var title = ""
    @State private var error: String?

    /// Готовый список известен уже при создании листа, и ждать `.task` ему
    /// незачем: подсказка открывалась бы кадром с пустым списком и выключенной
    /// кнопкой. Соседей — только в `.task`: за ними надо в базу.
    init(anchor: Trip, preselected: [Trip]? = nil, onCreated: @escaping (Journey) -> Void) {
        self.anchor = anchor
        self.preselected = preselected
        self.onCreated = onCreated
        // По дате, а не в порядке нажатий: список читается как будущее
        // путешествие, а оно идёт по дням.
        let seed = (preselected ?? []).sorted { $0.startDate < $1.startDate }
        _candidates = State(initialValue: seed)
        _selected = State(initialValue: Set(seed.map(\.id)))
    }

    /// Высота списка, ПОСЧИТАННАЯ, а не измеренная: `ScrollView` гибкий по
    /// вертикали и растягивается на всё, что ему дали, — поэтому под одной
    /// поездкой зияла пустая треть листа. Мерить его собственную высоту
    /// `GeometryReader`-ом, которым же и задавать ему рамку, — петля, от
    /// которой предостерегает `VehiclePickerSheet`.
    ///
    /// Считать надо ВСЁ, что в списке лежит, а не одни строки. Формула знала
    /// только их — а в лист с тех пор добавились подписи дней и рамка опорной
    /// поездки, и ветка «мало кандидатов» рисовала голый `VStack` вообще без
    /// потолка. Шесть кандидатов в разные дни давали лист в 849 пунктов при
    /// потолке телефона в 783, и кнопка «Создать» уезжала за нижний край —
    /// обычная неделя разъездов делала лист неработающим.
    private static let thumbWidth: CGFloat = 56
    private static let thumbHeight: CGFloat = 44
    private static let rowHeight: CGFloat = thumbHeight + 16
    /// Строка опорной поездки выше на подпись «Эта поездка».
    private static let anchorRowHeight: CGFloat = rowHeight + 6
    private static let rowSpacing: CGFloat = 8
    /// Подпись дня — сама по себе, без отступа над ней. 13.5 при строке в
    /// 13.1: слагаемые округляются ВВЕРХ, потому что промах в плюс — это
    /// пункт пустоты внизу у КОРОТКОГО списка, а промах в минус — доля пункта
    /// прокрутки там, где её быть не должно. Обрезать не может ни тот, ни
    /// другой: рамка сидит на `ScrollView`.
    private static let dayHeaderHeight: CGFloat = 13.5
    /// Отступ над подписью КАЖДОГО СЛЕДУЮЩЕГО дня (`padding(.top, 6)`).
    private static let dayHeaderGap: CGFloat = 6
    /// Сколько пунктов списку разрешено занять.
    ///
    /// Считается от конца: всё остальное в листе (шапка, подсказка, итог, поле
    /// имени, строка отказа, кнопка и поля по 20) занимает около 315 пунктов в
    /// худшем случае, а лист обязан влезать и в маленький телефон, где потолок
    /// ~637. Отсюда 280: полная высота листа не переваливает за 600 ни при
    /// каком числе кандидатов, и «Создать» видно всегда.
    private static let listBudget: CGFloat = 280

    /// Собран один раз: `LocalizedDateFormatter.templates` строит тринадцать
    /// `DateFormatter` за вызов, а время спрашивает каждая строка списка.
    private static let timeFormatters = LocalizedDateFormatter.templates("Hm")

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 16) {
            header(c)
            Text(AppStrings.journeyComposeHint(lang.language))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(c.textTertiary)
            candidateList(c)
            summary(c)
            TextField(AppStrings.journeyTitlePlaceholder(lang.language), text: $title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: title) { _, _ in error = nil }
            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.red)
            }
            createButton(c)
        }
        .padding(20)
        .background(c.bg)
        .animation(.easeInOut(duration: 0.15), value: error)
        .task {
            guard preselected == nil else { return }
            var window = manager.neighbours(of: anchor)
            // Опорная поездка — с запасом на случай, если менеджер однажды
            // начнёт возвращать её сам: дважды в списке она хуже, чем не
            // первой.
            if !window.contains(where: { $0.id == anchor.id }) { window.append(anchor) }
            candidates = window.sorted { $0.startDate < $1.startDate }
            // Отмечена ЦЕПОЧКА, а не окно: см. заголовочный комментарий.
            selected = Set(JourneySuggester.chainAround(anchor, in: candidates).map(\.id))
        }
    }

    // MARK: - Дни

    /// Кандидаты, разложенные по календарным дням старта: подписи «6 сен, сб»
    /// над строками. Без них список из десятка поездок читается как свалка —
    /// а вопрос листа («что было одной дорогой») отвечается по дням.
    private struct DayGroup: Identifiable {
        let id: Date
        var trips: [Trip]
    }

    private var groups: [DayGroup] {
        let calendar = Calendar.current
        var out: [DayGroup] = []
        for trip in candidates {
            let day = calendar.startOfDay(for: trip.startDate)
            if let i = out.indices.last, out[i].id == day {
                out[i].trips.append(trip)
            } else {
                out.append(DayGroup(id: day, trips: [trip]))
            }
        }
        return out
    }

    // MARK: - Куски

    /// Список ВСЕГДА в прокрутке и ВСЕГДА с точной высотой.
    ///
    /// Высота — `frame(height:)`, а не `maxHeight`: `ScrollView` жадный по
    /// вертикали и под `maxHeight` занял бы весь бюджет даже под одну строку
    /// (та же ловушка расписана в `VehiclePickerSheet` и
    /// `CompanionsPickerSheet`). Поэтому короткий список ровно такой, каким
    /// его посчитали, а длинный упирается в потолок и прокручивается.
    ///
    /// Второй ветки — «мало кандидатов, рисуем голым стеком» — больше нет:
    /// это она пускала лист за край экрана, и она же означала, что потолок
    /// проверяется по числу строк вместо пунктов.
    private func candidateList(_ c: AppTheme.Colors) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                listContent(c)
            }
        }
        .frame(height: min(listHeight, Self.listBudget))
        // Прокрутка не пружинит там, где прокручивать нечего: короткий список
        // стоит ровно на своём месте, а не отскакивает от края.
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Ровно та высота, которую займёт `listContent`: строки (у опорной —
    /// своя), подписи дней, отступы над ними и зазоры между всеми соседями.
    /// Разойдётся с содержимым — лист снова поедет за край, поэтому меняешь
    /// строку списка, меняй и слагаемое.
    private var listHeight: CGFloat {
        let days = groups
        guard !days.isEmpty else { return 0 }
        let rows = days.reduce(0) { $0 + $1.trips.count }
        let anchors = days.reduce(0) { $0 + $1.trips.filter { $0.id == anchor.id }.count }
        let rowsHeight = CGFloat(rows - anchors) * Self.rowHeight
            + CGFloat(anchors) * Self.anchorRowHeight
        let headersHeight = CGFloat(days.count) * Self.dayHeaderHeight
            + CGFloat(days.count - 1) * Self.dayHeaderGap
        // Зазор стоит между КАЖДОЙ парой соседей стека, а подписи дней — такие
        // же его дети, как строки.
        let gaps = CGFloat(rows + days.count - 1) * Self.rowSpacing
        return rowsHeight + headersHeight + gaps
    }

    @ViewBuilder
    private func listContent(_ c: AppTheme.Colors) -> some View {
        let all = groups
        ForEach(all) { group in
            Text(JourneyFormat.dayDate(group.id, language: lang.language))
                .textCase(.uppercase)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(c.textTertiary)
                .padding(.top, group.id == all.first?.id ? 0 : 6)
            ForEach(group.trips) { row($0, c: c) }
        }
    }

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "suitcase")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent, in: Circle())
            Text(AppStrings.journeyComposeTitle(lang.language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                NavCircleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.close(lang.language))
        }
    }

    /// Что получится из отмеченного — прямо над полем имени.
    ///
    /// Итог считает `JourneyAggregate.build`, тот же, что рисует экран
    /// путешествия: цифра, которую человек увидит здесь, обязана совпасть с
    /// цифрой, которую он увидит после «Создать».
    private func summary(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "map")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(selected.isEmpty ? c.textTertiary : AppTheme.accent)
            Text(summaryText())
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(selected.isEmpty ? c.textTertiary : c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.18), value: selected)
    }

    /// Строка кандидата: карта, имя, «10:32–12:58 · 177 км», галочка справа.
    ///
    /// Карта — тот же `MapSnapshotPreview`, что на плитках «Моих»: по названию
    /// «Дивноморское» и «Дивноморское» две половины одной дороги не отличить,
    /// а по ниткам маршрута — сразу.
    private func row(_ trip: Trip, c: AppTheme.Colors) -> some View {
        let isOn = selected.contains(trip.id)
        let isAnchor = trip.id == anchor.id
        return Button {
            Haptics.selection()
            // Отказ описывал ПРЕЖНИЙ выбор: оставить его на экране, где выбор
            // уже другой, значит соврать про даты, которых больше нет.
            error = nil
            if isOn { selected.remove(trip.id) } else { selected.insert(trip.id) }
        } label: {
            HStack(spacing: 12) {
                thumbnail(trip, c: c)
                VStack(alignment: .leading, spacing: 2) {
                    Text(JourneyFormat.tripTitle(trip, language: lang.language))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(metaText(trip))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                    if isAnchor {
                        Text(AppStrings.journeyComposeAnchor(lang.language))
                            .font(.system(size: 10.5, weight: .heavy))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? AppTheme.accent : c.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isAnchor {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppTheme.accent.opacity(0.55), lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Меньше двух точек — `MapSnapshotPreview` возвращается ДО того, как
    /// успевает признать себя неудачей, и мерцает вечно: целая колонка такого
    /// читается как экран, который всё ещё грузится. Та же заглушка, что на
    /// плитках «Моих», уменьшенная до миниатюры.
    @ViewBuilder
    private func thumbnail(_ trip: Trip, c: AppTheme.Colors) -> some View {
        let coords = trip.previewCoordinates
        Group {
            if coords.count > 1 {
                MapSnapshotPreview(
                    coordinates: coords,
                    tripId: trip.id,
                    height: Self.thumbHeight,
                    width: Self.thumbWidth
                )
            } else {
                ZStack {
                    Rectangle().fill(c.card)
                    Image(systemName: "map.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
            }
        }
        .frame(width: Self.thumbWidth, height: Self.thumbHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func createButton(_ c: AppTheme.Colors) -> some View {
        let enabled = !selected.isEmpty
        return Button {
            create()
        } label: {
            Text(AppStrings.journeyCreate(lang.language))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    enabled ? AppTheme.accent : c.cardAlt,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(PressableCardStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("journey_composer_create")
    }

    // MARK: - Строки

    /// «2 поездки · 187 км · 6 сен». Число берётся по головам, а не из
    /// `legCount`: тот считает только плечи, а свёрнутые местные поездки в
    /// путешествие входят наравне — человек отметил их галочкой и ждёт их в
    /// счёте. Километры — `totalMetres` того же агрегата, чтобы итог листа и
    /// итог экрана путешествия не разошлись ни на метр.
    private func summaryText() -> String {
        let ticked = candidates.filter { selected.contains($0.id) }
        guard let first = ticked.map(\.startDate).min(),
              let last = ticked.map({ $0.endDate ?? $0.startDate }).max() else {
            return AppStrings.journeyEmptyTitle(lang.language)
        }
        let l = lang.language
        let aggregate = JourneyAggregate.build(trips: ticked)
        let count = "\(ticked.count) \(AppStrings.nounTrips(l, ticked.count))"
        let km = "\(GarageFormat.odometer(aggregate.totalMetres / 1_000, lng: l)) \(AppStrings.km(l))"
        let dates = JourneyFormat.dateRange(from: first, to: last, language: l)
        return "\(count) · \(km) · \(dates)"
    }

    /// «10:32–12:58 · 177 км». Часы своим порядком у каждого языка
    /// (`templates`), а не жёстким `HH:mm`: половина мира пишет время с AM/PM.
    /// Километры целыми и через `GarageFormat.odometer`, как везде: своё
    /// `Int(distance / 1000)` и разряды не разбивало, и округляло вниз.
    private func metaText(_ trip: Trip) -> String {
        let l = lang.language
        let formatter = Self.timeFormatters[l]
        let start = formatter?.string(from: trip.startDate) ?? ""
        let finish = trip.endDate.flatMap { formatter?.string(from: $0) }
        let time = finish.map { "\(start)\u{2013}\($0)" } ?? start
        let km = GarageFormat.odometer(trip.distanceKm, lng: l)
        return "\(time) · \(km) \(AppStrings.km(l))"
    }

    // MARK: - Создание

    private func create() {
        let trips = candidates.filter { selected.contains($0.id) }
        do {
            let journey = try manager.create(from: trips, title: title)
            Haptics.success()
            dismiss()
            onCreated(journey)
        } catch {
            // Единственная причина отказа, о которой человеку есть что решать,
            // — занятые даты. Пустой выбор кнопка не пропускает, так что
            // второй случай сюда не доходит; текст один, чтобы отказ никогда
            // не остался без объяснения.
            Haptics.error()
            self.error = AppStrings.journeyOverlaps(lang.language)
        }
    }
}
