import SwiftUI
import MapKit
import PhotosUI

struct TripCompleteSummaryView: View {
    let trip: Trip
    var completionData: TripCompletionData?
    let onPhotoSaved: (UIImage) -> Void
    let onDone: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @State private var showXP = false
    /// Multi-selection, kept for the life of the screen.
    ///
    /// A single-item picker forgets what you chose the moment it closes, so
    /// re-opening it and tapping the same photo — the gesture everyone uses to
    /// take one back — added it a second time. Holding the selection means the
    /// picker opens with your photos already ticked and a second tap unticks
    /// one, which is what that gesture means everywhere else.
    @State private var photoSelection: [PhotosPickerItem] = []
    /// Picked item → the photo it created, so a deselect can delete it.
    ///
    /// Keyed by the item itself, NOT by `itemIdentifier`: that property is nil
    /// unless the picker is built with an explicit `photoLibrary`, and keying
    /// on it meant every item was filtered out as «has no id» — the finish
    /// screen accepted photos and attached none of them.
    @State private var savedPhotoIds: [PhotosPickerItem: UUID] = [:]
    @State private var isSavingPhotos = false
    /// Figma 147:1251: OFF by default — trips stay private until the user
    /// opts in. Applied on «Готово».
    @State private var publishToFeed = false
    /// Inline description (canon: «Финиш = всё в одном экране»). Lands in
    /// `trip.notes`, so it is the same text the detail screen and the feed show.
    @State private var tripNotes: String = ""
    /// What the editor is typing into until it is saved. See the sheet below.
    @State private var notesDraft: String = ""
    @State private var showNotesEditor = false
    @State private var selectedBadge: Badge?

    var body: some View {
        // The finish screen is light-themed by design (Figma 147:1190) —
        // celebration reads better on the warm cream, independent of theme.
        let c = AppTheme.colors(for: .light)

        ScrollView {
        VStack(spacing: 0) {
            // No drag grabber: the sheet is presented with interactive
            // dismiss disabled (ContentView), and Figma 147:1190 has none —
            // showing the affordance would advertise a dead gesture.
            confettiHeader
                .padding(.top, 18)

            // Title
            Text(AppStrings.tripFinishedTitle(lang.language))
                .font(.inter(22, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.top, 8)

            // Route preview (speed-gradient polylines via RouteMapView).
            //
            // Drawn for a single point too. A trip that never moved still
            // happened somewhere, and showing that place beats showing an
            // empty slot — this used to require two points, so a two-minute
            // wait produced a blank card with a dot in it.
            if !trip.trackPoints.isEmpty {
                RouteMapView(
                    coordinates: trip.trackPoints.map(\.coordinate),
                    speeds: trip.trackPoints.map(\.speed)
                )
                .frame(height: 139)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                summaryStatCard(
                    value: String(format: "%.1f", trip.distanceKm),
                    unit: AppStrings.km(lang.language),
                    label: AppStrings.distance(lang.language),
                    color: AppTheme.green,
                    c: c
                )
                summaryStatCard(
                    // «02:12» is unreadable at a glance — two hours twelve, or
                    // two minutes twelve? The app already has one honest
                    // format and the canon uses it: «2 ч 14 мин».
                    value: compactDuration(lang.language),
                    unit: "",
                    label: AppStrings.duration(lang.language),
                    // Figma 147:1190: time is neutral dark, not accent.
                    color: c.text,
                    c: c
                )
                summaryStatCard(
                    value: String(format: "%.0f", trip.displayAverageSpeedKmh(SettingsManager.shared.avgSpeedMode)),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.avgSpeed(lang.language),
                    color: AppTheme.blue,
                    c: c
                )
                summaryStatCard(
                    value: String(format: "%.0f", trip.maxSpeedKmh),
                    unit: AppStrings.kmh(lang.language),
                    label: AppStrings.maxShort(lang.language),
                    color: AppTheme.red,
                    c: c
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Gamification section
            if let data = completionData {
                gamificationSection(data: data, c: c)
            }

            // Description, then publish — the canon's «Финиш = всё в одном
            // экране»: an optional note and an instant toggle, no intermediate
            // publish screen.
            descriptionCard(c)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            // Publish row (Figma 147:1251): OFF by default. Applied on «Готово».
            publishRow(c)
                .padding(.horizontal, 20)
                .padding(.top, 10)
        }
        }
        // Pinned, not scrolled: the actions belong to the sheet, not to the
        // end of the content. Inside the scroll view they sat wherever the
        // content happened to end, leaving a field of empty sheet under them.
        .safeAreaInset(edge: .bottom) { bottomBar(c) }
        .background(c.bg)
        .environment(\.colorScheme, .light)
        // The editor edits a DRAFT. Bound straight to `tripNotes` it wrote
        // through on every keystroke, so «Отмена» dismissed a sheet whose text
        // was already on the card — and «Готово» then saved the draft the user
        // had just discarded.
        .sheet(isPresented: $showNotesEditor) {
            NotesEditorView(text: $notesDraft) {
                tripNotes = notesDraft
                mapVM.tripManager.updateNotes(for: trip.id, notes: tripNotes)
                showNotesEditor = false
            }
            .environmentObject(lang)
            .presentationDetents([.medium, .large])
        }
        .overlay {
            if let badge = selectedBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: true,
                    language: lang.language,
                    colorScheme: .light,
                    earnCount: completionData?.repeatedBadgeCounts[badge.id],
                    lastEarnedDate: trip.endDate ?? trip.startDate,
                    // The drive that just ended is the one that earned it, so
                    // the card can print what it actually took («47.3 км»
                    // under «проедьте 42.2 км») instead of the rule alone.
                    recordValue: badge.recordValue(for: trip, language: lang.language),
                    onDismiss: { selectedBadge = nil }
                )
            }
        }
        .onAppear { tripNotes = trip.tripDescription ?? "" }
    }

    /// Фото + Готово, pinned to the bottom of the sheet.
    private func bottomBar(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $photoSelection,
                // The garage of photos for one trip is small; the cap keeps a
                // stray «select all» from stalling the save loop.
                maxSelectionCount: 10,
                selectionBehavior: .continuousAndOrdered,
                matching: .images
            ) {
                HStack(spacing: 6) {
                    Image(systemName: savedPhotoIds.isEmpty ? "camera.fill" : "checkmark.circle.fill")
                        .font(.system(size: 15))
                    Text(savedPhotoIds.isEmpty
                         ? AppStrings.photoShort(lang.language)
                         : "\(AppStrings.photoShort(lang.language)) (\(savedPhotoIds.count))")
                        .font(.inter(14, weight: .bold))
                }
                .foregroundStyle(c.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 1))
            }
            .accessibilityIdentifier("summary_photo")

