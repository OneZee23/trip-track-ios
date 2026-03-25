import SwiftUI

struct FeedView: View {
    @StateObject private var feedVM: FeedViewModel
    @ObservedObject private var settings = SettingsManager.shared
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Binding var selectedTab: Int
    @State private var selectedTripId: UUID?
    @State private var didLoad = false
    @State private var showStats = false
    @State private var showBadges = false
    @State private var showSettings = false
    @State private var showProfile = false
    @State private var showGarage = false
    @State private var tripToDelete: Trip?
    @State private var collapsedSections: Set<String> = []

    init(tripManager: TripManager, selectedTab: Binding<Int>) {
        _feedVM = StateObject(wrappedValue: FeedViewModel(tripManager: tripManager))
        _selectedTab = selectedTab
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ZStack(alignment: .bottom) {
        NavigationStack {
            ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ContributionCalendarView(
                        dateFrom: Binding(
                            get: { feedVM.filters.dateFrom },
                            set: { newDate in
                                feedVM.setDateRange(from: newDate, to: feedVM.filters.dateTo)
                            }
                        ),
                        dateTo: Binding(
                            get: { feedVM.filters.dateTo },
                            set: { newDate in
                                feedVM.setDateRange(from: feedVM.filters.dateFrom, to: newDate)
                            }
                        ),
                        language: lang.language,
                        maxKmDay: feedVM.maxKmDay,
                        kmByDay: { feedVM.kmByDay(for: $0) }
                    )
                    .padding(.top, 4)
                    .id("feedTop")

                    quickStats(c)

                    filterBar(c)
                        .padding(.top, 2)

                    tripSections(c)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .onReceive(NotificationCenter.default.publisher(for: .feedScrollToTop)) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollProxy.scrollTo("feedTop", anchor: .top)
                }
            }
            } // ScrollViewReader
            .navigationDestination(isPresented: Binding(
                get: { selectedTripId != nil },
                set: { if !$0 { selectedTripId = nil } }
            )) {
                if let id = selectedTripId {
                    TripDetailView(tripId: id, viewModel: TripsViewModel(tripManager: feedVM.tripManager))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("PixelCar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        VStack(spacing: 1) {
                            Text("ROAD  TRIP")
                                .font(.custom("PressStart2P-Regular", size: 10))
                                .foregroundStyle(AppTheme.accent)
                            Text("TRACKER")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(c.textTertiary)
                                .tracking(2)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showProfile = true } label: {
                        Text(settings.avatarEmoji)
                            .font(.system(size: 22))
                            .frame(width: 38, height: 38)
                            .background(c.cardAlt, in: Circle())
                    }
                }
            }
            .toolbarBackground(c.bg.opacity(0.95), for: .navigationBar)
            .toolbarBackground(.automatic, for: .navigationBar)
        }
        .toast(item: $feedVM.toastItem)
        .refreshable { feedVM.language = lang.language; feedVM.loadTrips() }
        .onAppear { if !didLoad { didLoad = true; feedVM.language = lang.language; feedVM.loadTrips() } }
        .sheet(isPresented: $feedVM.showFilters) {
            FilterSheetView(
                filters: $feedVM.filters,
                regions: feedVM.uniqueRegions,
                onApply: {
                    feedVM.applyFilters()
                    feedVM.showFilters = false
                },
                onResetSecondary: {
                    feedVM.resetSecondaryFilters()
                    feedVM.showFilters = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStats) {
            StatsView(tripManager: feedVM.tripManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToFeedWithRegionFilter)) { notif in
            if let region = notif.object as? String {
                feedVM.setRegionFilter(region)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(themeManager.preferredColorScheme)
        }
        .sheet(isPresented: $showGarage) {
            GarageView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            AppStrings.deleteTrip(lang.language),
            isPresented: Binding(
                get: { tripToDelete != nil },
                set: { if !$0 { tripToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete(lang.language), role: .destructive) {
                if let trip = tripToDelete {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        feedVM.softDeleteTrip(trip)
                    }
                }
                tripToDelete = nil
            }
            Button(AppStrings.cancel(lang.language), role: .cancel) {
                tripToDelete = nil
            }
        }

        // Recording banner overlay
        if mapVM.isRecording {
            RecordingBanner(
                distance: mapVM.distance,
                duration: mapVM.duration,
                onTap: { selectedTab = 1 }
            )
            .padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: mapVM.isRecording)
        }
        } // ZStack
    }

    // MARK: - Trip Sections

    @ViewBuilder
    private func tripSections(_ c: AppTheme.Colors) -> some View {
        if feedVM.trips.isEmpty {
            FeedEmptyStateView(
                hasFilters: feedVM.filters.isActive,
                onStartTrip: { selectedTab = 1 },
                onResetFilters: { feedVM.resetFilters() }
            )
        } else {
            ForEach(feedVM.sections) { section in
                sectionHeader(section, c: c)

                if !collapsedSections.contains(section.id) {
                    ForEach(section.trips) { trip in
                        tripCard(trip, c: c)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ section: TripSection, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.25)) {
                if collapsedSections.contains(section.id) {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        } label: {
            HStack {
                Text(section.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(c.textTertiary)
                    .tracking(0.5)
                Spacer()
                Image(systemName: collapsedSections.contains(section.id) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var activeVehicle: Vehicle? {
        if let id = settings.selectedVehicleId {
            return settings.vehicles.first { $0.id == id }
        }
        return settings.vehicles.first
    }

    private func tripCard(_ trip: Trip, c: AppTheme.Colors) -> some View {
        SwipeToDeleteCard(
            onTap: {
                Haptics.tap()
                selectedTripId = trip.id
            },
            onDelete: {
                Haptics.action()
                tripToDelete = trip
            }
        ) {
            FeedTripCardView(
                trip: trip,
                vehicleName: activeVehicle?.name,
                vehicleEmoji: activeVehicle?.avatarEmoji ?? settings.avatarEmoji,
                vehicle: activeVehicle,
                fuelCurrency: "₽"
            )
        }
        .onAppear {
            feedVM.loadMoreIfNeeded(currentTrip: trip)
        }
    }

    // MARK: - Quick Stats

    private func quickStats(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            statPill(
                label: AppStrings.trips(lang.language),
                value: "\(feedVM.totalTripCount)",
                color: AppTheme.accent,
                c: c
            )
            statPill(
                label: AppStrings.km(lang.language),
                value: String(format: "%.0f", feedVM.totalKm),
                color: c.text,
                c: c
            )
            statPill(
                label: AppStrings.time(lang.language),
                value: feedVM.formattedTotalTime,
                color: c.text,
                c: c
            )
        }
    }

    private func statPill(label: String, value: String, color: Color, c: AppTheme.Colors) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 12)
    }

    // MARK: - Filter Bar

    private func filterBar(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            Button {
                feedVM.showFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14))
                    .glassPill(isActive: feedVM.filters.isActive)
            }
            .buttonStyle(.plain)

            if let region = feedVM.filters.region {
                Button {
                    feedVM.setRegionFilter(nil)
                } label: {
                    HStack(spacing: 4) {
                        Text(region)
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .glassPill(isActive: true)
                }
                .buttonStyle(.plain)
            }

            if feedVM.filters.hasDateFilter {
                Button {
                    feedVM.setDateRange(from: nil, to: nil)
                } label: {
                    HStack(spacing: 4) {
                        Text(dateChipText)
                        Image(systemName: "xmark")
                            .font(.system(size: 12))
                    }
                    .glassPill(isActive: true)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    // MARK: - Empty State (replaced by FeedEmptyStateView)

    // MARK: - Helpers

    private func animationDelay(for trip: Trip) -> Double {
        guard let index = feedVM.trips.firstIndex(where: { $0.id == trip.id }) else { return 0 }
        return min(Double(index) * 0.05, 0.5)
    }

    private static let chipDateFormatters: (ru: DateFormatter, en: DateFormatter) = {
        let ru = DateFormatter()
        ru.locale = Locale(identifier: "ru_RU")
        ru.dateFormat = "d MMM"
        let en = DateFormatter()
        en.locale = Locale(identifier: "en_US")
        en.dateFormat = "d MMM"
        return (ru, en)
    }()

    private var dateChipText: String {
        let formatter = lang.language == .ru ? Self.chipDateFormatters.ru : Self.chipDateFormatters.en
        guard let from = feedVM.filters.dateFrom else { return "" }
        let fromStr = formatter.string(from: from)
        guard let to = feedVM.filters.dateTo else { return fromStr }
        if Calendar.current.isDate(from, inSameDayAs: to) {
            return fromStr
        }
        return "\(fromStr) – \(formatter.string(from: to))"
    }
}
