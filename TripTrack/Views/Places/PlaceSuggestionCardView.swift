import SwiftUI

/// Строка подсказки «Похоже, вы здесь бываете»: имя, сколько поездок тут
/// начиналось или заканчивалось, и кнопка «Сохранить как место».
///
/// Кнопка ОДНА и она отдельная, а сама карточка не нажимается: у подсказки
/// нет своего экрана — открывать там нечего, — и строка, которая «нажимается
/// целиком» ради единственного действия, обещала бы переход. Вложенной в
/// нажимаемую строку кнопка тоже быть не может: так уже ломалось «Вступить»
/// в каталоге клубов, где внешняя кнопка перехватывала тап.
struct PlaceSuggestionCardView: View {
    let suggestion: PlaceSuggestion
    let onSave: () -> Void

    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let l = lang.language
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(AtlasTheme.accentSoft)
                    Image(systemName: "mappin")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AtlasTheme.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name ?? AppStrings.placeSuggestUnnamed(l))
                        .font(AppType.itemTitle)
                        .foregroundStyle(AtlasTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AppStrings.placeSuggestTrips(l, trips: tripsCount(l)))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            // Кнопка встаёт ПОД текстом и с отступом под кружок: так она
            // читается действием этой карточки, а не значком в её углу.
            Button {
                Haptics.tap()
                onSave()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                    Text(AppStrings.placeSuggestSave(l)).font(AppType.button)
                }
                .foregroundStyle(AtlasTheme.accentInk)
                .padding(.leading, 10).padding(.trailing, 14)
                .frame(height: 44)
                .background(AtlasTheme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
            .padding(.leading, 48)
            .accessibilityIdentifier("place_suggestion_save_\(suggestion.cell)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14).padding(.bottom, 12)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("place_suggestion_\(suggestion.cell)")
    }

    /// «3 поездки» — счётное существительное через CLDR, не через `if .ru`.
    private func tripsCount(_ l: LanguageManager.Language) -> String {
        "\(AppStrings.formattedCount(suggestion.trips, lang: l)) \(AppStrings.nounTrips(l, suggestion.trips))"
    }
}

/// «Как появляются места» — карточка-образец и три шага (макет S2/S3).
///
/// Показывается, пока мест меньше трёх И подсказать нечего: экран обязан
/// объяснять себя делом, а не пустотой. Как только подсказки появились,
/// карточка уходит — она объясняла ровно то, что теперь видно строками.
struct PlacesHowItWorksCard: View {
    /// `nil` — поездок ещё нет вовсе, и кнопка ведёт не в поездку, а в
    /// запись: нажатие, которое ничего не делает, хуже отсутствующего.
    let onOpenLastTrip: (() -> Void)?
    /// Уйти на запись поездки. Единственная кнопка экрана, у которого нет
    /// ни поездок, ни мест.
    var onStartRecording: (() -> Void)?

    @EnvironmentObject private var lang: LanguageManager

    private static let dayMonth = LocalizedDateFormatter.templates("dMMM")

