import SwiftUI
import MapKit

struct HiddenPartsEditorView: View {
    let trip: Trip
    let onSave: (TripHiddenParts) -> Void
    var onRename: () -> Void = {}

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hiddenPartsEditor.didShowFirstNudge") private var didShowFirstNudge = false
    @State private var editorModel: HiddenPartsEditorModel
    @State private var resolution: HiddenPartsResolution
    @State private var routePrefix: [Double]
    @State private var parked: HiddenPartsGeometry.ParkedBoundaries
    @State private var activeHandleID: String?
    @State private var focusedHandleID: String?
    @State private var pulseHandleID: String?
    @State private var handleNudgeID: String?
    @State private var activeDetents: [String: Int] = [:]
    @State private var lastAppliedIndices: [String: Int] = [:]
    @State private var lastAppliedOutsideEndpoints: [String: Bool] = [:]
    @State private var lastResolutionUpdate = Date.distantPast
    @State private var pendingGesture: HiddenHandleGesture?
    @State private var toastItem: ToastItem?
    @State private var mapShowsPublic = false
    @State private var hiddenTitlePlace: (isStart: Bool, locality: String)?
    private let initialFocusCoordinate: CLLocationCoordinate2D?
    /// Read once per editor: a drag re-evaluates the body twenty times a second, and every
    /// `load()` decodes UserDefaults again. Neither setting can change while the editor is open.
    private let defaultEdge: Int
    private let homeZone: (centre: CLLocationCoordinate2D, radius: Double)?
    /// The whole track never changes here, so its derived arrays are built once instead of
    /// on every body pass (10 000 points: tens of milliseconds per pass).
    private let allCoordinates: [CLLocationCoordinate2D]
    private let segmentBreaks: [Int]
    private let pointIndexByID: [UUID: Int]
    @State private var resolving = false
    @State private var resolveAgain = false

