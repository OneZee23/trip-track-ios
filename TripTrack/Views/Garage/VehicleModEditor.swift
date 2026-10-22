import PhotosUI
import SwiftUI

struct VehicleModEditor: View {
    let vehicle: Vehicle
    let entry: VehicleMod
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @State private var title: String
    @State private var date: Date
    @State private var odometer: String
    @State private var selected: [UUID]
    @State private var photos: [VehiclePhoto]
    @State private var picking: [PhotosPickerItem] = []
    @State private var deleting = false
    @State private var importing = false
    @FocusState private var titleFocused: Bool

    init(vehicle: Vehicle, entry: VehicleMod, appUnit: DistanceUnit) {
        self.vehicle = vehicle
        self.entry = entry
        _title = State(initialValue: entry.title)
        _date = State(initialValue: min(entry.calendarDate ?? Date(), Date()))
        _odometer = State(
            initialValue: OdometerField.fieldText(km: entry.odometerKm, unit: vehicle.dashboardUnit(app: appUnit)))
        let photos = VehiclePhotoStore.photos(of: vehicle.id)
        let available = Set(photos.map(\.id))
        _selected = State(initialValue: Array(entry.photoIds.filter(available.contains).prefix(VehicleMod.photoLimit)))
        _photos = State(initialValue: photos)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = vehicle.dashboardUnit(app: distanceUnit)
        let parsedOdometer = OdometerField.storedKm(odometer, unit: unit)
        let validOdometer =
            odometer.trimmingCharacters(in: .whitespaces).isEmpty
            || (parsedOdometer.map { $0.isFinite && $0 >= 0 } ?? false)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppStrings.garageModTitle(l)).font(.inter(19, weight: .bold)).foregroundStyle(c.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(
                        c.textSecondary
                    )
                    .frame(width: 44, height: 44).background(c.cardAlt, in: Circle())
                }.buttonStyle(PressableCardStyle()).accessibilityLabel(AppStrings.close(l))
            }
            TextField(AppStrings.garageModTitle(l), text: $title)
                .font(.inter(15)).padding(12).background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: title) { _, value in if value.count > 80 { title = String(value.prefix(80)) } }
                .focused($titleFocused).submitLabel(.done).onSubmit { titleFocused = false }
                .accessibilityIdentifier("garage_mod_title")
            DatePicker(
                AppStrings.garageModDate(l), selection: $date,
                in: VehicleMod.dateBounds(selected: date, now: Date()), displayedComponents: .date
            )
            .datePickerStyle(.compact).font(.inter(14)).tint(AppTheme.accent)
            HStack {
                Text(AppStrings.garageMileage(l)).font(.inter(14)).foregroundStyle(c.text)
                Spacer()
                TextField("0", text: $odometer).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .font(.inter(15, weight: .semibold)).frame(maxWidth: 160)
                Text(Measure.distanceParts(km: 0, unit: unit, lang: l).unit).font(.inter(13)).foregroundStyle(
                    c.textSecondary)
            }.padding(12).background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
            Text(AppStrings.garageModPhotos(l)).font(.inter(12)).foregroundStyle(c.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { photo in
                        Button {
                            if selected.contains(photo.id) {
                                selected.removeAll { $0 == photo.id }
                            } else if selected.count < VehicleMod.photoLimit {
                                selected.append(photo.id)
                            }
                            Haptics.tap()
                        } label: {
                            VehiclePhotoImage(photo: photo, maxSize: 180).frame(width: 64, height: 64).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .topTrailing) {
                                    if selected.contains(photo.id) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(
                                            .white, AppTheme.accent
                                        ).padding(3)
                                    }
                                }
                        }.buttonStyle(PressableCardStyle()).accessibilityLabel(AppStrings.photos(l))
                            .accessibilityAddTraits(selected.contains(photo.id) ? .isSelected : [])
                    }
                    PhotosPicker(
                        selection: $picking, maxSelectionCount: max(1, VehicleMod.photoLimit - selected.count),
                        matching: .images
                    ) {
                        Image(systemName: "plus").font(.system(size: 19)).foregroundStyle(AppTheme.accent)
                            .frame(width: 64, height: 64).background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
                    }.disabled(selected.count >= VehicleMod.photoLimit || importing).accessibilityLabel(
                        AppStrings.addPhotos(l))
                }
            }
            Button {
                save(unit: unit)
            } label: {
                Text(AppStrings.save(l)).font(.inter(16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(
                        AppTheme.accent.opacity(trimmed.isEmpty || !validOdometer || importing ? 0.4 : 1),
                        in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(PressableCardStyle()).disabled(trimmed.isEmpty || !validOdometer || importing)
                .accessibilityIdentifier("garage_mod_save")
            if vehicle.mods.contains(where: { $0.id == entry.id }) {
                Button {
                    deleting = true
                } label: {
                    Text(AppStrings.garageModDelete(l)).font(.inter(14, weight: .semibold)).foregroundStyle(
                        AppTheme.red
                    )
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("garage_mod_delete")
            }
        }.padding(20).foregroundStyle(c.text)
            .contentSizedSheet(background: c.card)
            .onChange(of: picking) { _, items in Task { await importPhotos(items) } }
            .appConfirm(
                isPresented: $deleting, title: AppStrings.garageModDeleteTitle(l),
                message: AppStrings.garageModDeleteBody(l),
                actions: [
                    AppDialogAction(
                        AppStrings.garageModDelete(l), kind: .destructive, identifier: "garage_mod_delete_confirm"
                    ) {
                        let current = settings.vehicle(for: vehicle.id)?.mods ?? vehicle.mods
                        settings.updateVehicleGarage(id: vehicle.id, mods: current.filter { $0.id != entry.id })
                        dismiss()
                    }
                ], cancelTitle: AppStrings.cancel(l))
    }

    private func save(unit: DistanceUnit) {
        let parsed = OdometerField.storedKm(odometer, unit: unit)
        guard
            odometer.trimmingCharacters(in: .whitespaces).isEmpty || (parsed != nil && parsed!.isFinite && parsed! >= 0)
        else { return }
        var updated = entry
        updated.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        updated.date = VehicleMod.day(date)
        updated.odometerKm = parsed
        updated.photoIds = selected
        var mods = settings.vehicle(for: vehicle.id)?.mods ?? vehicle.mods
        if let index = mods.firstIndex(where: { $0.id == updated.id }) {
            mods[index] = updated
        } else {
            guard mods.count < VehicleMod.limit else { return }
            mods.append(updated)
        }
        settings.updateVehicleGarage(id: vehicle.id, mods: mods)
        Haptics.success()
        dismiss()
    }

    @MainActor private func importPhotos(_ items: [PhotosPickerItem]) async {
        importing = true
        defer {
            importing = false
            picking = []
        }
        for item in items where selected.count < VehicleMod.photoLimit {
            // The picker can take seconds; a sign-out with a wipe in between
            // deletes this car, and a photo added after that would be an
            // orphan of the previous account.
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                settings.vehicle(for: vehicle.id) != nil,
                let photo = VehiclePhotoStore.add(image, to: vehicle.id)
            else { continue }
            selected.append(photo.id)
        }
        photos = VehiclePhotoStore.photos(of: vehicle.id)
    }
}
