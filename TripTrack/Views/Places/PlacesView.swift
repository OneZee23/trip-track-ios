import SwiftUI

/// Вкладка «Места» (0.6.8, S1/S2): карта булавок и список; пусто — сцена
/// `empty_places`. Свой `NavigationStack` с типизированным путём — как у
/// «Я»: экран места и экран поездки пушатся здесь, чужие переходы (чип у
/// отметки в ленте или профиле) приходят двухфазно через `.navigateToPlace`.
///
/// С 0.8.0 экран отвечает не только на «какие места я отметил». Отмечать —
/// ручное действие, о котором человек с одной поездкой не знает, и владелец
/// на устройстве увидел ровно это: «ощущение, что экран пустой». Поэтому под
/// списком стоят ПОДСКАЗКИ (`PlaceSuggestions` — дворы, где поездки
/// начинались и заканчивались), а пока и подсказать нечего — карточка «Как
/// появляются места» с дорогой к последней поездке. Пустая сцена 0.6.2
/// осталась, но одной фразой она больше не ограничивается.
struct PlacesView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @StateObject private var model = PlacesTabViewModel()
    @State private var path: [PlacesDest] = []

    /// Меньше трёх мест — экран ещё не умеет рассказать о себе сам, и
    /// карточка «как это работает» стоит своего места. Подсказки её
    /// отменяют: они объясняют то же самое делом.
    private var showsHowItWorks: Bool { model.items.count < 3 && model.suggestions.isEmpty }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        NavigationStack(path: $path) {
            Group {
                if model.items.isEmpty && model.suggestions.isEmpty {
                    emptyState(c: c, l: l)
                } else {
                    list(c: c, l: l)
                }
            }
            .background(c.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PlacesDest.self) { dest in
                switch dest {
                case .place(let id):
                    PlaceDetailView(placeId: id, onOpenTrip: { push(.trip($0, focus: $1)) })
                        .hideAppTabBar()
                case .trip(let id, let focus):
                    TripDetailView(tripId: id, viewModel: TripsViewModel(tripManager: mapVM.tripManager), focus: focus)
                }
            }
        }
        .task { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPlace)) { note in
            guard let id = note.object as? UUID else { return }
            path = [.place(id)]
        }
    }

    /// Идемпотентный push — быстрый двойной тап по одной и той же булавке
    /// или карточке не должен класть в стек два экземпляра одного экрана:
    /// тогда «назад» пришлось бы жать дважды. Как `ProfileView.push`.
    private func push(_ dest: PlacesDest) {
        guard path.last != dest else { return }
        path.append(dest)
    }

    private func openLastTrip() {
        guard let id = model.lastTripId else { return }
        push(.trip(id, focus: .top))
    }

    private func header(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        HStack {
            Text(AppStrings.tabPlaces(l))
                .font(.inter(28, weight: .heavy))
                .tracking(-0.56)
                .foregroundStyle(c.text)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 10)
    }

    /// Булавки мест И подсказок на ОДНОЙ карте: вторую заводить нельзя,
    /// `PlacesMapView` умеет несколько булавок и подбирает область по всем.
    private var pins: [PlacePin] {
        model.items.map { PlacePin(id: $0.id, coordinate: $0.place.coordinate) }
            + model.suggestions.map { PlacePin(id: $0.id, coordinate: $0.coordinate, isSuggested: true) }
    }

    private func list(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                header(c, l)
                PlacesMapView(pins: pins,
                              // Карта на 220pt живёт внутри списочного ScrollView: с
                              // включённым pan/zoom жест, начатый на карте, панорамирует
                              // её вместо того чтобы скроллить список. isInteractive
                              // гасит только scroll/zoom у MKMapView — тап по булавке
                              // (didSelect) не завязан на эти жесты и продолжает работать.
                              isInteractive: false,
                              onPinTap: { tapped in
                                  // Подсказка — ещё не экран: у неё нет ни истории,
                                  // ни проездов. Открываем только место.
                                  guard model.items.contains(where: { $0.id == tapped }) else { return }
                                  push(.place(tapped))
                              })
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                LazyVStack(spacing: 10) {
                    ForEach(model.items) { item in
                        PlaceCardView(item: item) { push(.place(item.id)) }
                    }
                }
                .padding(.horizontal, 16)
                .accessibilityIdentifier("places_list")
                suggestionsSection(c, l)
                if showsHowItWorks {
                    PlacesHowItWorksCard(onOpenLastTrip: model.lastTripId == nil ? nil : openLastTrip)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, CustomTabBar.clearance)
        }
        .scrollIndicators(.hidden)
        // Как лента: скролл до физического низа, клиренс — от него.
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func suggestionsSection(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        if !model.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.placeSuggestSection(l))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.44)
                    .textCase(.uppercase)
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(model.suggestions) { suggestion in
                    PlaceSuggestionCardView(suggestion: suggestion) { model.save(suggestion) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .accessibilityIdentifier("places_suggestions")
        }
    }

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header(c, l)
                VStack(spacing: 0) {
                    EmptyStateIllustration(name: "empty_places", size: 148)
                    Text(AppStrings.placesEmptyTitle(l))
                        .font(.inter(21, weight: .heavy)).foregroundStyle(c.text)
                        .multilineTextAlignment(.center).padding(.top, 22)
                }
                .padding(.horizontal, 36)
                .padding(.top, 24)
                .accessibilityIdentifier("places_empty")
                // Карточка вместо одной фразы: три строки говорят, ЧТО
                // сделать, а фраза только объясняла, откуда берутся места.
                PlacesHowItWorksCard(onOpenLastTrip: model.lastTripId == nil ? nil : openLastTrip)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
            }
            .padding(.bottom, CustomTabBar.clearance)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        // Тот же приём, что у `list`: без него центр сцены считается от края
        // safe area, а не от физического низа, и стоит выше пилюли.
        .ignoresSafeArea(edges: .bottom)
    }
}

/// Направления стека «Мест». Типизирован, как `MeDest`: ссылка с чужим
/// значением здесь была бы мертва.
enum PlacesDest: Hashable {
    case place(UUID)
    case trip(UUID, focus: TripFocus)
}
