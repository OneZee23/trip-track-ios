import SwiftUI

/// «Когда» и «Машина» — один компактный блок под картой (решение владельца
/// 20 сен, §1/§3): обе строки короткие, две отдельные карточки были бы лишним
/// воздухом на листе, где карта уже забрала основную площадь.
struct ManualTripWhenVehicleCard: View {
    @ObservedObject var model: ManualTripModel
    let vehicles: [Vehicle]

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    private let calendar = Calendar.current

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 14) {
            whenRow(c)
            durationRow(c)
            if model.durationTouched, let suggested = model.suggestedDuration {
                suggestedButton(suggested, c: c)
            }
            Divider().overlay(c.border)
            vehicleRow(c)
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Когда

    // Чипы и пикер на РАЗНЫХ строках, а не в одном `HStack`: компактный
    // `DatePicker` с датой И временем не сжимается сам — на общей строке он
    // забирал всю ширину и обрезал «Сегодня»/«Вчера» до многоточия.
    private func whenRow(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.manualTripStart(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            HStack(spacing: 8) {
                dayChip(title: AppStrings.today(lang.language), day: Date(), c: c)
                dayChip(title: AppStrings.yesterday(lang.language),
                        day: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), c: c)
                Spacer(minLength: 0)
            }
            DatePicker(
                "", selection: $model.startDate, in: model.startBounds,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("manual_trip_start")
        }
    }

    private func dayChip(title: String, day: Date, c: AppTheme.Colors) -> some View {
        let selected = calendar.isDate(model.startDate, inSameDayAs: day)
        return Button {
            Haptics.selection()
            model.setStartDay(day)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .white : c.text)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? AppTheme.accent : c.cardAlt, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Длительность

    private func durationRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Text(AppStrings.manualTripDuration(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            Spacer(minLength: 8)
            durationButton("minus", c: c) {
                model.adjustDuration(by: -ManualTripModel.durationStep)
            }
            Text(ManualTripDurationText.string(model.duration, lang: lang.language))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(c.text)
                .frame(minWidth: 72)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("manual_trip_duration")
            durationButton("plus", c: c) {
                model.adjustDuration(by: ManualTripModel.durationStep)
            }
        }
    }

    private func durationButton(
        _ icon: String, c: AppTheme.Colors, action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.text)
                .frame(width: 32, height: 32)
                .background(c.cardAlt, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableCardStyle())
    }

    private func suggestedButton(_ suggested: TimeInterval, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            model.applySuggestedDuration()
        } label: {
            Text(AppStrings.manualTripSuggestedTime(
                lang.language, time: ManualTripDurationText.string(suggested, lang: lang.language)))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("manual_trip_suggested")
    }

    // MARK: - Машина

    private func vehicleRow(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.vehiclePickerTitle(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    vehicleChip(id: nil, title: AppStrings.noVehicle(lang.language), c: c)
                    ForEach(vehicles) { vehicle in
                        vehicleChip(id: vehicle.id, title: vehicle.name, c: c)
                    }
                }
            }
        }
    }

    private func vehicleChip(id: UUID?, title: String, c: AppTheme.Colors) -> some View {
        let selected = model.vehicleId == id
        return Button {
            Haptics.selection()
            model.vehicleId = id
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : c.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? AppTheme.accent : c.cardAlt, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableCardStyle())
    }
}
