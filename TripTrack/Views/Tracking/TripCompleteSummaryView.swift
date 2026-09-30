import SwiftUI
import MapKit
import PhotosUI

struct TripCompleteSummaryView: View {
    let trip: Trip
    var completionData: TripCompletionData?
    let onDone: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.distanceUnit) private var distanceUnit

    /// Три числа итога — расстояние, средняя, максимум — из одного места и в
    /// одной единице. Врозь их печатает вёрстка (число крупно, подпись мелко),
    /// но собирает всё равно `Measure`: подпись склоняется по числу.
    private var tripDistance: Measure.Parts {
        Measure.distanceParts(
            metres: trip.distance, unit: distanceUnit, lang: lang.language, style: .tenths)
    }

    private var tripAvgSpeed: Measure.Parts {
        Measure.speedParts(
            ms: trip.displayAverageSpeedMS(SettingsManager.shared.avgSpeedMode),
            unit: distanceUnit, lang: lang.language)
    }

    private var tripMaxSpeed: Measure.Parts {
        Measure.speedParts(ms: trip.maxSpeed, unit: distanceUnit, lang: lang.language)
    }
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

    // MARK: - «Сказать спасибо» (0.8.4)

    /// Показывать ли карточку. Решает `TipMoment` ОДИН раз, на появлении
    /// экрана: спрашивать календарь на каждой перерисовке незачем, а ответ за
    /// время, пока человек смотрит на свой итог, не меняется.
    @State private var showTipCard = false
    @State private var showTipJar = false
    @State private var showDraftDiscard = false
    @State private var selectedBadge: Badge?
    /// Выгорание тумана на герое (0.7.0). Живёт у экрана, а не у блока
    /// «Открыто»: играет его ГЕРОЙ, а блок только рассказывает словами.
    @StateObject private var heroSweep = RevealSweep()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // Черновик: вопрос «Твоя?» — прямо в итогах, человек уже смотрит
            // на экран (спека §3.3).
            if trip.isDraft {
                DraftTripBanner(tripId: trip.id) { showDraftDiscard = true }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            // Route preview (speed-gradient polylines via RouteMapView).
            //
            // Drawn for a single point too. A trip that never moved still
            // happened somewhere, and showing that place beats showing an
            // empty slot — this used to require two points, so a two-minute
            // wait produced a blank card with a dot in it.
            if !trip.trackPoints.isEmpty {
                heroMap
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                summaryStatCard(
                    value: tripDistance.value,
                    unit: tripDistance.unit,
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
                    value: tripAvgSpeed.value,
                    unit: tripAvgSpeed.unit,
                    label: AppStrings.avgSpeed(lang.language),
                    color: AppTheme.blue,
                    c: c
                )
                summaryStatCard(
                    value: tripMaxSpeed.value,
                    unit: tripMaxSpeed.unit,
                    label: AppStrings.maxShort(lang.language),
                    color: AppTheme.red,
                    c: c
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // «Открыто» — между числами поездки и наградами: сначала
            // «сколько проехал», потом «что от этого изменилось на карте»,
            // потом опыт и значки.
            revealedSection

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
            // Не у черновика: публиковать то, что ещё не вошло в мир, нечего
            // — гейт синка всё равно отбил бы.
            if !trip.isDraft {
                publishRow(c)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }

            // Просьба сказать спасибо — ПОСЛЕДНЕЙ строкой и только иногда.
            // Сначала человек увидел свою дорогу, километры, награды и то, что
            // она открыла на карте; вопрос идёт после всего этого и ничего не
            // перекрывает. Когда он вообще уместен — решает `TipMoment`.
            if showTipCard {
                TripSummaryTipCard(
                    onTip: {
                        showTipCard = false
                        showTipJar = true
                    },
                    onDismiss: {
                        TipLedger().noteDeclined()
                        withAnimation(.easeOut(duration: 0.2)) { showTipCard = false }
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
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
        .appConfirm(
            isPresented: $showDraftDiscard,
            title: AppStrings.deleteTrip(lang.language),
            actions: [
                AppDialogAction(AppStrings.delete(lang.language), kind: .destructive) {
                    DraftDecisionQueue.shared.enqueue(trip.id, .discard)
                    NotificationCenter.default.post(name: .draftTripDecisionQueued, object: nil)
                    onDone()
                }
            ]
        )
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
                    recordValue: badge.recordValue(for: trip, unit: distanceUnit, language: lang.language),
                    onDismiss: { selectedBadge = nil }
                )
            }
        }
        .onAppear { tripNotes = trip.tripDescription ?? "" }
        .sheet(isPresented: $showTipJar) {
            TipJarSheet().environmentObject(lang)
        }
        .onAppear(perform: decideTipCard)
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
                commitEdits()
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

    /// Что человек наменял на этом экране — в базу.
    ///
    /// Своим методом, потому что выходов с экрана стало ДВА: «Готово» и тап по
    /// блоку «Открыто». Второй уводит на «Атлас», и написанное описание с
    /// галочкой публикации обязано пережить этот уход — иначе выход через
    /// печать молча съедал бы работу.
    private func commitEdits() {
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
                // Метаданные читаем из БАЙТОВ, пока они есть.
                //
                // Системный `PhotosPicker` не просит доступа к библиотеке — и
                // не должен: человек выбрал кадр, приложение получило файл, а
                // время съёмки и координата лежат в нём. Спросить вместо этого
                // `PHAsset` (как делает свой пикер) тут нельзя дважды:
                // `itemIdentifier` у этого пикера пуст, а доступ к галерее
                // ради уже полученных данных — регрессия приватности.
                //
                // Ниже `savePhoto` пересжимает кадр в свой JPEG, и спросить
                // будет уже не у чего: без этих двух строк снимок с финиша
                // навсегда оставался без места на карте и без отметки.
                let meta = PhotoMetadata.read(fromImageData: data)
                if let photo = mapVM.tripManager.addPhoto(
                    to: trip.id, image: image,
                    capturedAt: meta.capturedAt,
                    latitude: meta.latitude, longitude: meta.longitude) {
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

    // MARK: - Герой и момент открытия (0.7.0)

    /// Маршрут поездки на карте с личным туманом — и он же играет выгорание,
    /// когда разбор трека доложит, что поездка что-то открыла.
    ///
    /// Второй карты для этого на экране НЕТ: одинаковый маршрут в одинаковом
    /// стиле двумя карточками ниже читался не как «мир изменился», а как
    /// «почему-то две карты». Вуаль ложится поверх `RouteMapView` в `ZStack` и
    /// живёт ровно столько, сколько непустая сводка: ничего не открыли — герой
    /// остаётся таким, каким был всегда.
    private var heroMap: some View {
        ZStack {
            RouteMapView(
                coordinates: trip.trackPoints.map(\.coordinate),
                speeds: trip.trackPoints.map(\.speed),
                // Карточка итогов — это и есть момент раскрытия: срез без
                // даты («мир, как он есть сейчас»), а поездка ложится в
                // него секундой позже, на финишном `ingest`. Карта его
                // дождётся сама — у среза без даты она переспрашивает слой
                // по `.revealedLayerChanged` (`RouteMapView.installFog`), и
                // коридор сегодняшней дороги проступает прямо на глазах.
                fogCutoffDate: nil,
                showsFog: true
            )
            if hasNewGround {
                RevealSweepVeil(
                    coordinates: trip.trackPoints.map(\.coordinate),
                    sweep: heroSweep,
                    reduceMotion: reduceMotion
                )
            }
        }
        .frame(height: 139)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    /// Спросить ли на этой карточке «сказать спасибо».
    ///
    /// Решается ОДИН раз, на появлении экрана, и отдаётся чистой функции
    /// `TipMoment`: «не чаще раза в полгода» и «два отказа — навсегда»
    /// проверяются календарём, а не экраном, и тестом их можно задать только
    /// так.
    ///
    /// Отметка «спрашивали» ставится В МОМЕНТ ПОКАЗА, а не нажатия: полгода
    /// считаются от того, когда человека потревожили, а ответил он или просто
    /// закрыл экран — уже не важно.
    private func decideTipCard() {
        guard !showTipCard else { return }
        #if DEBUG
        // Иначе карточку не увидеть вовсе: ей нужны двадцать поездок, месяц с
        // приложением и дорога в сто километров разом. Флаг ЯВНЫЙ и
        // детерминированный — принцип отладочных флагов 0.8.2; журнал он при
        // этом НЕ трогает, чтобы прогон не съедал настоящий срок молчания.
        if ProcessInfo.processInfo.arguments.contains("-debug-tip-moment") {
            showTipCard = true
            return
        }
        #endif
        let ledger = TipLedger()
        let ask = TipMoment.shouldAsk(.init(
            now: Date(),
            storefrontHidesPlus: PlusAccess.shared.storefrontHidesPlus,
            tripDistanceMetres: trip.distance,
            isDraft: trip.isDraft,
            tripCount: mapVM.cachedTripCount,
            // Тот же источник, что у предложения PRO: ответ на «когда человек
            // поставил приложение» обязан быть один.
            firstLaunchAt: ProOfferLedger().firstLaunchAt,
            lastAskedAt: ledger.lastAskedAt,
            declines: ledger.declines,
            tippedAt: ledger.tippedAt,
            afterFailure: !SyncQueue.shared.failed.isEmpty
        ))
        guard ask else { return }
        ledger.noteAsked()
        showTipCard = true
    }

    /// Поездка и правда что-то открыла. Тот же сигнал, что поднимает блок
    /// «Открыто», — иначе выгорание и карточка разъехались бы во времени.
    private var hasNewGround: Bool {
        guard let found = completionData?.discoveries else { return false }
        return !found.isEmpty
    }

    // MARK: - «Открыто» (0.7.0)

    /// Блок находок — отдельным свойством, а не веткой в `body`: тело этого
    /// экрана и так близко к пределу вывода типов SwiftUI (см. `CLAUDE.md`,
    /// «Ловушки»), и вставлять в него ещё одно `if let` с собственной вёрсткой
    /// нельзя.
    ///
    /// Разбор трека кончается ПОЗЖЕ остальных чисел финиша, поэтому сводка
    /// доезжает до уже показанной карточки — и блок появляется пружиной, а не
    /// подменяет содержимое рывком. `nil` — «ещё считается»: ни блока, ни
    /// каркаса, ни надписи «ищем» (искать может и нечего).
    @ViewBuilder
    private var revealedSection: some View {
        let found = completionData?.discoveries
        Group {
            if let found, !found.isEmpty {
                TripRevealedBlock(
                    discoveries: found,
                    onOpen: { id in
                        // Тем же путём, что «Готово»: правки человека
                        // сохраняются ДО ухода с экрана, иначе тап по печати
                        // молча выбрасывал бы набранное описание и снятую
                        // галочку публикации.
                        commitEdits()
                        onDone()
                        NotificationCenter.default.post(name: .openDiscovery, object: id)
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82),
                   value: completionData?.discoveries)
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
        let h = AppStrings.hoursUnitShort(lang)
        let m = AppStrings.minutesUnitShort(lang)
        if hours > 0 {
            if minutes == 0 { return "\(hours) \(h)" }
            return "\(hours) \(h) \(minutes) \(m)"
        }
        if minutes > 0 { return "\(minutes) \(m)" }
        return "\(total) \(AppStrings.secondsUnitShort(lang))"
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
