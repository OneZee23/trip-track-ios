import SwiftUI
import MapKit

/// Что именно печатает карточка находки — посчитано ДО `body`.
///
/// Чистая функция от находки, языка и одного флага облака: карточка
/// открывается из трёх мест (сетка журнала, тап по печати на карте, переход
/// `.navigateToDiscovery`), и три места не имеют права решать по-своему, что
/// показывать у секрета без истории и что писать вместо имени
/// первооткрывателя. Тот же приём, что у `JournalBuilder` и
/// `TripSegmentMetrics`: правило проверяется тестом, а не открытым экраном.
struct DiscoveryCardModel: Equatable {

    /// Круг загадки на мини-карте.
    ///
    /// Радиус подсказки НЕ хранится: он считался от плотности открытого вокруг
    /// (`RiddleHint.radiusMetres`) в тот день, когда круг стоял на карте, и
    /// задним числом его не восстановить. Зато точка решённой загадки известна
    /// точно — значит круг рисуется вокруг НЕЁ и самым тесным из радиусов
    /// подсказки. Это напоминание о форме загадки, а не сама подсказка: искать
    /// в нём уже нечего.
    struct Circle: Equatable {
        let centre: CLLocationCoordinate2D
        let radiusMetres: Double

        static func == (lhs: Circle, rhs: Circle) -> Bool {
            lhs.centre.latitude == rhs.centre.latitude
                && lhs.centre.longitude == rhs.centre.longitude
                && lhs.radiusMetres == rhs.radiusMetres
        }
    }

    let kind: DiscoveryKind
    let symbol: SealSymbol
    /// Вид словом («СЕКРЕТ») — шапка карточки, она же подпись медальона.
    let kindLabel: String
    /// Имя находки: название секрета, имя объекта загадки, заголовок вехи.
    /// `nil` — нерассказанный секрет: тогда на карточке только печать и дата.
    let title: String?
    /// История секрета. В проде — только то, что прислал сервер; в Debug на её
    /// месте стоит заглушка, чтобы карточку было видно до волны 3.
    let story: String?
    /// Строка под датой: у загадки — про что она была, у вехи — где случилось.
    let detail: String?
    /// Своя дата находки, полная («18 июня 2026»).
    let dateLine: String
    /// «решена проездом 12.09» — только у загадки.
    let solvedLine: String?
    /// «нашли 7 человек · первым — Илья». `nil` без Cloud Sync и без ответа
    /// сервера: ноль вместо «не спрашивали» — это не осторожность, а враньё.
    let findersLine: String?
    /// Мини-карта с кругом — только у загадки.
    let circle: Circle?
    /// Кнопка «На карте». Её нет, когда карточку открыли С КАРТЫ: вести
    /// человека туда, где он уже стоит, — обещание без содержания.
    let showsOnMap: Bool

    /// Самый тесный радиус подсказки (`RiddleHint.minRadiusMetres`).
    static var riddleCircleMetres: Double { RiddleHint.minRadiusMetres }

    static func make(
        discovery: Discovery,
        cloudSync: Bool,
        lang: LanguageManager.Language,
        showsOnMap: Bool = false
    ) -> DiscoveryCardModel {
        DiscoveryCardModel(
            kind: discovery.kind,
            symbol: discovery.symbol,
            kindLabel: AppStrings.sealKind(lang, kind: discovery.kind),
            title: title(for: discovery, lang),
            story: story(for: discovery, lang),
            detail: detail(for: discovery, lang),
            dateLine: Self.dayMonthYear[lang]?.string(from: discovery.foundAt) ?? "",
            solvedLine: solvedLine(for: discovery, lang),
            findersLine: findersLine(for: discovery, cloudSync: cloudSync, lang),
            circle: discovery.kind == .riddle
                ? Circle(centre: discovery.coordinate, radiusMetres: riddleCircleMetres)
                : nil,
            showsOnMap: showsOnMap
        )
    }

    /// Имя объекта, если оно есть; иначе — слова, собранные из ключа.
    ///
    /// У вехи имени в базе нет вовсе (оно зависит от языка телефона), у
    /// безымянной загадки бандла — тоже. У секрета без ответа сервера имени
    /// нет и взять его неоткуда: в каталоге лежит только хеш ячейки.
    private static func title(
        for discovery: Discovery, _ lang: LanguageManager.Language
    ) -> String? {
        if let name = discovery.title, !name.isEmpty { return name }
        switch discovery.kind {
        case .milestone: return MilestoneCopy.title(forKey: discovery.key, lang)
        case .riddle:    return AppStrings.riddleSolvedTitle(lang)
        case .secret:    return nil
        }
    }

