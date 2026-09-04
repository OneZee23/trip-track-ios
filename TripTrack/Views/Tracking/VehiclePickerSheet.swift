import SwiftUI

/// Vehicle picker at record start (Figma 542:119): white bottom sheet with
/// «Без транспорта» on top, one row per vehicle below it, a checkmark on the
/// current choice, and a Garage footer. Selection persists through
/// SettingsManager so the slide-to-start records against the picked vehicle.
///
/// Recording without any transport is a normal outcome here, not a failure to
/// choose: a new garage is empty and stays empty until someone deliberately
/// fills it, so «Без транспорта» is the state most people arrive in. It leads
/// the list and wears the same selected chrome as a vehicle for that reason.
struct VehiclePickerSheet: View {
    /// Whether picking also makes this the app's current vehicle.
    ///
    /// True where the pick is about what you are ABOUT to drive (the recording
    /// screen). False where it is about what you drove three weeks ago — the
    /// trip editor — because there the write-through silently changed which
    /// vehicle the next recording would be stamped with.
    var persistsSelection: Bool = true
    /// Показывать ли машины, на которые сейчас нельзя писать (в архиве,
    /// проданные).
    ///
    /// На записи — нет: гараж обещает, что пишем на активную, и шторка обязана
    /// говорить то же самое. В редакторе СТАРОЙ поездки — да: поездка могла
    /// быть на машине, которую с тех пор убрали в архив или продали, и
    /// запретить это указать значило бы запретить исправлять историю.
    var includesArchived: Bool = false
    /// Чья галочка стоит: `nil` — общий выбор приложения, `.some(x)` — значение
    /// ЭТОЙ поездки (само по себе может быть `nil` = «без транспорта»).
    ///
    /// Двойной опционал ровно поэтому: «не передали» и «передали пусто» здесь
    /// разные ответы. Без него редактор поездки, записанной на машину А, ставил
    /// галочку на активную машину Б — то есть показывал не то, что правит.
    var checkedVehicleId: UUID??
    /// Called with the picked vehicle, `nil` for «Без транспорта». The
    /// recording screen uses it to restamp the trip that is already running;
    /// the editor uses it to set the field. Both sides already take `UUID?` —
    /// a trip with no vehicle is a valid trip, all the way down.
    var onPick: ((UUID?) -> Void)?
    /// Показывать ли строку «Ехал пассажиром» (0.6.3, включена на записи в 0.6.4).
    ///
    /// Раньше строка жила только в редакторе поездки: рассуждение было, что на
    /// экране записи выбирают, НА ЧЁМ поедешь, а не КЕМ ехал. На практике это
    /// значило, что сказать «я пассажир» можно было только задним числом, уже
    /// после поездки, — а до тех пор километры такси лежали на своей машине.
    /// Решение отменено: строка есть и на записи тоже. Свойством КОНКРЕТНОЙ
    /// поездки она при этом быть не перестала — в `selectedVehicleId` она не
    /// пишется никогда, иначе следующая поездка молча унаследовала бы «я
    /// пассажир».
    var showsTransferOption: Bool = false
    /// Помечена ли редактируемая поездка трансфером — для галочки.
    var isTransferSelected: Bool = false
    /// Выбран трансфер. Отдельный колбэк, а не `onPick(nil)`: «без транспорта»
    /// значит «не указал машину», а трансфер — «ехал не за рулём», и путать
    /// их нельзя, иначе километры молча останутся на чьём-то одометре.
    var onPickTransfer: (() -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            grabber

            Text(AppStrings.vehiclePickerTitle(lang.language))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.bottom, 16)

            rows(c: c)

