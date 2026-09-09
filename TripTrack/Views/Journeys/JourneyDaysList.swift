import SwiftUI

/// Лента путешествия по дням: одна карточка на день, внутри — шапка «ДЕНЬ 1 ·
/// Вс, 6 сент.» и строки: плечи дороги и свёрнутые стоянки, разделённые
/// волоском.
///
/// Одна карточка на ДЕНЬ, а не на строку. Прежде плечо рисовалось голой строкой
/// прямо на фоне страницы, а стоянка — своей рамкой, и один и тот же день
/// выглядел как два разных списка. Заодно ушёл второй заголовок дня: стоянка
/// печатала собственный, и над одним днём стояло «ДЕНЬ 1» дважды подряд.
///
/// Про базу и геокодер лента не знает НИЧЕГО: имена мест ей приносит экран
/// готовым словарём. Спрашивать их отсюда значило бы ходить в CoreData из
/// `body` — на каждую перерисовку прокрутки и на каждую строку.
struct JourneyDaysList: View {
    let aggregate: JourneyAggregate
    let language: LanguageManager.Language
    /// id первой поездки стоянки → «Тбилиси». Пусто — покажем «по городу».
    ///
    /// Не по номеру дня: в одном дне стоянок бывает ДВЕ — покатались по
    /// городу, съездили в соседний, вернулись, — и номер дня склеил бы их
    /// имена и раскрытие в одно.
    var localNames: [UUID: String] = [:]
    var onOpenTrip: (Trip) -> Void
    /// «Убрать из путешествия»: поездка остаётся в истории, из окна уходит.
    var onRemoveLeg: (Trip) -> Void

    @Environment(\.colorScheme) private var scheme
    /// Раскрытые стоянки, по id первой поездки каждой.
    @State private var expanded: Set<UUID> = []
    /// Плечо, у которого открыто меню действий. Одно на весь список: два
    /// поповера разом система всё равно не покажет.
    @State private var menuTripId: UUID?

