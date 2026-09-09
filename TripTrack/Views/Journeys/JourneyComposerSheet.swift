import SwiftUI

/// «Объединить в путешествие»: соседи за ±7 дней, все отмечены, лишние
/// снимаются; имя — по желанию, иначе «Краснодар — Тбилиси» соберётся само.
///
/// Список приходит уже суженным (`JourneyManager.neighbours`), и опорная
/// поездка в нём НЕ лежит — её лист ставит первой сам. Особенной она при этом
/// не становится: снять галочку можно и с неё. Человек пришёл сюда с экрана
/// одной поездки, но собирает историю, а не список её спутников — запрет
/// «эту нельзя» был бы правилом, которого он не просил.
struct JourneyComposerSheet: View {
    let anchor: Trip
    let onCreated: (Journey) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = JourneyManager.shared
    @State private var candidates: [Trip] = []
    @State private var selected: Set<UUID> = []
    @State private var title = ""
    @State private var error: String?

    /// Высота строки, посчитанная, а не измеренная: `ScrollView` гибкий по
    /// вертикали и растягивается на всё, что ему дали, — поэтому под одной
    /// поездкой зияла пустая треть листа. Мерить его собственную высоту
    /// `GeometryReader`-ом, которым же и задавать ему рамку, — петля, от
    /// которой предостерегает `VehiclePickerSheet`. Кандидаты ограничены
    /// окном ±7 дней, так что до пяти строк список рисуется целиком, а
    /// дальше листается в счётной рамке.
    private static let rowHeight: CGFloat = 60
    private static let rowSpacing: CGFloat = 8
    private static let maxVisibleRows = 5
    private static var maxListHeight: CGFloat {
        CGFloat(maxVisibleRows) * rowHeight + CGFloat(maxVisibleRows - 1) * rowSpacing
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 16) {
            header(c)
            Text(AppStrings.journeyNeighboursHint(lang.language))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(c.textTertiary)
            candidateList(c)
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
            candidates = manager.neighbours(of: anchor)
            // Опорная поездка — первой и с запасом на случай, если менеджер
            // однажды начнёт возвращать её сам: дважды в списке она хуже, чем
            // не первой.
            if !candidates.contains(where: { $0.id == anchor.id }) {
                candidates.insert(anchor, at: 0)
            }
            selected = Set(candidates.map(\.id))
        }
    }

    // MARK: - Куски

    /// До пяти кандидатов — обычный `VStack`: он сам говорит листу, сколько
    /// места ему нужно. Больше — прокрутка в рамке ровно на пять строк.
    @ViewBuilder
    private func candidateList(_ c: AppTheme.Colors) -> some View {
        if candidates.count <= Self.maxVisibleRows {
            VStack(spacing: Self.rowSpacing) {
                ForEach(candidates) { row($0, c: c) }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(candidates) { row($0, c: c) }
                }
            }
            .frame(height: Self.maxListHeight)
        }
    }

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "suitcase")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent, in: Circle())
            Text(AppStrings.journeyCombine(lang.language))
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

    /// Строка кандидата: галочка, название, дата и километры. Ничего больше —
    /// человек выбирает, какие поездки составляют одну историю, а не изучает
    /// каждую из них заново.
    private func row(_ trip: Trip, c: AppTheme.Colors) -> some View {
        let isOn = selected.contains(trip.id)
        return Button {
            Haptics.selection()
            // Отказ описывал ПРЕЖНИЙ выбор: оставить его на экране, где выбор
            // уже другой, значит соврать про даты, которых больше нет.
            error = nil
            if isOn { selected.remove(trip.id) } else { selected.insert(trip.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? AppTheme.accent : c.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText(trip))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(metaText(trip))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
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

    /// Тот же ответ, что дают карточки поездок: имя, иначе регион, иначе дата.
    /// Расходиться им нельзя — это одна и та же поездка на двух экранах.
    private func titleText(_ trip: Trip) -> String {
        if trip.hasDisplayableName,
           let t = TripAutoTitle.localized(trip.title, startDate: trip.startDate, language: lang.language),
           !t.isEmpty {
            return t
        }
        if let region = RegionDisplay.localized(trip.region, language: lang.language), !region.isEmpty {
            return region
        }
        return dateText(trip.startDate)
    }

    /// «14 сент · 143 км». Километры целыми: разница в сотню метров ничего не
    /// решает в выборе, из каких поездок сложить историю.
    private func metaText(_ trip: Trip) -> String {
        let km = Int(trip.distance / 1000)
        return "\(dateText(trip.startDate)) · \(km) \(AppStrings.km(lang.language))"
    }

    /// Тот же «14 сент» без точки, что на карточках поездок, — своим
    /// формирователем он вышел бы «14 сент.» и разошёлся бы с лентой.
    private func dateText(_ date: Date) -> String {
        ProfileDateFormat.dayMonth(date, lang: lang.language)
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