    /// История — только у секрета и только та, что приехала с сервера.
    ///
    /// В Debug её место занимает заглушка: каталог секретов до волны 3 пуст, и
    /// без неё карточку секрета на симуляторе не увидеть вовсе. В проде
    /// заглушки НЕТ — обещать «историю с обновлением» тому, у кого выключен
    /// Cloud Sync, значит обещать то, чего не будет.
    private static func story(
        for discovery: Discovery, _ lang: LanguageManager.Language
    ) -> String? {
        if let story = discovery.story, !story.isEmpty { return story }
        #if DEBUG
        return discovery.kind == .secret ? AppStrings.cardStoryPending(lang) : nil
        #else
        return nil
        #endif
    }

    private static func detail(
        for discovery: Discovery, _ lang: LanguageManager.Language
    ) -> String? {
        switch discovery.kind {
        case .riddle:
            return RiddleCopy.line(for: RiddleCopy.type(ofRiddleKey: discovery.key), lang)
        case .milestone:
            return MilestoneCopy.place(forKey: discovery.key, lang)
        case .secret:
            return nil
        }
    }

    private static func solvedLine(
        for discovery: Discovery, _ lang: LanguageManager.Language
    ) -> String? {
        guard discovery.kind == .riddle else { return nil }
        let day = Self.dayMonth[lang]?.string(from: discovery.foundAt) ?? ""
        return AppStrings.cardSolvedOn(lang, date: day)
    }

    /// «нашли 7 человек · первым — Илья».
    ///
    /// Два условия, и оба обязательны: без Cloud Sync счётчика не существует
    /// (спрашивать было нечем), а `finders == nil` — это «не спрашивали», а не
    /// ноль. Имени может не быть при живом счётчике — профиль первого закрыт, и
    /// тогда он «кто-то», а не пустое место.
    private static func findersLine(
        for discovery: Discovery, cloudSync: Bool, _ lang: LanguageManager.Language
    ) -> String? {
        guard cloudSync, let finders = discovery.finders, finders > 0 else { return nil }
        let name = discovery.firstFinderName.flatMap { $0.isEmpty ? nil : $0 }
            ?? AppStrings.cardFirstSomeone(lang)
        return AppStrings.cardFoundBy(lang, count: finders, name: name)
    }

    /// Форматы живут в `static let`, а не собираются при каждом показе:
    /// `DateFormatter` дорог, а карточка пересобирается на каждое движение
    /// листа.
    private static let dayMonthYear = LocalizedDateFormatter.templates("dMMMyyyy")
    /// «12.09» — порядок полей фиксирован нарочно: это короткая пометка рядом
    /// со словом «проездом», а не дата в прозе.
    private static let dayMonth = LocalizedDateFormatter.patterns("dd.MM")
}