            Button {
                if publishToFeed {
                    mapVM.tripManager.updatePrivacy(for: trip.id, isPrivate: false)
                    NotificationCenter.default.post(
                        name: .tripPrivacyChanged,
                        object: PrivacyChangePayload(tripId: trip.id, isPrivate: false)
                    )
                }
                let saved = tripNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                if saved != (trip.tripDescription ?? "") {
                    mapVM.tripManager.updateNotes(for: trip.id, notes: saved)
                }
                onDone()
                // The trip you just made is the thing you want to look at, and
                // the summary is a card, not the trip. Hand off to its detail.
                NotificationCenter.default.post(name: .openTripDetail, object: trip.id)
            } label: {
                Text(AppStrings.done(lang.language))
                    .font(.inter(14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .accessibilityIdentifier("summary_done")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(c.bg)
        .onChange(of: photoSelection) { _, items in
            syncPhotos(items)
        }
    }

    /// Adds what was newly ticked and deletes what was unticked.
    private func syncPhotos(_ items: [PhotosPickerItem]) {
        // Gone from the selection → gone from the trip.
        for (item, photoId) in savedPhotoIds where !items.contains(item) {
            mapVM.tripManager.deletePhoto(id: photoId, from: trip.id)
            savedPhotoIds.removeValue(forKey: item)
        }
        let fresh = items.filter { savedPhotoIds[$0] == nil }
        guard !fresh.isEmpty else { return }
        isSavingPhotos = true
        Task {
            for item in fresh {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                if let photo = mapVM.tripManager.addPhoto(to: trip.id, image: image) {
                    await MainActor.run { savedPhotoIds[item] = photo.id }
                }
            }
            await MainActor.run { isSavingPhotos = false }
        }
    }

    /// Inline «Добавить описание…» → the same editor the trip detail uses.
    /// Clamped to two lines here so a long note cannot push the card apart.
    private func descriptionCard(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            notesDraft = tripNotes
            showNotesEditor = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Text(tripNotes.isEmpty
                     ? AppStrings.describeTripPlaceholder(lang.language)
                     : tripNotes)
                    .font(.inter(14, weight: tripNotes.isEmpty ? .medium : .regular))
                    .foregroundStyle(tripNotes.isEmpty ? c.textTertiary : c.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .padding(.top, 12)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("summary_description")
    }

    /// Confetti that actually falls.
    ///
    /// It used to be eight squares parked at fixed offsets — the frozen frame
    /// of a celebration, which reads as decoration nobody finished. Each piece
    /// now drifts down its own column at its own speed, tumbling as it goes,
    /// and wraps around, so the header is alive for as long as the card is up
    /// without ever costing more than a few dozen rectangles.
    private var confettiHeader: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for piece in Self.confetti {
                    let cycle = (t * piece.speed + piece.phase)
                        .truncatingRemainder(dividingBy: 1)
                    let y = cycle * (size.height + 12) - 6
                    let x = size.width * piece.column
                        + sin((t * piece.sway + piece.phase) * .pi * 2) * 5
                    let rect = CGRect(x: -3, y: -3, width: 6, height: 6)

                    var layer = context
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .degrees(t * piece.spin * 60 + piece.phase * 360))
                    // Fades in at the top and out at the bottom, so pieces
                    // enter and leave instead of popping at the edges.
                    layer.opacity = min(1, min(cycle, 1 - cycle) * 6)
                    layer.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(piece.color)
                    )
                }
            }
        }
        .frame(height: 46)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct ConfettiPiece {
        let color: Color
        /// Horizontal position as a fraction of the header's width.
        let column: CGFloat
        /// Falls per second, so pieces separate instead of marching in step.
        let speed: Double
        /// Where in its fall the piece starts, so they do not all begin at the top.
        let phase: Double
        let spin: Double
        let sway: Double
    }

    private static let confetti: [ConfettiPiece] = [
        .init(color: AppTheme.accent, column: 0.06, speed: 0.28, phase: 0.10, spin: 1.2, sway: 0.5),
        .init(color: Color(red: 0xF5/255, green: 0xBE/255, blue: 0x1E/255), column: 0.19, speed: 0.36, phase: 0.55, spin: -0.9, sway: 0.7),
        .init(color: Color(red: 0x2E/255, green: 0xAE/255, blue: 0x50/255), column: 0.31, speed: 0.24, phase: 0.80, spin: 1.5, sway: 0.4),
        .init(color: AppTheme.accent, column: 0.44, speed: 0.40, phase: 0.25, spin: -1.3, sway: 0.6),
        .init(color: Color(red: 0x38/255, green: 0x84/255, blue: 0xE0/255), column: 0.56, speed: 0.30, phase: 0.65, spin: 1.0, sway: 0.55),
        .init(color: AppTheme.red, column: 0.69, speed: 0.34, phase: 0.05, spin: -1.6, sway: 0.45),
        .init(color: Color(red: 0x50/255, green: 0xBE/255, blue: 0xD2/255), column: 0.81, speed: 0.26, phase: 0.40, spin: 1.1, sway: 0.65),
        .init(color: AppTheme.accent, column: 0.93, speed: 0.38, phase: 0.90, spin: -1.0, sway: 0.5),
    ]

    /// «Опубликовать в ленту» + subtitle + privacy footnote + toggle.
    private func publishRow(_ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 38, height: 38)
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.publishToFeed(lang.language))
                    .font(.inter(14, weight: .bold))
                    .foregroundStyle(c.text)
                // One line, and it says what each position of the switch does.
                // The old pair — «Поездка появится в общей ленте» over
                // «Поездки приватны, пока Вы не опубликуете их сами» — spent
                // three lines restating the title and never mentioned «выкл».
                Text(AppStrings.publishToggleHint(lang.language))
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // Figma 480:137. This card is the app's only place where a
                // trip is handed to the public, and it had stopped saying the
                // rule the consent rests on — that nothing leaves the phone
                // unless you send it. The hint above says what the switch
                // does; this says what happens when you never touch it.
                Text(AppStrings.publishFootnote(lang.language))
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $publishToFeed)
                .labelsHidden()
                .tint(AppTheme.accent)
                .accessibilityLabel(AppStrings.publishToFeed(lang.language))
                .accessibilityIdentifier("publish_toggle")
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    // MARK: - Gamification Section

    private func gamificationSection(data: TripCompletionData, c: AppTheme.Colors) -> some View {
        VStack(spacing: 10) {
            // XP earned (Figma 147:1190: bare «+N XP» ↔ pixel LEVEL UP pill)
            HStack {
                Text("+\(data.xpEarned) XP")
                    .font(.inter(28, weight: .heavy))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
                if data.didLevelUp {
                    Text("LEVEL UP!")
                        .font(.custom("PressStart2P-Regular", size: 9))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.11, green: 0.11, blue: 0.11)))
                        .overlay(Capsule().strokeBorder(AppTheme.accent, lineWidth: 1.5))
                }
            }

            // No rank/level row here.
            //
            // It used to render «Водитель … LVL 6» with a progress bar, cited
            // to this very node — and the node has no such row: the canon card
            // is «+N XP» with the LEVEL UP pill, the streak, and the badges.
            // The level and its progress belong to the driver screen in «Я»,
            // which owns that whole story; repeating a slice of it here made
            // the finish card argue with it (and «LVL 6» in a pixel font is
            // not how that screen writes a level either).

            // Streak (Figma 147:1241: «14 дней подряд»)
            if data.currentStreak > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                    Text(AppStrings.streakDaysInARow(lang.language, n: data.currentStreak))
                        .font(.inter(13, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                }
            }

            // Repeat route info
            if let road = data.roadCard, !road.isNew, road.timesDriven > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.accent)
                    Text(AppStrings.repeatRouteTimes(lang.language, n: road.timesDriven))
                        .font(.inter(13, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                }
            }

            // New badges — Figma: 46pt tinted circle + the badge NAME below
            // (repeat count folds into the name row when applicable).
            if !data.newBadges.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(data.newBadges.prefix(4)) { badge in
                        // Tappable: a badge you have never seen before appears
                        // for two seconds and disappears with the sheet, and
                        // until now there was nothing to press to find out
                        // what it was for.
                        Button {
                            Haptics.tap()
                            selectedBadge = badge
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(badge.color.opacity(0.15))
                                        .frame(width: 46, height: 46)
                                        .shadow(color: badge.color.opacity(0.3), radius: 6)

                                    Image(systemName: badge.icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(badge.color)
                                }

                                // Name only, as the canon draws it. The «×5»
                                // that used to hang off it was the lifetime
                                // count of a repeatable badge, and «×5» after
                                // one short drive reads as «five at once».
                                // That number now lives in the badge's own
                                // card, where it can say «Получено 5 раз».
                                Text(badge.title(lang.language))
                                    .font(.inter(9, weight: .bold))
                                    .foregroundStyle(badge.color)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(width: 74)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("summary_badge")
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        // XP card (Figma 147:1190): warm tint + accent border + accent glow.
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0xFF/255, green: 0xF7/255, blue: 0xF0/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppTheme.accent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: AppTheme.accent.opacity(0.12), radius: 16, y: 4)
        // Entrance fade-in keyed on showXP, triggered from onAppear below.
        .opacity(showXP ? 1 : 0)
        .scaleEffect(showXP ? 1 : 0.97)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { showXP = true } }
    }

    /// Duration for this card's stat cell only.
    ///
    /// The shared `Trip.formattedTimeHuman` keeps the seconds under an hour,
    /// and «45 мин 20 сек» wants ~172pt in a cell about 133pt wide: it fit only
    /// by shrinking to ≈0.78, so the one number that reads smaller than its
    /// three neighbours was the one nobody meant to de-emphasise. Seconds are
    /// noise once the drive is over, so they are dropped below an hour — and
    /// kept below a minute, where they are the whole value.
    private func compactDuration(_ lang: LanguageManager.Language) -> String {
        let total = Int(trip.duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            if minutes == 0 { return lang == .ru ? "\(hours) ч" : "\(hours) h" }
            return lang == .ru ? "\(hours) ч \(minutes) мин" : "\(hours) h \(minutes) min"
        }
        if minutes > 0 { return lang == .ru ? "\(minutes) мин" : "\(minutes) min" }
        return lang == .ru ? "\(total) сек" : "\(total) sec"
    }

    private func summaryStatCard(value: String, unit: String, label: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.inter(24, weight: .heavy).monospacedDigit())
                    .foregroundStyle(color)
                    // «2 ч 14 мин» is a longer string than «02:12» ever was;
                    // it shrinks rather than wrapping or clipping.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.inter(14, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
            }
            Text(label)
                .font(.inter(10, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(c.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }
}