    /// Полсекунды — столько же ждёт система до контекстного меню и столько же
    /// длится сжатие в `HoldableCardStyle`: карточка «поддаётся» ровно к тому
    /// моменту, когда меню появляется.
    private static let holdDuration: TimeInterval = 0.5
    /// Отступ вложенной строки стоянки: кружок домика (26) плюс зазор до
    /// заголовка. Местная поездка встаёт ровно под именем города, а не под его
    /// иконкой.
    private static let nestedInset: CGFloat = 44
    /// Боковое поле карточки дня. Его же на отрицательный знак берёт волосок,
    /// чтобы дотянуться до правого края карточки.
    private static let cardPadding: CGFloat = 14

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        // `LazyVStack`: у месячного путешествия дней три десятка, и каждый
        // день — карточки плеч с миниатюрами фотографий. Обычный `VStack`
        // строил их все до первого кадра, вместе с чтением снимков с диска.
        LazyVStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(text: AppStrings.journeyByDays(language))
                .padding(.bottom, 2)
            ForEach(aggregate.days, id: \.number) { day in
                dayCard(day, c)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: expanded)
    }

    // MARK: - День

    /// Карточка дня: шапка и строки под ней. Заголовок здесь ОДИН и всегда
    /// про этот день — диапазон «Дни 2–4» ушёл на саму стоянку, потому что
    /// это её свойство, а не дня, в котором она началась.
    private func dayCard(_ day: JourneyAggregate.Day, _ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader(day, c)
                .padding(.bottom, 6)
            ForEach(Array(day.items.enumerated()), id: \.offset) { index, item in
                if index > 0 { hairline(c, inset: 0) }
                itemView(item, in: day, c: c)
            }
        }
        .padding(.horizontal, Self.cardPadding)
        .padding(.vertical, 12)
        .surfaceCard()
    }

    private func dayHeader(_ day: JourneyAggregate.Day, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            // Тёмная плашка на светлой теме и светлая на тёмной: цвет текста
            // как фон, цвет фона как чернила — иначе в тёмной теме белый номер
            // ложился на почти белую плашку.
            Text(AppStrings.journeyDay(language, day.number))
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(c.bg)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(c.text, in: Capsule())
            Text(JourneyFormat.dayDate(day.date, language: language))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Волосок между строками: слева отступ (у вложенных — больше), справа
    /// дотягивается до самого края карточки. Так видно, что строки — соседи по
    /// одному списку, а не отдельные плитки.
    private func hairline(_ c: AppTheme.Colors, inset: CGFloat) -> some View {
        Rectangle()
            .fill(c.border)
            .frame(height: 0.5)
            .padding(.leading, inset)
            .padding(.trailing, -Self.cardPadding)
            .padding(.vertical, 9)
    }

    @ViewBuilder
    private func itemView(
        _ item: JourneyAggregate.Item, in day: JourneyAggregate.Day, c: AppTheme.Colors
    ) -> some View {
        switch item {
        case .leg(let trip):
            legRow(trip, c: c)
        case .local(let trips, _, let lastDayNumber):
            stayRows(trips, in: day, lastDayNumber: lastDayNumber, c: c)
        }
    }

    // MARK: - Плечо

    /// Строка плеча. Открывает поездку — потому и шеврон, и отклик под пальцем:
    /// строка, которая ведёт куда-то, обязана об этом сказать до нажатия. За
    /// удержанием — «Убрать из путешествия», поэтому стиль `Holdable`: сжатие
    /// идёт полсекунды и видно, что палец надо задержать.
    private func legRow(_ trip: Trip, c: AppTheme.Colors) -> some View {
        tripButton(trip, accessibilityId: "journey_leg_row") {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(JourneyFormat.tripTitle(trip, language: language))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    chevron(c)
                }
                Text(legMeta(trip))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                momentsRow(trip, c: c)
            }
        }
    }

    /// Кнопка поездки — одна на плечо и на местную строку внутри стоянки.
    /// Убрать из путешествия можно и ту и другую, и меню у них одно на список,
    /// поэтому вся оснастка (удержание, поповер, действие для VoiceOver) живёт
    /// в одном месте: разъедься эти две копии — и половина строк молча
    /// перестала бы убираться.
    private func tripButton<Label: View>(
        _ trip: Trip, accessibilityId: String, @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            // Меню уже открыто долгим тапом — но кнопка всё равно получит своё
            // нажатие на отпускании, и без этой проверки поездка открывалась бы
            // «сама», поверх только что показанного поповера.
            guard menuTripId == nil else { return }
            Haptics.tap()
            onOpenTrip(trip)
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(HoldableCardStyle())
        .accessibilityIdentifier(accessibilityId)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.holdDuration).onEnded { _ in
                Haptics.action()
                menuTripId = trip.id
            }
        )
        // Поповер, а не системное меню: `Menu` роняет чужую плашку поверх
        // нашей карточки (см. `ActionPopoverList`).
        .popover(isPresented: Binding(
            get: { menuTripId == trip.id },
            set: { if !$0 { menuTripId = nil } }
        )) {
            ActionPopoverList(items: [
                .init(title: AppStrings.journeyRemoveLeg(language),
                      systemImage: "minus.circle",
                      isDestructive: true,
                      accessibilityId: "journey_remove_leg") {
                    // Поповер закрывается ДО правки: убранное плечо исчезает из
                    // ленты, и UIKit роняет поповер вместе со строкой, к которой
                    // тот был привязан, — тем же приёмом, что `present {}` на
                    // экране путешествия.
                    menuTripId = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 260_000_000)
                        onRemoveLeg(trip)
                    }
                }
            ])
        }
        // Удержание — жест, которого VoiceOver не знает: без этого действия
        // убрать плечо с озвучкой было бы нечем вовсе.
        .accessibilityAction(named: Text(AppStrings.journeyRemoveLeg(language))) {
            onRemoveLeg(trip)
        }
    }

    private func chevron(_ c: AppTheme.Colors) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(c.textTertiary)
    }

    /// «5 ч 20 мин · 480 км · 2 отметки».
    private func legMeta(_ trip: Trip) -> String {
        var parts = [
            JourneyFormat.duration(trip.duration, language: language),
            "\(Int(trip.distance / 1000)) \(AppStrings.km(language))",
        ]
        if !trip.checkpoints.isEmpty {
            parts.append("\(trip.checkpoints.count) \(AppStrings.nounCheckpoints(language, trip.checkpoints.count))")
        }
        return parts.joined(separator: " · ")
    }

    /// «Пятигорск · Чегем · 4 фото» — что от плеча осталось в памяти.
    /// Нечего показать — строки нет вовсе: пустая строка «0 фото» занимает
    /// столько же места, сколько настоящая, и не говорит ничего.
    @ViewBuilder
    private func momentsRow(_ trip: Trip, c: AppTheme.Colors) -> some View {
        let text = momentsText(trip)
        if !text.isEmpty {
            HStack(spacing: 7) {
                // Первый снимок, а не «обложка»: обложки у ПОЕЗДКИ нет —
                // `coverPhotoId` есть только у путешествия и у отметки. Тот же
                // первый снимок показывают карточки ленты, и заводить здесь
                // своё правило значило бы разойтись с ними.
                if let photo = trip.photos.first {
                    AsyncThumbnailView(filename: photo.filename, maxSize: 48)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
            }
            .padding(.top, 2)
        }
    }

    private func momentsText(_ trip: Trip) -> String {
        var parts: [String] = []
        for (index, checkpoint) in trip.checkpoints.enumerated() {
            let name = checkpoint.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            // Имя по умолчанию собирается по НОМЕРУ ВО ВРЕМЕНИ и не хранится —
            // то же правило, что у «Моментов» на экране поездки.
            if let name, !name.isEmpty {
                parts.append(name)
            } else {
                parts.append(AppStrings.checkpointDefaultName(language, number: index + 1))
            }
        }
        if !trip.photos.isEmpty {
            parts.append("\(trip.photos.count) \(AppStrings.nounPhotos(language, trip.photos.count))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Стоянка

    /// Свёрнутая стоянка: пять поездок по Тбилиси — это не пять строк истории,
    /// а одна. Раскрывается на месте вложенными строками, в той же карточке
    /// дня: своя рамка вокруг стоянки делала из одного дня два списка.
    private func stayRows(
        _ trips: [Trip], in day: JourneyAggregate.Day, lastDayNumber: Int, c: AppTheme.Colors
    ) -> some View {
        // Стоянка без единой поездки не существует: `JourneyAggregate` заводит
        // её только вокруг первой. Пустой ключ — заглушка, до которой не дойти.
        let key = trips.first?.id ?? UUID()
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                if isOpen { expanded.remove(key) } else { expanded.insert(key) }
            } label: {
                stayHeading(trips, key: key, in: day, lastDayNumber: lastDayNumber,
                            isOpen: isOpen, c: c)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("journey_local_group")
            .accessibilityAddTraits(isOpen ? .isSelected : [])

            if isOpen {
                ForEach(trips) { trip in
                    hairline(c, inset: Self.nestedInset)
                    localTripRow(trip, c: c)
                }
            }
        }
    }

    private func stayHeading(
        _ trips: [Trip], key: UUID, in day: JourneyAggregate.Day, lastDayNumber: Int,
        isOpen: Bool, c: AppTheme.Colors
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "house")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(c.textSecondary)
                .frame(width: 26, height: 26)
                .background(c.cardAlt, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    // Имени места нет (геокодер ещё не доехал до этих
                    // координат) — «Стоянка», а не «по городу»: иначе в
                    // заголовке и в строке под ним стояло бы одно и то же
                    // «по городу» дважды подряд.
                    Text(localNames[key] ?? AppStrings.journeyStayFallback(language))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    // Диапазон — только когда стоянка и правда тянется дальше
                    // своего дня. Иначе он повторял бы шапку карточки слово в
                    // слово, а повтор читается как ошибка вёрстки.
                    if lastDayNumber > day.number {
                        Text(AppStrings.journeyDays(language, from: day.number, to: lastDayNumber))
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(0.3)
                            .textCase(.uppercase)
                            .foregroundStyle(c.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(c.cardAlt, in: Capsule())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                Text(localMeta(trips))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            }
        }
    }

    /// Местная поездка внутри раскрытой стоянки: «15:00 · Геленджик ·
    /// 14 мин · 9 км». Время слева, потому что за один день таких строк бывает
    /// пять и различает их именно оно — города у всех одинаковые.
    private func localTripRow(_ trip: Trip, c: AppTheme.Colors) -> some View {
        tripButton(trip, accessibilityId: "journey_local_trip_row") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(JourneyFormat.time(trip.startDate, language: language))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(JourneyFormat.tripTitle(trip, language: language))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(legMeta(trip))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer(minLength: 0)
                chevron(c)
            }
            .padding(.leading, Self.nestedInset)
        }
    }

    /// «5 поездок по городу · 62 км · 3 ч 05 мин · 11 фото».
    private func localMeta(_ trips: [Trip]) -> String {
        let metres = trips.reduce(0.0) { $0 + $1.distance }
        let seconds = trips.reduce(0.0) { $0 + $1.duration }
        let photos = trips.reduce(0) { $0 + $1.photos.count }
        var parts = [
            "\(trips.count) \(AppStrings.nounTrips(language, trips.count)) \(AppStrings.journeyAroundTown(language))",
            "\(Int(metres / 1000)) \(AppStrings.km(language))",
            JourneyFormat.duration(seconds, language: language),
        ]
        if photos > 0 {
            parts.append("\(photos) \(AppStrings.nounPhotos(language, photos))")
        }
        return parts.joined(separator: " · ")
    }
}
