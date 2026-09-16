import SwiftUI
import MapKit
import CoreLocation
import QuartzCore

// MARK: - Строка

/// Строка блока «Открыто»: «42 км нового пути · 1 секрет · 1 веха».
///
/// Чистая функция и отдельный тип, а не метод вью, по той же причине, по
/// которой чисты `AutoTripPolicy` и `JourneyEditSheet.startBounds`: правило
/// «ненулевые части, в этом порядке, через одну точку» проверяется тестом, а
/// не открытым экраном после поездки — поездки, на которой нашлись СРАЗУ и
/// секрет, и загадка, и веха, можно ждать месяцами.
enum TripRevealedLine {

    /// Разделитель — тот же, что у «42 км · 2 ч 14 мин» на карточке поездки:
    /// точка с двумя неразрывными пробелами, чтобы строка не переносилась по
    /// ней на новую.
    static let separator = "\u{00A0}· "

    /// - Parameter km: УЖЕ НАПЕЧАТАННОЕ расстояние («42 км», «26 mi») или
    ///   `nil`, если открытых километров нет. Число сюда приходит готовым
    ///   нарочно: делит на единицу ровно `Measure`, и второй копии этого
    ///   решения в блоке итогов быть не должно.
    static func compose(
        _ lang: LanguageManager.Language,
        km: String?,
        secrets: Int,
        riddles: Int,
        milestones: Int
    ) -> String {
        var parts: [String] = []
        if let km, !km.isEmpty { parts.append(AppStrings.revealedNewPath(lang, km: km)) }
        if secrets > 0 {
            parts.append("\(secrets) \(AppStrings.nounSecrets(lang, secrets))")
        }
        if riddles > 0 {
            parts.append("\(riddles) \(AppStrings.nounRiddles(lang, riddles))")
        }
        if milestones > 0 {
            parts.append("\(milestones) \(AppStrings.nounMilestones(lang, milestones))")
        }
        return parts.joined(separator: separator)
    }
}

// MARK: - Выгорание тумана

/// Прогресс выгорания тумана на ГЕРОЕ экрана итогов: 0 → 1 за 0.7 с.
///
/// Прерываемо и монотонно. Монотонность здесь не украшение: `CADisplayLink`
/// присылает время системных часов, и первый кадр после возврата из фона
/// приходит с прыжком назад — туман, поехавший обратно, читался бы как
/// поломка. Поэтому прогресс только растёт, а второй `start` на уже
/// доигравшем экране не начинает всё заново.
///
/// `advance(to:)` — отдельный метод, а не тело `@objc` шага, чтобы тест мог
/// прогнать анимацию своим временем: `CADisplayLink` в юнит-тесте не тикает.
@MainActor
final class RevealSweep: ObservableObject {

    /// Спека §3: ~0.7 с. Дольше — и человек ждёт анимацию, короче — и он не
    /// успевает понять, что именно на карте изменилось.
    static let duration: TimeInterval = 0.7
    /// При `isReduceMotionEnabled` выгорания нет вовсе — туман снимается
    /// кроссфейдом за 0.3 с. Живёт здесь, а не у вью: длительность и правило
    /// «мгновенная единица» — одно решение.
    static let crossfade: TimeInterval = 0.3

    @Published private(set) var progress: Double = 0

    private var link: CADisplayLink?
    private var startedAt: CFTimeInterval?

