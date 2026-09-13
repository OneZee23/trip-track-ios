import SwiftUI

/// Вкладка «Места» (0.6.8, S1/S2): карта булавок и список; пусто — сцена
/// `empty_places`. Свой `NavigationStack` с типизированным путём — как у
/// «Я»: экран места и экран поездки пушатся здесь, чужие переходы (чип у
/// отметки в ленте или профиле) приходят двухфазно через `.navigateToPlace`.
///
/// Форма пустого экрана — та же, что у пустых экранов 0.6.2:
/// `EmptyStateIllustration`, заголовок, одна фраза. Сцена — своя,
/// `empty_places`: дорога, булавка на обочине и пустой указатель; нарисована
/// владельцем 12 сентября в ряд с остальными пустыми сценами 0.6.2.
struct PlacesView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @StateObject private var model = PlacesTabViewModel()
    @State private var path: [PlacesDest] = []

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        NavigationStack(path: $path) {
            Group {
                if model.items.isEmpty {
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

    private func list(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                header(c, l)
                PlacesMapView(pins: model.items.map { PlacePin(id: $0.id, coordinate: $0.place.coordinate) },
                              // Карта на 220pt живёт внутри списочного ScrollView: с
                              // включённым pan/zoom жест, начатый на карте, панорамирует
                              // её вместо того чтобы скроллить список. isInteractive
                              // гасит только scroll/zoom у MKMapView — тап по булавке
                              // (didSelect) не завязан на эти жесты и продолжает работать.
                              isInteractive: false,
                              onPinTap: { push(.place($0)) })
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
            }
            .padding(.bottom, CustomTabBar.clearance)
        }
        .scrollIndicators(.hidden)
        // Как лента: скролл до физического низа, клиренс — от него.
        .ignoresSafeArea(edges: .bottom)
    }

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            header(c, l)
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                EmptyStateIllustration(name: "empty_places", size: 148)
                Text(AppStrings.placesEmptyTitle(l))
                    .font(.inter(21, weight: .heavy)).foregroundStyle(c.text)
                    .multilineTextAlignment(.center).padding(.top, 22)
                Text(AppStrings.placesEmptyBody(l))
                    .font(.inter(14)).lineSpacing(6).foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            .padding(.horizontal, 36)
            .accessibilityIdentifier("places_empty")
            Spacer(minLength: 0)
        }
        .padding(.bottom, CustomTabBar.clearance)
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
