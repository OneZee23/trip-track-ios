import SwiftUI
import CoreLocation

/// Чужой паспорт машины — экраны 17 и 18 канона 0.6.4.
///
/// Один экран на оба состояния: «18 · фото и карта закрыты» — это не отдельный
/// экран, а тот же самый без двух блоков. Скрытое ИСЧЕЗАЕТ, а не заменяется
/// плашкой «скрыто»: плашка сообщила бы, что там что-то есть.
///
/// Рекорды считаются по ПУБЛИЧНЫМ поездкам — сервер приватных не отдаёт.
/// Подпись об этом стоит под ними намеренно: у владельца те же рекорды будут
/// другими, и без объяснения расхождение читается как ошибка.
struct PublicVehicleView: View {
    let accountId: UUID
    let vehicleId: UUID
    let ownerName: String?
    /// Машина из списка гаража — чтобы шапка нарисовалась сразу, а не после
    /// круга загрузки. Полные данные всё равно догружаются.
    let preloaded: PublicVehicle?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var vehicle: PublicVehicle?
    @State private var trips: [Trip] = []
    @State private var agg: MeAggregates?
    @State private var regionCount = 0
    @State private var cityCount = 0
    @State private var routes: [[CLLocationCoordinate2D]] = []
    @State private var failed = false
    @State private var showActions = false
    @State private var showReport = false
    /// Жалоба на КОНКРЕТНЫЙ снимок. Отдельно от жалобы на машину: модерации
    /// нужно знать, что именно смотреть, а «пожаловаться на машину» из-за
    /// одной фотографии — это заявка, по которой непонятно, что делать.
    @State private var reportPhoto: ReportedPhoto?

    /// Обёртка вместо расширения `UUID: Identifiable`: такое расширение
    /// подцепилось бы ко всему проекту и однажды выстрелило бы в чужом месте.
    private struct ReportedPhoto: Identifiable { let id: UUID }
    @State private var showSignIn = false