            if listed.isEmpty {
                emptyHint(c: c)
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            garageFooter
        }
        // Measure what is actually in the sheet and make the sheet that tall.
        //
        // The height used to be arithmetic — a 160pt «chrome» constant that
        // included room for the home indicator, plus 62 per row. iOS 26 turned
        // sheets into cards that float inset from the screen edge and add that
        // room themselves, so the two stacked: the card came out taller than
        // the space it had and its bottom corners were cut off by the screen,
        // with a band of empty sheet above them. Measuring works on both,
        // because it asks the content instead of guessing for it.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
        .background(c.bg)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
    }

    /// Seeded with a plausible first-frame height so the sheet does not open at
    /// zero and animate open; the real measurement lands on the same frame.
    /// One row taller than it used to be, since «Без транспорта» is always
    /// there.
    @State private var contentHeight: CGFloat = 320

    private struct SheetHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// Что вообще показано в списке. Единственное место, где шторка решает
    /// этот вопрос, — и после фильтра список может стать короче гаража, но
    /// никогда длиннее, поэтому измерение высоты выше остаётся верным.
    private var listed: [Vehicle] {
        includesArchived ? settings.vehicles : settings.recordableVehicles
    }

    /// Машина, у которой стоит галочка.
    private var checked: UUID? {
        if case let .some(explicit) = checkedVehicleId { return explicit }
        return settings.selectedVehicleId
    }

    private static let rowSpacing: CGFloat = 4

    // MARK: - Chrome

    private var grabber: some View {
        Capsule()
            .fill(.primary.opacity(0.18))
            .frame(width: 34, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 14)
    }

    // MARK: - Rows

    private func rows(c: AppTheme.Colors) -> some View {
        // No ScrollView: the garage is capped at five vehicles, so with the
        // «Без транспорта» row the list tops out at six and always fits — and a
        // ScrollView is flexible, which means it stretches to whatever height
        // the sheet was given instead of telling the sheet how tall it needs to
        // be. Fixed content is what makes the measurement above possible.
        VStack(spacing: Self.rowSpacing) {
            noVehicleRow(c: c)
            if showsTransferOption {
                transferRow(c: c)
            }
            ForEach(listed) { vehicle in
                vehicleRow(vehicle, c: c)
            }
        }
        .padding(.horizontal, 16)
    }

    /// «Без транспорта» — the trip still records, it just has no vehicle to
    /// bill the fuel, mileage and level to. A neutral glyph rather than a car:
    /// a car with a slash through it would read as an error state.
    /// «Ехал пассажиром» — такси, автобус, чужая машина.
    ///
    /// Стоит рядом с «Без транспорта» намеренно: обе строки означают «машины у
    /// этой поездки нет», но по разным причинам, и разница видна в пробеге.
    private func transferRow(c: AppTheme.Colors) -> some View {
        Button {
            Haptics.selection()
            onPickTransfer?()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isTransferSelected ? AppTheme.accentBg : c.cardAlt)
                        .frame(width: 42, height: 42)
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(isTransferSelected ? AppTheme.accent : c.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.tripTransferTitle(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(AppStrings.tripTransferHint(lang.language))
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isTransferSelected {
                    selectedCheck
                }
            }
            .modifier(PickerRowChrome(selected: isTransferSelected))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_picker_transfer")
    }

    private func noVehicleRow(c: AppTheme.Colors) -> some View {
        // Checked whenever the selection resolves to nothing, not only when the
        // id is literally nil: deleting the selected vehicle can leave a
        // dangling id behind, and a strict `== nil` then put the checkmark on
        // no row at all. VehicleChip already reads that same state as «Без
        // транспорта» — the sheet has to agree with the chip that opened it.
        let selected = !isTransferSelected && settings.vehicle(for: checked) == nil
        return Button {
            Haptics.selection()
            if persistsSelection {
                settings.selectVehicle(id: nil)
            }
            onPick?(nil)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(c.cardAlt)
                        .frame(width: 42, height: 42)
                    Image(systemName: "minus.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(c.textTertiary)
                }
                Text(AppStrings.noVehicleOption(lang.language))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                Spacer()
                if selected {
                    selectedCheck
                }
            }
            .modifier(PickerRowChrome(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_picker_none")
    }

    private func vehicleRow(_ vehicle: Vehicle, c: AppTheme.Colors) -> some View {
        let selected = !isTransferSelected && vehicle.id == checked
        return Button {
            Haptics.selection()
            // Persist the pick — a bare `selectedVehicleId =` would not write
            // through to CoreData, so slide-to-start (which re-reads from the
            // settings entity) would record against the previous vehicle.
            if persistsSelection {
                settings.selectVehicle(id: vehicle.id)
            }
            onPick?(vehicle.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    // The sprite's ground with no edge to it — a filled dark
                    // disc in a light row is the same sticker problem the
                    // square plate had, just rounder. The «no vehicle» row
                    // above keeps the card colour: it holds a glyph, not a
                    // sprite, and has nothing to stand on.
                    Circle()
                        .fill(LinearGradient(
                            colors: [AppTheme.spritePlateTop, AppTheme.spritePlateBottom],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 42, height: 42)
                    if let asset = vehicle.avatarImageName {
                        Image(asset)
                            .resizable()
                            // Nearest-neighbour: the pixel cars are drawn at
                            // asset resolution and smoothing turns them to mush.
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    } else {
                        Text(vehicle.avatarEmoji).font(.system(size: 20))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vehicle.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        // Two identical grey hatchbacks are told apart by the
                        // plate and nothing else. The owner always sees their
                        // own — `plateVisible` governs strangers, not this.
                        if vehicle.hasPlate {
                            VehiclePlateChip(plate: vehicle.plate, size: 10)
                        }
                    }
                    Text("\(GarageFormat.odometer(vehicle.displayOdometerKm, lng: lang.language)) \(AppStrings.km(lang.language))")
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer()
                if selected {
                    selectedCheck
                }
            }
            .modifier(PickerRowChrome(selected: selected))
        }
        .buttonStyle(.plain)
    }

    private var selectedCheck: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(AppTheme.accent)
    }

    // MARK: - Empty garage

    /// The sheet still has a job with an empty garage — it says the trip will
    /// record anyway and offers the way out of the empty state, instead of
    /// leaving a lone row over a void.
    private func emptyHint(c: AppTheme.Colors) -> some View {
        Text(AppStrings.garageEmptyPickerHint(lang.language))
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.top, 12)
    }

    // MARK: - Footer

    private var garageFooter: some View {
        // Same door either way, named for what is behind it: an empty garage
        // has nothing to «manage» yet.
        let label = settings.vehicles.isEmpty
            ? AppStrings.addVehicleTitle(lang.language)
            : AppStrings.manageInGarage(lang.language)

        return Button {
            Haptics.tap()
            dismiss()
            // Garage lives under the Я tab — switch there; ProfileView
            // hosts the Garage entry point.
            NotificationCenter.default.post(name: .openGarage, object: nil)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AppTheme.accent)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 20)
        .accessibilityIdentifier("vehicle_picker_garage")
    }
}

/// Selected-row chrome, shared by «Без транспорта» and the vehicles so the
/// no-vehicle choice cannot drift into looking like the lesser option.
private struct PickerRowChrome: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? AppTheme.accent.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? AppTheme.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
    }
}
