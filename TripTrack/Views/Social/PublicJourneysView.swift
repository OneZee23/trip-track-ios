import SwiftUI

/// Хаб «Путешествия» чужого профиля (S7, 0.6.8) — ВСЕ путешествия аккаунта,
/// не только три на карточке-входе в `PublicProfileView`.
///
/// Пагинация — тот же курсорный приём, что у `RemoteTripSource`: страница за
/// страницей, дедуп по id (граница курсора может оказаться включающей) и по
/// курсору (сервер, повторяющий курсор, иначе держал бы клиент в вечной
/// пагинации), догрузка когда экран подходит к концу списка.
struct PublicJourneysView: View {
    let accountId: UUID
    let ownerName: String?
    /// Тот же мост, что у `PublicGarageView`/`PublicProfileView`: пришли из
    /// `PreviewNavigator` (сеть в шите) или из типизированного стека (лента,
    /// «Я», инбокс) — в обоих случаях тап по карточке кладёт `.publicJourney`
    /// в общий путь.
    var pushPath: Binding<[ProfilePreviewDest]>?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var journeys: [PublicJourneyDto] = []
    @State private var nextCursor: String?
    @State private var state: LoadState = .loading
    @State private var isLoadingMore = false
    @State private var didInitialLoad = false
    /// Дедуп id и курсора — см. `RemoteTripSource.load()`, тот же приём.
    @State private var seenIds = Set<UUID>()
    @State private var seenCursors = Set<String>()

    private enum LoadState: Equatable { case loading, loaded, failed }
    private static let pageSize = 20

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ScrollView {
            VStack(spacing: 12) {
                content(c: c, l: l)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        // См. `PublicProfileView`/`FollowListView`: скролл обязан доходить до
        // физического низа, иначе к отступу прибавляется домашний индикатор,
        // а плавающий таб-бар безопасную зону игнорирует.
        .ignoresSafeArea(edges: .bottom)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            CustomNavBar(title: AppStrings.journeysTitle(l), subtitle: ownerName)
        }
        .hideAppTabBar()
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await load()
        }
    }

    @ViewBuilder
    private func content(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if state == .loading, journeys.isEmpty {
            SkeletonPlaceholder(shape: .card, count: 3)
        } else if state == .failed, journeys.isEmpty {
            errorState(c: c, l: l)
        } else if journeys.isEmpty {
            emptyState(c: c, l: l)
        } else {
            ForEach(journeys) { dto in
                JourneyCardView(
                    journey: Journey(publicJourney: dto, ownerId: accountId),
                    legs: dto.legs.map(Trip.init(publicLeg:)),
                    onTap: { openJourney(dto.id) }
                )
                .onAppear {
                    Task { await loadMoreIfNeeded(current: dto) }
                }
            }
            if isLoadingMore {
                CarLoadingView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 8) {
            Spacer(minLength: 60)
            Text(AppStrings.journeyEmptyTitle(l))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Text(AppStrings.publicDataLoadFailed(l))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
            Button {
                Haptics.tap()
                Task { await load() }
            } label: {
                Text(AppStrings.retry(l))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(AppTheme.accent.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private func openJourney(_ id: UUID) {
        guard let pushPath else { return }
        Haptics.tap()
        pushPath.wrappedValue.cappedAppend(.publicJourney(id))
    }

    // MARK: - Networking

    private func load() async {
        state = .loading
        journeys = []
        nextCursor = nil
        seenIds = []
        seenCursors = []
        await fetchPage()
    }

    /// Догрузка при подходе к концу списка — тот же порог, что у
    /// `SocialFeedStore.loadMoreIfNeeded`: последние несколько строк, а не
    /// самая последняя, чтобы прокрутка не замирала в ожидании сети.
    private func loadMoreIfNeeded(current: PublicJourneyDto) async {
        guard nextCursor != nil, !isLoadingMore, state != .failed else { return }
        guard let idx = journeys.firstIndex(where: { $0.id == current.id }) else { return }
        guard idx >= journeys.count - 3 else { return }
        await fetchPage()
    }

    private func fetchPage() async {
        guard !isLoadingMore else { return }
        let isFirstPage = journeys.isEmpty
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let res: PublicJourneysResponse = try await APIClient.shared.get(
                APIEndpoint.userJourneys(
                    accountId.uuidString, cursor: nextCursor, limit: Self.pageSize),
                requiresAuth: AuthService.shared.isSignedIn)
            for dto in res.journeys where seenIds.insert(dto.id).inserted {
                journeys.append(dto)
            }
            if let next = res.nextCursor, !next.isEmpty, seenCursors.insert(next).inserted {
                nextCursor = next
            } else {
                nextCursor = nil
            }
            state = .loaded
        } catch {
            // Первая страница отвалилась — экран пуст, показываем отказ с
            // повтором. Догрузка отвалилась — то, что уже есть, остаётся на
            // экране; список просто перестаёт расти молча, как у
            // `RemoteTripSource`.
            if isFirstPage { state = .failed }
        }
    }
}
