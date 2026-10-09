import SwiftUI
import OSLog
import CoreLocation

private let navLog = Logger(subsystem: "com.triptrack", category: "nav")

/// «Я» tab — 0.6.0 canon (Figma 580:122 list / 755:119 grid, 127:896 guest).
/// Self-hosts a `NavigationStack` (ContentView mounts the tab bare) and pushes
/// Статистика, Уровни, Достижения, «Как видят другие» + trip details (all hide
/// the tab bar via the existing preference). History follows the hero and a
/// compact disclosure for garage, PRO, achievements and clubs.
///
/// The canon header and stat strip are now ONE object, `ProfileHeroCard` — the
/// screen opened as four stacked greys and read as a settings page. The grey
/// sync line that sat under the name went to «Настройки → Аккаунт и
/// синхронизация», the row that can actually do something about it.
///
/// Pre-0.6.0 features that are NOT here: everything that moved into the
/// settings sheet (gear) or into Уровни (LVL pill), plus three the user cut
/// outright — the follower/following counter card, «Год в кадре» / Wrapped,
/// and the «Моменты» rail.
struct ProfileView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var auth = AuthService.shared
    /// Наблюдается, а не читается разово: путешествие создаётся с экрана
    /// поездки, и «Мои» обязаны схлопнуть плечи сразу по возвращении, а не
    /// после следующей перезагрузки ленты.
    @ObservedObject private var journeys = JourneyManager.shared
    /// Два бита про платное — «куплено?» и «эта витрина вообще продаёт?».
    /// Читаются только здесь, решение принимает `PlusGate`.
    @ObservedObject private var plusAccess = PlusAccess.shared
    /// Нужен ради статуса подписки: `PlusAccess` знает только «есть/нет», а
    /// строке PRO нужны восемь случаев (триал, грейс, ждём одобрения, дата).
    @ObservedObject private var plusStore = PlusStore.shared

    /// True when hosted as the «Я» tab (0.6.0) — the floating tab bar needs
    /// scroll clearance. False when presented as the legacy Feed sheet.
    private let hostedInTab: Bool

    init(hostedInTab: Bool = false) {
        self.hostedInTab = hostedInTab
    }

    /// Typed destinations for the Я stack.
    private enum MeDest: Hashable {
        /// Гараж — страница, а не шит. Канон 0.6.4 рисует его полноэкранным,
        /// и внутри него «машина» пушится дальше по этому же стеку.
        case garage
        /// Список черновиков (0.8.2). Единственный новый экран переделки:
        /// экран поездки не меняется, «Я» меняется на один раздел.
        case drafts
        case stats
        /// Чужая статистика и чужая карта (0.6.3). Те же экраны, что и свои,
        /// с другим источником поездок; имя владельца едет с ними, чтобы
        /// шапка отличала одну «Статистику» от другой.
        case publicStats(UUID, String?)
        case publicMap(UUID, String?)
        /// Чужой гараж и чужая машина (0.6.4) — как статистика и карта, с
        /// именем владельца для шапки.
        case publicGarage(UUID, String?)
        case publicVehicle(UUID, UUID, String?)
        /// Чужое публичное путешествие (0.6.8) — открывается из карточки
        /// плеча на чужом профиле/в ленте внутри «Как видят другие», того же
        /// моста `socialDest`/`meDest`, что и статистика/карта/гараж.
        case publicJourney(UUID)
        /// Хаб «Путешествия» чужого профиля (S7, 0.6.8) — тот же мост, что и
        /// у гаража.
        case publicJourneys(UUID, String?)
        /// «Мой профиль» — the hub behind the header (avatar + name/handle/bio
        /// /level/stats rows). Its five row editors are NOT cases here: four
        /// of them are sheets this view presents, and the fifth is Статистика,
        /// which already has one.
        case myProfile
        /// «Уровни» (canon 888:3848) — a pushed screen, not the bottom sheet it
        /// used to be, reached from the header LVL pill and from «Мой профиль»'s
        /// «Уровень» row. One surface, two entry points: whichever way it was
        /// opened, the back chevron goes where the user came from.
        case levels
        /// Флаг страны — a pushed screen (`CountryPickerView` draws its own
        /// `CustomNavBar` and pops itself), so it belongs in this path rather
        /// than in a sheet.
        ///
        /// One entry point: the «Страна» row of «Мой профиль» (`onTapCountry`).
        /// The country is profile data, not app configuration, so the settings
        /// sheet no longer carries a second copy of the row.
        case country
        /// The whole award list, and one award. `Badge` cannot be the payload
        /// — it carries the `checkUnlocked` closure and so isn't `Hashable` —
        /// so the path holds the catalogue id and the destination resolves it
        /// against `Badge.all`. That is also what keeps a rebuilt path
        /// pointing at the right badge instead of at a stale copy of one.
        case achievements
        case achievement(String)
        /// «Как видят другие» — the viewer's own public profile. An ORDINARY
        /// pushed screen (canon 580:438: back circle, «@username», «⋯»), not
        /// the fullScreenCover over a hand-rolled ZStack navigator it used to
        /// be: that cover had no fixed header, so the whole page — floating
        /// orange «Готово» band included — moved as one loose sheet and read
        /// as a web page rather than as a screen of this app.
        ///
        /// Payload is the same pair `ProfilePreviewDest.profile` carries, so
        /// `socialPath` can bridge the two: a stranger opened from a follow
        /// list arrives with the summary the list already had.
        case publicProfile(UUID, SocialAuthor?)
        /// Подписчики / подписки of whichever profile is on top. Only ever
        /// reached from `.publicProfile`.
        case followList(UUID, FollowListMode)
        case trip(UUID)
        /// Путешествие (0.6.6) — по id, а не по значению: даты правятся с
        /// самого экрана, и копия окна показывала бы прежние плечи.
        case journey(UUID)
        /// A «Со мной» trip — NOT in the local database (someone else's),
        /// so it carries its own `SocialFeedTrip` payload rather than just
        /// an id, exactly like `ProfilePreviewDest.socialTrip` does for the
        /// feed. Kept as a separate case (rather than reusing that shared
        /// enum for `mePath`) because `mePath`'s type predates it and this
        /// is the only spot in the Я stack that needs a non-owned trip.
        case companionTrip(SocialFeedTrip)
        /// Клубы (0.6.8): вкладки «Группы» больше нет — тизер, каталог и
        /// страница клуба пушатся отсюда, из строки под гаражом. Три случая,
        /// а не один экран со своим стеком: вложенный `NavigationStack`
        /// запрещён, а `mePath` типизирован, и `NavigationLink(value: Club)`
        /// в нём отключён — поэтому экраны клубов отдают нажатие замыканием,
        /// а пушит профиль.
        case clubs
        case clubsCatalog
        case club(Club)
    }

    /// How История draws its trips — canon 580:122 (list) / 755:119 (grid).
    private enum HistoryMode: String {
        case list
        case grid
    }

    @State private var mePath: [MeDest] = []
    /// Разовая карточка «профиль теперь показывает больше» (0.6.3).
    /// Пересчитывается на каждый вход/выход: вычисленное один раз в
    /// инициализаторе значение означало бы, что гость, вошедший в этой же
    /// сессии, узнает о новой видимости только после перезапуска.
    @State private var showsVisibilityNotice = false
    @State private var showSettings = false
    /// Разовая карточка ведёт прямо в «Приватность», а не в общий список.
    @State private var opensPrivacyFromNotice = false
    /// Presented here rather than from «Мой профиль» itself, for the same
    /// reason the three field editors are: one host owns every presentation
    /// this stack raises.
    /// Открытая витрина оформления. Одна переменная на все виды: четыре
    /// `@State`-флага рядом умели бы показать два листа сразу.
    @State private var showcase: ProShowcaseKind?
    /// Лист «Вписать поездку» (0.8.0). Гейт решает, что покажется в нём —
    /// форма или пейвол (`manualTripHost`).
    @State private var showManualTrip = false
    /// Чем лист открывается: `nil` у обычных входов («+», карточка
    /// приветствия), дата — у пустого дня календаря, зеркало точек/машины —
    /// у «Добавить обратную дорогу». Ставится ДО `showManualTrip = true`.
    @State private var manualTripPreset: ManualTripPreset?
    /// Тост после успешной записи (§4в) — «Открыть поездку» /
    /// «Добавить обратную дорогу», наш `AppConfirmDialog`, не системный алерт.
    @State private var manualTripResult: ManualTripCreationResult?
    /// The three field editors behind «Мой профиль». The hub only reports the
    /// tap; presenting them here keeps every editor on one host, which is what
    /// keeps them all on one host — a
    /// sheet is a separate presentation and does not inherit the app root's.
    @State private var showNameEditor = false
    @State private var showUsernameEditor = false
    @State private var showAboutEditor = false
    /// Client-side aggregates. Since 0.6.0 they feed exactly two things: the
    /// strip's region count and the «data has landed» gate — everything
    /// История draws comes out of `allTrips` instead.
    @State private var agg: MeAggregates?
    /// Every completed trip, newest first. `agg.recentTrips` stops at 10,
    /// which made a date filter over История meaningless.
    @State private var historyLibrary = ProfileHistoryLibrary(trips: [])
    private var allTrips: [Trip] { historyLibrary.trips }
    /// Черновики — отдельно от `allTrips`: в мир они не вошли, и ни
    /// статистика, ни путешествия, ни календарь их не видят (спека §3.2).
    @State private var drafts: [Trip] = []
    /// Filtered trips, folded journey rows, grid runs and historical levels
    /// move together. Unrelated body updates only read this prepared value.
    @State private var preparedHistory = PreparedProfileHistory.empty
    @State private var historyQuery = ""
    @FocusState private var historySearchFocused: Bool
    @State private var showsProfileSections = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which awards are earned — the one thing `AchievementDetailView` needs
    /// that a badge id cannot carry. Resolved by the award destinations
    /// themselves (`refreshUnlockedBadges`) rather than in `loadAggregates`:
    /// that path runs on every trip save and every sync pull, and this walk is
    /// only worth paying for once someone actually opens an award.
    @State private var unlockedBadgeIds: Set<String> = []
    /// Σ km per calendar day and the busiest of those days — the calendar's
    /// heat ramp. Walked once per load in `loadAggregates`, never in `body`:
    /// it touches every trip.
    @State private var kmByDay: [Date: Double] = [:]
    @State private var maxKmDay: Double = 0
    @State private var dateFrom: Date?
    @State private var dateTo: Date?
    /// `@AppStorage` cannot hold the enum itself, so the raw value is what
    /// persists and `historyMode` maps it back (unknown value → canon list).
    @AppStorage("profileHistoryMode") private var historyModeRaw = HistoryMode.list.rawValue

    // MARK: - Объединение в путешествие (0.6.6) — состояние

    /// Опорная поездка листа объединения. Не `nil` — лист открыт: отдельного
    /// флага нет специально, два источника правды тут разошлись бы на первом
    /// же закрытии.
    @State private var composerAnchor: Trip?
    /// Готовый список для листа — только у подсказки, которая уже собрала
    /// цепочку сама. `nil` значит «ищи соседей ±7 дней», и это случай долгого
    /// нажатия на карточку.
    @State private var composerPreselected: [Trip]?
    /// Лист закрывается сам, и подтвердить, что путешествие создано, больше
    /// нечем — то же решение, что на экране поездки.
    @State private var toastItem: ToastItem?

    /// Витрина «Плюса» и лист чаевых. Два листа, а не один с сегментом:
    /// подписка и чаевые — разные сделки (см. `TipEntry`).
    @State private var showPaywall = false

    // MARK: - Подсказка путешествия (0.6.6) — состояние

    /// Цепочка, которую предлагает `JourneySuggester`. Пусто — баннера нет.
    @State private var suggestedTrips: [Trip] = []
    /// «Владикавказ, Тбилиси · 6 поездок» — считается один раз на подсказку,
    /// а не в `body`: имена мест лежат в CoreData, и ходить туда на каждой
    /// перерисовке (а этот экран наблюдает `SyncQueue`) незачем.
    @State private var suggestionSubtitle = ""
    /// Догадка про дом, пока человек её не подтвердил. nil — вопроса нет:
    /// либо дом известен, либо уже спрашивали, либо данных мало.
    @State private var homeCandidate: CLLocationCoordinate2D?
    @State private var homeCandidateName = ""
    /// Счётчик ответов «Да» про дом. Единственное, ради чего он есть, — ключ
    /// `.task(id:)`: пересчёт подсказки после подтверждения дома живёт в
    /// структурированной задаче экрана, а не в `Task {}`, который экран не
    /// отменит.
    @State private var homeAcceptedTick = 0

    /// Тело разрезано надвое, как у `TripDetailView`: цепочка модификаторов
    /// «Моих» уже упиралась в предел вывода типов SwiftUI, и следующий
    /// добавленный `.onChange` ронял компилятор по таймауту — в случайном
    /// месте, а не там, где его дописали.
    var body: some View {
        stage
            .manualTripHost(
                isPresented: $showManualTrip,
                tripManager: mapVM.tripManager,
                preset: manualTripPreset,
                onCreated: { result in
                    Task { await loadAggregates() }
                    manualTripResult = result
                }
            )
            .appConfirm(
                item: $manualTripResult,
                title: { _ in AppStrings.manualTripSuccessMessage(lang.language) },
                actions: manualTripResultActions
            )
            // Путешествия меняются и без перезагрузки библиотеки: пул с
            // другого телефона, стирание данных, удаление обёртки с её экрана.
            // Подсказка считается по ним (`existing` в
            // `JourneySuggester.suggestion`), и без этой строки она продолжала
            // бы предлагать объединить то, что уже объединено, — до следующей
            // записанной поездки.
            .onChange(of: journeys.journeys) { _, _ in
                refreshVisibleTrips()
                Task { await refreshJourneyPrompts(trips: allTrips) }
            }
            // Человек подтвердил дом — подсказка может быть готова уже сейчас.
            .task(id: homeAcceptedTick) {
                guard homeAcceptedTick > 0 else { return }
                await refreshJourneyPrompts(trips: allTrips)
            }
            // Контекстное предложение PRO. Вешается РОВНО на два экрана — сюда
            // и на «Ленту», — и список этот закрыт спекой §11: запись, экран
            // поездки и лист ручной поездки перечислены в ней как запрещённые.
            .proContextOffer(tripCount: mapVM.cachedTripCount)
            .proShowcase($showcase)
    }

    // MARK: - Ручная поездка (0.8.0, редизайн 20 сен)

    /// Тап по пустому дню календаря: только дата, лист открывается пустым во
    /// всём остальном.
    private func openManualTrip(forDay day: Date) {
        manualTripPreset = .forDay(day)
        showManualTrip = true
    }

    /// «Открыть поездку» / «Добавить обратную дорогу» на тосте после записи —
    /// в этом порядке, безопасное (открыть) ближе к большому пальцу.
    private func manualTripResultActions(_ result: ManualTripCreationResult) -> [AppDialogAction] {
        [
            AppDialogAction(
                AppStrings.manualTripSuccessOpen(lang.language),
                kind: .primary, identifier: "manual_trip_toast_open"
            ) {
                push(.trip(result.tripId))
            },
            AppDialogAction(
                AppStrings.manualTripSuccessReturn(lang.language),
                kind: .plain, identifier: "manual_trip_toast_return"
            ) {
                manualTripPreset = .returnTrip(
                    from: result.from, to: result.to,
                    vehicleId: result.vehicleId, firstTripEnd: result.endDate
                )
                showManualTrip = true
            }
        ]
    }

    /// Вынесено из цепочки `stage`: `body` этого экрана уже упирался в предел
    /// вывода типов SwiftUI на одном добавленном `.onChange` (CLAUDE.md,
    /// «Ловушки»), и собранный на месте `Binding` — самое дорогое звено в ней.
    private var authErrorBinding: Binding<Bool> {
        Binding(
            get: { auth.lastAuthError != nil },
            set: { if !$0 { auth.lastAuthError = nil } }
        )
    }

    @ViewBuilder
    private var stageNavigation: some View {
        let c = AppTheme.colors(for: scheme)

        NavigationStack(path: $mePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero()

                    if mapVM.cachedTripCount == 0 {
                        // First-launch welcome — zeros read as broken, so the
                        // strip/achievements/history stay hidden until ≥1 trip.
                        firstTripWelcomeCard(c)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        if !auth.isSignedIn {
                            guestSignInCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        } else if showsVisibilityNotice {
                            visibilityNoticeCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                        // Zero trips does not mean zero cars: the Гараж is
                        // where a new user names the thing they drive, and
                        // it is the one section here that has something to
                        // do before the first kilometre.
                        garageSection(c)

                        plusSection()

                        clubsSection()
                    } else {
                        if !auth.isSignedIn {
                            guestSignInCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        } else if showsVisibilityNotice {
                            visibilityNoticeCard(c)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }

                        profileSections(c)

                        // Над «Историей», а не под ней: подсказка про только
                        // что законченное путешествие теряет смысл, если её
                        // надо доскроллить.
                        journeyPrompts()

                        // Раздел «Черновики»: ОДНА карточка вместо списка
                        // полных карточек поездок (спека §2). Нет черновиков —
                        // раздела нет совсем: ни пустой карточки, ни текста.
                        if !drafts.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ProfileSectionLabel(text: AppStrings.draftsTitle(lang.language))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 4)
                                    .padding(.bottom, 8)
                                    .accessibilityIdentifier("profile_drafts_header")
                                ProfileDraftsRow(count: drafts.count,
                                                 lastAt: drafts.map(\.startDate).max()) {
                                    push(.drafts)
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.bottom, 12)
                        }

                        if !allTrips.isEmpty {
                            historyBlock(c)
                        } else if agg != nil {
                            // No trips at all: canon empty card. Before this
                            // the section simply wasn't rendered, so a fresh
                            // user saw the Я tab end after the stat grid with
                            // nothing telling them what happens next.
                            //
                            // Шапка над ней — ради «+» (0.8.0): без неё
                            // единственный вход в «Вписать поездку» из «Мои»
                            // появлялся бы только после ПЕРВОЙ записанной
                            // поездки, а человеку с пустой библиотекой
                            // вписать старую дорогу нужнее всех.
                            historyHeader(c)
                            noTripsCard(c)
                        } else {
                            // Nil aggregates with no trips means the library
                            // has not been read yet — a different thing from
                            // an empty one, and until now they looked the
                            // same: the page simply ended.
                            ProfileHistorySkeleton(isGrid: historyMode == .grid)
                        }

                        // «Со мной» — trips the user rode as an accepted
                        // companion. Signed-out users can't be a companion
                        // on anything (the endpoint needs a token), so this
                        // never even asks while signed out. Draws nothing of
                        // its own when there's nothing to show — see
                        // `WithMeSectionModel`.
                        if auth.isSignedIn {
                            WithMeSection(onTapTrip: { push(.companionTrip($0)) })
                        }

                    }
                }
                // As a tab (0.6.0), leave room for the floating tab bar so the
                // last row can scroll clear of it; as a sheet there is no bar.
                // Клиренс — как у гаража и паспорта, от границы безопасной зоны.
                .padding(.bottom, hostedInTab ? CustomTabBar.clearanceAboveSafeArea : 40)
            }
            .scrollIndicators(.hidden)
            .background(c.bg)
            .toast(item: $toastItem)
            .sheet(item: $composerAnchor) { anchor in journeyComposer(anchor: anchor) }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MeDest.self) { dest in
                switch dest {
                case .garage:
                    GarageView()
                case .drafts:
                    draftsDest
                case .stats:
                    // Push onto THIS stack. Without the callback the screen
                    // falls back to the app-wide `.openTripDetail` channel,
                    // which switches to the Лента tab and opens the trip there
                    // — so «назад» from a trip you opened in Статистика landed
                    // in the feed, and the only way back to the list you were
                    // reading was Я → Статистика → scroll down and find it again.
                    StatsScreenView(
                        tripManager: mapVM.tripManager,
                        onOpenTrip: { push(.trip($0)) }
                    )
                case .myProfile:
                    myProfileHub()
                case .levels:
                    LevelsView()
                case .country:
                    CountryPickerView(
                        // "" is this app's «not set»; the picker speaks nil.
                        selection: settings.profileCountry.isEmpty ? nil : settings.profileCountry,
                        onSelect: { settings.profileCountry = $0 ?? "" }
                    )
                case .achievements:
                    // Fed the already-loaded library, not a second CoreData
                    // read. The walk runs here too so the answer is ready
                    // before the user can tap a tile out of the grid.
                    AchievementsView(trips: allTrips) { badge in
                        push(.achievement(badge.id))
                    }
                    .task(id: allTrips.count) { await refreshUnlockedBadges() }
                case .achievement(let id):
                    achievementDetail(id)
                case .publicProfile(let id, let author):
                    // The same screen strangers get from the Лента (canon
                    // 580:579) — it decides for itself that the viewer is
                    // looking at their own account and swaps «Подписаться»
                    // for «Это вы» plus the preview notice card. Nothing
                    // about the CHROME differs: one nav bar, drawn by the
                    // screen, pinned above the scroll.
                    PublicProfileView(
                        accountId: id,
                        preloaded: author,
                        pushPath: socialPath,
                        // The Я stack renders `.trip` and `.companionTrip`,
                        // which is what `socialPath` folds trip pushes into —
                        // so a card on the preview opens like one in the feed.
                        opensTrips: true
                    )
                    .hideAppTabBar()
                case .followList(let id, let mode):
                    FollowListView(accountId: id, mode: mode, pushPath: socialPath)
                        .hideAppTabBar()
                case .publicStats(let id, let name):
                    StatsScreenView(
                        tripManager: mapVM.tripManager,
                        source: RemoteTripSource(accountId: id),
                        ownerName: name
                    )
                    .hideAppTabBar()
                case .publicMap(let id, let name):
                    PublicMapView(accountId: id, ownerName: name)
                        .hideAppTabBar()
                case .publicGarage(let id, let name):
                    garageDest(id: id, name: name)
                case .publicVehicle(let id, let vid, let name):
                    vehicleDest(id: id, vehicleId: vid, name: name)
                case .publicJourney(let id):
                    // Task 4 replaces `PublicJourneyView` wholesale — this
                    // task only wires the stack so the destination compiles.
                    PublicJourneyView(journeyId: id, pushPath: socialPath)
                        .hideAppTabBar()
                case .publicJourneys(let id, let name):
                    PublicJourneysView(accountId: id, ownerName: name, pushPath: socialPath)
                        .hideAppTabBar()
                case .trip(let id):
                    // Same construction FeedView uses; TripDetailView manages
                    // its own chrome and hides the tab bar itself.
                    // KNOWN LIMITATION: no pushPath is passed, so deep
                    // chains from here (trip → reactor profile → followers
                    // → profile, depth ≥4) use TripDetailView's legacy
                    // isPresented fallback and can show the cosmetic
                    // nav-bar «Back» flash. A typed mixed-path stack would
                    // fix it; deferred — История's primary flow is 1 deep.
                    TripDetailView(
                        tripId: id,
                        viewModel: TripsViewModel(tripManager: mapVM.tripManager),
                        preview: allTrips.first(where: { $0.id == id })
                    )
                case .journey(let id):
                    // Экран путешествия сам рисует свою шапку и прячет таб-бар.
                    JourneyDetailView(journeyId: id)
                case .clubs:
                    GroupsComingSoonView(onOpenCatalog: { push(.clubsCatalog) })
                case .clubsCatalog:
                    ClubsCatalogView(onOpenClub: { push(.club($0)) })
                case .club(let club):
                    // Таб-бар остаётся, как у гаража и как рисует канон
                    // (`ClubDetailView`): пушнутый экран со своей шапкой.
                    ClubDetailView(club: club)
                case .companionTrip(let trip):
                    // Same construction FeedView's `.socialTrip` destination
                    // uses: `social:` feeds the screen someone else's trip,
                    // rendered through `Trip(social:)` instead of a local
                    // CoreData read.
                    TripDetailView(
                        tripId: trip.id,
                        viewModel: TripsViewModel(tripManager: mapVM.tripManager),
                        social: trip
                    )
                }
            }
        }
    }

    private var stageDataWatchers: some View {
        stageNavigation
        .onAppear {
            settings.reloadGamificationState()
        }
        // The other half of `refreshVisibleTrips`'s contract: the library moves
        // in `loadAggregates`, the range moves here.
        .onChange(of: dateFrom) { _, _ in refreshVisibleTrips() }
        .onChange(of: dateTo) { _, _ in refreshVisibleTrips() }
        .onChange(of: historyQuery) { _, _ in refreshVisibleTrips() }
        .onChange(of: lang.language) { _, _ in refreshVisibleTrips() }
        .task {
            await loadAggregates()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripRecordingEnded)) { _ in
            Task { await loadAggregates() }
        }
        // 0.8.0: вписанная рукой поездка ложится в базу мимо записи — без
        // этого её карточка не появилась бы в «Мои» до перезахода на вкладку.
        .onReceive(NotificationCenter.default.publisher(for: .manualTripCreated)) { _ in
            Task { await loadAggregates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncPullCompleted)) { _ in
            Task { await loadAggregates() }
        }
    }

    private var stageRoutingWatchers: some View {
        stageDataWatchers
        // История pushes TripDetailView, where trips get deleted or flip
        // privacy — without these the popped-back list keeps a ghost row
        // (tapping it lands on an empty detail with no back affordance).
        // StatsCache MUST be dropped first: its only invalidation keys are
        // trip count + last startDate, so a privacy flip (neither changes)
        // would make loadAggregates recompute over the stale cached [Trip]
        // array and keep the old globe/lock icon.
        .onReceive(NotificationCenter.default.publisher(for: .tripDeleted)) { _ in
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        // «Моя» уводит черновик в историю, «Удалить» — в никуда.
        .onReceive(NotificationCenter.default.publisher(for: .draftTripResolved)) { _ in
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tripPrivacyChanged)) { _ in
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        // Pop-back from TripDetailView: title renames post no notification
        // and change neither StatsCache key — refresh over a dropped cache
        // so История picks up edits made inside the detail screen.
        .onChange(of: mePath) { oldPath, newPath in
            guard newPath.count < oldPath.count,
                  let popped = oldPath.last, case .trip = popped else { return }
            StatsCache.invalidate()
            Task { await loadAggregates() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGarageReady)) { _ in
            // Second phase of VehiclePickerSheet's «Управлять в Гараже»:
            // ContentView switched to the Я tab, waited for this view to
            // mount, then re-posted.
            push(.garage)
        }
        // Настройки видимости просят показать превью. Лист к этому моменту
        // уже закрылся сам — иначе push ушёл бы под него.
        .onChange(of: auth.isSignedIn) { _, _ in refreshVisibilityNotice() }
        // `isPublicProfile` приезжает из `/auth/me` уже после появления экрана,
        // поэтому карточка ждёт ответа, а не решает по пустому значению.
        .onChange(of: auth.isPublicProfile) { _, _ in refreshVisibilityNotice() }
        .task { await primeVisibilityState() }
        .onReceive(NotificationCenter.default.publisher(for: .openOwnProfilePreview)) { _ in
            guard let accountId = TokenStore.shared.accountId else { return }
            showSettings = false
            // Пауза на закрытие листа: push под ещё не уехавшим листом
            // выполняется, но остаётся невидимым. `Task`, а не
            // `DispatchQueue.main.asyncAfter` — правило дома.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                push(.publicProfile(accountId, nil))
            }
        }
    }

    private var stage: some View {
        stageRoutingWatchers
        // Одноразовый флаг: без сброса КАЖДОЕ следующее открытие настроек до
        // конца сессии само прыгало бы в «Приватность».
        .sheet(isPresented: $showSettings, onDismiss: { opensPrivacyFromNotice = false }) {
            ProfileSettingsSheet(opensPrivacy: opensPrivacyFromNotice)
                .environmentObject(lang)
                .environment(\.navBarInSheet, true)
                .environmentObject(themeManager)
        }
        .sheet(isPresented: $showNameEditor) {
            NameEditorSheet(
                initialName: auth.userName ?? "",
                isPlaceholder: RandomDisplayName.isPlaceholder(auth.userName),
                onSave: { newName in
                    Task { await auth.updateUserName(newName) }
                }
            )
            .environmentObject(lang)
        }
        .sheet(isPresented: $showUsernameEditor) {
            UsernameEditorSheet(
                initialUsername: settings.profileUsername,
                // SHIPPING BLOCKER: there is no handle on the server and no
                // endpoint to ask, so every lookup answers "не удалось
                // проверить" — the editor's own degraded branch, which still
                // lets the user save. Two accounts CAN claim the same handle
                // until the backend lands `/social/username-available`.
                // No endpoint to ask yet — the editor hides its verdict line
                // instead of printing a failure the user cannot act on, and
                // still lets them save. Two accounts CAN claim the same handle
                // until the backend lands `/social/username-available`.
                canCheckAvailability: false,
                checkAvailability: { _ in nil },
                onSave: { settings.profileUsername = $0 }
            )
            .environmentObject(lang)
        }
        .sheet(isPresented: $showAboutEditor) {
            AboutEditorSheet(
                initialText: settings.profileBio,
                onSave: { settings.profileBio = $0 }
            )
            .environmentObject(lang)
        }
        // House dialog, never the system's — see «Dialogs» in CLAUDE.md.
        // Acknowledgement only: «ОК» is the single way out, so there is no
        // cancel row under it.
        .appConfirm(
            isPresented: authErrorBinding,
            title: AppStrings.signInFailedTitle(lang.language),
            // Generic localized copy — same defence as SignInPromptSheet:
            // never echo `String(describing: APIError)` because the
            // `unknownServer.message` case would surface server-controlled
            // text into the dialog. The house card changes nothing about that
            // rule: the error object stays out of the copy.
            message: AppStrings.signInPromptAppleFailed(lang.language),
            actions: [AppDialogAction(AppStrings.ok(lang.language))],
            cancelTitle: nil
        )
    }

    /// Extracted from the `.myProfile` destination: eight trailing closures in
    /// one expression inside a `switch` inside a `navigationDestination` put
    /// the type-checker over its time limit («unable to type-check this
    /// expression in reasonable time»).
    @ViewBuilder
    private func myProfileHub() -> some View {
        MyProfileView(
            onTapName: { showNameEditor = true },
            onTapUsername: { showUsernameEditor = true },
            onTapAbout: { showAboutEditor = true },
            // The same screen the LVL pill in the header opens.
            onTapLevel: { push(.levels) },
            onTapCountry: { push(.country) },
            onTapBackground: { showcase = .profileBackground },
            onTapAvatarFrame: { showcase = .avatarFrame },
            onTapStats: { push(.stats) },
            // Straight onto THIS stack — the same destination the
            // public profile's counters reach, minus the detour
            // through a preview of yourself.
            onTapFollowList: { mode in
                guard let accountId = TokenStore.shared.accountId else { return }
                push(.followList(accountId, mode))
            },
            // Signed out there is no public profile to preview —
            // the endpoint needs an account id. The hub hides the
            // row too; this is the second lock.
            onTapPreview: {
                guard let accountId = TokenStore.shared.accountId else { return }
                navLog.debug("push own-profile preview onto mePath (depth \(mePath.count))")
                push(.publicProfile(accountId, nil))
            }
        )

    }

    // MARK: - Navigation

    /// Idempotent push — a fast double-tap must not stack two copies of the
    /// same screen.
    private func push(_ dest: MeDest) {
        guard mePath.last != dest else { return }
        mePath.append(dest)
    }

    /// The social sub-stack (profile → follow list → profile → …) seen as the
    /// `[ProfilePreviewDest]` binding `PublicProfileView` and `FollowListView`
    /// already take. Reads project the social tail of `mePath`, writes fold it
    /// back — so every tap inside «как видят другие» is a REAL push on the Я
    /// stack (one back chevron, one swipe-back gesture, one place the path
    /// lives), and `cappedAppend`'s depth cap still bounds the chain.
    ///
    /// Handing those screens the binding — rather than letting them fall back
    /// to their own `.navigationDestination(isPresented:)` — is also what keeps
    /// this stack out of the isPresented-inside-a-typed-path bug documented on
    /// `ProfilePreviewDest`: with the binding wired in, both screens disable
    /// their local destinations.
    private var socialPath: Binding<[ProfilePreviewDest]> {
        Binding(
            get: { mePath.compactMap(Self.socialDest) },
            set: { newValue in
                // Everything up to the first social entry is untouched; the
                // social entries are contiguous at the tail, because the only
                // way into one is «Как видят другие» and the only thing you
                // reach from there is another social screen.
                let head = mePath.prefix { Self.socialDest($0) == nil }
                mePath = Array(head) + newValue.map(Self.meDest)
            }
        )
    }

    /// Вынесено из `navigationDestination`: его switch типизировался
    /// пятнадцать секунд ещё до гаража, и две новые ветки прямо в теле
    /// перевели компилятор в «unable to type-check in reasonable time».
    @ViewBuilder
    private func garageDest(id: UUID, name: String?) -> some View {
        PublicGarageView(accountId: id, ownerName: name)
            .hideAppTabBar()
    }

    @ViewBuilder
    /// Вынесено из `navigationDestination` отдельным свойством: ещё один
    /// `case` в том `switch` переполнил вывод типов SwiftUI — та же ловушка,
    /// что у `TripDetailView.body` и у самого `ProfileView.body` (CLAUDE.md).
    private var draftsDest: some View {
        DraftsListView { push(.trip($0)) }
    }

    private func vehicleDest(id: UUID, vehicleId: UUID, name: String?) -> some View {
        PublicVehicleView(accountId: id, vehicleId: vehicleId, ownerName: name)
            .hideAppTabBar()
    }

    private static func socialDest(_ dest: MeDest) -> ProfilePreviewDest? {
        switch dest {
        case .publicProfile(let id, let author): return .profile(id, author)
        case .followList(let id, let mode): return .followList(id, mode)
        case .publicStats(let id, let name): return .publicStats(id, name)
        case .publicMap(let id, let name): return .publicMap(id, name)
        case .publicGarage(let id, let name): return .publicGarage(id, name)
        case .publicVehicle(let id, let vid, let name): return .publicVehicle(id, vid, name)
        case .publicJourney(let id): return .publicJourney(id)
        case .publicJourneys(let id, let name): return .publicJourneys(id, name)
        case .drafts, .garage, .stats, .myProfile, .levels, .country, .achievements,
             .achievement, .trip, .journey, .companionTrip,
             .clubs, .clubsCatalog, .club:
            return nil
        }
    }

    /// The other half of the bridge. `.trip` / `.socialTrip` are unreachable
    /// through it today — neither the profile nor a follow list pushes a trip
    /// — but they are mapped rather than dropped so a future push lands on the
    /// Я stack's own trip destinations instead of vanishing.
    private static func meDest(_ dest: ProfilePreviewDest) -> MeDest {
        switch dest {
        case .profile(let id, let author): return .publicProfile(id, author)
        case .followList(let id, let mode): return .followList(id, mode)
        case .trip(let id, _): return .trip(id)
        case .socialTrip(let trip, _): return .companionTrip(trip)
        case .publicStats(let id, let name): return .publicStats(id, name)
        case .publicMap(let id, let name): return .publicMap(id, name)
        case .publicGarage(let id, let name): return .publicGarage(id, name)
        case .publicVehicle(let id, let vid, let name): return .publicVehicle(id, vid, name)
        case .publicJourney(let id): return .publicJourney(id)
        case .publicJourneys(let id, let name): return .publicJourneys(id, name)
        }
    }

    /// One award. The path carries only the id, so the badge is resolved here
    /// and «earned?» is re-derived instead of being frozen into the path: a
    /// flag captured at push time would be stale the moment the library moved
    /// underneath it. `Badge.all` is compiled in, so the lookup can only miss
    /// if a path outlives a catalogue rename — nothing to draw beats a crash.
    @ViewBuilder
    private func achievementDetail(_ id: String) -> some View {
        if let badge = Badge.all.first(where: { $0.id == id }) {
            AchievementDetailView(badge: badge, isUnlocked: unlockedBadgeIds.contains(id))
                .task(id: allTrips.count) { await refreshUnlockedBadges() }
        }
    }

    /// `computeStats` reads the streak row off the CoreData view context, so the
    /// trip walk stays on the main actor; only the pure pass over the badge
    /// catalogue goes off it. Same split as `ProfileAchievementsSection.load`.
    private func refreshUnlockedBadges() async {
        let stats = BadgeManager.computeStats(from: allTrips)
        let ids = await Task.detached(priority: .userInitiated) {
            Set(BadgeManager.unlockedBadges(for: stats).map(\.id))
        }.value
        guard !Task.isCancelled else { return }
        unlockedBadgeIds = ids
    }

    // MARK: - Hero (was the flat canon header, Figma 150:1244)

    /// Avatar, name, rank, the three lifetime numbers and the gear — one
    /// coloured card, wearing the background picked in «Мой профиль». See
    /// `ProfileHeroCard` for why the canon header stack was retired.
    ///
    /// No accessibility id on the card itself: an id on a container makes
    /// SwiftUI treat it as ONE element and swallow the buttons inside it, which
    /// takes the avatar, the pill and the gear away from VoiceOver and from the
    /// UI tests alike. The ids live on those buttons.
    private func hero() -> some View {
        ProfileHeroCard(
            background: ProfileBackground.from(settings.profileBackground),
            avatarEmoji: settings.avatarEmoji,
            name: headerDisplayName,
            // A signed-in account with no name shows «Добавьте имя» — a prompt,
            // drawn dimmer so it can't be mistaken for what the user is called.
            isNamePlaceholder: auth.isSignedIn
                && (auth.userName?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty,
            level: settings.profileLevel,
            rankTitle: DriverRank.from(level: settings.profileLevel).title(lang.language),
            trips: mapVM.cachedTripCount,
            km: mapVM.cachedTotalKm,
            regions: agg?.regionsAllTime ?? 0,
            showsStats: mapVM.cachedTripCount > 0,
            // Guests included, and on purpose: the avatar on the hub is local
            // state anyone can edit, and gating the tap would take the emoji
            // picker away from signed-out users, who had it before.
            onTapProfile: { push(.myProfile) },
            onTapLevel: { push(.levels) },
            onTapStats: { push(.stats) },
            onTapSettings: { showSettings = true }
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    /// The name in the header. When a signed-in account has no name yet this is
    /// a PROMPT, not a name — which is why the cards don't reuse it.
    private var headerDisplayName: String {
        let trimmed = auth.userName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard auth.isSignedIn else {
            // Soft session expiry preserves the display name on purpose —
            // demoting the hero to «Гость» right above a card saying
            // "nothing was lost" would contradict the card. Keep the name.
            if auth.needsReauth, !trimmed.isEmpty { return trimmed }
            return AppStrings.meGuestName(lang.language)
        }
        guard !trimmed.isEmpty else { return AppStrings.meAddYourName(lang.language) }
        return trimmed
    }

    /// «Здесь появятся ваши поездки» (canon). The point of the copy is the
    /// second line: recording is automatic and needs no account — that's the
    /// product's whole pitch, and the empty state is where it lands.
    private func noTripsCard(_ c: AppTheme.Colors) -> some View {
        let lng = lang.language
        return VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(c.cardAlt)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }

            Text(AppStrings.profileYourTripsWill(lng))
                .font(.inter(17, weight: .heavy))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)

            Text(AppStrings.profileRecordingStartsBy(lng))
                .font(.inter(14))
                .lineSpacing(4)
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            Button {
                Haptics.tap()
                NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
            } label: {
                Text(AppStrings.recordTripCta(lang.language))
                    .font(.inter(15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 15)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .surfaceCard(cornerRadius: 18)
        .padding(.horizontal, 16)
    }

    // MARK: - Гараж (promoted onto the Я tab)

    /// The Гараж used to be a row at the foot of the settings sheet — behind a
    /// gear, under a card of switches, four scrolls down. It is not a setting:
    /// it is a place with things in it that people open for pleasure, and it
    /// belongs on the screen about them.
    ///
    /// The section shows what the garage HAS (so the row is worth a look even
    /// when nobody taps it) and every tap lands on `GarageView` — the list,
    /// from the top. Deep-linking straight into one vehicle would need a new
    /// parameter on a screen this view does not own, and a push fired on a
    /// sheet's first frame is the kind of thing that lands on an empty stack.
    @ViewBuilder
    private func garageSection(_ c: AppTheme.Colors) -> some View {
        let l = lang.language

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProfileSectionLabel(text: AppStrings.garage(l))

                Spacer(minLength: 8)

                Button {
                    Haptics.tap()
                    push(.garage)
                } label: {
                    HStack(spacing: 5) {
                        // NOT «3 машины»: the app has no countable noun for
                        // transport (its own cap reads «5 единиц транспорта»),
                        // and pluralising it would lie about a moped.
                        Text(AppStrings.garageAllVehicles(l))
                            .font(.inter(13, weight: .semibold))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(c.textSecondary)
                    // The text is ~16pt tall; the target has to be 44. Grown
                    // with a frame and pulled back out of layout by the same
                    // amount, so the header keeps canon's 4/8 rhythm.
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -14)
                }
                .buttonStyle(.plain)
                // Kept verbatim from the settings row this replaces — the row
                // moved, so its identifier moved with it.
                .accessibilityIdentifier("settings_garage")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            Group {
                if settings.vehicles.isEmpty {
                    garageEmptyCard(c, l)
                } else {
                    garageVehiclesCard(c, l)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    /// Что сейчас с подпиской — ОДИН ответ на два места показа: раздел
    /// «Подписка» и строка чаевых в самом низу. Два вычисления одного статуса
    /// однажды разошлись бы — та же по форме находка, что у `PlusRow` в
    /// задаче 2, где на «видно ли платное» отвечали два места.
    private var proStatus: ProStatus {
        ProStatus.resolve(
            state: plusStore.state,
            expires: plusStore.displayExpiry,
            isPending: plusStore.awaitingApproval,
            storefrontHidesPlus: plusAccess.storefrontHidesPlus
        )
    }

    /// Раздел «Подписка» — под гаражом, над клубами.
    ///
    /// Строка ПРОПАДАЕТ целиком на витрине, которая платного не продаёт
    /// (`ProStatus.hiddenStorefront` → `showsRow == false`), а не
    /// показывается серой: спека §1 требует, чтобы платного не было ВИДНО, а
    /// не только чтобы оно не покупалось. Уже купивший видит строку и там —
    /// статус разбирает право ПЕРВЫМ, как `PlusGate`.
    ///
    /// Чаевые сюда БОЛЬШЕ НЕ ВХОДЯТ: с 0.8.4 они одной приглушённой строкой
    /// в самом низу «Я». Соседство с тарифом намекало, что за них что-то
    /// открывается, — а за ними не открывается ничего, и это единственное,
    /// что они обещают.

    @ViewBuilder
    private func plusSection() -> some View {
        // ОДИН ответ на «видно ли платное» — статус, а не второй гейт рядом.
        // Дата окончания берётся `displayExpiry`: при `.expired` Apple живую
        // уже не отдаёт, и показывать надо запомненную.
        let status = proStatus
        return VStack(alignment: .leading, spacing: 10) {
            if status.showsRow {
                // Заголовок раздела появился в 0.8.4 вместе со статусами: до
                // этого строка висела без имени, а теперь их в разделе две —
                // подписка и чаевые, и это разные сделки.
                ProfileSectionLabel(text: AppStrings.meProSection(lang.language))
                PlusRow(status: status) { showPaywall = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        // Оба листа висят ЗДЕСЬ, а не в цепочке `stage`: `ProfileView.body`
        // уже один раз упёрся в предел вывода типов SwiftUI на ОДНОМ
        // добавленном модификаторе (см. «Ловушки» в CLAUDE.md), и запас на
        // этом файле тратить незачем. Это презентации, а не накладки, —
        // правило «диалог вешать в корне экрана» их не касается.
        .sheet(isPresented: $showPaywall) {
            PlusPaywallSheet().environmentObject(lang)
        }
    }

    /// «Клубы — скоро» (0.6.8): под гаражом, над историей — там же, где и
    /// гараж, и по той же причине: под бесконечным списком никто не скроллит.
    /// Свой заголовок — решение владельца после QA: без него строка читалась
    /// второй карточкой раздела «Гараж».
    private func clubsSection() -> some View {
        let l = lang.language
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProfileSectionLabel(text: AppStrings.clubsTitle(l))
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            ProfileClubsRow { push(.clubs) }
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }

    /// ONE row: the vehicle currently selected as the main one.
    ///
    /// It listed all of them at first — five is the app's cap, so the card
    /// «could never run long» — but five rows is ~330pt of transport standing
    /// between the profile and История, which is the section people actually
    /// come back for. The rest are one tap away behind «Весь транспорт ›», and
    /// the header is where that promise belongs.
    @ViewBuilder
    private func garageVehiclesCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        // No explicit selection (a garage filled before the picker existed, or
        // a deleted main) falls back to the first vehicle — the same fallback
        // the rest of the app reads `selectedVehicleId` with, so the ✓ here
        // can't disagree with the one inside the Гараж.
        if let main = settings.vehicles.first(where: { $0.id == settings.selectedVehicleId })
            ?? settings.recordableVehicles.first {
            garageVehicleRow(main, isMain: true, c: c, l: l)
                .surfaceCard(cornerRadius: 16)
                .accessibilityIdentifier("profile_garage_card")
        }
    }

    private func garageVehicleRow(
        _ vehicle: Vehicle,
        isMain: Bool,
        c: AppTheme.Colors,
        l: LanguageManager.Language
    ) -> some View {
        Button {
            Haptics.tap()
            push(.garage)
        } label: {
            HStack(spacing: 12) {
                // Силуэт, а не фотография. Фотография здесь пробовалась и
                // дважды ломала строку: снимок в маленькой плитке не имеет
                // своего размера и растягивал её до настоящих пропорций кадра.
                // Превью — это упоминание машины, а не показ; фотографии живут
                // в самом гараже, куда эта строка и ведёт.
                VehicleSpritePlate(
                    assetName: vehicle.avatarImageName,
                    fallbackEmoji: vehicle.isPixelAvatar ? nil : vehicle.avatarEmoji,
                    plateSize: 44,
                    uniformHeight: true,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vehicle.name.isEmpty ? AppStrings.unnamedVehicle(l) : vehicle.name)
                            .font(.inter(14.5, weight: .bold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // The owner's only cue that others cannot see this one
                        // — same lock the Гараж card wears, same reason.
                        if !vehicle.visibleToOthers {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(c.textTertiary)
                                .accessibilityLabel(AppStrings.vehicleHiddenFromOthers(l))
                        }

                        if isMain {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                                .accessibilityLabel(AppStrings.vehicleMainLabel(l))
                        }
                    }

                    // Единица приборки ЭТОЙ машины — как на карточке гаража и
                    // в пикере: один одометр, один ответ во всех четырёх
                    // местах, где он показан.
                    Text(Measure.odometer(km: vehicle.displayOdometerKm,
                                          unit: vehicle.dashboardUnit(app: distanceUnit),
                                          lang: l))
                        .font(.inter(11.5, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VehicleLevelPill(level: vehicle.level, size: 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Nothing in the garage yet: one row that says what a vehicle is FOR here
    /// (it levels up with you), because «Гараж пуст» on its own is a dead end.
    private func garageEmptyCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            push(.garage)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.accentBg)
                        .frame(width: 44, height: 44)
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppStrings.garageEmptyTitle(l))
                        .font(.inter(14.5, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(AppStrings.garageEmptyBody(l))
                        .font(.inter(11.5))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("profile_garage_empty")
    }

    private var profileSectionsTitle: String {
        var items = [AppStrings.garage(lang.language)]
        if proStatus.showsRow { items.append("PRO") }
        items.append(AppStrings.achievementsSection(lang.language))
        items.append(AppStrings.clubsTitle(lang.language))
        return items.joined(separator: " · ")
    }

    /// Rare destinations stay one tap away, above the unbounded trip list.
    private func profileSections(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.tap()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    showsProfileSections.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(profileSectionsTitle)
                        .font(.interScaled(14, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showsProfileSections ? 180 : 0))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(c.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            .padding(.horizontal, 16)
            .accessibilityIdentifier("profile_sections_toggle")
            .accessibilityValue(showsProfileSections
                ? AppStrings.historySectionsExpanded(lang.language)
                : AppStrings.historySectionsCollapsed(lang.language))

            if showsProfileSections {
                if !allTrips.isEmpty {
                    ProfileAchievementsSection(
                        trips: allTrips,
                        onTapAll: { push(.achievements) },
                        // Straight to the award, not to the list: a
                        // tappable chip that opens a grid the user has
                        // to find the same badge in again is a chip
                        // that may as well not be tappable.
                        onTapBadge: { push(.achievement($0.id)) }
                    )
                    // Resolved HERE, not at the award destination: the
                    // chips open one directly, and a set that is still
                    // empty on the destination's first frame paints an
                    // earned badge as «Ещё не открыто» (a hidden one as
                    // «? ? ?») before flipping. Only runs while the
                    // section is actually on screen.
                    .task(id: allTrips.count) { await refreshUnlockedBadges() }
                    .padding(.bottom, 12)
                }

                garageSection(c)
                plusSection()
                clubsSection()
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - История (Figma 580:172 header · 580:122 list · 755:119 grid)

    /// Header row, calendar filter, then the trips themselves. Canon goes
    /// straight from the calendar into the cards — the month headings the
    /// pre-0.6.0 list drew are gone, the calendar names the dates now.
    @ViewBuilder
    private func historyBlock(_ c: AppTheme.Colors) -> some View {
        // One filtered array for both consumers: the calendar prints the count,
        // the list draws the rows, and they must never disagree about what
        // "matched" means.
        let trips = preparedHistory.visibleTrips

        historyHeader(c)

        ProfileHistoryCalendar(
            dateFrom: $dateFrom,
            dateTo: $dateTo,
            kmByDay: kmByDay,
            maxKmDay: maxKmDay,
            filteredCount: trips.count
        )
        .padding(.horizontal, 16)
        // Canon's 16pt gap to the first card. As padding rather than a spacer
        // so it survives a filter that matches nothing, where the calendar
        // would otherwise butt straight into «Со мной».
        .padding(.bottom, 16)

        if !trips.isEmpty {
            switch historyMode {
            case .grid:
                gridHistory(preparedHistory.gridRuns)
            case .list:
                listHistory(preparedHistory.rows)
            }
        } else {
            historyEmptyState(c)
        }
    }

    /// Сетка рисуется кусками: подряд идущие поездки — своей решёткой,
    /// путешествие — карточкой во всю ширину между ними. Растянуть клетку
    /// `LazyVGrid` на обе колонки нечем, а две половинки путешествия — не
    /// карточка.
    private func gridHistory(_ runs: [[HistoryRow]]) -> some View {
        LazyVStack(spacing: 12) {
            // Ключ — id первой строки куска, а не его номер: по номеру SwiftUI
            // считает вторую решётку той же, что была первой, и после
            // объединения плечи переезжают между кусками без анимации.
            ForEach(runs, id: \.[0].id) { run in
                if run.count == 1, case .journey(let journey, let legs) = run[0] {
                    JourneyCardView(journey: journey, legs: legs) {
                        push(.journey(journey.id))
                    }
                } else {
                    LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                        ForEach(run) { row in
                            if case .trip(let trip) = row {
                                ProfileTripTile(
                                    trip: trip,
                                    // Долгий тап открывает лист объединения —
                                    // значит удержание видно под пальцем
                                    // (CLAUDE.md, «Нажатие обязано отвечать»).
                                    pressResponse: .hold,
                                    onTap: { openTrip(trip) }
                                )
                                // `simultaneousGesture`, а не `.onLongPressGesture`:
                                // карточка — `Button`, и он забирает касание
                                // раньше, чем сработает жест сверху. Вместе с
                                // кнопкой жест доходит; тап после удержания
                                // гасит `openTrip` по `composerAnchor`.
                                //
                                // Длительность — у стиля кнопки: жест обязан
                                // сработать ровно тогда, когда плитка дожалась.
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: HoldableCardStyle.holdDuration)
                                        .onEnded { _ in openJourneyComposer(anchor: trip) }
                                )
                                // Удержание — жест, которого VoiceOver не
                                // знает: без этого действия лист объединения
                                // с озвучкой недостижим вовсе. Та же строка,
                                // что у плеча путешествия.
                                .accessibilityAction(named: Text(AppStrings.journeyCombine(lang.language))) {
                                    openJourneyComposer(anchor: trip)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        // Breathing room before «Со мной», whose own label only
        // carries a 4pt top pad.
        .padding(.bottom, 12)
    }

    private func listHistory(_ rows: [HistoryRow]) -> some View {
        // The level shown is the one held WHEN each trip was driven,
        // not today's. Same number on every card told the owner what
        // they already knew; this way the list shows them growing.
        // Search and calendar filters change which trips are visible, not
        // the XP earned before them. Folded journey legs also keep their XP.
        let historicalLevels = preparedHistory.historicalLevels
        return LazyVStack(spacing: 12) {
            ForEach(rows) { row in
                switch row {
                case .trip(let trip):
                    ProfileTripCardView(
                        trip: trip,
                        level: historicalLevels?[trip.id] ?? settings.profileLevel,
                        vehicle: settings.vehicles.first { $0.id == trip.vehicleId },
                        // Долгий тап открывает лист объединения — значит
                        // удержание видно под пальцем (CLAUDE.md, «Нажатие
                        // обязано отвечать»).
                        pressResponse: .hold,
                        onTap: { openTrip(trip) }
                    )
                    // См. комментарий у плитки выше: кнопка съедает
                    // `.onLongPressGesture`, `simultaneousGesture` — нет, а
                    // длительность приходит от стиля карточки.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: HoldableCardStyle.holdDuration)
                            .onEnded { _ in openJourneyComposer(anchor: trip) }
                    )
                    .accessibilityAction(named: Text(AppStrings.journeyCombine(lang.language))) {
                        openJourneyComposer(anchor: trip)
                    }
                case .journey(let journey, let legs):
                    JourneyCardView(journey: journey, legs: legs) {
                        push(.journey(journey.id))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    /// Two flexible columns inside the 14pt margins. Static so a scroll
    /// doesn't rebuild the descriptors on every redraw.
    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 2
    )

    private var historyMode: HistoryMode {
        HistoryMode(rawValue: historyModeRaw) ?? .list
    }

    private func historyHeader(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(AppStrings.historySection(lang.language))
                    .font(.interScaled(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(c.text)
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize { historyModeControls(c) }
            }
            if dynamicTypeSize.isAccessibilitySize { historyModeControls(c) }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(c.textSecondary)
                TextField(AppStrings.historySearch(lang.language), text: $historyQuery,
                          prompt: Text(AppStrings.historySearch(lang.language)).foregroundStyle(c.textSecondary))
                    .font(.interScaled(15))
                    .foregroundStyle(c.text)
                    .submitLabel(.search)
                    .focused($historySearchFocused)
                    .onSubmit { historySearchFocused = false }
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profile_history_search")
                if !historyQuery.isEmpty {
                    Button { historyQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(c.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.historyClearSearch(lang.language))
                    .accessibilityIdentifier("profile_history_clear_search")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(minHeight: 48)
            .background(c.card, in: RoundedRectangle(cornerRadius: 14))
            if ManualTripEntry.isVisible { historyAddButton(c) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func historyModeControls(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 4) {
            historyModeButton(.grid, systemImage: "square.grid.2x2.fill",
                              label: AppStrings.historyModeGrid(lang.language),
                              identifier: "profile_history_grid", c: c)
            historyModeButton(.list, systemImage: "line.3.horizontal",
                              label: AppStrings.historyModeList(lang.language),
                              identifier: "profile_history_list", c: c)
        }
    }

    private func historyAddButton(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            manualTripPreset = nil
            showManualTrip = true
        } label: {
            Label(AppStrings.manualTripEntry(lang.language), systemImage: "plus")
                .font(.interScaled(15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("profile_history_add")
    }

    private func historyEmptyState(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(historyQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? AppStrings.historyNoTripsInPeriod(lang.language)
                 : AppStrings.historyNoMatches(lang.language))
                .accessibilityIdentifier("profile_history_empty")
                .font(.interScaled(17, weight: .semibold))
                .foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                historyQuery = ""
                dateFrom = nil
                dateTo = nil
            } label: {
                Text(AppStrings.historyClearFilters(lang.language))
                    .font(.interScaled(15, weight: .medium))
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("profile_history_clear_filters")
            // A date always filters. Manual creation is a separate, explicit
            // action and keeps that chosen day through the purchase flow.
            if ManualTripEntry.isVisible, historyQuery.isEmpty,
               let day = dateFrom, dateTo.map({ Calendar.current.isDate(day, inSameDayAs: $0) }) ?? true {
                Button { openManualTrip(forDay: day) } label: {
                    Label(AppStrings.manualTripEntry(lang.language), systemImage: "plus")
                        .font(.interScaled(15, weight: .semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile_history_empty_add")
            }
        }
        .tint(AppTheme.accent)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 16)
        .padding(.horizontal, 16)
    }

    private func historyModeButton(
        _ mode: HistoryMode,
        systemImage: String,
        label: String,
        identifier: String,
        c: AppTheme.Colors
    ) -> some View {
        let isActive = historyMode == mode
        return Button {
            guard !isActive else { return }
            Haptics.tap()
            historyModeRaw = mode.rawValue
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? AppTheme.accent : c.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// Recompute only when the library, journeys, query, language or dates
    /// change. No count/date cache key: same-count edits must replace cards too.
    private func refreshVisibleTrips() {
        preparedHistory = PreparedProfileHistory(
            library: historyLibrary, journeys: journeys.journeys,
            query: historyQuery, from: dateFrom, to: dateTo,
            language: lang.language
        )
    }

    // MARK: - Объединение в путешествие (0.6.6)

    /// Обычный тап по карточке. Пока лист объединения открыт, он не открывает
    /// НИЧЕГО: долгое нажатие срабатывает, пока палец на экране, и кнопка
    /// карточки успевает доложить о нажатии ещё раз — уже на отпускании. Тогда
    /// поверх листа уезжал бы ещё и экран поездки.
    ///
    /// Щелчок бьётся ЗДЕСЬ, после проверки, а не внутри карточки: удержание
    /// уже отдало свой (`Haptics.action`), и второй щелчок на отпускании
    /// докладывал о переходе, которого не будет, — одно нажатие отвечало
    /// дважды.
    private func openTrip(_ trip: Trip) {
        guard composerAnchor == nil else { return }
        Haptics.tap()
        push(.trip(trip.id))
    }

    /// Долгое нажатие на карточку в «Мои» — тот же лист, что и с экрана
    /// поездки: соседей ±7 дней он найдёт сам, а человеку остаётся снять
    /// лишние. Отклик — самый заметный из наших: человек держал палец дольше,
    /// чем при обычном тапе, и должен понять, что это было нарочно.
    private func openJourneyComposer(anchor: Trip) {
        Haptics.action()
        composerPreselected = nil
        composerAnchor = anchor
    }

    /// Лист объединения. `preselected` заполнен только у подсказки — она уже
    /// собрала цепочку, и досыпать ей соседей значит переспросить о том, на
    /// что человек только что ответил.
    private func journeyComposer(anchor: Trip) -> some View {
        JourneyComposerSheet(anchor: anchor, preselected: composerPreselected) { _ in
            // Тот же лист приходит и из подсказки: путешествие создано,
            // предлагать его второй раз не о чем.
            suggestedTrips = []
            toastItem = ToastItem(
                type: .success,
                message: AppStrings.journeyCreated(lang.language)
            )
        }
        .environmentObject(lang)
        .environmentObject(themeManager)
        .contentSizedSheet(background: AppTheme.colors(for: scheme).bg)
    }

    // MARK: - Подсказка путешествия (0.6.6)

    /// Отказ помнится по id ПОСЛЕДНЕЙ поездки цепочки: она же и закрывает
    /// цепочку возвращением домой, то есть не изменится, даже если человек
    /// потом допишет поездку внутрь окна. По первой поездке ключ уезжал бы
    /// вместе с любой более ранней записью, и «не сейчас» пришлось бы жать
    /// снова. Сам ключ живёт в `SettingsManager`: его стирает «Удалить
    /// аккаунт», и второй литерал там разошёлся бы с этим молча.
    private static let dismissedSuggestionKey = SettingsManager.dismissedJourneySuggestionKey

    /// Контейнер стоит ВСЕГДА, а карточки появляются и исчезают внутри него.
    ///
    /// Пружина висит здесь, а не в обработчиках: `withAnimation` в них
    /// анимировал только исчезновение — появление приходило из фонового счёта,
    /// мимо любого `withAnimation`, и карточка возникала рывком. Пустой
    /// контейнер ничего не занимает: нижний отступ он берёт только когда
    /// внутри что-то есть.
    private func journeyPrompts() -> some View {
        let hasPrompts = homeCandidate != nil || !suggestedTrips.isEmpty
        return VStack(spacing: 12) {
            if let home = homeCandidate {
                HomeQuestionCard(
                    place: homeCandidateName,
                    onYes: { acceptHome(home) },
                    onNo: { declineHome() }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !suggestedTrips.isEmpty {
                JourneySuggestionBanner(
                    subtitle: suggestionSubtitle,
                    onCombine: { combineSuggestion() },
                    onDismiss: { dismissSuggestion() }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, hasPrompts ? 12 : 0)
        .animation(Self.promptSpring, value: homeCandidate != nil)
        .animation(Self.promptSpring, value: suggestedTrips.isEmpty)
    }

    /// Одна пружина на обе карточки: они задают вопрос одной формы и уезжать
    /// обязаны одинаково.
    private static let promptSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Считает вопрос про дом и подсказку. Зовётся из `loadAggregates` — то
    /// есть на входе в «Мои» и на `.tripRecordingEnded`. Не из `MapViewModel`:
    /// запись поездки не обязана знать про путешествия, а человек всё равно
    /// увидит карточку только здесь.
    ///
    /// Оба правила ходят по ВСЕЙ библиотеке, поэтому считаются в стороне от
    /// главного потока — рядом с `loadAggregates`, по тем же причинам.
    private func refreshJourneyPrompts(trips: [Trip]) async {
        guard let home = settings.homeLocation else {
            // Дом неизвестен — подсказок нет: без него «ночь не дома»
            // неотличима от ночи дома, и любая подсказка была бы монеткой.
            suggestedTrips = []
            // Спрашивать ли — решает `JourneySuggester.shouldAskHome`: «нет»
            // держится месяц, «да» навсегда.
            guard JourneySuggester.shouldAskHome(
                homeLocation: nil,
                homeAsked: settings.homeAsked,
                declinedAt: settings.homeDeclinedAt,
                now: Date()
            ) else { homeCandidate = nil; return }
            let candidate = await Task.detached(priority: .utility) {
                JourneySuggester.inferHome(trips: trips)
            }.value
            guard !Task.isCancelled else { return }
            homeCandidate = candidate
            // Батч из одной координаты — не крюк ради экономии: та же очередь
            // в фоновый контекст, что и у подписи цепочки ниже, а не свой
            // синхронный `cachedLocality` на главном потоке.
            if let candidate {
                let localities = await mapVM.tripManager.cachedLocalities(for: [candidate])
                guard !Task.isCancelled else { return }
                homeCandidateName = placeName(candidate, localities: localities)
            } else {
                homeCandidateName = ""
            }
            return
        }
        homeCandidate = nil
        let existing = journeys.journeys
        let now = Date()
        let chain = await Task.detached(priority: .utility) {
            JourneySuggester.suggestion(trips: trips, home: home, existing: existing, now: now)
        }.value
        guard !Task.isCancelled else { return }
        let dismissed = UserDefaults.standard.string(forKey: Self.dismissedSuggestionKey)
        guard let chain, chain.last?.id.uuidString != dismissed else {
            suggestedTrips = []
            return
        }
        // Имена мест — одним запросом в фоновом контексте, ДО того как
        // подпись соберётся: своя выборка на каждое плечо шла бы в главный
        // `viewContext` ровно в тот момент, когда экран рисуется.
        let ends = chain.dropLast().compactMap { JourneyAggregate.endCoordinate(of: $0) }
        let localities = await mapVM.tripManager.cachedLocalities(for: ends)
        guard !Task.isCancelled else { return }
        suggestionSubtitle = subtitleText(for: chain, localities: localities)
        suggestedTrips = chain
    }

    /// «Владикавказ, Тбилиси · 6 поездок».
    ///
    /// Имена берутся у концов поездок, кроме последней: она кончилась дома, и
    /// «Краснодар» в списке того, КУДА ездили, — не ответ, а шум. Дальше двух
    /// имён строка не растёт: карточка про то, узнал человек свою поездку или
    /// нет, а не про маршрутный лист.
    private func subtitleText(for chain: [Trip], localities: [String: String]) -> String {
        var names: [String] = []
        for trip in chain.dropLast() {
            guard let end = JourneyAggregate.endCoordinate(of: trip),
                  let name = localities[TripManager.geocodeCacheKey(for: end)],
                  !names.contains(name) else { continue }
            names.append(name)
            if names.count == 2 { break }
        }
        let count = "\(chain.count) \(AppStrings.nounTrips(lang.language, chain.count))"
        return names.isEmpty ? count : names.joined(separator: ", ") + " · " + count
    }

    /// Имя места из батч-словаря `cachedLocalities`, иначе координата. Точка
    /// вместо запятой намеренно: координата — техническое число, а не «45,03»
    /// в русской записи, где разделитель пары стал бы неотличим от
    /// разделителя дробной части.
    private func placeName(_ coordinate: CLLocationCoordinate2D, localities: [String: String]) -> String {
        if let name = localities[TripManager.geocodeCacheKey(for: coordinate)] { return name }
        return String(format: "%.3f, %.3f", coordinate.latitude, coordinate.longitude)
    }

    private func acceptHome(_ home: CLLocationCoordinate2D) {
        settings.homeLocation = home
        settings.homeAsked = true
        homeCandidate = nil
        // Дом появился — подсказка может быть готова прямо сейчас, и ждать
        // следующей поездки, чтобы её показать, незачем. Счётчик, а не
        // `Task {}`: работа висит на `.task(id:)` экрана и умирает вместе с
        // ним, а не догоняет ушедшего человека фоновым перебором библиотеки.
        homeAcceptedTick += 1
    }

    private func declineHome() {
        // «Нет» — это на месяц, а не навсегда (`JourneySuggester.homeReaskDelay`).
        // Чаще всего он означает, что ночей ещё мало и вывод показал работу
        // вместо двора; вернуть вопрос человеку было бы нечем — задать дом
        // руками в 0.6.6 нельзя.
        settings.homeDeclinedAt = Date()
        homeCandidate = nil
    }

    private func combineSuggestion() {
        guard let anchor = suggestedTrips.first else { return }
        composerPreselected = suggestedTrips
        composerAnchor = anchor
    }

    private func dismissSuggestion() {
        if let last = suggestedTrips.last {
            UserDefaults.standard.set(last.id.uuidString, forKey: Self.dismissedSuggestionKey)
        }
        suggestedTrips = []
    }

    // MARK: - Guest sign-in card (Figma 424:128 — kept byte-identical)

    /// Guest sync card: explains sync and signs in DIRECTLY via the shared
    /// Apple button — no sheet hop. The footnote is the "можно позже"
    /// affordance; the card just stays.
    /// Разовая карточка про новую видимость (0.6.3).
    ///
    /// 0.6.3 включил пер-блочную видимость с дефолтом «всё открыто». Дефолт
    /// выбран сознательно, иначе фича родилась бы мёртвой — но у существующих
    /// аккаунтов наружу поехало то, на что они не подписывались, и единственное,
    /// что делает такой дефолт честным, это сказать о нём один раз и тут же
    /// дать настройку. Обе кнопки закрывают карточку навсегда: человек либо
    /// пошёл настраивать, либо решил, что его всё устраивает.
    private func visibilityNoticeCard(_ c: AppTheme.Colors) -> some View {
        let l = lang.language
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accentBg)
                    Image(systemName: "eye.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.visibilityNoticeTitle(l))
                        .font(.inter(14, weight: .bold))
                        .foregroundStyle(c.text)
                    Text(AppStrings.visibilityNoticeBody(l))
                        .font(.inter(12))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    dismissVisibilityNotice()
                    // Флаг ВЫСТАВЛЯЕТСЯ РАНЬШЕ показа и отдельным тиком:
                    // замыкание `.sheet` читает его в момент презентации, и
                    // выставленный в той же транзакции он мог приехать туда
                    // ещё false — лист открывался бы без перехода в приватность.
                    opensPrivacyFromNotice = true
                    Task { @MainActor in showSettings = true }
                } label: {
                    Text(AppStrings.visibilityNoticeConfigure(l))
                        .font(.inter(13, weight: .bold))
                        .foregroundStyle(c.card)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    dismissVisibilityNotice()
                } label: {
                    Text(AppStrings.visibilityNoticeDismiss(l))
                        .font(.inter(13, weight: .bold))
                        .foregroundStyle(c.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(c.card, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(AppTheme.accentBg, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("visibility_notice_card")
    }

    /// `isPublicProfile` заполняет только `/auth/me`, а звали его лишь
    /// «Облачная синхронизация» и «Приватность». Без этого вызова флаг на
    /// холодном старте всегда nil — и разовая карточка, и гейт тумблеров
    /// видимости не срабатывали бы, пока человек сам не зайдёт в приватность.
    /// То есть ровно наоборот их назначению.
    private func primeVisibilityState() async {
        if auth.isSignedIn, auth.isPublicProfile == nil {
            await auth.refreshMe()
        }
        refreshVisibilityNotice()
    }

    private func refreshVisibilityNotice() {
        showsVisibilityNotice = VisibilityNoticeLatch.needsShow(
            isSignedIn: auth.isSignedIn, isPublicProfile: auth.isPublicProfile)
    }

    private func dismissVisibilityNotice() {
        VisibilityNoticeLatch.markShown()
        withAnimation(.easeOut(duration: 0.2)) { showsVisibilityNotice = false }
    }

    private func guestSignInCard(_ c: AppTheme.Colors) -> some View {
        // Soft session expiry wears the same card with different words: the
        // user did nothing wrong and lost nothing — the copy must say so
        // instead of re-pitching Cloud Sync to someone who already opted in.
        let expired = auth.needsReauth
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                // Figma 424:130 — the cloud sits on a 30×30 pale-peach
                // rounded-square tile (same treatment as SettingsIconRow),
                // not as a bare floating glyph.
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.accentBg)
                    Image(systemName: expired ? "person.crop.circle.badge.exclamationmark" : "icloud.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.syncCardKicker(lang.language))
                        .font(.inter(11, weight: .bold))
                        .kerning(0.22)
                        .foregroundStyle(c.textTertiary)
                    Text(expired
                         ? AppStrings.sessionExpiredTitle(lang.language)
                         : AppStrings.syncCardTitle(lang.language))
                        .font(.inter(15, weight: .bold))
                        .foregroundStyle(c.text)
                    Text(expired
                         ? AppStrings.sessionExpiredBody(lang.language)
                         : AppStrings.syncCardBody(lang.language))
                        .font(.inter(12.5))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }

            AppleSignInButton(
                cornerRadius: 999,
                height: 43,
                onError: { _ in
                    // ProfileView's existing alert (driven by lastAuthError)
                    // is this card's error surface; make sure ASAuthorization
                    // failures reach it too (API failures already set it).
                    if auth.lastAuthError == nil {
                        auth.lastAuthError = .transport("Apple sign-in failed")
                    }
                }
            )

            // "You can do it later" is a first-pitch line; after a session
            // expiry it reads as permission to ignore a broken sync.
            if !expired {
                Text(AppStrings.syncCardLater(lang.language))
                    .font(.inter(11))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .padding(14)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        .accessibilityIdentifier("profile_guest_signin")
    }

    // MARK: - First-trip welcome (0 trips)

    /// Friendly empty-state replacement for the stats stack on first launch
    /// (cachedTripCount == 0). Tap routes to the Tracking tab — the one
    /// action that matters before any data exists.
    ///
    /// Second button (0.8.0, §4б): «Вписать прошлую поездку», под тем же
    /// гейтом, что «+» в шапке «Истории» — на витрине, которая не продаёт
    /// платное, её нет вовсе; без «Плюса» замок ведёт в тот же пейвол.
    private func firstTripWelcomeCard(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 10) {
            recordFirstTripRow(c)
            if ManualTripEntry.isVisible {
                writePastTripRow(c)
            }
        }
    }

    private func recordFirstTripRow(_ c: AppTheme.Colors) -> some View {
        let lng = lang.language
        return Button {
            Haptics.tap()
            NotificationCenter.default.post(name: .switchToTrackingTab, object: nil)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentBg)
                        .frame(width: 52, height: 52)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppStrings.profileRecordYourFirst(lng))
                        .font(.inter(15, weight: .semibold))
                        .foregroundStyle(c.text)
                    Text(AppStrings.profileYourKilometersStreaks(lng))
                        .font(.inter(12))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("profile_welcome_record")
    }

    private func writePastTripRow(_ c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            manualTripPreset = nil
            showManualTrip = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: ManualTripEntry.isLocked ? "lock.fill" : "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ManualTripEntry.isLocked ? c.textTertiary : AppTheme.accent)
                Text(AppStrings.manualTripEntry(lang.language))
                    .font(.inter(14, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .surfaceCard(cornerRadius: 16)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("profile_welcome_manual_trip")
    }

    // MARK: - Data

    /// Library-wide ordering, historical levels and km-per-day values are
    /// prepared off the main actor once per load, never in `body`.
    private struct HistoryData {
        let library: ProfileHistoryLibrary
        var trips: [Trip] { library.trips }
        let kmByDay: [Date: Double]
        let maxKmDay: Double

        init(trips: [Trip], calendar: Calendar) {
            // The repository already sorts newest-first. Keep this invariant
            // even for another fetch path or a test double.
            let sortedTrips = trips.sorted { $0.startDate > $1.startDate }
            self.library = ProfileHistoryLibrary(trips: sortedTrips)
            var byDay: [Date: Double] = [:]
            for trip in sortedTrips {
                byDay[calendar.startOfDay(for: trip.startDate), default: 0] += trip.distance / 1000
            }
            self.kmByDay = byDay
            self.maxKmDay = byDay.values.max() ?? 0
        }
    }

    /// Fetch (StatsCache-aware, main) → crunch (detached) → publish (@State).
    private func loadAggregates() async {
        let tripManager = mapVM.tripManager
        let count = tripManager.fetchTripCount()
        let lastDate = tripManager.fetchLastTripDate()
        let trips: [Trip]
        if let cached = StatsCache.tripsIfValid(currentCount: count, currentLastDate: lastDate) {
            trips = cached
        } else {
            // ASYNC on purpose. `loadAggregates` runs on the MainActor (it is
            // a view's `.task`), so the synchronous read decoded every
            // polyline in the library on the main thread — the whole Я tab,
            // its scroll and the tab bar under it, frozen until the last trip
            // came back. The crunch below was already detached; this is the
            // half that was not.
            trips = await tripManager.fetchTripsAsync()
            StatsCache.update(trips: trips, count: count, lastDate: lastDate)
        }
        // Same fetch feeds both — История must not open a second read of the
        // library just to show more than the aggregates' last 10.
        let calendar = Calendar.current
        let crunched = await Task.detached(priority: .userInitiated) {
            () -> (aggregates: MeAggregates, history: HistoryData) in
            let aggregates = MeAggregates.compute(trips: trips, now: Date(), calendar: calendar)
            return (aggregates, HistoryData(trips: trips, calendar: calendar))
        }.value
        guard !Task.isCancelled else { return }
        agg = crunched.aggregates
        historyLibrary = crunched.history.library
        kmByDay = crunched.history.kmByDay
        maxKmDay = crunched.history.maxKmDay
        // Every path that reloads the library lands here — a deleted trip has
        // to leave the filtered list too, or its card stays and opens an empty
        // detail screen.
        refreshVisibleTrips()
        // Подсказка считается по ВСЕЙ библиотеке, а не по отрезку календаря:
        // цепочка «туда и обратно» не должна рваться из-за фильтра, который
        // человек поставил совсем для другого.
        await refreshJourneyPrompts(trips: crunched.history.trips)
        // Черновиков единицы, и выборка без точек трека — дёшево и здесь.
        drafts = tripManager.fetchDraftTrips()
    }
}