    var body: some View {
        let l = lang.language
        VStack(spacing: 12) {
            exampleCard(l)
            stepsCard(l)
            actionButton(l)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("places_how_card")
    }

    // MARK: Образец

    /// Как выглядит заведённое место — картинкой, а не словами.
    ///
    /// Карта здесь НАРИСОВАНА, а не `PlacesMapView`: настоящей карте нужна
    /// настоящая координата, а место в этой карточке выдуманное, и ставить
    /// его на чей-то реальный двор нельзя. Плашка «Пример» стоит поверх, и
    /// карточка не нажимается — открывать нечего.
    private func exampleCard(_ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ExampleRouteArt()
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
                    .clipped()
                Text(AppStrings.placesExample(l))
                    .font(AppType.statCaption)
                    .textCase(.uppercase)
                    .tracking(AppType.statCaptionTracking)
                    .foregroundStyle(AtlasTheme.secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(AtlasTheme.control.opacity(0.94), in: Capsule())
                    .padding(12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.placesExampleName(l))
                    .font(AppType.itemTitle)
                    .foregroundStyle(AtlasTheme.ink)
                Text(examplePasses(l))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
                Text(AppStrings.placeUsually(l, time: CheckpointReading.clock(52 * 60, lang: l)))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// «3 проезда · последний 25 сент.» — теми же composers, что настоящая
    /// строка списка: у образца и у живой карточки один набор слов, иначе
    /// человек увидел бы одно, а получил другое.
    private func examplePasses(_ l: LanguageManager.Language) -> String {
        let count = "\(AppStrings.formattedCount(3, lang: l)) \(AppStrings.nounPasses(l, 3))"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        guard let f = Self.dayMonth[l] else { return count }
        return "\(count) · \(AppStrings.placeLastPass(l, date: f.string(from: yesterday)))"
    }

    // MARK: Три шага

    private func stepsCard(_ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            step("record.circle", AppStrings.placesHowMarkTitle(l), AppStrings.placesHowMark(l))
            AtlasTheme.separator.frame(height: 1)
            step("hand.tap", AppStrings.placesHowTapTitle(l), AppStrings.placesHowTap(l))
            AtlasTheme.separator.frame(height: 1)
            step("sparkles", AppStrings.placesHowSuggestTitle(l), AppStrings.placesHowSuggest(l))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
    }

    private func step(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(AtlasTheme.chip)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AtlasTheme.ink)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppType.itemTitle)
                    .foregroundStyle(AtlasTheme.ink)
                Text(detail)
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    // MARK: Кнопка

    @ViewBuilder
    private func actionButton(_ l: LanguageManager.Language) -> some View {
        if let onOpenLastTrip {
            button(AppStrings.placesOpenLastTrip(l), id: "places_open_last_trip", action: onOpenLastTrip)
        } else if let onStartRecording {
            button(AppStrings.recordTripCta(l), id: "places_start_recording", action: onStartRecording)
        }
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(AppType.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AtlasTheme.accent, in: RoundedRectangle(cornerRadius: AtlasTheme.statRadius, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier(id)
    }
}

/// Нарисованный клочок карты для карточки-образца: бумага, пара дорог,
/// терракотовая нитка и булавка с выноской. Ни координат, ни MapKit —
/// выдуманному месту настоящая карта не нужна, а рисунок стоит ноль.
private struct ExampleRouteArt: View {
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                AtlasTheme.searchBackground
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.72))
                    p.addLine(to: CGPoint(x: w, y: h * 0.52))
                    p.move(to: CGPoint(x: w * 0.22, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.34, y: h))
                    p.move(to: CGPoint(x: w * 0.78, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.70, y: h))
                }
                .stroke(AtlasTheme.handle.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.08, y: h * 0.92))
                    p.addCurve(to: CGPoint(x: w * 0.54, y: h * 0.62),
                               control1: CGPoint(x: w * 0.26, y: h * 0.86),
                               control2: CGPoint(x: w * 0.38, y: h * 0.74))
                    p.addCurve(to: CGPoint(x: w * 0.94, y: h * 0.16),
                               control1: CGPoint(x: w * 0.70, y: h * 0.50),
                               control2: CGPoint(x: w * 0.82, y: h * 0.28))
                }
                .stroke(AtlasTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                pin(at: CGPoint(x: w * 0.54, y: h * 0.62))
            }
        }
        .accessibilityHidden(true)
    }

    private func pin(at point: CGPoint) -> some View {
        VStack(spacing: 4) {
            Text(AppStrings.placesExampleName(lang.language))
                .font(AppType.caption)
                .foregroundStyle(AtlasTheme.ink)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(AtlasTheme.control, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            Circle()
                .fill(AtlasTheme.accent)
                .frame(width: 14, height: 14)
                .overlay { Circle().strokeBorder(.white, lineWidth: 2.6) }
        }
        .position(x: point.x, y: point.y - 16)
    }
}
