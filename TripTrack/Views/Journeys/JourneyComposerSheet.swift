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
    /// Высота списка кандидатов. `ScrollView` жадный по вертикали и без этого
    /// забирает все 320 пунктов даже под одну строку — под единственной
    /// поездкой зияла пустая треть листа.
    @State private var listHeight: CGFloat = 0

    /// Потолок списка: дальше он листается. Больше половины экрана лист
    /// кандидатов не заслуживает — под ним ещё имя и кнопка.
    private static let maxListHeight: CGFloat = 320

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 16) {
            header(c)
            Text(AppStrings.journeyNeighboursHint(lang.language))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(c.textTertiary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(candidates) { row($0, c: c) }
                }
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                    }
                }
            }
            .frame(height: min(max(listHeight, 1), Self.maxListHeight))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
            TextField(AppStrings.journeyTitlePlaceholder(lang.language), text: $title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
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
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// Высота содержимого списка — чтобы лист был ровно такой, какой нужен.
private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