    /// Доля пути, пройденная за `elapsed`. Зажата в [0, 1] и посчитана
    /// отдельно от состояния — тест читает её без объекта и без времени.
    static func value(elapsed: TimeInterval, duration: TimeInterval = RevealSweep.duration) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, elapsed / duration))
    }

    /// - Parameter reduceMotion: `true` — прогресс встаёт в единицу сразу, и
    ///   `CADisplayLink` не заводится вовсе. Кроссфейд рисует вью.
    func start(reduceMotion: Bool) {
        guard begin(reduceMotion: reduceMotion, now: CACurrentMediaTime()) else { return }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Часы анимации отдельно от `CADisplayLink`: тест гоняет выгорание своим
    /// временем, а настоящий кадровый таймер в него не лезет — заведённый в
    /// юнит-тесте, он тикал бы системными часами и перескакивал всю анимацию
    /// на первом же кадре.
    ///
    /// - Returns: нужен ли кадровый таймер (`false` — анимации не будет).
    @discardableResult
    func begin(reduceMotion: Bool, now: CFTimeInterval) -> Bool {
        guard progress < 1, link == nil else { return false }
        if reduceMotion {
            progress = 1
            return false
        }
        startedAt = now
        return true
    }

    /// Снимает `CADisplayLink` — на исчезновении вуали и на последнем кадре.
    /// Прогресс при этом остаётся там, где стоял: экран, к которому вернулись,
    /// не имеет права играть анимацию во второй раз.
    func cancel() {
        link?.invalidate()
        link = nil
        startedAt = nil
    }

    /// Шаг анимации по внешним часам.
    func advance(to now: CFTimeInterval) {
        guard let startedAt else { return }
        let next = Self.value(elapsed: now - startedAt)
        // Только вперёд: см. про прыжок часов в шапке типа.
        progress = max(progress, next)
        if progress >= 1 { cancel() }
    }

    @objc private func step(_ link: CADisplayLink) {
        MainActor.assumeIsolated { advance(to: link.timestamp) }
    }

    // MARK: Направление

    /// Куда «дует» выгорание: от начала трека к его концу, в экранных
    /// координатах (север сверху, восток справа).
    ///
    /// Чистая функция от координат, а не проекция настоящей карты: точную
    /// геометрию `MKMapView` вуали не отдаёт, а направление дороги на
    /// экране — отдаёт бесплатно, и его достаточно, чтобы туман снимался
    /// ВДОЛЬ пути, а не поперёк. Долгота сжимается по широте, иначе на
    /// шестидесятой параллели дорога на восток «наклонялась» бы вдвое.
    static func axis(
        from coordinates: [CLLocationCoordinate2D]
    ) -> (start: UnitPoint, end: UnitPoint) {
        guard let first = coordinates.first, let last = coordinates.last else {
            return (.leading, .trailing)
        }
        let shrink = cos(first.latitude * .pi / 180)
        let dx = (last.longitude - first.longitude) * shrink
        let dy = first.latitude - last.latitude          // экран растёт вниз
        let scale = max(abs(dx), abs(dy))
        guard scale > 1e-9 else { return (.leading, .trailing) }
        let ux = dx / scale
        let uy = dy / scale
        return (UnitPoint(x: 0.5 - ux / 2, y: 0.5 - uy / 2),
                UnitPoint(x: 0.5 + ux / 2, y: 0.5 + uy / 2))
    }
}

// MARK: - Блок