    init(accountId: UUID, vehicleId: UUID, ownerName: String?, preloaded: PublicVehicle? = nil) {
        self.accountId = accountId
        self.vehicleId = vehicleId
        self.ownerName = ownerName
        self.preloaded = preloaded
        _vehicle = State(initialValue: preloaded)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            nav(c: c, l: l)
            ScrollView {
                VStack(spacing: 12) {
                    if let v = vehicle {
                        header(v, c: c, l: l)
                        if let about = v.about, !about.isEmpty {
                            aboutCard(about, c: c, l: l)
                        }
                        photosCard(v, c: c, l: l)
                        // Карта — только если владелец её не выключил. Нет
                        // флага (старый сервер) трактуем как «не показывать»:
                        // молчание не разрешение.
                        if v.mapVisible == true, !routes.isEmpty {
                            mapCard(c: c, l: l)
                        }
                        if let agg, agg.tripCount > 0 {
                            records(agg, c: c, l: l)
                            Text(AppStrings.publicRecordsNote(l))
                                .font(.system(size: 11))
                                .foregroundStyle(c.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if failed {
                            Text(AppStrings.garageLoadFailed(l))
                                .font(.system(size: 12))
                                .foregroundStyle(c.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else if failed {
                        unavailable(c: c, l: l)
                    } else {
                        CarLoadingView().padding(.top, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg.ignoresSafeArea())
        // У экрана СВОЯ шапка с шевроном, поэтому системный навбар прячем —
        // иначе на экране две кнопки «назад», и непонятно, чем они разные.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: vehicleId) { await load() }
        // Домовой список действий, не системное меню — см. «Dialogs» в CLAUDE.md.
        .sheet(isPresented: $showActions) {
            ActionPopoverList(items: actionItems(l))
                .presentationDetents([.height(140)])
        }
        .sheet(item: $reportPhoto) { shot in
            ReportSheet(target: .vehiclePhoto(shot.id))
                .environmentObject(lang)
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(target: .vehicle(vehicleId))
                .environmentObject(lang)
        }
        .sheet(isPresented: $showSignIn) {
            // Общий повод: жалоба — не «реакция» и не «подписка», для неё
            // отдельного текста нет, и выдумывать его ради одного экрана
            // значит заводить строку, которую больше нигде не прочитают.
            SignInPromptSheet(action: .generic)
                .environmentObject(lang)
        }
    }

    // MARK: - Шапка

    private func nav(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(vehicle?.name ?? "")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(c.text)
                if let ownerName {
                    Text(ownerName)
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.text)
                        // 44×44 — минимум, ниже которого палец промахивается,
                        // а VoiceOver читает «кнопка» без имени: у картинки
                        // подписи нет, и системный ярлык её не заменяет.
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(AppStrings.back(l))
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private func header(_ v: PublicVehicle, c: AppTheme.Colors,
                        l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            VehicleSpritePlate(
                assetName: VehicleAvatar.assetName(
                    style: v.avatarStyle, avatar: v.avatarEmoji),
                fallbackEmoji: v.avatarEmoji,
                plateSize: 210,
                cornerRadius: 20
            )
            .padding(.top, 4)

            Text(v.name)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.top, 12)

            if let sub = v.modelLine(l) {
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            if v.isSold {
                Text(AppStrings.publicVehicleSold(l))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 6)
            }
            // Номер показывается, только если владелец его открыл. Сервер в
            // противном случае просто не присылает поле.
            if let plate = v.plate, !plate.isEmpty {
                VehiclePlateChip(plate: plate).padding(.top, 8)
            }
            LvlPill(level: v.level, rankTitle: "").padding(.top, 12)

            // Круги — только когда есть чем их наполнить. При выключенной
            // владельцем карте сервер геометрию не отдаёт, и рядом с шестизначным
            // пробегом и LVL 7 висело «0 поездок · 0 регионов · 0 дней»: экран
            // противоречил сам себе и заодно докладывал, что человек что-то
            // прячет. Доктрина этого экрана — скрытое ИСЧЕЗАЕТ, а не заменяется
            // нулями.
            if (v.mapVisible ?? false), (agg?.tripCount ?? 0) > 0 {
                // Разделитель тоже внутри: без кругов он оставался висеть
                // чертой, отделяющей шапку от пустоты.
                Divider().overlay(c.border).padding(.top, 16)
                circles(c: c, l: l).padding(.top, 14)
            }

            Divider().overlay(c.border).padding(.top, 14)
            HStack(spacing: 8) {
                if let created = v.createdAt {
                    Text(AppStrings.inGarageSince(
                        l, when: StatsPeriodFormat.monthYearGenitive(created, l)))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer(minLength: 8)
                // «…» существует ради ОДНОГО пункта — жалобы. Без входа в
                // жалобу на пользовательский контент релиз заворачивают.
                Button {
                    Haptics.tap()
                    showActions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(c.cardAlt, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .surfaceCard(cornerRadius: 20)
    }

    private func circles(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let count = agg?.tripCount ?? 0
        let days = Set(trips.map { Calendar.current.startOfDay(for: $0.startDate) }).count
        return HStack(spacing: 0) {
            circle(String(count), AppStrings.nounTrips(l, count), c: c)
            circle(String(regionCount), AppStrings.nounRegions(l, regionCount), c: c)
            circle(String(days), AppStrings.nounDays(l, days), c: c)
        }
    }

    private func circle(_ value: String, _ label: String, c: AppTheme.Colors) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .heavy)).foregroundStyle(c.text)
            Text(label).font(.system(size: 11)).foregroundStyle(c.textTertiary)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Блоки

    /// Фотографии машины — то, ради чего в чужой паспорт и заходят.
    ///
    /// Скрытые снимки не приезжают вовсе (сервер их не кладёт в ответ), и
    /// плашки «фотографии скрыты» здесь нет намеренно: она отличала бы
    /// человека, который прячет, от человека, которому нечего показать.
    @ViewBuilder
    private func photosCard(_ v: PublicVehicle, c: AppTheme.Colors,
                            l: LanguageManager.Language) -> some View {
        let shots = v.photos ?? []
        if !shots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let main = shots.first(where: { $0.isMain }) ?? shots.first {
                    remoteImage(main.best, height: 190, corner: 16)
                        .contextMenu { reportItem(main.id, l) }
                }
                let rest = shots.filter { $0.id != (shots.first(where: { $0.isMain }) ?? shots[0]).id }
                if !rest.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(rest) { shot in
                                remoteImage(shot.thumb, height: 84, corner: 12)
                                    .frame(width: 110)
                                    .contextMenu { reportItem(shot.id, l) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Пожаловаться на снимок. Долгий тап — платформенный жест для медиа, и
    /// для действия, которое совершают раз в год, он уместен; на саму машину
    /// жалоба лежит в видимом «…» в шапке.
    @ViewBuilder
    private func reportItem(_ photoId: UUID, _ l: LanguageManager.Language) -> some View {
        Button(role: .destructive) {
            Haptics.tap()
            reportPhoto = ReportedPhoto(id: photoId)
        } label: {
            Label(AppStrings.reportProfileAction(l), systemImage: "flag")
        }
    }

    /// Одна форма для всех снимков: пока грузится — фон, а не пустота, иначе
    /// карточка прыгает по высоте на каждой загрузке.
    private func remoteImage(_ url: URL?, height: CGFloat, corner: CGFloat) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(Color.gray.opacity(0.18))
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }

    private func aboutCard(_ about: String, c: AppTheme.Colors,
                           l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(about).font(.system(size: 13)).foregroundStyle(c.text)
            if let ownerName {
                Text(AppStrings.publicAboutBy(l, name: ownerName))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func mapCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.vehicleWhereWas(l))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
                Text(placesLine(l))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }
            VehicleMiniMap(routes: routes)
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func placesLine(_ l: LanguageManager.Language) -> String {
        let r = "\(regionCount) " + AppStrings.nounRegions(l, regionCount)
        let city = "\(cityCount) " + AppStrings.nounCities(l, cityCount)
        return r + " · " + city
    }

    private func records(_ a: MeAggregates, c: AppTheme.Colors,
                         l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.statsRecords(l), color: c.textSecondary)
            record(AppStrings.recordLongest(l),
                   a.longestTripTitle ?? a.longestTripRegion ?? "—",
                   GarageFormat.odometer(a.longestTripKm, lng: l) + " " + AppStrings.km(l),
                   dot: AppTheme.green, c: c)
            if let peak = trips.max(by: { $0.elevation < $1.elevation }), peak.elevation > 0 {
                record(AppStrings.recordHighest(l),
                       peak.title ?? peak.region ?? "—",
                       GarageFormat.odometer(peak.elevation, lng: l) + " " + AppStrings.unitMeters(l),
                       dot: AppTheme.accent, c: c)
            }
        }
    }

    private func record(_ label: String, _ subtitle: String, _ value: String,
                        dot: Color, c: AppTheme.Colors) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundStyle(c.textTertiary)
                Text(subtitle).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 15, weight: .heavy)).foregroundStyle(c.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surfaceCard(cornerRadius: 16)
    }

    /// Машина скрыта или удалена — и это ОДИН ответ на оба случая: сообщение
    /// не должно подтверждать, что такая машина существует.
    private func unavailable(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 8) {
            Text(AppStrings.publicVehicleUnavailable(l))
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Действия

    private func actionItems(_ l: LanguageManager.Language) -> [ActionPopoverList.Item] {
        [
            .init(title: AppStrings.reportProfileAction(l), systemImage: "flag", isDestructive: true) {
                showActions = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 260_000_000)
                    // Гостю жалоба тоже доступна — но сначала вход: без
                    // аккаунта её некому приписать и не с кем разбираться.
                    if AuthService.shared.isSignedIn { showReport = true }
                    else { showSignIn = true }
                }
            },
        ]
    }

    // MARK: - Загрузка

    private func load() async {
        failed = false
        async let full = loadVehicle()
        async let biography = loadTrips()
        let (v, bio) = await (full, biography)
        if let v { vehicle = v } else if vehicle == nil { failed = true }
        if let bio {
            trips = bio.trips
            agg = bio.agg
            regionCount = bio.regions
            cityCount = bio.cities
            routes = bio.routes
        } else if v?.mapVisible == true {
            failed = true
        }
    }

    private func loadVehicle() async -> PublicVehicle? {
        try? await APIClient.shared.get(
            APIEndpoint.userVehicle(accountId.uuidString, vehicleId.uuidString),
            requiresAuth: AuthService.shared.isSignedIn)
    }

    private struct Biography {
        var trips: [Trip]
        var agg: MeAggregates
        var regions: Int
        var cities: Int
        var routes: [[CLLocationCoordinate2D]]
    }

    private func loadTrips() async -> Biography? {
        let source = RemoteTripSource(accountId: accountId, vehicleId: vehicleId)
        let res = await source.load()
        guard !res.failed else { return nil }
        let mine = res.trips
        guard !mine.isEmpty else {
            return Biography(trips: [], agg: MeAggregates(), regions: 0, cities: 0, routes: [])
        }
        await RegionAtlas.shared.loadIfNeeded()
        let exploration = MapExploration.build(
            trips: mine,
            visitedHashes: TerritoryManager.geohashes(
                fromTrips: mine.map { $0.previewCoordinates }, precision: 6),
            atlas: RegionAtlas.shared)
        return Biography(
            trips: mine,
            agg: MeAggregates.compute(trips: mine, now: Date(), calendar: .current),
            regions: exploration.regions.count,
            cities: exploration.regions.reduce(0) { $0 + $1.visitedCityCount },
            routes: mine.map { $0.previewCoordinates }.filter { $0.count >= 2 })
    }
}
