import CoreGraphics
import Foundation

/// Положения панели «Мест» (спека «Места v2» §4).
///
/// Шесть, и достаются они по-разному: три тянутся пальцем, два ставит выбор
/// булавки, одно — пустая вкладка, которая не тянется вовсе. Перечислены
/// сверху вниз по экрану.
enum PlacesPanelStop: Equatable, CaseIterable {
    /// Список целиком, скролл внутри. Самое верхнее.
    case list
    /// Пустая вкладка: образец, «Мест пока нет», «Отметить в поездке».
    case empty
    /// По умолчанию: заголовок, «Мои места», подсказки.
    case half
    /// Карточка выбранной подсказки под заголовком.
    case selectedHint
    /// Строка выбранного места под заголовком.
    case selectedPlace
    /// Только заголовок: карта во всю высоту.
    case map

    /// Куда можно попасть пальцем. Остальные ставит экран.
    static let draggable: [PlacesPanelStop] = [.list, .half, .map]

    var isDraggable: Bool { Self.draggable.contains(self) }
}

/// Геометрия нижней панели «Мест».
///
/// **Ни одной абсолютной координаты** (принцип 2 спеки): нижние положения
/// считаются от ВЕРХА КАПСУЛЫ ТАБ-БАРА, верхнее — от безопасной зоны сверху.
/// Числа таблицы спеки — следствие формул, а не источник, и сверяет их
/// `PlacesSlotTests` по пяти телефонам.
///
/// Близнец `AtlasSlot`, и это сознательно два типа, а не один: таблицы
/// положений у вкладок разные, а вот ПРАВИЛА жеста общие и живут в
/// `SlotGesture` — расходиться им нельзя.
struct PlacesSlot: Equatable {
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat

    init(height: CGFloat, safeTop: CGFloat, safeBottom: CGFloat) {
        self.height = height
        self.safeTop = safeTop
        self.safeBottom = safeBottom
    }

    /// Верх капсулы таб-бара. Всё нижнее считается от него.
    ///
    /// `CustomTabBar.bottomGap` у нас 22 всегда, и от индикатора «домой» он не
    /// зависит (решение 0.8.1). Спека считает 10 pt на телефонах без
    /// индикатора — там наша панель ниже таблицы ровно на эти 12 pt, и менять
    /// таб-бар ради таблицы нельзя: он вне объёма этой переделки.
    var tabBarTop: CGFloat {
        height - CustomTabBar.bottomGap - CustomTabBar.pillHeight
    }

    /// Высота содержимого каждого положения — ЧИСЛОМ, а не измерением.
    ///
    /// Правило CLAUDE.md, купленное дважды сломанным экраном: внутри панели
    /// скролл, он отвечает «возьму сколько предложите», и измерение уходит
    /// вниз и не возвращается.
    static func contentHeight(_ stop: PlacesPanelStop) -> CGFloat {
        switch stop {
        case .map: return 100
        case .selectedPlace: return 164
        case .selectedHint: return 232
        case .half: return 374
        case .empty: return 474
        case .list: return 0   // считается от безопасной зоны, см. `top(of:)`
        }
    }

    func top(of stop: PlacesPanelStop) -> CGFloat {
        stop == .list ? listTop : tabBarTop - Self.contentHeight(stop)
    }

    /// Список: `безопасная зона + 56`. Сверху остаётся полоска карты.
    var listTop: CGFloat { safeTop + 56 }

    /// Есть ли на этом экране ПОЛОВИНА (спека §9).
    ///
    /// На SE её нет вовсе: между картой и списком там не остаётся высоты, на
    /// которой список показывал бы больше одной строки. Остаются два
    /// положения — карта и полный список, — и вкладка открывается СПИСКОМ, а
    /// не картой: на маленьком экране полезнее список.
    var showsHalf: Bool { height >= 700 }

    /// Чем вкладка открывается: половиной, а на SE списком.
    var defaultStop: PlacesPanelStop { showsHalf ? .half : .list }

    /// Лист экрана места на старте. На SE он ниже: 300 вместо 374, иначе
    /// карте под ним не остаётся и трёхсот точек (спека §9).
    var placeSheetTop: CGFloat { tabBarTop - (showsHalf ? 374 : 300) }

    /// Прокрученный лист экрана места уходит под блюр-шапку до самой зоны.
    var placeSheetScrolledTop: CGFloat { safeTop }

    // MARK: Жест

    /// Границы тянущихся положений: выше списка и ниже карты руками не уходит.
    var upperBound: CGFloat { listTop }
    var lowerBound: CGFloat { top(of: .map) }

    func clamped(_ top: CGFloat) -> CGFloat {
        SlotGesture.clamped(top, lower: lowerBound, upper: upperBound)
    }

    /// Положения, доступные пальцу на ЭТОМ экране.
    var reachableStops: [PlacesPanelStop] {
        showsHalf ? PlacesPanelStop.draggable : [.list, .map]
    }

    /// Куда встанет отпущенная панель.
    ///
    /// Бросок быстрее `flickVelocity` летит к СОСЕДНЕМУ положению по
    /// направлению жеста, даже против ближайшего; иначе решают границы на
    /// 45 % пути. Программные положения (выбранное место, подсказка, пустая
    /// вкладка) в этом выборе не участвуют — руками в них не попадают.
    func settle(top: CGFloat, velocity: CGFloat, from: PlacesPanelStop) -> PlacesPanelStop {
        let stops = reachableStops
        let current = stops.firstIndex(of: from) ?? (stops.count / 2)
        if velocity < -SlotGesture.flickVelocity {
            return stops[Swift.max(0, current - 1)]
        }
        if velocity > SlotGesture.flickVelocity {
            return stops[Swift.min(stops.count - 1, current + 1)]
        }
        // Границы считаются между СОСЕДНИМИ достижимыми положениями, поэтому
        // на SE, где половины нет, граница одна — прямо между картой и
        // списком, а не там, где стояла бы половина.
        for index in stride(from: stops.count - 1, to: 0, by: -1) {
            let lower = self.top(of: stops[index])
            let upper = self.top(of: stops[index - 1])
            if top > SlotGesture.boundary(from: lower, to: upper) { return stops[index] }
        }
        return stops[0]
    }

    // MARK: Что над панелью

    /// Подпись Apple и кнопки карты стоят над панелью — но НИКОГДА не по
    /// списку: инсет по нему съел бы весь кадр, а MapKit кадрирует камеру по
    /// сумме полей разметки (CLAUDE.md, 0.8.1).
    /// Исключение одно — пустая вкладка: там панель по спеке занимает почти
    /// весь экран, но и кадрировать на ней нечего (ни булавок, ни команд
    /// камере), поэтому живого кадра с неё не требуется.
    func mapBottomInset(_ stop: PlacesPanelStop) -> CGFloat {
        let anchor = stop == .list ? top(of: defaultStop == .list ? .map : .half) : top(of: stop)
        return height - anchor + 8
    }
}
