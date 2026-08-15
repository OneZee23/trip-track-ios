import SwiftUI

/// «Редактировать поездку» (Figma 543:119).
///
/// Everything editable about a trip in one place: name, description, the car it
/// was driven in, and who can see it. Before this, the name was edited by
/// tapping the title, the description by tapping the description, and the
/// privacy by tapping a chip — three discoveries the user had to make on their
/// own, and no single screen that said "this is what you can change".
///
/// Every control here STAGES a change; nothing leaves the sheet until «Готово».
/// Access used to be the exception — it closed the sheet and raised the publish
/// confirmation, which threw away whatever had been typed and not yet saved.
/// Now it opens a picker like any other field, and the confirmation the parent
/// owns runs after the edits are safely written.
struct TripEditSheet: View {
    let trip: Trip
    /// Cars to choose from — the garage, in its own order.
    let vehicles: [Vehicle]
    let onSave: (_ title: String, _ description: String, _ vehicleId: UUID?, _ isPrivate: Bool) -> Void

    /// The server's own limit for a trip note.
    private static let notesLimit = 500
    /// Fixed, and that matters: a description box that grows with the sheet
    /// feeds its own height back into the measured detent, and the sheet
    /// inflates to full screen the moment you drag it — with no way back down.
    private static let notesHeight: CGFloat = 108

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var vehicleId: UUID?
    @State private var isPrivate: Bool = true
    @State private var showVehiclePicker = false
    @State private var showAccessPicker = false

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == vehicleId }
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 0) {
            header(c)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderHeightKey.self, value: proxy.size.height)
                    }
                )
            // Scrollable so a keyboard covering half the sheet still leaves the
            // car and access rows reachable. `.basedOnSize` keeps it feeling
            // like a static form until it actually needs to scroll.
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field(label: AppStrings.tripTitleLabel(lang.language), c: c) {
                        TextField(AppStrings.tripTitlePlaceholder(lang.language), text: $title)
                            .font(.system(size: 16))
                            .foregroundStyle(c.text)
                            .submitLabel(.done)
                            .accessibilityIdentifier("edit_title_field")
                    }

                    field(label: AppStrings.descriptionSection(lang.language), c: c) {
                        ZStack(alignment: .topLeading) {
                            // TextEditor has no placeholder of its own, and an
                            // empty description card with no prompt reads as
                            // broken rather than as empty.
                            if notes.isEmpty {
                                Text(AppStrings.describeTripPlaceholder(lang.language))
                                    .font(.system(size: 16))
                                    .foregroundStyle(c.textTertiary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $notes)
                                .font(.system(size: 16))
                                .foregroundStyle(c.text)
                                .scrollContentBackground(.hidden)
                                .frame(height: Self.notesHeight)
                                .onChange(of: notes) { _, new in
                                    // Hard cap rather than a warning after the
                                    // fact: the server rejects longer notes, and
                                    // finding that out on «Готово» loses the
                                    // tail of what you wrote.
                                    if new.count > Self.notesLimit {
                                        notes = String(new.prefix(Self.notesLimit))
                                    }
                                }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            // «75 / 500» (canon 117:503) — quiet until it starts
                            // to matter.
                            Text("\(notes.count) / \(Self.notesLimit)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(
                                    notes.count > Self.notesLimit - 40 ? AppTheme.accent : c.textTertiary
                                )
                                .padding(.trailing, 2)
                        }
                        .accessibilityIdentifier("edit_notes_field")
                    }

                    // МАШИНА — the picker the recording screen already uses,
                    // so the car is chosen the same way wherever you are.
                    field(label: AppStrings.vehicleSectionLabel(lang.language), c: c) {
                        Button {
                            Haptics.tap()
                            showVehiclePicker = true
                        } label: {
                            HStack(spacing: 12) {
                                vehicleAvatar(c: c)
                                Text(selectedVehicle?.name ?? AppStrings.noVehicle(lang.language))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(c.text)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(c.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("edit_vehicle_row")
                    }

                    field(label: AppStrings.accessSectionLabel(lang.language), c: c) {
                        Button {
                            Haptics.tap()
                            showAccessPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isPrivate ? "lock.fill" : "globe")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isPrivate ? c.textSecondary : AppTheme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isPrivate
                                         ? AppStrings.privacyOnlyMe(lang.language)
                                         : AppStrings.privacyPublic(lang.language))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(c.text)
                                    Text(isPrivate
                                         ? AppStrings.privacyOnlyMeHint(lang.language)
                                         : AppStrings.privacyPublicHint(lang.language))
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(c.textTertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(c.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("edit_access_row")
                    }
                }
                .padding(16)
                // The form's OWN height, never its position on screen. Measured
                // by position, scrolling the form would shrink the number,
                // which shrinks the sheet, which scrolls the form further — the
                // same runaway that used to inflate this sheet, running the
                // other way.
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SheetHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(c.bg)
        .onPreferenceChange(SheetHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
        .onPreferenceChange(HeaderHeightKey.self) { height in
            guard height > 0 else { return }
            headerHeight = height
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showVehiclePicker) {
            VehiclePickerSheet { picked in vehicleId = picked }
                .environmentObject(lang)
        }
        .sheet(isPresented: $showAccessPicker) {
            TripAccessPickerSheet(isPrivate: $isPrivate)
                .environmentObject(lang)
        }
        .onAppear {
            // Only a real name is pre-filled. Saving stamps every trip with its
            // start date, and offering that back as the field's VALUE is what
            // taught people the trip was called «14 Jun, 12:31» while the detail
            // screen — which knows a stamp is not a name — headed it with the
            // region. Empty with a prompt is the honest state, and it also means
            // typing that same date is a real edit rather than a no-op the save
            // guard would drop.
            title = trip.hasDisplayableName ? (trip.title ?? "") : ""
            notes = trip.tripDescription ?? ""
            vehicleId = trip.vehicleId
            isPrivate = trip.isPrivate
        }
    }

    /// «Отмена · Редактировать поездку · Готово».
    ///
    /// Hand-built rather than a `navigationTitle`: on iOS 26 the toolbar draws
    /// each button as a wide glass pill, and between two of them an inline
    /// title had so little room left that it came out as «Редактировать
    /// поезд…». The same header pattern the notes editor uses.
    private func header(_ c: AppTheme.Colors) -> some View {
        ZStack {
            Text(AppStrings.editTripTitle(lang.language))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // Never let the title run under the buttons.
                .padding(.horizontal, 84)

            HStack {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Text(AppStrings.cancel(lang.language))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
                .accessibilityIdentifier("edit_cancel")

                Spacer()

                Button {
                    Haptics.action()
                    onSave(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes.trimmingCharacters(in: .whitespacesAndNewlines),
                        vehicleId,
                        isPrivate
                    )
                    dismiss()
                } label: {
                    Text(AppStrings.done(lang.language))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
                .accessibilityIdentifier("edit_done")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    /// Seeded with plausible first-frame values so the sheet does not open at
    /// zero and animate open; the real measurements land on the same frame.
    @State private var contentHeight: CGFloat = 470
    @State private var headerHeight: CGFloat = 50

    /// Header plus form plus a hair of breathing room, never taller than most
    /// of the screen — past that the form scrolls instead of the sheet growing.
    private var sheetHeight: CGFloat {
        min(headerHeight + contentHeight + 12, UIScreen.main.bounds.height * 0.9)
    }

    private struct SheetHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private struct HeaderHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @ViewBuilder
    private func vehicleAvatar(c: AppTheme.Colors) -> some View {
        ZStack {
            Circle().fill(c.cardAlt).frame(width: 34, height: 34)
            if let v = selectedVehicle {
                if v.isPixelAvatar {
                    Image(v.avatarEmoji)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                } else {
                    Text(v.avatarEmoji).font(.system(size: 17))
                }
            } else {
                Image(systemName: "car.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textTertiary)
            }
        }
    }

    private func field<Content: View>(
        label: String,
        c: AppTheme.Colors,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(c.textTertiary)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfaceCard()
        }
    }
}

/// «Доступ» — who can see this trip. Two rows, each saying what it means, and
/// the choice is staged like every other field: it takes effect on «Готово».
struct TripAccessPickerSheet: View {
    @Binding var isPrivate: Bool

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 280

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(alignment: .leading, spacing: 0) {
            Text(AppStrings.accessSectionLabel(lang.language))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

            VStack(spacing: 10) {
                option(
                    isPrivateOption: true,
                    icon: "lock.fill",
                    title: AppStrings.privacyOnlyMe(lang.language),
                    hint: AppStrings.privacyOnlyMeHint(lang.language),
                    c: c
                )
                option(
                    isPrivateOption: false,
                    icon: "globe",
                    title: AppStrings.privacyPublic(lang.language),
                    hint: AppStrings.privacyPublicHint(lang.language),
                    c: c
                )
            }
            .padding(.horizontal, 16)

            Text(AppStrings.tripEditAPublicTrip(lang.language))
                .font(.system(size: 12.5))
                .foregroundStyle(c.textTertiary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: AccessSheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(AccessSheetHeightKey.self) { h in
            guard h > 0 else { return }
            contentHeight = h
        }
        .background(c.bg)
        .presentationDetents([.height(contentHeight + 12)])
        .presentationDragIndicator(.visible)
    }

    private func option(
        isPrivateOption: Bool,
        icon: String,
        title: String,
        hint: String,
        c: AppTheme.Colors
    ) -> some View {
        let selected = isPrivate == isPrivateOption
        return Button {
            Haptics.selection()
            isPrivate = isPrivateOption
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isPrivateOption ? c.textSecondary : AppTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(hint)
                        .font(.system(size: 12.5))
                        .foregroundStyle(c.textTertiary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? AppTheme.accent : c.textTertiary.opacity(0.5))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(c.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(selected ? AppTheme.accent : .clear, lineWidth: 1.5)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isPrivateOption ? "access_option_private" : "access_option_public")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct AccessSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
