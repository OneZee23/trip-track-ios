import SwiftUI

/// Лента путешествия по дням: «ДЕНЬ 1 · 12 сен», под ним плечи строками, а
/// стоянка со всеми местными поездками — одной свёрнутой карточкой.
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

    @Environment(\.colorScheme) private var scheme
    /// Раскрытые стоянки, по id первой поездки каждой.
    @State private var expanded: Set<UUID> = []

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 20) {
            DetailSectionHeader(text: AppStrings.journeyByDays(language))
            ForEach(aggregate.days, id: \.number) { day in
                dayBlock(day, c)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: expanded)
    }

    // MARK: - День

    private func dayBlock(_ day: JourneyAggregate.Day, _ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(day.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 10) {
                    if let header = header(for: item, in: day, at: index) {
                        headerRow(header, c)
                    }
                    itemView(item, in: day, c: c)
                }
            }
        }
    }

    /// Какой заголовок стоит НАД этой строкой — и стоит ли вообще.
    ///
    /// Стоянка носит свой: она тянется через несколько дней («ДНИ 2–4»), и
    /// заголовок дня, в котором она началась, о ней соврал бы. Плечо получает
    /// заголовок дня, только если оно в дне первое — или если перед ним стояла
    /// стоянка со своим: иначе строка осталась бы под чужой шапкой.
    private func header(
        for item: JourneyAggregate.Item, in day: JourneyAggregate.Day, at index: Int
    ) -> (badge: String, date: String)? {
        switch item {
        case .local(let trips, _):
            return localHeader(trips, in: day)
        case .leg:
            if index > 0, case .leg = day.items[index - 1] { return nil }
            return (AppStrings.journeyDay(language, day.number),
                    JourneyFormat.dayDate(day.date, language: language))
        }
    }

    private func localHeader(
        _ trips: [Trip], in day: JourneyAggregate.Day
    ) -> (badge: String, date: String) {
        guard let first = trips.first, let last = trips.last else {
            return (AppStrings.journeyDay(language, day.number),
                    JourneyFormat.dayDate(day.date, language: language))
        }
        let lastNumber = Self.dayNumber(of: last.startDate, dayOne: day.date, number: day.number)
        guard lastNumber > day.number else {
            return (AppStrings.journeyDay(language, day.number),
                    JourneyFormat.dayDate(day.date, language: language))
        }
        return (AppStrings.journeyDays(language, from: day.number, to: lastNumber),
                JourneyFormat.dateRange(from: first.startDate, to: last.startDate, language: language))
    }

    /// Та же арифметика дней, что в `JourneyAggregate`: календарные сутки от
    /// начала дня до начала дня, а не деление секунд на 86 400.
    private static func dayNumber(of date: Date, dayOne: Date, number: Int) -> Int {
        let calendar = Calendar.current
        let delta = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dayOne),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return number + delta
    }

    private func headerRow(_ header: (badge: String, date: String), _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            // Тёмная плашка на светлой теме и светлая на тёмной: цвет текста
            // как фон, цвет фона как чернила — иначе в тёмной теме белый номер
            // ложился на почти белую плашку.
            Text(header.badge)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(c.bg)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(c.text, in: Capsule())
            Text(header.date)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func itemView(
        _ item: JourneyAggregate.Item, in day: JourneyAggregate.Day, c: AppTheme.Colors
    ) -> some View {
        switch item {
        case .leg(let trip):
            legRow(trip, c: c)
        case .local(let trips, _):
            localCard(trips, in: day, c: c)
        }
    }

    // MARK: - Плечо

    /// Строка плеча. Открывает поездку — потому и шеврон, и отклик под пальцем:
    /// строка, которая ведёт куда-то, обязана об этом сказать до нажатия.
    private func legRow(_ trip: Trip, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            onOpenTrip(trip)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(JourneyFormat.tripTitle(trip, language: language))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                Text(legMeta(trip))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                momentsRow(trip, c: c)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("journey_leg_row")
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
            parts.append(name?.isEmpty == false
                ? name!
                : AppStrings.checkpointDefaultName(language, number: index + 1))
        }
        if !trip.photos.isEmpty {
            parts.append("\(trip.photos.count) \(AppStrings.nounPhotos(language, trip.photos.count))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Стоянка

    /// Свёрнутая стоянка: пять поездок по Тбилиси — это не пять строк истории,
    /// а одна. Раскрывается на месте теми же строками плеч.
    private func localCard(
        _ trips: [Trip], in day: JourneyAggregate.Day, c: AppTheme.Colors
    ) -> some View {
        // Стоянка без единой поездки не существует: `JourneyAggregate` заводит
        // её только вокруг первой. Пустой ключ — заглушка, до которой не дойти.
        let key = trips.first?.id ?? UUID()
        let isOpen = expanded.contains(key)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.selection()
                if isOpen { expanded.remove(key) } else { expanded.insert(key) }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Image(systemName: "house")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(c.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(c.card, in: Circle())
                        Text(localNames[key] ?? AppStrings.journeyAroundTown(language))
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                    Text(localMeta(trips))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("journey_local_group")
            .accessibilityAddTraits(isOpen ? .isSelected : [])

            if isOpen {
                Rectangle()
                    .fill(c.border)
                    .frame(height: 0.5)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(trips) { legRow($0, c: c) }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.bg)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(c.border, lineWidth: 1)
                }
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
