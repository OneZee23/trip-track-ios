import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var lang: LanguageManager
    /// Sheets are separate presentations — the override applied to the
    /// Garage sheet itself (ProfileView) does not reach a sheet presented
    /// from HERE, so the add-vehicle form must re-apply it.
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    /// Главные снимки всего гаража, снятые разом. Не в теле вью: там это была
    /// бы выборка на карточку на каждый кадр прокрутки.
    /// Считывается СРАЗУ, а не задачей после первого кадра: иначе гараж
    /// рисуется силуэтами и через мгновение подменяет их фотографиями — рвано
    /// и без причины, потому что данные лежат на устройстве. Запрос запомнен в
    /// хранилище, поэтому пересоздание экрана его не повторяет.
    @State private var mainPhotos: [UUID: VehiclePhoto] = VehiclePhotoStore.mainPhotos()

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
        .task(id: settings.vehicles.count) { mainPhotos = VehiclePhotoStore.mainPhotos() }
        .onChange(of: detailVehicleId) { _, id in
            // Вернулись с экрана машины — там могли сменить главную.
            if id == nil { mainPhotos = VehiclePhotoStore.mainPhotos() }
        }
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

    /// Три раздела: АКТИВНАЯ, ОСТАЛЬНЫЕ, ПРОДАННЫЕ.
    ///
    /// Архива здесь больше нет. Он был подготовкой к монетизации («бесплатно
    /// активна одна, остальные убери руками»), а не пользой: человек разбирал
    /// собственный гараж, чтобы приложение перестало ему мешать. Машин
    /// столько, сколько есть, все рабочие.
    ///
    /// Разделение осталось ради одного честного различия: **на что пойдёт
    /// следующая поездка**. Активная — пойдёт. Остальные — можно переключить
    /// одним тапом. Проданные — нельзя вообще, и это не ограничение, а правда:
    /// машина уехала к другому человеку, чужая дорога в её паспорте была бы
    /// враньём. Поэтому проданные отдельной секцией, а не меткой в общем
    /// списке: разница между «можно ездить» и «нельзя» не должна быть мелким
    /// текстом.
    @ViewBuilder
    private func vehicleList(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Тот же ответ, что даст экран записи, — иначе гараж снова начнёт
        // обещать одно, а запись делать другое.
        let active = settings.vehicle(for: settings.activeRecordableVehicleId)
        let others = settings.recordableVehicles
            .filter { $0.id != active?.id }
            .sorted { $0.displayOdometerKm > $1.displayOdometerKm }
        // Через `!isRecordable`, а не `isSold` напрямую: раздел обязан
        // покрывать ВСЁ, что не попало в первые два. Иначе машина в состоянии,
        // которое мы не предусмотрели, пропадёт из гаража насовсем — вместе с
        // единственной дверью, за которой её можно вернуть.
        let recordableIds = Set(settings.recordableVehicles.map(\.id))
        let sold = settings.vehicles
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

        if !sold.isEmpty {
            GarageSectionLabel(text: AppStrings.garageSold(l), color: c.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            ForEach(sold) { vehicle in
                vehicleCard(vehicle, c: c, l: l)
            }
            Text(AppStrings.garageSoldHint(l))
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
            VStack(alignment: .leading, spacing: 0) {
                // Полоса сверху — лицо машины. Высота одна для всех карточек,
                // и когда фотографии нет, в ней стоит силуэт: разная высота
                // соседних карточек читается как поломка вёрстки, а не как
                // «у этой машины есть фото, а у той нет».
                VehicleFace(
                    photo: .local(mainPhotos[vehicle.id]),
                    assetName: vehicle.avatarImageName,
                    fallbackEmoji: vehicle.isPixelAvatar ? nil : vehicle.avatarEmoji,
                    style: .banner,
                    dimmed: vehicle.isSold
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            // Обрезаем ЗДЕСЬ: полоса идёт во всю ширину, а `surfaceCard` только
            // красит фон. Без этого её прямые углы вылезали бы за скругления.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            if !isMain, !vehicle.isSold {
                Button {
                    settings.selectVehicle(id: vehicle.id)
                } label: {
                    Label(AppStrings.makeMainVehicle(l), systemImage: "star")
                }
            }
            // Снять продажу можно здесь же: иначе единственная дорога назад
            // лежит в четырёх тапах внутри формы редактирования.
            if vehicle.isSold {
                Button {
                    settings.setVehicleSold(id: vehicle.id, soldAt: nil)
                } label: {
                    Label(AppStrings.vehicleUnsell(l), systemImage: "arrow.uturn.backward")
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
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        // На крупном системном шрифте картинка, заголовок, абзац и кнопка
        // перестают помещаться в экран, и первым за край уходит именно
        // «Добавить машину» — единственное действие пустого гаража. Внутри
        // прокрутки блок по-прежнему стоит по центру, пока места хватает, и
        // прокручивается, когда перестаёт.
        .modifier(ScrollableWhenTall())
    }

    /// Центрирует, пока помещается, и прокручивает, когда нет.
    private struct ScrollableWhenTall: ViewModifier {
        func body(content: Content) -> some View {
            GeometryReader { proxy in
                ScrollView {
                    content.frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
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
