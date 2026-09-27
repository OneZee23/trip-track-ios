import CoreGraphics
import Foundation

/// Нижний слот «Атласа»: где стоит шторка, кнопки карты и подпись Apple.
///
/// **Считается ОТ КРАЁВ, а не под один телефон** (спека §9: «ничего не
/// рисуется под один экран»). Числа в таблице спеки — следствие формул, а не
/// наоборот, и сторож `AtlasSlotTests` сверяет их по всем четырём телефонам
/// доски S7.
///
/// Начало отсчёта — ВЕРХ КАПСУЛЫ ТАБ-БАРА, а не низ экрана: таб-бар в этой
/// версии не меняется (спека §2), и слот обязан стоять над ним на одних и тех
/// же полях независимо от того, есть ли у телефона индикатор «домой». Отсюда
/// же и единственное расхождение с таблицей спеки — на iPhone SE она считает
/// таб-бар на 10 pt от низа, а у нас `CustomTabBar.bottomGap` равен 22 всегда
/// (решение 0.8.1: геометрия бара от индикатора НЕ зависит). Слот там ниже
/// таблицы ровно на эти 12 pt, и это осознанно: двигать таб-бар ради таблицы
/// значило бы менять то, что спека менять запрещает.
struct AtlasSlot: Equatable {
    /// Высота экрана.
    let height: CGFloat
    /// Безопасная зона сверху — от неё считается верх списка.
    let safeTop: CGFloat
    /// Безопасная зона снизу: ноль у телефонов без индикатора «домой».
    let safeBottom: CGFloat

    init(height: CGFloat, safeTop: CGFloat, safeBottom: CGFloat) {
        self.height = height
        self.safeTop = safeTop
        self.safeBottom = safeBottom
    }

    // MARK: Положения шторки

    /// Верх капсулы таб-бара. Всё нижнее считается от него.
    var tabBarTop: CGFloat {
        height - CustomTabBar.bottomGap - CustomTabBar.pillHeight
    }

    /// Сводка: `верх таб-бара − высота содержимого`. По умолчанию 166 pt,
    /// то есть 588 на iPhone 15.
    func collapsedTop(_ variant: AtlasSummaryVariant = .summary) -> CGFloat {
        tabBarTop - variant.contentHeight
    }

    /// Подсказка под карточкой места: `верх таб-бара − 54`.
    var peekTop: CGFloat { tabBarTop - 54 }

    /// Список: `отступ сверху + 56`. Сверху остаётся полоска карты, и она же
    /// работает как «свернуть».
    var expandedTop: CGFloat { safeTop + 56 }

    /// Подсостояния (регион, город, город в тумане) держат верх не выше 420 —
    /// иначе гаснут заголовок и кнопки карты, а они там нужны (доска S1).
    var substateTopLimit: CGFloat { 420 }

    func top(of detent: AtlasSheetDetent, variant: AtlasSummaryVariant = .summary) -> CGFloat {
        switch detent {
        case .peek: return peekTop
        case .collapsed: return collapsedTop(variant)
        case .expanded: return expandedTop
        }
    }

    // MARK: Компактная высота

    /// Есть ли под карточкой места строка подсказки.
    ///
    /// На экранах ниже 700 pt её нет вовсе (спека §9): карточка стоит на 12 pt
    /// над таб-баром, а закрытие возвращает сводку.
    var showsPeekRow: Bool { height >= 700 }

    // MARK: Модальные шторки и поиск

    /// Поиск поднимает шторку сюда, вместе с клавиатурой.
    var searchTop: CGFloat { safeTop + 8 }

    /// Нижнее поле модальных шторок: безопасная зона, а без индикатора — 16.
    var modalBottomPadding: CGFloat { safeBottom > 0 ? safeBottom : 16 }

    // MARK: Жест

    /// Граница, за которой отпущенная шторка летит в список.
    ///
    /// 45 % пути, а не половина: открыть список должно быть легче, чем
    /// закрыть (спека §4, доска S1 — «порог между сводкой и списком 45 %
    /// пути»).
    func settleBoundary(_ variant: AtlasSummaryVariant = .summary) -> CGFloat {
        let from = collapsedTop(variant)
        return from - (from - expandedTop) * 0.45
    }

    /// Куда лететь, отпустив шторку.
    ///
    /// Скорость больше 300 pt/с летит ПО НАПРАВЛЕНИЮ жеста к соседнему
    /// положению; иначе решает граница. `peek` из этого выбора исключён —
    /// руками в него не попадают: шторка уходит туда только когда выбрано
    /// место, и тогда жест по ней означает «сними выбор и покажи список».
    static func settle(top: CGFloat, velocity: CGFloat,
                       slot: AtlasSlot,
                       variant: AtlasSummaryVariant = .summary) -> AtlasSheetDetent {
        if velocity < -Self.flickVelocity { return .expanded }
        if velocity > Self.flickVelocity { return .collapsed }
        return top <= slot.settleBoundary(variant) ? .expanded : .collapsed
    }

    /// Скорость, с которой отпущенная шторка летит по направлению жеста.
    static let flickVelocity: CGFloat = 300

    /// Сопротивление за границей: выше списка и ниже сводки шторка идёт
    /// втрое медленнее пальца.
    static let rubber: CGFloat = 0.3

    /// Куда встанет верх шторки при пальце, утащившем её за границу.
    ///
    /// Границы — список сверху и сводка снизу; `peek` ниже сводки, и пока
    /// шторка в нём, нижней границей становится он сам, иначе карточка места
    /// подпрыгивала бы вверх на любом касании.
    func clamped(top: CGFloat, lowerBound: AtlasSheetDetent = .collapsed,
                 variant: AtlasSummaryVariant = .summary) -> CGFloat {
        let lower = self.top(of: lowerBound, variant: variant)
        if top < expandedTop { return expandedTop - (expandedTop - top) * Self.rubber }
        if top > lower { return lower + (top - lower) * Self.rubber }
        return top
    }

    // MARK: Затухание

    /// Прозрачность заголовка вкладки и кнопки периода.
    ///
    /// Видны, пока верх шторки не выше 420; между 420 и 280 гаснут линейно.
    static func headerOpacity(sheetTop: CGFloat) -> CGFloat {
        ramp(value: sheetTop, hidden: 280, visible: 420)
    }

    /// Прозрачность кнопок карты и подписи Apple. Они привязаны к ВЕРХУ
    /// СЛОТА, а не к шторке: когда слот занят карточкой места, следовать надо
    /// за карточкой.
    static func controlsOpacity(slotTop: CGFloat) -> CGFloat {
        ramp(value: slotTop, hidden: 240, visible: 300)
    }

    private static func ramp(value: CGFloat, hidden: CGFloat, visible: CGFloat) -> CGFloat {
        guard visible > hidden else { return value >= visible ? 1 : 0 }
        return min(1, max(0, (value - hidden) / (visible - hidden)))
    }

    // MARK: Отступы над слотом

    /// Кнопки карты стоят на 12 pt выше слота.
    static let controlsGap: CGFloat = 12
    /// Подпись Apple — на 8 pt выше слота.
    static let attributionGap: CGFloat = 8
}
