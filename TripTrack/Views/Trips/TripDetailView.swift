import SwiftUI
import MapKit

struct TripDetailView: View {
    let tripId: UUID
    @ObservedObject var viewModel: TripsViewModel
    /// When present, reactor-avatar taps push onto this shared path
    /// (capped via `cappedAppend`) instead of attaching a local
    /// `.navigationDestination(isPresented:)`. Using the typed path dodges
    /// the SwiftUI NavigationStack flash at depth 4+ that the chained
    /// isPresented approach was triggering from Feed → Trip → Profile → …
    var pushPath: Binding<[ProfilePreviewDest]>?
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
    @State private var storyShare: (data: StoryShareData, url: String?)?
    @State private var isGeneratingShare = false
    @State private var showDeleteConfirm = false
    @State private var reactionEntries: [SocialReactionEntry] = []
    @State private var selectedReactorAuthor: SocialAuthor?
    @State private var isMapFullscreen = false
    @ObservedObject private var auth = AuthService.shared
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
                        // Interactive map + corner "expand" button that
                        // presents the route in a fullscreen cover. The button
                        // only appears when we actually have a route — no
                        // point letting the user expand the blank-map fallback.
                        ZStack(alignment: .bottomTrailing) {
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

                            if cachedCoordinates.count > 1 {
                                Button {
                                    Haptics.tap()
                                    isMapFullscreen = true
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(.black.opacity(0.45), in: Circle())
                                }
                                .padding(.trailing, 12)
                                .padding(.bottom, 12)
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

                // Sticky back button + menu — outside ScrollView, floating over the map
                HStack {
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

                    Spacer()

                    Menu {
                        Button {
                            Haptics.tap()
                            Task { await openStoryShare(for: trip) }
                        } label: {
                            Label(
                                lang.language == .ru ? "Поделиться" : "Share",
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .disabled(isGeneratingShare)
                        Button(role: .destructive) {
                            Haptics.action()
                            showDeleteConfirm = true
                        } label: {
                            Label(
                                AppStrings.delete(lang.language),
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
                .padding(.top, safeAreaTop)
                .padding(.horizontal, 16)
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
        .background(NavBarKiller())
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .modifier(TripDetailLocalReactorDestination(
            selectedReactorAuthor: $selectedReactorAuthor,
            enabled: pushPath == nil
        ))
        .hideAppTabBar()
        .fullScreenCover(isPresented: $isMapFullscreen) {
            FullscreenMapSheet(
                coordinates: cachedCoordinates,
                speeds: cachedSpeeds,
                fogCutoffDate: trip?.endDate
            )
        }
        .confirmationDialog(
            AppStrings.deleteTrip(lang.language),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(lang.language), role: .destructive) {
                mapVM.tripManager.deleteTrip(id: tripId)
                NotificationCenter.default.post(name: .tripDeleted, object: tripId)
                dismiss()
            }
            Button(AppStrings.cancel(lang.language), role: .cancel) {}
        }
        .task(id: tripId) {
            if trip == nil {
                trip = viewModel.tripDetail(id: tripId)
                if let t = trip {
                    cachedCoordinates = t.trackPoints.map(\.coordinate)
                    cachedSpeeds = t.trackPoints.map(\.speed)
                }
                badgeLastEarnedDates = BadgeManager.lastEarnedDates(for: trip?.earnedBadgeIds ?? [], using: mapVM.tripManager)
            }
            await loadReactions()
        }
        .onChange(of: trip?.isPrivate) { _, newValue in
            if newValue == false { Task { await loadReactions() } }
            else { reactionEntries = [] }
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
        .sheet(isPresented: Binding(
            get: { storyShare != nil },
            set: { if !$0 { storyShare = nil } }
        )) {
            if let share = storyShare {
                StoryShareSheet(data: share.data, shareUrl: share.url)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .environmentObject(lang)
            }
        }
    }

    // MARK: - Story Share

    private func openStoryShare(for trip: Trip) async {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true
        defer { isGeneratingShare = false }

        let authorName = AuthService.shared.userName
            ?? (lang.language == .ru ? "Моя поездка" : "My trip")
        let authorEmoji = settings.avatarEmoji
        let data = StoryShareData.from(trip, authorName: authorName, authorEmoji: authorEmoji, lang: lang.language)

        // If signed in, try to generate a public share link via the server.
        // If offline or not signed in — fall back to image-only share.
        var url: String?
        if AuthService.shared.isSignedIn {
            do {
                let req = SocialShareRequest(tripId: trip.id, expiresInDays: nil)
                let res: SocialShareResponse = try await APIClient.shared.post(
                    APIEndpoint.socialShare, body: req)
                url = res.shareUrl
            } catch {
                url = nil
            }
        }

        storyShare = (data, url)
    }

    // MARK: - Info Panel

    @ViewBuilder
    private func infoPanel(trip: Trip, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Date + time + vehicle. Share moved to the overflow menu in the
            // top chrome so the info panel reads cleaner — `isGeneratingShare`
            // still gates the Menu item so double-taps don't double-fire.
            dateTimeLine(trip: trip, c: c)
                .padding(.bottom, 8)

            // Title with edit button
            titleSection(trip: trip, c: c)

            privacyToggle(trip: trip, c: c)
                .padding(.top, 10)

            statsGrid(trip: trip, c: c)
                .padding(.top, 16)

            // Reactions from followers show only for public trips of signed-in users.
            if !trip.isPrivate, auth.isSignedIn, !reactionEntries.isEmpty {
                reactionsSection(c)
                    .padding(.top, 16)
            }

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

    private func reactionsSection(_ c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("\(reactionEntries.count)")
                    .font(.system(size: 18, weight: .heavy).monospacedDigit())
                    .foregroundStyle(c.text)
                Text((isRu ? "реакций" : "reactions").uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(c.textTertiary)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(reactionEntries.enumerated()), id: \.offset) { idx, entry in
                    reactionRow(entry, c: c, isRu: isRu)
                    if idx < reactionEntries.count - 1 {
                        Divider().padding(.leading, 50)
                    }
                }
            }
            .surfaceCard(cornerRadius: 14)
        }
    }

    private func reactionRow(_ entry: SocialReactionEntry, c: AppTheme.Colors, isRu: Bool) -> some View {
        Button {
            Haptics.tap()
            if let pushPath {
                pushPath.wrappedValue.cappedAppend(.profile(entry.user.id, entry.user))
            } else {
                selectedReactorAuthor = entry.user
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppTheme.accentBg)
                    .frame(width: 34, height: 34)
                    .overlay { Text(entry.user.avatarEmoji ?? "🚗").font(.system(size: 17)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.user.displayName ?? (isRu ? "Пользователь" : "User"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text("LVL \(entry.user.profileLevel)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(c.textTertiary)
                }
                Spacer()
                Text(entry.emoji).font(.system(size: 22))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func loadReactions() async {
        guard let t = trip, !t.isPrivate, auth.isSignedIn else { return }
        do {
            let res: SocialReactionsResponse = try await APIClient.shared.post(
                APIEndpoint.socialReactions, body: SocialUnreactRequest(tripId: t.id))
            await MainActor.run { reactionEntries = res.reactions }
        } catch {
            // Non-fatal — reactions section just stays hidden
        }
    }

    @ViewBuilder
    private func privacyToggle(trip: Trip, c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        let isPrivate = trip.isPrivate
        // Plain HStack + onTapGesture instead of Button — Button + custom background
        // inside a ScrollView often loses its hit-region in SwiftUI 17/18. The tap
        // gesture on a contentShape'd HStack is dependable.
        HStack(spacing: 6) {
            Image(systemName: isPrivate ? "lock.fill" : "globe")
                .font(.system(size: 11, weight: .semibold))
            Text(isPrivate
                 ? (isRu ? "Только для меня" : "Only me")
                 : (isRu ? "Видна друзьям" : "Visible to followers"))
                .font(.system(size: 12, weight: .semibold))
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(isPrivate ? c.textSecondary : AppTheme.accent)
        .background(
            Capsule().fill(isPrivate ? c.cardAlt : AppTheme.accentBg)
        )
        .contentShape(Capsule())
        .onTapGesture {
            Haptics.selection()
            let newValue = !isPrivate
            mapVM.tripManager.updatePrivacy(for: tripId, isPrivate: newValue)
            self.trip = viewModel.tripDetail(id: tripId)
            // Pass the new privacy state so the feed can optimistically remove/add the
            // card before the server round-trip completes.
            NotificationCenter.default.post(
                name: .tripPrivacyChanged,
                object: PrivacyChangePayload(tripId: tripId, isPrivate: newValue)
            )
        }
    }

    private func commitTitleEdit() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if let err = ContentFilter.validate(trimmed, field: .tripTitle, language: lang.language) {
                toastItem = ToastItem(type: .error, message: err)
                cancelTitleEdit()
                return
            }
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

/// Gates the local-state reactor `.navigationDestination` so SwiftUI only
/// sees it in contexts where we don't have a shared `pushPath` (i.e. the
/// legacy path — which no live flow hits today). When a parent provides a
/// `pushPath`, attaching this modifier would register a second destination
/// on the same NavigationStack and re-expose the depth-4 flash bug.
private struct TripDetailLocalReactorDestination: ViewModifier {
    @Binding var selectedReactorAuthor: SocialAuthor?
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.navigationDestination(isPresented: Binding(
                get: { selectedReactorAuthor != nil },
                set: { if !$0 { selectedReactorAuthor = nil } }
            )) {
                if let author = selectedReactorAuthor {
                    PublicProfileView(accountId: author.id, preloaded: author)
                }
            }
        } else {
            content
        }
    }
}

