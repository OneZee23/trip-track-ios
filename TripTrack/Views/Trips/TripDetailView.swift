import SwiftUI
import MapKit

struct TripDetailView: View {
    let tripId: UUID
    @ObservedObject var viewModel: TripsViewModel
    @State private var trip: Trip?
    @State private var showPhotoPicker = false
    @State private var pickedImages: [UIImage] = []
    @State private var selectedPhotoIndex: Int?
    @State private var selectedDetailBadge: Badge?
    @State private var badgeLastEarnedDates: [String: Date] = [:]
    @State private var photoToDelete: TripPhoto?
    @State private var toastItem: ToastItem?
    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var originalTitle: String = ""
    @State private var cachedCoordinates: [CLLocationCoordinate2D] = []
    @State private var cachedSpeeds: [Double] = []
    @FocusState private var isTitleFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @ObservedObject private var settings = SettingsManager.shared

    private var mapBaseHeight: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.bounds.height ?? 844) * 0.45
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        ZStack(alignment: .topLeading) {
            if let trip {
                ScrollView {
                    VStack(spacing: 0) {
                        // Interactive map
                        Group {
                            if cachedCoordinates.count > 1 {
                                RouteMapView(
                                    coordinates: cachedCoordinates,
                                    speeds: cachedSpeeds,
                                    isInteractive: true,
                                    fogCutoffDate: trip.endDate
                                )
                            } else {
                                c.cardAlt
                                    .overlay {
                                        Image(systemName: "map")
                                            .font(.largeTitle)
                                            .foregroundStyle(c.textTertiary)
                                    }
                            }
                        }
                        .frame(height: mapBaseHeight)

                        // Bottom info panel
                        infoPanel(trip: trip, c: c)
                            .background(c.bg)
                    }
                    .background(alignment: .top) {
                        Color(UIColor(white: 0.12, alpha: 1.0))
                            .frame(height: mapBaseHeight + 1000)
                            .offset(y: -1000)
                    }
                }
                .coordinateSpace(name: "detailScroll")
                .scrollIndicators(.hidden)
                .background(ScrollBounceDisabler())

                // Sticky back button — outside ScrollView
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .padding(.top, safeAreaTop)
                .padding(.leading, 16)
            } else {
                // Loading skeleton
                VStack(spacing: 0) {
                    c.cardAlt
                        .frame(height: mapBaseHeight)
                        .shimmer()
                        .overlay { CarLoadingView() }
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 200, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 160, height: 20)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(0..<6, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 16).fill(c.cardAlt).frame(height: 80)
                            }
                        }
                    }
                    .padding(16)
                    .shimmer()
                    Spacer()
                }
            }
        }
        .background(c.bg)
        .background(EnableSwipeBack())
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .task(id: tripId) {
            guard trip == nil else { return }
            trip = viewModel.tripDetail(id: tripId)
            if let t = trip {
                cachedCoordinates = t.trackPoints.map(\.coordinate)
                cachedSpeeds = t.trackPoints.map(\.speed)
            }
            badgeLastEarnedDates = BadgeManager.lastEarnedDates(for: trip?.earnedBadgeIds ?? [], using: mapVM.tripManager)
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView(selectedImages: $pickedImages)
        }
        .onChange(of: pickedImages) { newImages in
            for image in newImages {
                if let photo = mapVM.tripManager.addPhoto(to: tripId, image: image) {
                    trip?.photos.append(photo)
                }
            }
            pickedImages = []
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedPhotoIndex != nil },
            set: { if !$0 { selectedPhotoIndex = nil } }
        )) {
            if let photos = trip?.photos, let index = selectedPhotoIndex {
                PhotoFullScreenView(
                    photos: photos,
                    initialIndex: index,
                    onDismiss: { selectedPhotoIndex = nil }
                )
            }
        }
        .overlay {
            if let badge = selectedDetailBadge {
                BadgeDetailOverlay(
                    badge: badge,
                    isUnlocked: true,
                    language: lang.language,
                    colorScheme: scheme,
                    lastEarnedDate: badgeLastEarnedDates[badge.id],
                    onDismiss: { selectedDetailBadge = nil }
                )
            }
        }
        .toast(item: $toastItem)
        .confirmationDialog(
            AppStrings.deletePhoto(lang.language),
            isPresented: Binding(
                get: { photoToDelete != nil },
                set: { if !$0 { photoToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(lang.language), role: .destructive) {
                if let photo = photoToDelete {
                    Haptics.action()
                    mapVM.tripManager.deletePhoto(id: photo.id, from: tripId)
                    trip?.photos.removeAll { $0.id == photo.id }
                    toastItem = ToastItem(
                        type: .success,
                        message: AppStrings.photoDeleted(lang.language)
                    )
                }
                photoToDelete = nil
            }
        }
    }

    // MARK: - Info Panel

    @ViewBuilder
    private func infoPanel(trip: Trip, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date + time + vehicle + share button
            HStack(alignment: .top) {
                dateTimeLine(trip: trip, c: c)
                Spacer()
                ShareLink(item: shareTripText(trip)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 32, height: 32)
                        .background(c.cardAlt, in: Circle())
                }
            }
            .padding(.bottom, 8)

            // Title with edit button
            titleSection(trip: trip, c: c)

            statsGrid(trip: trip, c: c)
                .padding(.top, 16)

            badgesSection(trip: trip, c: c)

            photosSection(c)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, safeAreaBottom + 90)
        .background(c.bg)
    }

    private func dateTimeLine(trip: Trip, c: AppTheme.Colors) -> some View {
        let datePart = formattedDate(trip.startDate)
        let timePart = timeRange(trip)

        var vehiclePart = ""
        if let vehicle = tripVehicle {
            let emoji = vehicle.isPixelAvatar ? "🚗" : vehicle.avatarEmoji
            vehiclePart = " · \(emoji) \(vehicle.name)"
        }

        return Text("\(datePart), \(timePart)\(vehiclePart)")
            .font(.system(size: 13))
            .foregroundStyle(c.textSecondary)
    }

    private var tripVehicle: Vehicle? {
        if let vid = trip?.vehicleId {
            return settings.vehicles.first { $0.id == vid }
        }
        return nil
    }

    private func titleSection(trip: Trip, c: AppTheme.Colors) -> some View {
        HStack {
            if isEditingTitle {
                TextField(
                    AppStrings.tripTitlePlaceholder(lang.language),
                    text: $editedTitle
                )
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(c.text)
                .focused($isTitleFieldFocused)
                .onSubmit { commitTitleEdit() }
                .transition(.opacity)
            } else {
                Text(trip.title ?? formattedDateFallback(trip.startDate))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(c.text)
                    .transition(.opacity)
            }

            Spacer()

            if isEditingTitle {
                // Cancel button
                Button {
                    Haptics.tap()
                    cancelTitleEdit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(c.textTertiary)
                }

                // Save button
                Button {
                    Haptics.action()
                    commitTitleEdit()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.green)
                }
            } else {
                Button {
                    Haptics.tap()
                    editedTitle = trip.title ?? ""
                    originalTitle = editedTitle
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isEditingTitle = true
                    }
                    isTitleFieldFocused = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 18))
                        .foregroundStyle(c.textTertiary)
                }
            }
        }
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.25), value: isEditingTitle)
    }

    private func commitTitleEdit() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            mapVM.tripManager.updateTitle(for: tripId, title: trimmed)
            trip = viewModel.tripDetail(id: tripId)
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditingTitle = false
        }
        isTitleFieldFocused = false
    }

    private func cancelTitleEdit() {
        editedTitle = originalTitle
        withAnimation(.easeInOut(duration: 0.25)) {
            isEditingTitle = false
        }
        isTitleFieldFocused = false
    }

    private func statsGrid(trip: Trip, c: AppTheme.Colors) -> some View {
        let l = lang.language
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            DetailStatCard(
                value: String(format: "%.1f %@", trip.distanceKm, AppStrings.km(l)),
                label: AppStrings.distance(l),
                color: AppTheme.green,
                staggerIndex: 0
            )
            DetailStatCard(
                value: trip.formattedDurationHuman(l),
                label: AppStrings.duration(l),
                color: AppTheme.accent,
                staggerIndex: 1
            )
            DetailStatCard(
                value: String(format: "%.0f %@", trip.averageSpeedKmh, AppStrings.kmh(l)),
                label: AppStrings.avgSpeed(l),
                color: AppTheme.blue,
                staggerIndex: 2
            )
            DetailStatCard(
                value: String(format: "%.0f %@", trip.maxSpeedKmh, AppStrings.kmh(l)),
                label: AppStrings.maxSpeed(l),
                color: AppTheme.red,
                staggerIndex: 3
            )
            DetailStatCard(
                value: String(format: "%.0f %@", elevationGain(trip), AppStrings.m(l)),
                label: AppStrings.elevationGain(l),
                color: AppTheme.green,
                staggerIndex: 4
            )
            DetailStatCard(
                value: String(format: "%.0f %@", maxAltitude(trip), AppStrings.m(l)),
                label: AppStrings.maxAltitude(l),
                color: AppTheme.blue,
                staggerIndex: 5
            )

            // Fuel consumption (if vehicle configured)
            if let fuel = tripFuelInfo(trip) {
                DetailStatCard(
                    value: String(format: "~%.1f %@", fuel.volume, fuel.volUnit),
                    label: l == .ru ? "Расход" : "Fuel",
                    color: AppTheme.yellow,
                    staggerIndex: 6
                )
                DetailStatCard(
                    value: String(format: "~%.0f %@", fuel.cost, fuel.currency),
                    label: l == .ru ? "Стоимость" : "Cost",
                    color: AppTheme.accent,
                    staggerIndex: 7
                )
            }
        }
    }

    private func tripFuelInfo(_ trip: Trip) -> (volume: Double, cost: Double, volUnit: String, currency: String)? {
        let vehicle: Vehicle?
        if let vid = trip.vehicleId {
            vehicle = settings.vehicles.first { $0.id == vid }
        } else {
            vehicle = nil
        }
        guard let v = vehicle, v.cityConsumption > 0, trip.distanceKm > 0.1 else { return nil }
        let fuel = v.fuelCost(distanceKm: trip.distanceKm, avgSpeedKmh: trip.averageSpeedKmh)

        let volumeUnit = UserDefaults.standard.string(forKey: "volumeUnit") ?? "liters"
        let currency = trip.fuelCurrency ?? FuelCurrency.current
        let volShort = volumeUnit == "gallons" ? (lang.language == .ru ? "гал" : "gal") : (lang.language == .ru ? "л" : "L")

        let volume: Double
        if volumeUnit == "gallons" {
            volume = fuel.liters / 3.78541
        } else {
            volume = fuel.liters
        }

        return (volume, fuel.cost, volShort, currency)
    }

    // MARK: - Badges Section

    @ViewBuilder
    private func badgesSection(trip: Trip, c: AppTheme.Colors) -> some View {
        if !trip.earnedBadgeIds.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.badges(lang.language))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.textSecondary)

                TripBadgesRow(
                    badgeIds: trip.earnedBadgeIds,
                    maxVisible: 8,
                    size: 36,
                    onTap: { badge in selectedDetailBadge = badge }
                )
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Photos Section

    private func photosSection(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(AppStrings.photos(lang.language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.text)
                Spacer()
                Button { showPhotoPicker = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.accent)
                }
            }

            if let photos = trip?.photos, !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            AsyncThumbnailView(filename: photo.filename)
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .onTapGesture {
                                    selectedPhotoIndex = index
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photoToDelete = photo
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(4)
                                }
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "camera")
                            .font(.system(size: 24))
                            .foregroundStyle(c.textTertiary)
                        Text(AppStrings.addPhotos(lang.language))
                            .font(.system(size: 12))
                            .foregroundStyle(c.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
                .surfaceCard(cornerRadius: 12)
                .onTapGesture { showPhotoPicker = true }
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Helpers

    private static let dateFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM yyyy"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM yyyy"
        return (ru, en)
    }()

    private static let dateTimeFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM, HH:mm"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM, HH:mm"
        return (ru, en)
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func formattedDate(_ date: Date) -> String {
        let fmts = Self.dateFormatters
        return (lang.language == .ru ? fmts.ru : fmts.en).string(from: date)
    }

    private func formattedDateFallback(_ date: Date) -> String {
        let fmts = Self.dateTimeFormatters
        return (lang.language == .ru ? fmts.ru : fmts.en).string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private func elevationGain(_ trip: Trip) -> Double {
        guard trip.trackPoints.count > 1 else { return 0 }
        var gain: Double = 0
        for i in 1..<trip.trackPoints.count {
            let delta = trip.trackPoints[i].altitude - trip.trackPoints[i-1].altitude
            if delta > 0 { gain += delta }
        }
        return gain
    }

    private func maxAltitude(_ trip: Trip) -> Double {
        trip.trackPoints.map(\.altitude).max() ?? 0
    }

    private func timeRange(_ trip: Trip) -> String {
        let start = Self.timeFormatter.string(from: trip.startDate)
        if let end = trip.endDate {
            return "\(start) – \(Self.timeFormatter.string(from: end))"
        }
        return start
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 59
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    private func shareTripText(_ trip: Trip) -> String {
        let l = lang.language
        let title = trip.title ?? formattedDateFallback(trip.startDate)
        let date = formattedDate(trip.startDate)
        let dist = String(format: "%.1f %@", trip.distanceKm, AppStrings.km(l))
        let time = trip.formattedDurationHuman(l)
        let speed = String(format: "%.0f %@", trip.averageSpeedKmh, AppStrings.kmh(l))

        if l == .ru {
            return "\(title)\n\(date)\n\nДистанция: \(dist)\nВремя: \(time)\nСр. скорость: \(speed)\n\n— TripTrack"
        } else {
            return "\(title)\n\(date)\n\nDistance: \(dist)\nTime: \(time)\nAvg speed: \(speed)\n\n— TripTrack"
        }
    }
}

// MARK: - Detail Stat Card

private struct DetailStatCard: View {
    let value: String
    let label: String
    let color: Color
    var staggerIndex: Int = 0
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.colors(for: scheme).textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .surfaceCard(cornerRadius: 16)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(Double(staggerIndex) * 0.05)) {
                appeared = true
            }
        }
    }
}

// MARK: - Swipe Back Helper

private struct EnableSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        SwipeBackController()
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

private class SwipeBackController: UIViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
    }
}

// MARK: - Disable ScrollView Bounce

private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> ScrollBounceFinderView {
        ScrollBounceFinderView()
    }
    func updateUIView(_ uiView: ScrollBounceFinderView, context: Context) {}
}

private class ScrollBounceFinderView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        var current: UIView? = self
        while let parent = current?.superview {
            if let scrollView = parent as? UIScrollView {
                scrollView.bounces = false
                return
            }
            current = parent
        }
    }
}

