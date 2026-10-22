import SwiftUI

struct VehicleModsSection: View {
    let mods: [VehicleMod]
    let unit: DistanceUnit
    var photoPages: [UUID: [PhotoFullScreenView.Page]] = [:]
    var onEdit: ((VehicleMod) -> Void)? = nil
    var onAdd: (() -> Void)? = nil
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @State private var photos: SelectedPhotos?
    private struct SelectedPhotos: Identifiable {
        let id: UUID
        let title: String
        let pages: [PhotoFullScreenView.Page]
    }

    var body: some View {
        if !mods.isEmpty || onAdd != nil {
            let c = AppTheme.colors(for: scheme)
            VStack(alignment: .leading, spacing: 14) {
                Text(AppStrings.garageMods(lang.language)).font(.inter(16, weight: .bold)).foregroundStyle(c.text)
                    .accessibilityIdentifier("garage_mods")
                ForEach(VehicleMod.ordered(mods)) { mod in
                    Button {
                        Haptics.tap()
                        if let onEdit {
                            onEdit(mod)
                        } else if let pages = photoPages[mod.id], !pages.isEmpty {
                            photos = SelectedPhotos(id: mod.id, title: mod.title, pages: pages)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(AppTheme.accent).frame(width: 6, height: 6).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mod.title).font(.inter(14, weight: .semibold)).foregroundStyle(c.text)
                                Text(metadata(mod)).font(.inter(12)).foregroundStyle(c.textSecondary)
                            }
                            Spacer(minLength: 0)
                            if onEdit != nil {
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(c.textTertiary).padding(.top, 6)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(PressableCardStyle())
                        .disabled(onEdit == nil && (photoPages[mod.id] ?? []).isEmpty)
                        .accessibilityIdentifier("garage_mod_\(mod.id)")
                }
                if let onAdd, mods.count < VehicleMod.limit {
                    Button(action: onAdd) {
                        Label(AppStrings.garageAddMod(lang.language), systemImage: "plus")
                            .font(.inter(13, weight: .semibold)).foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44).contentShape(
                                Rectangle())
                    }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("garage_add_mod")
                }
            }.padding(16).surfaceCard(cornerRadius: 20)
                .fullScreenCover(item: $photos) { selected in
                    GaragePhotoGrid(title: selected.title, pages: selected.pages)
                }
        }
    }

    private func metadata(_ mod: VehicleMod) -> String {
        let l = lang.language
        var parts: [String] = []
        if let date = mod.calendarDate {
            let f = DateFormatter()
            f.locale = l.locale
            f.setLocalizedDateFormatFromTemplate("dMMMyyyy")
            parts.append(f.string(from: date))
        }
        if let km = mod.odometerKm { parts.append(Measure.distance(km: km, unit: unit, lang: l)) }
        let count = onEdit == nil ? (photoPages[mod.id]?.count ?? 0) : mod.photoIds.count
        if count > 0 { parts.append(AppStrings.photosCount(l, n: count)) }
        return parts.joined(separator: " · ")
    }
}
