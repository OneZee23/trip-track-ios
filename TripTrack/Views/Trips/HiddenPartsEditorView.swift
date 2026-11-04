import SwiftUI
import MapKit

struct HiddenPartsEditorView: View {
    let trip: Trip
    let onSave: (TripHiddenParts) -> Void
    var onRename: () -> Void = {}

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dismiss) private var dismiss
    @State private var editorModel: HiddenPartsEditorModel
    @State private var choosing: EdgeChoice?
    @State private var firstSectionFix: TripRouteLocator.Fix?
    @State private var mapShowsPublic = false

    fileprivate enum EdgeChoice { case start, end, sectionStart, sectionEnd }
    private let presets: [Int] = [0, 200, 500, 1_000, 2_000]

    init(trip: Trip, onSave: @escaping (TripHiddenParts) -> Void, onRename: @escaping () -> Void = {}) {
        self.trip = trip
        self.onSave = onSave
        self.onRename = onRename
        _editorModel = State(initialValue: HiddenPartsEditorModel(parts: trip.hiddenParts ?? TripHiddenParts()))
    }

    private var draft: TripHiddenParts {
        get { editorModel.draft }
        set { editorModel.draft = newValue }
    }

    private var resolution: HiddenPartsResolution {
        HiddenPartsResolver.resolve(
            points: trip.trackPoints, recordingBreaks: trip.recordingBreaks,
            startMetres: draft.startMetres ?? PrivacySettings.load().edgeMetres ?? 0,
            endMetres: draft.endMetres ?? PrivacySettings.load().edgeMetres ?? 0,
            sections: draft.sections, zone: HomeSettings.load().activeZone)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language
        VStack(spacing: 0) {
            map(c)
                .frame(height: 210)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Capsule()
                        .fill(c.textTertiary.opacity(0.45))
                        .frame(width: 38, height: 5)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .padding(.top, 2)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                            guard value.translation.height > 65 else { return }
                            editorModel.cancel()
                            dismiss()
                        })
                        .accessibilityLabel(AppStrings.closeSheet(l))
                    header(c, l)
                    Text(summary(l))
                        .font(.inter(13, weight: .medium)).foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    tripBar(c, l)
                    edgePicker(title: AppStrings.hiddenStart(l), value: draft.startMetres,
                               choice: .start, c: c, l: l)
                    edgePicker(title: AppStrings.hiddenEnd(l), value: draft.endMetres,
                               choice: .end, c: c, l: l)
                    sections(c, l)
                    numberChoice(c, l)
                    localOnlyCard(c, l)
                    Toggle(AppStrings.hiddenShowPublic(l), isOn: $mapShowsPublic)
                        .font(.inter(14, weight: .semibold)).tint(AppTheme.accent)
                        .padding(14).background(c.card, in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityIdentifier("hidden_preview_toggle")
                    if shouldShowTitleHint {
                        Button { Haptics.tap(); dismiss(); onRename() } label: {
                            HStack(spacing: 5) {
                                Text(titleHint(l))
                            }
                            .font(.inter(12.5)).foregroundStyle(c.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PressableCardStyle())
                    }
                    if trip.isOnServer && !trip.isPrivate {
                        Text(AppStrings.hiddenAlreadySeen(l))
                            .font(.inter(12.5)).foregroundStyle(c.textSecondary)
                    }
                    if trip.trackPoints.isEmpty {
                        Text(AppStrings.hiddenLocalOnlyNotice(l))
                            .font(.inter(12.5)).foregroundStyle(c.textSecondary)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(c.bg.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier("hidden_parts_editor")
        .sheet(item: Binding(get: { choosing.map(ChoiceSheet.init) }, set: { choosing = $0?.choice })) { sheet in
            SettingsOptionPicker(
                title: AppStrings.hiddenChooseEdge(lang.language),
                options: presets,
                selection: selectedValue(for: sheet.choice),
                footnote: AppStrings.hiddenTapMapHint(lang.language),
                badge: { Measure.distance(metres: Double($0), unit: distanceUnit, lang: lang.language) },
                label: { $0 == 0 ? AppStrings.hiddenNone(lang.language) : Measure.distance(metres: Double($0), unit: distanceUnit, lang: lang.language) },
                onSelect: { value in applyPreset(value, to: sheet.choice) },
                accessibilityPrefix: "hidden_edge"
            )
        }
    }

    private func map(_ c: AppTheme.Colors) -> some View {
        let points = mapShowsPublic ? resolution.visiblePoints : trip.trackPoints
        let breaks = mapShowsPublic ? resolution.previewBreaks : []
        return RouteMapView(coordinates: points.map(\.coordinate),
                            speeds: points.map(\.speed), routeBreaks: breaks,
                            hiddenRuns: mapShowsPublic ? [] : resolution.hiddenRuns.map { $0.map(\.coordinate) },
                            hiddenLockPoints: mapShowsPublic ? [] : resolution.lockPoints,
                            hiddenLockAccessibilityLabel: AppStrings.hiddenRouteLockAccessibility(lang.language),
                            isInteractive: true,
                            onRouteTap: { coordinate, _ in selectRoutePoint(coordinate) },
                            showsFog: false, elevationStyle: .flat,
                            treatAsPreview: false)
            .overlay(alignment: .bottom) {
                if let choosing {
                    Text(instruction(for: choosing, lang: lang.language))
                        .font(.inter(13, weight: .semibold)).foregroundStyle(c.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(c.card, in: Capsule()).padding(.bottom, 10)
                }
            }
    }

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack {
            Text(AppStrings.hiddenEditorTitle(l)).font(.inter(20, weight: .bold)).foregroundStyle(c.text)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button { Haptics.tap(); onSave(editorModel.apply()); dismiss() } label: {
                Text(AppStrings.done(l)).font(.inter(15, weight: .bold)).foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("hidden_editor_done")
        }
    }

    private func tripBar(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(c.cardAlt).frame(height: 14)
                if !trip.trackPoints.isEmpty {
                    let sampleStride = max(1, trip.trackPoints.count / 48)
                    ForEach(Array(stride(from: 0, to: trip.trackPoints.count, by: sampleStride)), id: \.self) { index in
                        let band = SpeedColorScale.bands[SpeedColorScale.zone(forSpeedMS: trip.trackPoints[index].speed)]
                        Rectangle().fill(band.color)
                            .frame(width: max(2, width * CGFloat(sampleStride) / CGFloat(trip.trackPoints.count)), height: 14)
                            .offset(x: width * CGFloat(index) / CGFloat(trip.trackPoints.count))
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
            HStack { Text(clock(trip.startDate)); Spacer(); Text(clock(trip.endDate ?? trip.startDate)) }
                .font(.inter(10, weight: .medium)).foregroundStyle(c.textTertiary)
                .offset(y: 15)
        }
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hidden_trip_bar")
    }

    private func edgePicker(title: String, value: Int?, choice: EdgeChoice, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.inter(14, weight: .semibold)).foregroundStyle(c.textSecondary)
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { metres in
                    let isSelected = (value ?? PrivacySettings.load().edgeMetres ?? 0) == metres
                    Button { Haptics.selection(); applyPreset(metres, to: choice) } label: {
                        Text(metres == 0 ? AppStrings.hiddenNone(l) : Measure.distance(metres: Double(metres), unit: distanceUnit, lang: l))
                            .font(.inter(12, weight: .semibold)).foregroundStyle(isSelected ? .white : c.text)
                            .padding(.horizontal, 11).padding(.vertical, 9)
                            .background(isSelected ? AppTheme.accent : c.card, in: Capsule())
                    }.buttonStyle(PressableCardStyle())
                }
            }
            if value == nil {
                Text(AppStrings.hiddenDefault(l)).font(.inter(11.5)).foregroundStyle(c.textTertiary)
            }
        }
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
                Haptics.tap(); firstSectionFix = nil; choosing = .sectionStart
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
            Text(AppStrings.hiddenNumbersPreview(l, distance: visibleDistance(), duration: visibleDuration()))
                .font(.inter(12)).foregroundStyle(c.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func localOnlyCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let photoCount = trip.photos.filter { photo in
            HiddenPartsResolver.photoIsHidden(capturedAt: photo.capturedAt, coordinate: photo.exifCoordinate,
                                              resolution: resolution, points: trip.trackPoints, zone: HomeSettings.load().activeZone)
        }.count
        return VStack(alignment: .leading, spacing: 5) {
            Text(AppStrings.hiddenLocalCardTitle(l)).font(.inter(14, weight: .bold)).foregroundStyle(c.text)
            Text(AppStrings.hiddenLocalCardBody(l, pieces: resolution.hiddenRanges.count, photos: photoCount))
                .font(.inter(12.5)).foregroundStyle(c.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(c.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var shouldShowTitleHint: Bool {
        !trip.titleIsCustom && ((draft.startMetres ?? PrivacySettings.load().edgeMetres ?? 0) > 0 || (draft.endMetres ?? PrivacySettings.load().edgeMetres ?? 0) > 0)
    }

    private func titleHint(_ language: LanguageManager.Language) -> String {
        let hidesStart = (draft.startMetres ?? PrivacySettings.load().edgeMetres ?? 0) > 0
        return hidesStart
            ? AppStrings.hiddenTitleHintStart(language, title: trip.title ?? "")
            : AppStrings.hiddenTitleHint(language, title: trip.title ?? "")
    }

    private func summary(_ l: LanguageManager.Language) -> String {
        AppStrings.hiddenSummary(l, start: formatMetres(draft.startMetres), end: formatMetres(draft.endMetres), sections: draft.sections.count)
    }

    private func formatMetres(_ value: Int?) -> String {
        let metres = value ?? PrivacySettings.load().edgeMetres ?? 0
        return metres == 0 ? AppStrings.hiddenNone(lang.language) : Measure.distance(metres: Double(metres), unit: distanceUnit, lang: lang.language)
    }

    private func position(_ date: Date) -> CGFloat {
        let start = trip.startDate.timeIntervalSince1970
        let end = (trip.endDate ?? trip.trackPoints.last?.timestamp ?? trip.startDate).timeIntervalSince1970
        guard end > start else { return 0 }
        return CGFloat(min(1, max(0, (date.timeIntervalSince1970 - start) / (end - start))))
    }

    private func clock(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func sectionDistance(_ section: HiddenSection) -> String {
        let selected = trip.trackPoints.filter { section.from <= $0.timestamp && $0.timestamp <= section.to }
        let metres = zip(selected, selected.dropFirst()).reduce(0.0) { total, pair in total + GeometryUtils.haversineDistance(pair.0.coordinate, pair.1.coordinate) }
        return Measure.distance(metres: metres, unit: distanceUnit, lang: lang.language)
    }

    private func visibleDistance() -> String {
        let metres = resolution.visibleRuns.reduce(0.0) { sum, run in
            sum + zip(run, run.dropFirst()).reduce(0.0) { $0 + GeometryUtils.haversineDistance($1.0.coordinate, $1.1.coordinate) }
        }
        return Measure.distance(metres: metres, unit: distanceUnit, lang: lang.language)
    }

    private func visibleDuration() -> String {
        let seconds = resolution.visibleRuns.reduce(0.0) { $0 + (($1.last?.timestamp.timeIntervalSince($1.first?.timestamp ?? $1[0].timestamp)) ?? 0) }
        return Trip.formattedTimeHuman(seconds, lang: lang.language)
    }

    private func handleDrag(_ id: UUID, movingStart: Bool, width: CGFloat, initialDate: Date) -> some Gesture {
        DragGesture(minimumDistance: 3).onChanged { value in
            guard width > 0 else { return }
            let ratio = min(1, max(0, position(initialDate) + value.translation.width / width))
            let index = Int(ratio * CGFloat(max(0, trip.trackPoints.count - 1)))
            guard trip.trackPoints.indices.contains(index) else { return }
            let time = trip.trackPoints[index].timestamp
            guard let item = draft.sections.firstIndex(where: { $0.id == id }) else { return }
            editorModel.moveBoundary(id, to: time, movingStart: movingStart)
        }
    }

    private func selectRoutePoint(_ coordinate: CLLocationCoordinate2D) {
        let fix = TripRouteLocator.Index(points: trip.trackPoints, startDate: trip.startDate).passes(near: coordinate).first
        guard let fix else { return }
        Haptics.selection()
        switch choosing {
        case .sectionStart:
            firstSectionFix = fix; choosing = .sectionEnd
        case .sectionEnd:
            guard let first = firstSectionFix else { return }
            let from = min(first.timestamp, fix.timestamp), to = max(first.timestamp, fix.timestamp)
            guard from < to else { return }
            editorModel.addSection(from: from, to: to)
            firstSectionFix = nil; choosing = nil
        default: break
        }
    }

    private func applyPreset(_ metres: Int, to choice: EdgeChoice) {
        switch choice {
        case .start: editorModel.setStartPreset(metres)
        case .end: editorModel.setEndPreset(metres)
        case .sectionStart: choosing = .sectionStart
        case .sectionEnd: choosing = .sectionEnd
        }
    }

    private func selectedValue(for choice: EdgeChoice) -> Int {
        switch choice {
        case .start: return draft.startMetres ?? PrivacySettings.load().edgeMetres ?? 0
        case .end: return draft.endMetres ?? PrivacySettings.load().edgeMetres ?? 0
        default: return 0
        }
    }

    private func instruction(for choice: EdgeChoice, lang: LanguageManager.Language) -> String {
        switch choice {
        case .sectionStart: return AppStrings.hiddenTapStart(lang)
        case .sectionEnd: return AppStrings.hiddenTapEnd(lang)
        default: return AppStrings.hiddenTapMapHint(lang)
        }
    }

}

fileprivate struct ChoiceSheet: Identifiable {
    let choice: HiddenPartsEditorView.EdgeChoice
    var id: String { String(describing: choice) }
    init(_ choice: HiddenPartsEditorView.EdgeChoice) { self.choice = choice }
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
