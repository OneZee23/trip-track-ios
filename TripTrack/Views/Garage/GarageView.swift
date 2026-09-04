import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var lang: LanguageManager
    /// Sheets are separate presentations — the override applied to the
    /// Garage sheet itself (ProfileView) does not reach a sheet presented
    /// from HERE, so the add-vehicle form must re-apply it.
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @State private var showAddVehicle = false
    @State private var detailVehicleId: UUID?
    @State private var deleteCandidateId: UUID?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        // БЕЗ собственного NavigationStack: гараж — полноценная СТРАНИЦА,
        // которую пушит хозяин (профиль). Раньше он выезжал шитом снизу, и
        // это расходилось с каноном; а свой стек внутри чужого запрещён
        // домашними правилами и ломает жест «назад».
        Group {
            VStack(spacing: 0) {
                navRow(c: c, l: l)
                // An empty garage is a screen, not a card: it has to own the
                // space under the nav row to centre in it, so it replaces the
                // scroll view instead of living inside it.
                if settings.vehicles.isEmpty {
                    emptyState(c: c, l: l)
                } else {
                    vehicleScroll(c: c, l: l)
                }
            }
            .background(c.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailVehicleId) { id in
                VehicleDetailView(vehicleId: id)
            }
            .sheet(isPresented: $showAddVehicle) {
                VehicleEditFormView(mode: .add)
                    .environmentObject(lang)
            }
            // House dialog, never the system's — see «Dialogs» in CLAUDE.md.
            .appConfirm(
                isPresented: deleteConfirmation,
                title: AppStrings.deleteVehicleConfirm(l),
                // Without it the dialog asks to delete and says nothing about
                // what happens to the trips — the one thing worth fearing.
                message: AppStrings.deleteVehicleBody(l),
                actions: deleteActions(l),
                cancelTitle: AppStrings.cancel(l)
            )
        }
    }

    /// The candidate is captured HERE, while the card is on screen, not read
    /// back inside the handler: the dialog dismisses itself first, and that
    /// dismissal runs `deleteConfirmation`'s setter, which has already cleared
    /// `deleteCandidateId` by the time the handler fires.
    private func deleteActions(_ l: LanguageManager.Language) -> [AppDialogAction] {
        guard let id = deleteCandidateId else { return [] }
        return [
            AppDialogAction(AppStrings.deleteVehicle(l), kind: .destructive) {
                performDelete(id: id)
            }
        ]
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(
            get: { deleteCandidateId != nil },
            set: { if !$0 { deleteCandidateId = nil } }
        )
    }

    // MARK: - Nav Row (Figma 152:1328)

    /// The app's own nav bar, not a local copy of one.
    ///
    /// This row used to be hand-built from `GarageCircleNavButton` — a 34pt
    /// circle like the canon control but with a fainter shadow, a smaller
    /// glyph and no 44pt hit area — inset 2pt from the top. On a sheet, whose
    /// top edge is a hard rounded boundary with UIKit's grabber over the first
    /// 10pt, 2pt glued the buttons into the corner and clipped them against
    /// it. `CustomNavBar` already solves exactly this: it insets 20pt inside a
    /// sheet for the grabber, 20pt horizontally so the controls clear the
    /// curved glass, and it carries `NavCircleIcon` — the same control every
    /// other sheet in the app uses.
    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Потолок считает ТОЛЬКО те машины, на которые можно писать. Иначе
        // архив не даёт ничего: убрал лишнюю — место всё равно занято, и
        // «убери в архив» превращается в уборку на экране без последствий.
        let atCap = settings.recordableVehicles.count >= 5
        return CustomNavBar(title: AppStrings.garage(l)) {
            Button {
                Haptics.tap()
                showAddVehicle = true
            } label: {
                NavCircleIcon(systemImage: "plus")
            }
            .buttonStyle(.plain)
            .disabled(atCap)
            .opacity(atCap ? 0.35 : 1)
            .accessibilityIdentifier("garage_add")
        }
        // Presented as a sheet from Profile, Settings and the Feed — the bar
        // needs to know so it clears the grabber.
        .environment(\.navBarInSheet, true)
    }

    // MARK: - Vehicle List

    private func vehicleScroll(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                vehicleList(c: c, l: l)
            }
            .padding(.horizontal, 16)
            // The first card sat flush against the nav row, so the
            // highlighted one read as growing out of it.
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
    }

    /// Три раздела: АКТИВНАЯ, ОСТАЛЬНЫЕ, АРХИВ.
    ///
    /// Раньше было два, и второй назывался «АРХИВ», хотя считался как «всё,
    /// что не выбрано». Флаг `isArchived` при этом существовал и не
    /// использовался НИГДЕ. Получалось, что гараж обещал состояние, которого
    /// не было: экран записи спокойно предлагал любую «архивную» машину, и
    /// приложение спорило само с собой.
    ///
    /// Теперь архив — настоящее состояние, в которое машину кладёт человек
    /// руками. Автоматически туда не попадает никто и никогда: у тех, кто
    /// обновится, раздел «Архив» пуст, и все машины остаются рабочими.
    /// «Остальные» — те, на которые писать можно, просто сейчас активна не
    /// они; переключение бесплатно и мгновенно, о чём и говорит подпись.
    @ViewBuilder
    private func vehicleList(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Тот же ответ, что даст экран записи, — иначе гараж снова начнёт
        // обещать одно, а запись делать другое.
        let active = settings.vehicle(for: settings.activeRecordableVehicleId)
        let others = settings.recordableVehicles
            .filter { $0.id != active?.id }
            .sorted { $0.displayOdometerKm > $1.displayOdometerKm }
        // `!isRecordable`, а не `isArchived`: проданная машина, до которой по
        // какой-то причине не доехал флаг архива (например, приехала синком с
        // другого устройства), не попадала НИ В ОДИН раздел и пропадала из
        // гаража насовсем — вместе с единственной дверью, за которой её можно
        // вернуть. Раздел обязан покрывать всё, что не попало в первые два.
        let recordableIds = Set(settings.recordableVehicles.map(\.id))
        let archive = settings.vehicles
            .filter { !recordableIds.contains($0.id) }
            .sorted { $0.displayOdometerKm > $1.displayOdometerKm }

        if let active {
            GarageSectionLabel(text: AppStrings.garageActive(l), color: c.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            vehicleCard(active, c: c, l: l)
            Text(AppStrings.garageActiveHint(l))
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !others.isEmpty {
            GarageSectionLabel(text: AppStrings.garageOthers(l), color: c.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            ForEach(others) { vehicle in
                vehicleCard(vehicle, c: c, l: l)
            }
            // Прежняя подпись «Активна одна машина, переключить можно когда
            // угодно» наконец стоит под заголовком, которому не противоречит —
            // но только пока активная действительно есть. Без этой развилки
            // она утверждала бы «активна одна» прямо под пустым местом.
            Text(active == nil
                 ? AppStrings.garageNoActiveHint(l)
                 : AppStrings.garageArchiveHint(l))
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !archive.isEmpty {
            GarageSectionLabel(text: AppStrings.garageArchive(l), color: c.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            ForEach(archive) { vehicle in
                vehicleCard(vehicle, c: c, l: l)
            }
            Text(AppStrings.garageArchivedHint(l))
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if settings.recordableVehicles.count >= 5 {
            Text(AppStrings.maxVehiclesHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    // MARK: - Vehicle Card (Figma 152:1349 / 152:1362)

    private func vehicleCard(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Keep the exact existing main-vehicle fallback semantics.
        let isMain = vehicle.id == settings.activeRecordableVehicleId

        return Button {
            Haptics.tap()
            detailVehicleId = vehicle.id
        } label: {
            HStack(spacing: 14) {
                VehicleSpritePlate(
                    assetName: vehicle.avatarImageName,
                    fallbackEmoji: vehicle.isPixelAvatar ? nil : vehicle.avatarEmoji,
                    uniformHeight: true
                )

                VStack(alignment: .leading, spacing: 6) {
                    nameRow(vehicle, isMain: isMain, c: c, l: l)
                    identityLine(vehicle, c: c, l: l)

                    // The level line lives in this column, not across the
                    // whole card. Run full-bleed under the avatar it reads
                    // as a loading bar the card is waiting on; kept beside
                    // the name it reads as one more fact about the car,
                    // which is what it is.
                    HStack(spacing: 10) {
                        // Bar and pill share the decade colour: two
                        // different colours for one level would read as
                        // two facts.
                        VehicleXPBar(
                            progress: vehicle.progressToNextLevel,
                            tint: vehicle.levelColor
                        )
                        VehicleLevelPill(level: vehicle.level, size: 9)
                    }
                    .padding(.top, 2)
                }
                // The checkmark is trailing-aligned inside the name row,
                // so the column has to take the full card width instead
                // of being pushed left by a Spacer beside it.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        // Карточка «поддаётся» под пальцем, пока держишь: у долгого тапа тут
        // всё меню действий (сделать основной, в архив, удалить), а без
        // видимой реакции о нём просто не догадываются.
        .buttonStyle(HoldableCardStyle())
        .accessibilityIdentifier("garage_card")
        .background {
            // Drawn before `surfaceCard` so it lands ON the card fill rather
            // than behind it — the peach wash is what marks the main vehicle
            // at a glance; the border alone is easy to miss on a warm bg.
            if isMain {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.accentBg)
            }
        }
        .surfaceCard(cornerRadius: 16)
        .overlay {
            if isMain {
                // `strokeBorder`, not `stroke`: stroke centres the line on the
                // card's edge, so half of it lies OUTSIDE the bounds and the
                // scroll view clips it — most visibly along the top, where the
                // content has no inset to spare. strokeBorder keeps the whole
                // line inside.
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.accent, lineWidth: 2)
            }
        }
        .contextMenu {
            if !isMain, !vehicle.isArchived {
                Button {
                    settings.selectVehicle(id: vehicle.id)
                } label: {
                    Label(AppStrings.makeMainVehicle(l), systemImage: "star")
                }
            }
            // Подтверждения нет намеренно: действие обратимо одним тапом
            // отсюда же, а диалог на обратимое действие — это шум.
            // Проданную из архива не поднимаем: снятие «продана» — отдельный
            // шаг, иначе случайный тап переписал бы историю машины.
            // У проданной машины выход из архива один — снять продажу, и он
            // лежал в четырёх тапах внутри формы. Здесь же, рядом.
            if vehicle.isSold {
                Button {
                    settings.setVehicleSold(id: vehicle.id, soldAt: nil)
                } label: {
                    Label(AppStrings.vehicleUnsell(l), systemImage: "arrow.uturn.backward")
                }
            }
            if !vehicle.isSold {
                Button {
                    settings.setVehicleArchived(id: vehicle.id, archived: !vehicle.isArchived)
                } label: {
                    Label(vehicle.isArchived
                          ? AppStrings.vehicleUnarchiveAction(l)
                          : AppStrings.vehicleArchiveAction(l),
                          systemImage: vehicle.isArchived ? "tray.and.arrow.up" : "archivebox")
                }
            }
            Button(role: .destructive) {
                deleteCandidateId = vehicle.id
            } label: {
                Label(AppStrings.deleteVehicle(l), systemImage: "trash")
            }
        }
    }

    private func nameRow(
        _ vehicle: Vehicle,
        isMain: Bool,
        c: AppTheme.Colors,
        l: LanguageManager.Language
    ) -> some View {
        HStack(spacing: 6) {
            Text(vehicle.name.isEmpty ? AppStrings.unnamedVehicle(l) : vehicle.name)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .truncationMode(.tail)

            // Hidden transport is still fully usable here, so the only cue the
            // owner gets that others cannot see it is this lock.
            if !vehicle.visibleToOthers {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .accessibilityLabel(AppStrings.vehicleHiddenFromOthers(l))
            }

            // Проданная и убранная в архив выглядели в списке одинаково, а
            // «Архив» их и объединяет: без пометки понять, почему одну машину
            // нельзя вернуть тем же жестом, что другую, было неоткуда.
            if vehicle.isSold {
                Text(AppStrings.vehicleSoldBadge(l))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(c.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(c.cardAlt, in: Capsule())
            }

            Spacer(minLength: 8)

            if isMain {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(AppStrings.vehicleMainLabel(l))
            }
        }
    }

    /// The plate is the card's identity line — but it is optional, and bikes
    /// and mopeds never carry one, so the odometer takes the slot instead of
    /// letting the card change height from vehicle to vehicle.
    @ViewBuilder
    private func identityLine(
        _ vehicle: Vehicle,
        c: AppTheme.Colors,
        l: LanguageManager.Language
    ) -> some View {
        if vehicle.hasPlate {
            // The owner's own screen — `plate`, not `publicPlate`, which is
            // about what everyone else may see.
            VehiclePlateChip(plate: vehicle.plate)
        } else {
            Text("\(GarageFormat.odometer(vehicle.displayOdometerKm, lng: l)) \(AppStrings.km(l))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(c.textTertiary)
        }
    }

    // MARK: - Empty State

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 14) {
            // A drawn scene rather than the orange car that used to stand in
            // here: an empty carport reads as «nothing parked yet», where a
            // car reads as «here is a car», which is the opposite of what the
            // screen is saying. Sizing and framing live in the shared
            // component so every empty screen stays the same size as the rest.
            EmptyStateIllustration(name: "empty_garage", size: 148)

            VStack(spacing: 8) {
                Text(AppStrings.garageEmptyTitle(l))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(c.text)
                Text(AppStrings.garageEmptyBody(l))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Haptics.tap()
                showAddVehicle = true
            } label: {
                Text(AppStrings.addVehicleTitle(l))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("garage_empty_add")
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        // Dead centre of the remaining space sits low once the nav row has
        // taken the top of the sheet, so the block is lifted a notch.
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Takes the id rather than reading `deleteCandidateId`: the house dialog
    /// clears that state on dismissal, which happens BEFORE this runs.
    private func performDelete(id: UUID) {
        settings.deleteVehicle(id: id)
        if settings.selectedVehicleId == id {
            settings.selectVehicle(id: settings.recordableVehicles.first?.id)
        }
    }
}