/// «Открыто» — что поездка добавила к карте мира (спека §3).
///
/// Стоит между плитками итога и значками: сначала «сколько проехал», потом
/// «что от этого изменилось на карте», потом награды. Показывается только у
/// непустой сводки — `nil` в `TripCompletionData.discoveries` значит «ещё
/// считается», и блока в этот момент нет вовсе, а не пустой каркас.
///
/// **Своей карты у блока НЕТ.** Выгорание тумана играет ГЕРОЙ экрана — тот
/// самый `RouteMapView`, который и так показывает только что проеханный
/// маршрут (`RevealSweepVeil` над ним). Вторая карта здесь была: одинаковый
/// маршрут в одинаковом стиле двумя карточками ниже, и человек видел не «мир
/// изменился», а «почему-то две карты».
struct TripRevealedBlock: View {
    let discoveries: TripDiscoveries
    /// Нажатие на печать. `nil` — блок не нажимается (открывать нечего:
    /// поездка открыла километры, но ни одной печати не поставила).
    var onOpen: ((UUID) -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var distanceUnit

    /// Сколько печатей влезает в ряд до «+N». Шесть — ширина карточки на
    /// самом узком телефоне.
    private static let sealsShown = 6

    private var found: [Discovery] { discoveries.all }

    var body: some View {
        let c = AppTheme.colors(for: .light)
        if let onOpen, let first = found.first {
            Button { onOpen(first.id) } label: { card(c) }
                .buttonStyle(PressableCardStyle())
        } else {
            card(c)
        }
    }

    // MARK: Карточка

    private func card(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(c)
            Text(line)
                .font(.inter(13, weight: .semibold))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !found.isEmpty { seals(c) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("summary_revealed")
    }

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(SealPainter.ring(for: found.first?.kind ?? .milestone)))
            Text(AppStrings.revealedTitle(lang.language))
                .font(.inter(15, weight: .heavy))
                .foregroundStyle(c.text)
            Spacer(minLength: 0)
            // Шеврон — только когда нажатие и правда открывает печать на
            // «Атласе». Обещать переход там, где его нет, нельзя.
            if onOpen != nil, !found.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(c.textTertiary)
            }
        }
    }

    private func seals(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            ForEach(found.prefix(Self.sealsShown)) { discovery in
                Image(uiImage: SealPainter.image(
                    kind: discovery.kind, symbol: discovery.symbol, size: 28, scale: 3))
                    .accessibilityLabel(DiscoveryCopy.accessibility(for: discovery, lang.language))
            }
            if found.count > Self.sealsShown {
                Text("+\(found.count - Self.sealsShown)")
                    .font(.inter(12, weight: .bold))
                    .foregroundStyle(c.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Строка

    private var line: String {
        TripRevealedLine.compose(
            lang.language,
            km: kmText,
            secrets: discoveries.secrets.count,
            riddles: discoveries.riddles.count,
            milestones: discoveries.milestones.count
        )
    }

    /// Полкилометра — тот же порог, по которому сводка считает себя пустой
    /// (`TripDiscoveries.isEmpty`): ниже него это шум стоянки, а не открытый
    /// путь.
    private var kmText: String? {
        guard discoveries.newKm >= 0.5 else { return nil }
        return Measure.distance(
            km: discoveries.newKm, unit: distanceUnit, lang: lang.language, style: .adaptive)
    }
}

// MARK: - Вуаль выгорания

/// Туман, который снимается с ГЕРОЯ экрана итогов: вдоль пути — градиентом,
/// при `isReduceMotionEnabled` — кроссфейдом.
///
/// Кладётся поверх `RouteMapView` в `ZStack`, а не внутрь него: `MKMapView`
/// со своей вуалью перерисовывать шестьдесят раз в секунду нельзя (растр
/// вуали — мегабайты на фоновой очереди), а четыре стопа градиента стоят
/// ничего. Поэтому же вуаль своя, а не `FogVeilView`: тот отвечает на вопрос
/// «что открыто», эта — на вопрос «что открылось ПРЯМО СЕЙЧАС».
struct RevealSweepVeil: View {
    /// Точки маршрута — только ради направления выгорания.
    let coordinates: [CLLocationCoordinate2D]
    @ObservedObject var sweep: RevealSweep
    let reduceMotion: Bool

    var body: some View {
        let axis = RevealSweep.axis(from: coordinates)
        let veilColor = Color(FogVeilPainter.veilColorTop)
        Group {
            if reduceMotion {
                Rectangle()
                    .fill(veilColor)
                    .opacity(1 - sweep.progress)
                    .animation(.easeOut(duration: RevealSweep.crossfade), value: sweep.progress)
            } else {
                LinearGradient(
                    stops: RevealSweep.stops(veil: veilColor, progress: sweep.progress),
                    startPoint: axis.start,
                    endPoint: axis.end
                )
            }
        }
        .allowsHitTesting(false)
        // Кадром позже, а не в `onAppear`: при уменьшенном движении прогресс
        // встаёт в единицу СРАЗУ, и запуск в том же проходе обновления съел бы
        // весь кроссфейд — вуаль появилась бы уже прозрачной. Один кадр
        // непрозрачной вуали и есть то, из чего он потом растворяется.
        // `.task` снимается сам, когда вуаль уходит с экрана.
        .task {
            try? await Task.sleep(nanoseconds: 16_000_000)
            sweep.start(reduceMotion: reduceMotion)
        }
        .onDisappear { sweep.cancel() }
    }
}

// MARK: - Градиент выгорания

extension RevealSweep {

    /// Кромка выгорания: открытое перед ней, туман за ней, мягкий переход
    /// между. Отдельной функцией, а не выражением в `body`:
    /// `TripCompleteSummaryView` уже упиралась в предел вывода типов SwiftUI,
    /// и вуаль, которую в неё вставляют, не имеет права подталкивать её туда
    /// снова.
    ///
    /// Голова уезжает ЗА край (×1.15): иначе на последнем кадре у дальнего
    /// угла оставался бы тёмный клин шириной с саму кромку.
    static func stops(veil: Color, progress: Double) -> [Gradient.Stop] {
        let soft = 0.15
        let head = min(1 + soft, max(0, progress) * (1 + soft))
        let clearAt = min(1, max(0, head - soft))
        let veilAt = min(1, max(clearAt, head))
        return [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: clearAt),
            .init(color: veil, location: veilAt),
            .init(color: veil, location: 1)
        ]
    }
}
