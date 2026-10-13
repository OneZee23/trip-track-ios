import SwiftUI

/// «Когда» и «Машина» — один компактный блок под картой (решение владельца
/// 20 сен, §1/§3): обе строки короткие, две отдельные карточки были бы лишним
/// воздухом на листе, где карта уже забрала основную площадь.
struct ManualTripWhenVehicleCard: View {
    @ObservedObject var model: ManualTripModel
    let vehicles: [Vehicle]

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // The native compact date control has an intrinsic width at AX5.
        // Give it the card's space rather than widening the whole sheet.
        .padding(dynamicTypeSize.isAccessibilitySize ? 8 : 16)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Когда

    // Чипы и пикер на РАЗНЫХ строках, а не в одном `HStack`: компактный
    // `DatePicker` с датой И временем не сжимается сам — на общей строке он
    // забирал всю ширину и обрезал «Сегодня»/«Вчера» до многоточия.
    private func whenRow(_ c: AppTheme.Colors) -> some View {
        let dayLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.manualTripStart(lang.language))
                .font(.interScaled(11, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            dayLayout {
                dayChip(title: AppStrings.today(lang.language), day: Date(), c: c)
                dayChip(title: AppStrings.yesterday(lang.language),
                        day: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date(), c: c)
            }
            if dynamicTypeSize.isAccessibilitySize {
                // Native compact controls keep their native date/time editors.
                // Separate rows give each its full width at large text sizes.
                startPicker(components: [.date], identifier: "manual_trip_start")
                startPicker(components: [.hourAndMinute], identifier: "manual_trip_start_time")
            } else {
                startPicker(components: [.date, .hourAndMinute], identifier: "manual_trip_start")
            }
        }
    }

    private func startPicker(
        components: DatePickerComponents, identifier: String
    ) -> some View {
        DatePicker(
            AppStrings.manualTripStart(lang.language),
            selection: $model.startDate, in: model.startBounds,
            displayedComponents: components
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityIdentifier(identifier)
    }

    private func dayChip(title: String, day: Date, c: AppTheme.Colors) -> some View {
        let selected = calendar.isDate(model.startDate, inSameDayAs: day)
        return Button {
            Haptics.selection()
            model.setStartDay(day)
        } label: {
            Text(title)
                .font(.interScaled(13, weight: .semibold))
                .foregroundStyle(selected ? .white : c.text)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? AppTheme.accent : c.cardAlt, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }

    // MARK: - Длительность

    private func durationRow(_ c: AppTheme.Colors) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Text(AppStrings.manualTripDuration(lang.language))
                .font(.interScaled(11, weight: .semibold))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            durationControls(c)
        }
    }

    private func durationControls(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            durationButton("minus", c: c) {
                model.adjustDuration(by: -ManualTripModel.durationStep)
            }
            Text(ManualTripDurationText.string(model.duration, lang: lang.language))
                .font(.interScaled(15, weight: .bold))
                .foregroundStyle(c.text)
                .frame(minWidth: 72)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("\(icon == "plus" ? "+" : "−") \(ManualTripDurationText.string(ManualTripModel.durationStep, lang: lang.language))")
        .accessibilityValue(ManualTripDurationText.string(model.duration, lang: lang.language))
        .accessibilityIdentifier("manual_trip_duration_\(icon)")
    }

    private func suggestedButton(_ suggested: TimeInterval, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            model.applySuggestedDuration()
        } label: {
            Text(AppStrings.manualTripSuggestedTime(
                lang.language, time: ManualTripDurationText.string(suggested, lang: lang.language)))
                .font(.interScaled(12.5, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("manual_trip_suggested")
    }

    // MARK: - Машина

    private func vehicleRow(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.vehiclePickerTitle(lang.language))
                .font(.interScaled(11, weight: .semibold))
                .foregroundStyle(c.textSecondary)
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
                .font(.interScaled(14, weight: .semibold))
                .foregroundStyle(selected ? .white : c.text)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(selected ? AppTheme.accent : c.cardAlt, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
    }
}