    init(trip: Trip, onSave: @escaping (TripHiddenParts) -> Void, onRename: @escaping () -> Void = {},
         initialFocusCoordinate: CLLocationCoordinate2D? = nil) {
        self.trip = trip
        self.onSave = onSave
        self.onRename = onRename
        self.initialFocusCoordinate = initialFocusCoordinate
        let initialParts = trip.hiddenParts ?? TripHiddenParts()
        let defaultEdge = PrivacySettings.load().edgeMetres ?? 0
        let zone = HomeSettings.load().activeZone
        self.defaultEdge = defaultEdge
        self.homeZone = zone
        let points = trip.trackPoints
        allCoordinates = points.map(\.coordinate)
        segmentBreaks = points.indices.dropFirst().filter {
            points[$0].recordingSegmentIndex != points[$0 - 1].recordingSegmentIndex
        }
        pointIndexByID = Dictionary(points.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        _editorModel = State(initialValue: HiddenPartsEditorModel(parts: initialParts))
        _resolution = State(initialValue: HiddenPartsResolver.resolve(
            points: trip.trackPoints, recordingBreaks: trip.recordingBreaks,
            startMetres: initialParts.startMetres ?? defaultEdge,
            endMetres: initialParts.endMetres ?? defaultEdge,
            sections: initialParts.sections, zone: zone))
        _routePrefix = State(initialValue: HiddenPartsGeometry.prefix(points: trip.trackPoints,
                                                                       recordingBreaks: trip.recordingBreaks))
        _parked = State(initialValue: HiddenPartsGeometry.parkedBoundaries(points: trip.trackPoints))
    }

    private var draft: TripHiddenParts {
        get { editorModel.draft }
        set { editorModel.draft = newValue }
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        GeometryReader { geometry in
            let panelHeight = geometry.size.height * 0.45
            ZStack(alignment: .bottom) {
                map(c, panelHeight: panelHeight)
                VStack(spacing: 0) {
                    header(c, l)
                    Spacer(minLength: 0)
                    controlPanel(c, l).frame(height: panelHeight)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(c.bg)
        }
        .background(AppTheme.colors(for: scheme).bg.ignoresSafeArea())
        .ignoresSafeArea()
        // A container element: a bare identifier on the stack would replace the
        // children's own («hidden_editor_done» became «hidden_parts_editor»).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hidden_parts_editor")
        .task(id: trip.id) { hiddenTitlePlace = resolveHiddenTitlePlace() }
        // Keyed by the coordinate: a cover's content is first built from the body pass before the
        // tap, with no coordinate yet, and a plain `.task` would have run (and given up) on that.
        .task(id: focusKey) { await revealFocusedHandle() }
        .task {
            guard !didShowFirstNudge else { return }
            didShowFirstNudge = true
            guard !reduceMotion, UIView.areAnimationsEnabled else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            handleNudgeID = endHandle.ghost ? startHandle.id : endHandle.id
        }
        .onChange(of: draft.startMetres) { _, _ in refreshResolution() }
        .onChange(of: draft.endMetres) { _, _ in refreshResolution() }
        // The title hint only asks whether an edge hides anything. Re-reading the geocoder
        // cache on every metre of a drag was a Core Data fetch on the main actor each time.
        .onChange(of: (draft.startMetres ?? defaultEdge) > 0) { _, _ in hiddenTitlePlace = resolveHiddenTitlePlace() }
        .onChange(of: (draft.endMetres ?? defaultEdge) > 0) { _, _ in hiddenTitlePlace = resolveHiddenTitlePlace() }
        .onChange(of: draft.sections) { _, _ in refreshResolution() }
        .toast(item: $toastItem)
    }

    private func map(_ c: AppTheme.Colors, panelHeight: CGFloat) -> some View {
        let points = mapShowsPublic ? resolution.visiblePoints : trip.trackPoints
        let sectionPoints = resolution.visibleRuns.flatMap { $0 }
        let sectionIndices = sectionPoints.compactMap { pointIndexByID[$0.id] }
        let breaks = mapShowsPublic ? resolution.previewBreaks : segmentBreaks
        return RouteMapView(coordinates: mapShowsPublic ? points.map(\.coordinate) : allCoordinates,
                            speeds: points.map(\.speed), routeBreaks: breaks,
                            hiddenRuns: mapShowsPublic ? [] : resolution.hiddenRuns.map { $0.map(\.coordinate) },
                            hiddenLockPoints: mapShowsPublic ? [] : staticLockPoints,
                            hiddenLockAccessibilityLabel: AppStrings.hiddenRouteLockAccessibility(lang.language),
                            hiddenHandles: mapShowsPublic ? [] : handles,
                            hiddenHandlePanelHeight: panelHeight,
                            handleNudgeID: mapShowsPublic ? nil : handleNudgeID,
                            onHiddenHandleGesture: handleGesture,
                            onHiddenHandleAdjust: adjustHandle,
                            onRouteLongPress: mapShowsPublic ? nil : { _, index, _, _ in addSection(around: index) },
                            routeLongPressCoordinates: mapShowsPublic ? nil : sectionPoints.map(\.coordinate),
                            routeLongPressIndices: mapShowsPublic ? nil : sectionIndices,
                            routeLongPressBreaks: mapShowsPublic ? nil : breaks,
                            hiddenHandleRouteCoordinates: allCoordinates,
                            isInteractive: true,
                            showsFog: false, elevationStyle: .flat,
                            treatAsPreview: false,
                            fitInsets: UIEdgeInsets(top: 84, left: 24, bottom: panelHeight + 24, right: 24),
                            animatesFit: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("hidden_editor_map")
    }

    private func controlPanel(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(c.textTertiary.opacity(0.42)).frame(width: 38, height: 5).padding(.top, 10).padding(.bottom, 11)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.hiddenDragHint(l))
                        .font(.inter(12.5, weight: .medium)).foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary(l))
                        .font(.inter(13, weight: .semibold)).foregroundStyle(c.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("hidden_summary")
                    tripBar(c, l)
                    sections(c, l)
                    numberChoice(c, l)
                    localOnlyCard(c, l)
                    Toggle(AppStrings.hiddenShowPublic(l), isOn: $mapShowsPublic)
                        .font(.inter(14, weight: .semibold)).tint(AppTheme.accent)
                        .padding(14).background(c.cardAlt, in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityIdentifier("hidden_preview_toggle")
                    if shouldShowTitleHint {
                        Button { Haptics.tap(); dismiss(); onRename() } label: {
                            Text(titleHint(l)).font(.inter(12.5)).foregroundStyle(c.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(PressableCardStyle())
                    }
                    if trip.isOnServer && !trip.isPrivate {
                        Text(AppStrings.hiddenAlreadySeen(l)).font(.inter(12.5)).foregroundStyle(c.textSecondary)
                    }
                    if trip.trackPoints.isEmpty {
                        Text(AppStrings.hiddenLocalOnlyNotice(l)).font(.inter(12.5)).foregroundStyle(c.textSecondary)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(c.card, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .accessibilityIdentifier("hidden_controls_panel")
    }

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack {
            Button {
                Haptics.tap()
                editorModel.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(c.text)
                    .frame(width: 38, height: 38).background(c.card, in: Circle())
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityLabel(AppStrings.closeSheet(l))
            .accessibilityIdentifier("hidden_editor_close")
            Spacer(minLength: 10)
            Text(AppStrings.hiddenEditorTitle(l)).font(.inter(18, weight: .bold)).foregroundStyle(c.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 10)
            Button { Haptics.tap(); onSave(editorModel.apply()); dismiss() } label: {
                Text(AppStrings.done(l)).font(.inter(15, weight: .bold)).foregroundStyle(AppTheme.accent)
                    .frame(minHeight: 38)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("hidden_editor_done")
        }
        .padding(.horizontal, 16).padding(.top, 56).padding(.bottom, 8)
    }

    private func tripBar(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(c.cardAlt).frame(height: 14)
                if trip.trackPoints.count > 1 {
                    let points = trip.trackPoints
                    let sampleStride = max(1, points.count / 48)
                    ForEach(Array(stride(from: 0, to: points.count - 1, by: sampleStride)), id: \.self) { index in
                        let band = SpeedColorScale.bands[SpeedColorScale.zone(forSpeedMS: points[index].speed)]
                        let from = position(points[index].timestamp)
                        let to = position(points[min(index + sampleStride, points.count - 1)].timestamp)
                        Rectangle().fill(band.color)
                            .frame(width: max(2, width * (to - from)), height: 14)
                            .offset(x: width * from)
                    }
                } else {
                    Capsule().fill(AppTheme.accent.opacity(0.7)).frame(height: 14)
                }
                ForEach(resolution.hiddenRanges, id: \.from) { range in
                    let a = position(range.from)
                    let b = position(range.to)
                    Rectangle().fill(c.textTertiary.opacity(0.75))
                        .frame(width: max(12, width * (b - a)), height: 14)
                        .overlay {
                            StripedPattern().stroke(c.card.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        }
                        .offset(x: width * a)
                }
                ForEach(draft.sections) { section in
                    let start = position(section.from), end = position(section.to)
                    Circle().fill(c.card).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(c.textTertiary, lineWidth: 1))
                        .offset(x: max(0, min(width - 20, width * start - 10)))
                        .gesture(handleDrag(section.id, movingStart: true, width: width, initialDate: section.from))
                        .accessibilityLabel(AppStrings.hiddenSectionStartHandle(l))
                    Circle().fill(c.card).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(c.textTertiary, lineWidth: 1))
                        .offset(x: max(0, min(width - 20, width * end - 10)))
                        .gesture(handleDrag(section.id, movingStart: false, width: width, initialDate: section.to))
                        .accessibilityLabel(AppStrings.hiddenSectionEndHandle(l))
                }
            }
            .frame(maxHeight: .infinity)
            .clipShape(Capsule())
        }
        .frame(height: 24)
        .overlay(alignment: .bottom) {
            HStack { Text(clock(timeline.start)); Spacer(); Text(clock(timeline.end)) }
                .font(.inter(10, weight: .medium)).foregroundStyle(c.textTertiary)
                .offset(y: 15)
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hidden_trip_bar")
    }

    private func sections(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(spacing: 8) {
            ForEach(draft.sections) { section in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(c.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.hiddenSectionTitle(l, start: clock(section.from), end: clock(section.to)))
                            .font(.inter(13, weight: .semibold)).foregroundStyle(c.text)
                            .accessibilityIdentifier("hidden_section_title")
                        Text(sectionDistance(section)).font(.inter(11.5)).foregroundStyle(c.textSecondary)
                    }
                    Spacer()
                    Button { Haptics.tap(); editorModel.removeSection(section.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.textTertiary).frame(width: 32, height: 36)
                    }.buttonStyle(PressableCardStyle()).accessibilityLabel(AppStrings.delete(l))
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(c.card, in: RoundedRectangle(cornerRadius: 14))
            }
            Button {
                Haptics.tap(); addMiddleSection()
            } label: {
                Text(AppStrings.hiddenAddSection(l)).font(.inter(14, weight: .bold)).foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 13).background(c.card, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(PressableCardStyle()).accessibilityIdentifier("hidden_add_section")
        }
    }

    private func numberChoice(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.hiddenNumbersTitle(l)).font(.inter(14, weight: .semibold)).foregroundStyle(c.textSecondary)
            Picker(AppStrings.hiddenNumbersTitle(l), selection: Binding<Bool>(
                get: { editorModel.draft.numbersVisibleOnly },
                set: { editorModel.draft.numbersVisibleOnly = $0 }
            )) {
                Text(AppStrings.hiddenAllTrip(l)).tag(false)
                Text(AppStrings.hiddenWithoutHidden(l)).tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("hidden_numbers_choice")
            Text(numbersPreview(l))
                .font(.inter(12)).foregroundStyle(c.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("hidden_numbers_preview")
        }
    }

    private func localOnlyCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let photoCount = trip.photos.filter { photo in
            HiddenPartsResolver.photoIsHidden(capturedAt: photo.capturedAt, coordinate: photo.exifCoordinate,
                                              resolution: resolution, points: trip.trackPoints, zone: homeZone)
        }.count
        return VStack(alignment: .leading, spacing: 5) {
            Text(AppStrings.hiddenLocalCardTitle(l)).font(.inter(14, weight: .bold)).foregroundStyle(c.text)
            Text(AppStrings.hiddenLocalCardBody(l, pieces: resolution.hiddenRanges.count, photos: photoCount))
                .font(.inter(12.5)).foregroundStyle(c.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(c.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var shouldShowTitleHint: Bool {
        hiddenTitlePlace != nil
    }

    private func titleHint(_ language: LanguageManager.Language) -> String {
        return hiddenTitlePlace?.isStart == true
            ? AppStrings.hiddenTitleHintStart(language, title: trip.title ?? "")
            : AppStrings.hiddenTitleHint(language, title: trip.title ?? "")
    }

    private func resolveHiddenTitlePlace() -> (isStart: Bool, locality: String)? {
        guard !trip.titleIsCustom, let title = trip.title, !title.isEmpty,
              let first = trip.trackPoints.first, let last = trip.trackPoints.last else { return nil }
        let defaults = defaultEdge
        let repository = CoreDataTripRepository(persistenceController: .shared)
        let candidates: [(isStart: Bool, isHidden: Bool, coordinate: CLLocationCoordinate2D)] = [
            (true, (draft.startMetres ?? defaults) > 0, first.coordinate),
            (false, (draft.endMetres ?? defaults) > 0, last.coordinate)
        ]
        for candidate in candidates where candidate.isHidden {
            guard let locality = repository.cachedGeocode(for: candidate.coordinate)?.locality,
                  !locality.isEmpty,
                  title.localizedCaseInsensitiveContains(locality) else { continue }
            return (candidate.isStart, locality)
        }
        return nil
    }

    private func summary(_ l: LanguageManager.Language) -> String {
        AppStrings.hiddenSummary(
            l, start: formatMetres(startDisplayedMetres), end: formatMetres(endDisplayedMetres),
            sections: draft.sections.count,
            startParking: startParkingOnly, endParking: endParkingOnly)
    }

    private func formatMetres(_ value: Double) -> String {
        value <= 0 ? "" : Measure.distance(metres: value, unit: distanceUnit, lang: lang.language)
    }

    private var timeline: HiddenTimelineAxis {
        HiddenTimelineAxis(points: trip.trackPoints, tripStart: trip.startDate, tripEnd: trip.endDate)
    }

    private func position(_ date: Date) -> CGFloat { timeline.fraction(of: date) }

    private func clock(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func sectionDistance(_ section: HiddenSection) -> String {
        guard let first = index(at: section.from), let last = index(at: section.to),
              routePrefix.indices.contains(first), routePrefix.indices.contains(last) else { return Measure.distance(metres: 0, unit: distanceUnit, lang: lang.language) }
        let metres = max(0, routePrefix[last] - routePrefix[first])
        return Measure.distance(metres: metres, unit: distanceUnit, lang: lang.language)
    }

    private func numbersPreview(_ l: LanguageManager.Language) -> String {
        let numbers = HiddenPartsEditorModel.numbersForOthers(
            trip: trip, visibleRuns: resolution.visibleRuns, visibleOnly: draft.numbersVisibleOnly)
        return AppStrings.hiddenNumbersPreview(
            l, distance: Measure.distance(metres: numbers.metres, unit: distanceUnit, lang: l),
            duration: Trip.formattedTimeHuman(numbers.seconds, lang: l))
    }

    private func handleDrag(_ id: UUID, movingStart: Bool, width: CGFloat, initialDate: Date) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { value in
            guard width > 0 else { return }
            let ratio = position(initialDate) + value.translation.width / width
            guard let time = HiddenTimelineAxis.nearestTimestamp(
                to: timeline.date(atFraction: ratio), in: trip.trackPoints) else { return }
            let boundaryName = movingStart ? "from" : "to"
            let boundaryID = "section:\(boundaryName):\(id.uuidString)"
            guard let section = draft.sections.first(where: { $0.id == id }),
                  let candidateIndex = index(at: time),
                  let allowed = sectionHandles(section).first(where: { $0.id == boundaryID })?.allowedIndices else { return }
            let boundedIndex = min(allowed.upperBound, max(allowed.lowerBound, candidateIndex))
            editorModel.moveBoundary(id, to: trip.trackPoints[boundedIndex].timestamp, movingStart: movingStart)
        }
        .onEnded { _ in finishSectionIfTooShort(id) }
    }

    /// Resolves off the main actor, one pass at a time, and always finishes on the latest draft.
    /// The resolver walks the whole track (about 30 ms for 10 000 points on a Mac, more on a
    /// phone), and a drag asks for it twenty times a second: on the main actor the handle would
    /// stutter under the finger. The handle itself does not wait for this, only the dotted
    /// runs, the bar and the numbers do.
    private func refreshResolution() {
        if resolving { resolveAgain = true; return }
        resolving = true
        let points = trip.trackPoints, breaks = trip.recordingBreaks
        let start = draft.startMetres ?? defaultEdge, end = draft.endMetres ?? defaultEdge
        let sections = draft.sections, zone = homeZone
        Task { @MainActor in
            let resolved = await Task.detached(priority: .userInitiated) {
                HiddenPartsResolver.resolve(points: points, recordingBreaks: breaks,
                                            startMetres: start, endMetres: end,
                                            sections: sections, zone: zone)
            }.value
            resolution = resolved
            resolving = false
            if resolveAgain {
                resolveAgain = false
                refreshResolution()
            }
        }
    }

    private var defaultEdgeMetres: Int { defaultEdge }
    private var effectiveStartMetres: Int { max(0, draft.startMetres ?? defaultEdgeMetres) }
    private var effectiveEndMetres: Int { max(0, draft.endMetres ?? defaultEdgeMetres) }
    private var lastPointIndex: Int { max(0, trip.trackPoints.count - 1) }
    private var startVisibleIndex: Int { HiddenPartsGeometry.startIndex(forStoredMetres: effectiveStartMetres, prefix: routePrefix) }
    private var endVisibleIndex: Int { HiddenPartsGeometry.endIndex(forStoredMetres: effectiveEndMetres, prefix: routePrefix) }
    private var startDisplayedMetres: Double {
        HiddenPartsGeometry.displayedStartMetres(at: startVisibleIndex, prefix: routePrefix, departure: parked.departure)
    }
    private var endDisplayedMetres: Double {
        HiddenPartsGeometry.displayedEndMetres(at: endVisibleIndex, prefix: routePrefix, arrival: parked.arrival)
    }
    private var startParkingOnly: Bool {
        guard effectiveStartMetres > 0, let departure = parked.departure else { return false }
        return startVisibleIndex == departure + 1
    }
    private var endParkingOnly: Bool {
        guard effectiveEndMetres > 0, let arrival = parked.arrival else { return false }
        return endVisibleIndex == arrival - 1
    }
    private var startHandle: HiddenHandle { edgeHandle(isStart: true) }
    private var endHandle: HiddenHandle { edgeHandle(isStart: false) }
    private var handles: [HiddenHandle] {
        guard trip.trackPoints.count > 1 else { return [] }
        return [startHandle] + draft.sections.flatMap(sectionHandles) + [endHandle]
    }

    private var staticLockPoints: [CLLocationCoordinate2D] {
        let route = trip.trackPoints
        guard !route.isEmpty else { return resolution.lockPoints }
        var editableBoundaryIndices: Set<Int> = []
        if startVisibleIndex > 0 { editableBoundaryIndices.insert(startVisibleIndex) }
        if endVisibleIndex < lastPointIndex { editableBoundaryIndices.insert(endVisibleIndex) }
        for section in draft.sections {
            if let first = index(at: section.from), let last = index(at: section.to) {
                if first > 0 { editableBoundaryIndices.insert(first - 1) }
                if last < lastPointIndex { editableBoundaryIndices.insert(last + 1) }
            }
        }
        return resolution.lockPoints.filter { coordinate in
            guard let nearest = route.indices.min(by: { indexA, indexB in
                routeDistance(coordinate, route[indexA].coordinate) < routeDistance(coordinate, route[indexB].coordinate)
            }) else { return true }
            return !editableBoundaryIndices.contains(nearest)
        }
    }

    private func edgeHandle(isStart: Bool) -> HiddenHandle {
        let stored = isStart ? effectiveStartMetres : effectiveEndMetres
        let visibleIndex = isStart ? startVisibleIndex : endVisibleIndex
        let isGhost = stored == 0
        let parking = isStart ? startParkingOnly : endParkingOnly
        let parkedIndex = isStart ? parked.departure : parked.arrival
        let handleIndex: Int
        if parking, let parkedIndex { handleIndex = parkedIndex }
        else { handleIndex = isStart ? (isGhost ? 0 : visibleIndex) : (isGhost ? lastPointIndex : visibleIndex) }
        let lower: Int
        let upper: Int
        if isStart {
            lower = 0
            let sectionLimit = draft.sections.compactMap { index(at: $0.from) }.min().map { $0 - 1 } ?? lastPointIndex
            upper = min(HiddenPartsGeometry.maximumStartIndex(endingAt: endVisibleIndex, prefix: routePrefix), sectionLimit)
        } else {
            let sectionLimit = draft.sections.compactMap { index(at: $0.to) }.max().map { $0 + 1 } ?? 0
            lower = max(HiddenPartsGeometry.minimumEndIndex(startingAt: startVisibleIndex, prefix: routePrefix), sectionLimit)
            upper = lastPointIndex
        }
        let id = isStart ? "edge:start" : "edge:end"
        let info = edgeBubble(isStart: isStart, ghost: isGhost, parking: parking, index: visibleIndex)
        let label = isStart ? AppStrings.hiddenHandleStartLabel(lang.language) : AppStrings.hiddenHandleEndLabel(lang.language)
        return HiddenHandle(id: id, kind: isStart ? .start : .end, index: handleIndex,
                            allowedIndices: min(lower, upper)...max(lower, upper),
                            coordinate: coordinate(at: handleIndex), specialIndex: parkedIndex ?? (isStart ? 0 : lastPointIndex),
                            ghost: isGhost, lifted: activeHandleID == id,
                            pulse: pulseHandleID == id, accessibilityLabel: label,
                            value: "\(info.title), \(info.caption)", bubbleTitle: info.title,
                            bubbleCaption: info.caption,
                            bubbleVisible: activeHandleID == id || focusedHandleID == id)
    }

    private func edgeBubble(isStart: Bool, ghost: Bool, parking: Bool, index: Int) -> (title: String, caption: String) {
        if ghost {
            return (isStart ? AppStrings.hiddenHandleStartVisible(lang.language) : AppStrings.hiddenHandleEndVisible(lang.language),
                    AppStrings.hiddenHandleDragInward(lang.language))
        }
        if parking {
            let parkedIndex = isStart ? (parked.departure ?? 0) : (parked.arrival ?? lastPointIndex)
            let seconds = isStart
                ? trip.trackPoints[parkedIndex].timestamp.timeIntervalSince(trip.trackPoints[0].timestamp)
                : trip.trackPoints[lastPointIndex].timestamp.timeIntervalSince(trip.trackPoints[parkedIndex].timestamp)
            let duration = Trip.formattedTimeHuman(seconds, lang: lang.language)
            return (AppStrings.hiddenHandleParkingOnly(lang.language), isStart
                    ? AppStrings.hiddenHandleBeforeDeparture(lang.language, duration: duration)
                    : AppStrings.hiddenHandleAfterStop(lang.language, duration: duration))
        }
        if isStart {
            let distance = Measure.distance(metres: startDisplayedMetres, unit: distanceUnit, lang: lang.language)
            let time = trip.trackPoints[min(lastPointIndex, max(0, index))].timestamp.formatted(date: .omitted, time: .shortened)
            return (AppStrings.hiddenHandleStartHidden(lang.language, distance: distance),
                    AppStrings.hiddenHandleUntil(lang.language, time: time))
        }
        let distance = Measure.distance(metres: endDisplayedMetres, unit: distanceUnit, lang: lang.language)
        let firstHiddenIndex = min(lastPointIndex, max(0, index + 1))
        let time = trip.trackPoints[firstHiddenIndex].timestamp.formatted(date: .omitted, time: .shortened)
        return (AppStrings.hiddenHandleEndHidden(lang.language, distance: distance),
                AppStrings.hiddenHandleFrom(lang.language, time: time))
    }

    private func sectionHandles(_ section: HiddenSection) -> [HiddenHandle] {
        guard let fromIndex = index(at: section.from), let toIndex = index(at: section.to),
              !trip.trackPoints.isEmpty else { return [] }
        let sectionIndex = draft.sections.firstIndex(where: { $0.id == section.id }) ?? 0
        let previousEnd = sectionIndex > 0 ? index(at: draft.sections[sectionIndex - 1].to).map { $0 + 1 } : nil
        let nextStart = sectionIndex + 1 < draft.sections.count
            ? index(at: draft.sections[sectionIndex + 1].from).map { $0 - 1 } : nil
        let fromLower = max(startVisibleIndex + 1, previousEnd ?? 0)
        let toUpper = min(endVisibleIndex - 1, nextStart ?? lastPointIndex)
        let boundedFromLower = min(fromLower, toIndex)
        let boundedToUpper = max(toUpper, fromIndex)
        let title = AppStrings.hiddenSectionTitle(lang.language,
                                                   start: clock(trip.trackPoints[fromIndex].timestamp),
                                                   end: clock(trip.trackPoints[toIndex].timestamp))
        let distance = sectionDistance(section)
        let value = "\(title), \(distance)"
        return [
            HiddenHandle(id: "section:from:\(section.id.uuidString)", kind: .sectionFrom,
                         index: fromIndex, allowedIndices: min(boundedFromLower, toIndex)...max(boundedFromLower, toIndex),
                         coordinate: coordinate(at: fromIndex), specialIndex: nil, ghost: false,
                         lifted: activeHandleID == "section:from:\(section.id.uuidString)",
                         pulse: pulseHandleID == "section:from:\(section.id.uuidString)",
                         accessibilityLabel: AppStrings.hiddenSectionStartHandle(lang.language), value: value,
                         bubbleTitle: title, bubbleCaption: distance,
                         bubbleVisible: activeHandleID == "section:from:\(section.id.uuidString)" || focusedHandleID == "section:from:\(section.id.uuidString)"),
            HiddenHandle(id: "section:to:\(section.id.uuidString)", kind: .sectionTo,
                         index: toIndex, allowedIndices: min(fromIndex, boundedToUpper)...max(fromIndex, boundedToUpper),
                         coordinate: coordinate(at: toIndex), specialIndex: nil, ghost: false,
                         lifted: activeHandleID == "section:to:\(section.id.uuidString)",
                         pulse: pulseHandleID == "section:to:\(section.id.uuidString)",
                         accessibilityLabel: AppStrings.hiddenSectionEndHandle(lang.language), value: value,
                         bubbleTitle: title, bubbleCaption: distance,
                         bubbleVisible: activeHandleID == "section:to:\(section.id.uuidString)" || focusedHandleID == "section:to:\(section.id.uuidString)")
        ]
    }

    private func handleGesture(_ event: HiddenHandleGesture) -> Int? {
        switch event.phase {
        case .began:
            activeHandleID = event.handleID
            focusedHandleID = nil
            Haptics.tap()
            lastAppliedIndices[event.handleID] = event.snappedIndex
            lastAppliedOutsideEndpoints[event.handleID] = false
            lastResolutionUpdate = Date()
            return currentHandleIndex(event.handleID) ?? event.snappedIndex
        case .changed:
            let now = Date()
            guard event.snappedIndex != lastAppliedIndices[event.handleID] ||
                    event.outsideEndpoint != lastAppliedOutsideEndpoints[event.handleID] else {
                pendingGesture = nil
                return currentHandleIndex(event.handleID) ?? event.snappedIndex
            }
            guard now.timeIntervalSince(lastResolutionUpdate) >= 0.05 else {
                pendingGesture = event
                return event.snappedIndex
            }
            applyGesture(event)
            return currentHandleIndex(event.handleID) ?? event.snappedIndex
        case .ended:
            if let pendingGesture { applyGesture(pendingGesture) }
            if event.snappedIndex != lastAppliedIndices[event.handleID] ||
                event.outsideEndpoint != lastAppliedOutsideEndpoints[event.handleID] { applyGesture(event) }
            finishHandle(event.handleID)
            return currentHandleIndex(event.handleID) ?? event.snappedIndex
        case .cancelled:
            finishHandle(event.handleID)
            return currentHandleIndex(event.handleID) ?? event.snappedIndex
        }
    }

    private func currentHandleIndex(_ id: String) -> Int? {
        handles.first(where: { $0.id == id })?.index
    }

    private func applyGesture(_ event: HiddenHandleGesture) {
        pendingGesture = nil
        lastAppliedIndices[event.handleID] = event.snappedIndex
        lastAppliedOutsideEndpoints[event.handleID] = event.outsideEndpoint
        lastResolutionUpdate = Date()
        if event.handleID == "edge:start" {
            moveStartHandle(to: event.snappedIndex, outsideEndpoint: event.outsideEndpoint, id: event.handleID)
        } else if event.handleID == "edge:end" {
            moveEndHandle(to: event.snappedIndex, outsideEndpoint: event.outsideEndpoint, id: event.handleID)
        } else if let sectionID = sectionID(from: event.handleID) {
            editorModel.moveBoundary(sectionID, to: trip.trackPoints[event.snappedIndex].timestamp,
                                     movingStart: event.handleID.hasPrefix("section:from:"))
        }
    }

    private func moveStartHandle(to proposedIndex: Int, outsideEndpoint: Bool, id: String) {
        guard !trip.trackPoints.isEmpty else { return }
        if parked.departure != nil, proposedIndex <= (parked.departure ?? 0) {
            if outsideEndpoint {
                activeDetents[id] = nil
                activeDetents["parking:start"] = nil
                setEdgeValue(0, isStart: true)
            } else if let departure = parked.departure {
                activeDetents[id] = nil
                let boundary = HiddenPartsGeometry.startBoundary(near: departure + 1, prefix: routePrefix)
                setEdgeValue(boundary.metres, isStart: true)
                detentEntered("parking:start", value: 1)
            }
            return
        }
        activeDetents["parking:start"] = nil
        if parked.departure == nil, proposedIndex <= min(2, lastPointIndex) {
            activeDetents[id] = nil
            setEdgeValue(0, isStart: true)
            return
        }
        guard proposedIndex > 0 else { setEdgeValue(0, isStart: true); return }
        let sectionLimit = draft.sections.compactMap { index(at: $0.from) }.min().map { $0 - 1 } ?? lastPointIndex
        let maximumIndex = min(HiddenPartsGeometry.maximumStartIndex(endingAt: endVisibleIndex, prefix: routePrefix), sectionLimit)
        guard maximumIndex > 0 else { setEdgeValue(0, isStart: true); return }
        let boundedIndex = min(maximumIndex, proposedIndex)
        var boundary = HiddenPartsGeometry.startBoundary(near: boundedIndex, prefix: routePrefix)
        let distance = HiddenPartsGeometry.displayedStartMetres(at: boundary.index, prefix: routePrefix,
                                                                departure: parked.departure)
        if let detent = HiddenPartsGeometry.detent(near: distance) {
            let targetDistance = (parked.departure.map { routePrefix[$0] } ?? 0) + Double(detent)
            let targetIndex = min(maximumIndex, index(nearestPrefixTo: targetDistance))
            boundary = HiddenPartsGeometry.startBoundary(near: targetIndex, prefix: routePrefix)
            if abs(HiddenPartsGeometry.displayedStartMetres(at: boundary.index, prefix: routePrefix,
                                                           departure: parked.departure) - Double(detent))
                <= HiddenPartsGeometry.detentToleranceMetres {
                detentEntered(id, value: detent)
            } else {
                activeDetents[id] = nil
            }
        } else {
            activeDetents[id] = nil
        }
        setEdgeValue(boundary.metres, isStart: true)
    }

    private func moveEndHandle(to proposedIndex: Int, outsideEndpoint: Bool, id: String) {
        guard !trip.trackPoints.isEmpty else { return }
        if let arrival = parked.arrival, proposedIndex >= arrival {
            if outsideEndpoint {
                activeDetents[id] = nil
                activeDetents["parking:end"] = nil
                setEdgeValue(0, isStart: false)
            } else {
                activeDetents[id] = nil
                let boundary = HiddenPartsGeometry.endBoundary(near: arrival - 1, prefix: routePrefix)
                setEdgeValue(boundary.metres, isStart: false)
                detentEntered("parking:end", value: 1)
            }
            return
        }
        activeDetents["parking:end"] = nil
        if parked.arrival == nil, proposedIndex >= lastPointIndex - 2 {
            activeDetents[id] = nil
            setEdgeValue(0, isStart: false)
            return
        }
        guard proposedIndex < lastPointIndex else { setEdgeValue(0, isStart: false); return }
        let sectionLimit = draft.sections.compactMap { index(at: $0.to) }.max().map { $0 + 1 } ?? 0
        let minimumIndex = max(HiddenPartsGeometry.minimumEndIndex(startingAt: startVisibleIndex, prefix: routePrefix), sectionLimit)
        guard minimumIndex < lastPointIndex else { setEdgeValue(0, isStart: false); return }
        let boundedIndex = max(minimumIndex, proposedIndex)
        var boundary = HiddenPartsGeometry.endBoundary(near: boundedIndex, prefix: routePrefix)
        let distance = HiddenPartsGeometry.displayedEndMetres(at: boundary.index, prefix: routePrefix,
                                                              arrival: parked.arrival)
        if let detent = HiddenPartsGeometry.detent(near: distance) {
            let endOdometer = parked.arrival.map { routePrefix[$0] } ?? routePrefix.last ?? 0
            let targetIndex = max(minimumIndex, index(nearestPrefixTo: endOdometer - Double(detent)))
            boundary = HiddenPartsGeometry.endBoundary(near: targetIndex, prefix: routePrefix)
            if abs(HiddenPartsGeometry.displayedEndMetres(at: boundary.index, prefix: routePrefix,
                                                         arrival: parked.arrival) - Double(detent))
                <= HiddenPartsGeometry.detentToleranceMetres {
                detentEntered(id, value: detent)
            } else {
                activeDetents[id] = nil
            }
        } else {
            activeDetents[id] = nil
        }
        setEdgeValue(boundary.metres, isStart: false)
    }

    private func setEdgeValue(_ metres: Int, isStart: Bool) {
        if isStart { editorModel.setStartMetres(metres) } else { editorModel.setEndMetres(metres) }
    }

    private func detentEntered(_ id: String, value: Int) {
        guard activeDetents[id] != value else { return }
        activeDetents[id] = value
        Haptics.selection()
        pulseTransiently(id == "parking:start" ? "edge:start" : (id == "parking:end" ? "edge:end" : id))
    }

    private func pulseTransiently(_ id: String) {
        pulseHandleID = id
        let pulseID = pulseHandleID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(470))
            if pulseHandleID == pulseID { pulseHandleID = nil }
        }
    }

    private func finishHandle(_ id: String) {
        if let sectionID = sectionID(from: id) { finishSectionIfTooShort(sectionID) }
        activeHandleID = nil
        pendingGesture = nil
        lastAppliedIndices[id] = nil
        lastAppliedOutsideEndpoints[id] = nil
    }

    private func finishSectionIfTooShort(_ sectionID: UUID) {
        guard let section = draft.sections.first(where: { $0.id == sectionID }),
              let first = index(at: section.from), let last = index(at: section.to),
              HiddenPartsGeometry.sectionNeedsRemoval(from: first, to: last, prefix: routePrefix) else { return }
        removeSection(section, withUndo: true)
    }

    private func addSection(around index: Int) -> String? {
        guard trip.trackPoints.count > 1 else { Haptics.error(); return nil }
        let range = HiddenPartsGeometry.sectionRange(
            around: index, visibleStart: startVisibleIndex, visibleEnd: endVisibleIndex,
            prefix: routePrefix,
            occupied: draft.sections.compactMap { section in
                guard let first = self.index(at: section.from), let last = self.index(at: section.to) else { return nil }
                return first...last
            })
        guard let range else { Haptics.error(); return nil }
        let section = HiddenSection(id: UUID(), from: trip.trackPoints[range.lowerBound].timestamp,
                                    to: trip.trackPoints[range.upperBound].timestamp)
        editorModel.draft.sections = HiddenPartsEditorModel.merged(editorModel.draft.sections + [section])
        Haptics.selection()
        let handleID = "section:to:\(section.id.uuidString)"
        pulseTransiently(handleID)
        return handleID
    }

    private func addMiddleSection() {
        guard endVisibleIndex > startVisibleIndex else { Haptics.error(); return }
        let targetDistance = (routePrefix[startVisibleIndex] + routePrefix[endVisibleIndex]) / 2
        let index = index(nearestPrefixTo: targetDistance)
        _ = addSection(around: index)
    }

    private func removeSection(_ section: HiddenSection, withUndo: Bool) {
        let oldSections = draft.sections
        editorModel.removeSection(section.id)
        guard withUndo else { return }
        toastItem = ToastItem(type: .undo, message: AppStrings.hiddenSectionRemoved(lang.language),
                              undoLabel: AppStrings.undo(lang.language), undoAction: {
            editorModel.draft.sections = oldSections
        })
    }

    private func adjustHandle(_ id: String, direction: Int) {
        guard direction != 0 else { return }
        if id == "edge:start" {
            let target = startDisplayedMetres + Double(direction * 100)
            moveStartHandle(to: index(nearestPrefixTo: (parked.departure.map { routePrefix[$0] } ?? 0) + target),
                            outsideEndpoint: false, id: id)
        } else if id == "edge:end" {
            let endPrefix = parked.arrival.map { routePrefix[$0] } ?? routePrefix.last ?? 0
            moveEndHandle(to: index(nearestPrefixTo: endPrefix - endDisplayedMetres - Double(direction * 100)),
                          outsideEndpoint: false, id: id)
        } else if let sectionID = sectionID(from: id), let section = draft.sections.first(where: { $0.id == sectionID }) {
            let movingStart = id.hasPrefix("section:from:")
            let oldDate = movingStart ? section.from : section.to
            let targetDate = oldDate.addingTimeInterval(Double(direction * 60))
            guard let targetIndex = index(at: targetDate) else { return }
            editorModel.moveBoundary(sectionID, to: trip.trackPoints[targetIndex].timestamp, movingStart: movingStart)
        }
    }

    private var focusKey: String {
        initialFocusCoordinate.map { "\($0.latitude),\($0.longitude)" } ?? ""
    }

    private func revealFocusedHandle() async {
        guard let initialFocusCoordinate,
              let handle = handles.min(by: { routeDistance($0.coordinate, initialFocusCoordinate) < routeDistance($1.coordinate, initialFocusCoordinate) }) else { return }
        focusedHandleID = handle.id
        pulseHandleID = handle.id
        try? await Task.sleep(for: .seconds(2))
        if focusedHandleID == handle.id { focusedHandleID = nil; pulseHandleID = nil }
    }

    private func sectionID(from handleID: String) -> UUID? {
        guard let value = handleID.split(separator: ":").last else { return nil }
        return UUID(uuidString: String(value))
    }

    private func coordinate(at index: Int) -> CLLocationCoordinate2D {
        guard trip.trackPoints.indices.contains(index) else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        return trip.trackPoints[index].coordinate
    }

    private func index(at date: Date) -> Int? {
        guard !trip.trackPoints.isEmpty else { return nil }
        var low = 0
        var high = trip.trackPoints.count
        while low < high {
            let middle = (low + high) / 2
            if trip.trackPoints[middle].timestamp < date { low = middle + 1 } else { high = middle }
        }
        return min(trip.trackPoints.count - 1, low)
    }

    private func index(nearestPrefixTo target: Double) -> Int {
        guard !routePrefix.isEmpty else { return 0 }
        var low = 0
        var high = routePrefix.count
        while low < high {
            let middle = (low + high) / 2
            if routePrefix[middle] < target { low = middle + 1 } else { high = middle }
        }
        let after = min(routePrefix.count - 1, low)
        let before = max(0, after - 1)
        return abs(routePrefix[after] - target) < abs(routePrefix[before] - target) ? after : before
    }

    private func routeDistance(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Double {
        GeometryUtils.haversineDistance(lhs, rhs)
    }

}

private struct StripedPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        stride(from: -rect.height, through: rect.width, by: 7).forEach { x in
            path.move(to: CGPoint(x: x, y: rect.maxY)); path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
        }
        return path
    }
}