/// Карточка находки: одна на секрет, загадку и веху.
///
/// Заменила `DiscoveryPeekSheet` (0.7.0, волна 4): та отвечала на один вопрос
/// «что это за кружок», а карточка несёт историю секрета, счётчик
/// первооткрывателей, круг решённой загадки и вход на карту. Одна вьюха на три
/// вида, а не три экрана: отличия между ними — это `DiscoveryCardModel`, и
/// расходиться вёрстке трёх карточек не на чем.
///
/// Живёт в двух контейнерах: панелью выбранного объекта на «Атласе» (тап по
/// печати) и листом `contentSizedSheet` над журналом. Разницу несёт один флаг
/// `showsOnMap` — в панели кнопки нет, мы уже на карте.
///
/// Модель собирается в `body`, и это ровно та работа, которую там можно: сборка
/// строк по готовым полям находки и два готовых `DateFormatter`. В базу карточка
/// не ходит ни разу — ни за находкой (она пришла целиком), ни за счётчиком (он
/// в ней же), — поэтому вью-модель ей не нужна.
struct DiscoveryCardSheet: View {
    let discovery: Discovery
    /// Карточку открыли из журнала: у неё есть «На карте».
    var showsOnMap: Bool = false
    /// Что делать по «На карте» — камера к печати и закрыть карточку.
    var onShowOnMap: (() -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let model = DiscoveryCardModel.make(
            discovery: discovery,
            cloudSync: settings.cloudSyncEnabled,
            lang: lang.language,
            showsOnMap: showsOnMap
        )
        return VStack(alignment: .leading, spacing: 12) {
            header(model, c)
            if let story = model.story {
                Text(story)
                    .font(.inter(14))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let circle = model.circle {
                RiddleMiniMap(circle: circle)
            }
            if let solved = model.solvedLine {
                Text(solved)
                    .font(.inter(13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            if let finders = model.findersLine {
                Text(finders)
                    .font(.inter(13))
                    .foregroundStyle(c.textTertiary)
            }
            if model.showsOnMap {
                onMapButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mymap_discovery_card")
    }

    /// Медальон, вид, имя, дата и — у загадки с вехой — строка про то, что это
    /// было. У секрета медальон крупнее: у него кроме печати и названия на
    /// карточке может не быть ничего.
    private func header(_ model: DiscoveryCardModel, _ c: AppTheme.Colors) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Картинка кэширована по (вид, символ, масштаб) — `SealPainter`
            // рисует её один раз на всё приложение.
            Image(uiImage: SealPainter.image(
                kind: model.kind, symbol: model.symbol,
                size: sealSize(model.kind), scale: 3))
                .frame(width: sealSize(model.kind), height: sealSize(model.kind))

            VStack(alignment: .leading, spacing: 4) {
                Text(model.kindLabel)
                    .font(.inter(11, weight: .heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Color(SealPainter.ring(for: model.kind)))

                if let title = model.title {
                    Text(title)
                        .font(.inter(17, weight: .heavy))
                        .foregroundStyle(c.text)
                        .lineLimit(3)
                }

                Text(model.dateLine)
                    .font(.inter(12))
                    .foregroundStyle(c.textTertiary)

                if let detail = model.detail {
                    Text(detail)
                        .font(.inter(12))
                        .foregroundStyle(c.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 40)
        }
    }

    private func sealSize(_ kind: DiscoveryKind) -> CGFloat {
        kind == .secret ? 72 : 56
    }

    private var onMapButton: some View {
        Button {
            Haptics.tap()
            onShowOnMap?()
        } label: {
            Text(AppStrings.cardOnMap(lang.language))
                .font(.inter(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("mymap_discovery_on_map")
    }
}

/// Круг решённой загадки на куске настоящей карты.
///
/// Точки на ней НЕТ — тем же правилом, что у подсказки на тумане: круг это
/// «где-то здесь», и середина у него не ответ. Снимок тёмный и приглушённый:
/// карточка стоит на нашей поверхности, а дневная карта под текстом требует
/// такой пелены, что от карты ничего не остаётся.
///
/// Карты может не быть вовсе (холодные плитки, самолётный режим) — тогда
/// остаётся тёмный фон с одним кругом, а не серая сетка MapKit: решает это
/// `AtlasSharePoster.usableSnapshot`, тот же, что у постера.
private struct RiddleMiniMap: View {
    let circle: DiscoveryCardModel.Circle

    @Environment(\.colorScheme) private var scheme
    @State private var snapshot: UIImage?
    /// Радиус в ТОЧКАХ ЭКРАНА — считает проекция самого снимка, а не наша
    /// арифметика по широте: у снимка своя, и круг разъехался бы с тайлами.
    @State private var radiusPoints: CGFloat = 0

    static let height: CGFloat = 120
    /// Сколько радиусов влезает в полуширину кадра: круг занимает кадр, но не
    /// упирается в его края.
    private static let zoomOut: Double = 1.5

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        return GeometryReader { geo in
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .overlay(Color.black.opacity(0.28))
                }
                DashedCircle(radius: radiusPoints)
                    .stroke(
                        Color(SealPainter.ring(for: .riddle)).opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: geo.size.width) { await load(size: geo.size) }
        }
        .frame(height: Self.height)
        .background(c.cardAlt)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private func load(size: CGSize) async {
        guard size.width > 1, snapshot == nil else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: circle.centre,
            latitudinalMeters: circle.radiusMetres * 2 * Self.zoomOut,
            longitudinalMeters: circle.radiusMetres * 2 * Self.zoomOut
        )
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        let config = MKStandardMapConfiguration(elevationStyle: .flat)
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        // Холодные тайлы возвращаются пустыми достаточно часто, чтобы одна
        // попытка регулярно давала СЕТКУ БЕЗ КАРТЫ (та же беда у постера и у
        // карточек ленты — и именно так вышел первый кадр этой карточки).
        // Лестница из трёх попыток, а не одна.
        var taken: MKMapSnapshotter.Snapshot?
        for delay in [UInt64(0), 700_000_000, 2_000_000_000] {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            if Task.isCancelled { return }
            taken = try? await MKMapSnapshotter(options: options).start()
            if taken != nil { break }
        }
        guard let snap = taken else { return }
        let east = CLLocationCoordinate2D(
            latitude: circle.centre.latitude,
            longitude: circle.centre.longitude
                + circle.radiusMetres / (111_320 * max(0.01, cos(circle.centre.latitude * .pi / 180)))
        )
        // Радиус считает проекция снимка ВСЕГДА — даже когда сам кадр
        // показывать нельзя: круг на тёмном фоне обязан остаться того же
        // размера, что и на карте.
        radiusPoints = abs(snap.point(for: east).x - snap.point(for: circle.centre).x)
        // Пустая сетка MapKit — не карта. Тот же вопрос и тот же ответ, что у
        // постера: холодные/офлайновые плитки приходят светлой миллиметровкой
        // с водяным знаком «Maps», и карточка загадки с ней выглядит сломанной.
        // Фон `c.cardAlt` с одним пунктирным кругом читается честнее.
        snapshot = AtlasSharePoster.usableSnapshot(snap.image)
    }
}

/// Круг заданного радиуса ровно в середине кадра.
private struct DashedCircle: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard radius > 1 else { return Path() }
        let r = min(radius, min(rect.width, rect.height) / 2 - 2)
        return Path(ellipseIn: CGRect(
            x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2))
    }
}
