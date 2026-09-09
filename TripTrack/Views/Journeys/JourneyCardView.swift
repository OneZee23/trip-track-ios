import SwiftUI
import CoreLocation

/// Карточка путешествия в «Моих» (Figma A, 2849:160): карта всех плеч, плашка
/// «ПУТЕШЕСТВИЕ · 4 ДНЯ», стопка миниатюр плеч, имя и строка итога.
///
/// Стоит ВМЕСТО своих плеч: шесть записей о дороге в Тбилиси — одна история, и
/// шесть карточек подряд её как раз и прятали. Плечи приходят снаружи
/// (`HistoryFolding`), потому что их уже отобрал календарь: спрашивать базу
/// второй раз значило бы иметь две правды о том, что внутри окна.
struct JourneyCardView: View {
    let journey: Journey
    let legs: [Trip]
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme

    /// Итог считается на создании карточки, а не в `body`: `body` зовётся на
    /// каждый кадр прокрутки, а `JourneyAggregate.build` перебирает все точки
    /// всех плеч.
    private let aggregate: JourneyAggregate
    /// Ниточки плеч в общей рамке. Каждое плечо своим маршрутом — склейка
    /// одной линией дорисовала бы прямую через пустоту между городами.
    private let routes: [[CLLocationCoordinate2D]]
    /// Четыре самых новых плеча в стопку. Больше не влезает, а «+N» на такой
    /// маленькой стопке читается как ошибка вёрстки.
    private let thumbs: [Trip]
    private let windowEnd: Date

    /// Имена мест для имени по умолчанию. Кэш геокодера живёт в CoreData, так
    /// что читается он один раз в `.task`, а не из `body`.
    @State private var startName: String?
    @State private var farthestName: String?

    private static let mapHeight: CGFloat = 150
    private static let thumbSide: CGFloat = 28

    init(journey: Journey, legs: [Trip], onTap: @escaping () -> Void) {
        self.journey = journey
        self.legs = legs
        self.onTap = onTap
        self.aggregate = JourneyAggregate.build(trips: legs)
        self.routes = legs.map(\.previewCoordinates).filter { $0.count > 1 }
        self.thumbs = Array(legs.sorted { $0.startDate > $1.startDate }.prefix(4))
        self.windowEnd = journey.endDate
            ?? legs.map { $0.endDate ?? $0.startDate }.max()
            ?? journey.startDate
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        Button {
            Haptics.tap()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                mapSection(c)
                    .overlay(alignment: .topLeading) { pill }
                    .overlay(alignment: .topTrailing) { thumbnailStack(c) }

                titleRow(c)
                    .padding(.horizontal, 13)
                    .padding(.top, 11)

                Text(metaText)
                    .font(.inter(11.5, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.top, 3)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Не `.surfaceCard()`: карта прижата к трём краям карточки, и
            // клип после `surfaceCard` унёс бы вместе с углами и тень — ровно
            // тот же порядок, что у плитки сетки.
            .background(RoundedRectangle(cornerRadius: 16).fill(c.card))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: scheme == .dark ? .clear : .black.opacity(0.03), radius: 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("profile_journey_card")
        .task(id: journey.id) { loadNames() }
    }

    // MARK: - Карта

    @ViewBuilder
    private func mapSection(_ c: AppTheme.Colors) -> some View {
        if routes.isEmpty {
            // Ни одного трека (плечи без `previewPolyline`) — та же «карты
            // нет», что на карточке поездки, а не вечный шиммер.
            ZStack {
                Rectangle().fill(c.cardAlt)
                Image(systemName: "map.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .frame(height: Self.mapHeight)
            .frame(maxWidth: .infinity)
        } else {
            CardMapPreview(routes: routes)
                .frame(height: Self.mapHeight)
                .frame(maxWidth: .infinity)
        }
    }

    /// Тёмная плашка поверх карты: её фон не зависит от темы, потому что снизу
    /// не тема, а тайлы.
    private var pill: some View {
        HStack(spacing: 5) {
            Image(systemName: "suitcase.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            Text(pillText)
                .font(.inter(10, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.black.opacity(0.72), in: Capsule())
        .padding(10)
    }

    /// Стопка миниатюр плеч — те же снимки тайлов, что на плитках «Истории»
    /// (`MapSnapshotPreview`), а не рисованная нитка: у `LightRoutePreview`
    /// зашита рамка в 16 точек, и на квадрате в 28 от маршрута остаётся
    /// вертикальная чёрточка.
    @ViewBuilder
    private func thumbnailStack(_ c: AppTheme.Colors) -> some View {
        if !thumbs.isEmpty {
            HStack(spacing: -10) {
                ForEach(thumbs) { leg in
                    ZStack {
                        Rectangle().fill(c.cardAlt)
                        // Меньше двух точек — снимок не поедет и останется
                        // шиммером навсегда; пустая плашка честнее.
                        if leg.previewCoordinates.count > 1 {
                            MapSnapshotPreview(
                                coordinates: leg.previewCoordinates,
                                tripId: leg.id,
                                height: Self.thumbSide,
                                width: Self.thumbSide
                            )
                        }
                    }
                    .frame(width: Self.thumbSide, height: Self.thumbSide)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(.white, lineWidth: 2)
                    }
                }
            }
            .padding(10)
        }
    }

    // MARK: - Строки

    private func titleRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Text(titleText)
                .font(.inter(19, weight: .heavy))
                .tracking(-0.2)
                .foregroundStyle(c.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 4)

            // Шеврон стоит там, где нажатие ОТКРЫВАЕТ: вся карточка ведёт на
            // экран путешествия.
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
    }

    /// «ПУТЕШЕСТВИЕ · 4 ДНЯ».
    private var pillText: String {
        let l = lang.language
        let days = max(aggregate.calendarDays, 1)
        return "\(AppStrings.journeyWord(l)) · \(days) \(AppStrings.nounDays(l, days))"
            .uppercased(l)
    }

    /// Имя человека, иначе «Краснодар — Тбилиси», иначе даты — тот же порядок,
    /// что на экране путешествия: одна запись не может называться на двух
    /// экранах по-разному.
    private var titleText: String {
        if let title = journey.title, !title.isEmpty { return title }
        if let auto = aggregate.defaultTitle(startName: startName, farthestName: farthestName),
           !auto.isEmpty {
            return auto
        }
        return dateRangeText
    }

    /// «12–17 сен · 1 640 км · 6 поездок · 19 ч в пути». Числа — те же, что в
    /// четырёх плитках итога на экране путешествия, включая «поездки»: там
    /// считаются плечи дороги, а местные поездки у ночёвки свёрнуты.
    private var metaText: String {
        let l = lang.language
        // Одни и те же даты заголовком и первым словом подписи — не строка
        // итога, а сбой: имени взять неоткуда, и заголовок сам стал датами.
        var parts = titleText == dateRangeText ? [] : [dateRangeText]
        parts.append("\(TripDetailFormat.groupedNumber(aggregate.totalMetres / 1000)) \(AppStrings.km(l))")
        parts.append("\(aggregate.legCount) \(AppStrings.nounTrips(l, aggregate.legCount))")
        let driving = JourneyFormat.duration(aggregate.drivingSeconds, language: l)
        if !driving.isEmpty {
            parts.append("\(driving) \(AppStrings.journeyDrivingLabel(l).lowercased(l))")
        }
        return parts.joined(separator: " · ")
    }

    private var dateRangeText: String {
        JourneyFormat.dateRange(from: journey.startDate, to: windowEnd, language: lang.language)
    }

    private func loadNames() {
        // Кэш геокодера — у общего `TripManager`, того же, что у экрана
        // путешествия: свой завести нельзя, внутри него очередь записи.
        let geocoder = mapVM.tripManager
        startName = aggregate.firstStart.flatMap { geocoder.cachedLocality(for: $0) }
        farthestName = aggregate.farthestEnd.flatMap { geocoder.cachedLocality(for: $0) }
    }
}
