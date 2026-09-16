import SwiftUI

/// Состояние раскрытия карты поездки: герой → весь экран и обратно.
///
/// Чистый тип, а не набор булевых флагов в экране, по той же причине, по
/// которой чист `ReplayBarState`: из состояния выводится ВСЁ — целевой кадр
/// карты, видимость хрома, интерактивность, что показывает слот героя, — и
/// разойтись этим ответам друг с другом нельзя.
enum MapExpansionState: String, Equatable, CaseIterable {
    /// Карта в слоте героя, полноэкранной раскладки нет вовсе.
    case collapsed
    /// Карта едет на весь экран.
    case expanding
    /// Карта на весь экран, стоит.
    case expanded
    /// Карта едет обратно в слот героя.
    case collapsing

    /// Существует ли полноэкранная раскладка. `collapsed` — её нет в дереве.
    var isPresented: Bool { self != .collapsed }

    /// Занимает ли кадр карты весь экран.
    ///
    /// `expanding` — это ОДИН кадр, в котором карта уже переехала в
    /// полноэкранный слой, но стоит ещё ровно в рамке героя: без него
    /// пружине было бы не от чего отталкиваться, и карта возникала бы на
    /// весь экран сразу. `collapsing` — тот же кадр наоборот.
    var fillsScreen: Bool { self == .expanded }

    /// Хром (закрыть, зум, плашка реплея, карточки) — только на стоящей
    /// карте. Он появляется ПОСЛЕ движения: кнопка, приехавшая вместе с
    /// картой, заставляет глаз следить за ней, а не за тем, что открылось.
    var showsChrome: Bool { self == .expanded }

    /// Пальцы карта принимает только когда встала: жест, начатый на едущем
    /// кадре, спорит с пружиной.
    var isInteractive: Bool { self == .expanded }

    /// Слот героя показывает снимок вместо живой карты — во всём, кроме
    /// покоя: карта в это время лежит в полноэкранном слое.
    var heroShowsSnapshot: Bool { self != .collapsed }

    // MARK: - Времена

    /// Одна пружина на весь переход — и кадр карты, и подложка.
    static let response: Double = 0.38
    static let dampingFraction: Double = 0.9

    /// Reduce Motion: вместо пружины кроссфейд. Движение — это и есть то,
    /// от чего человек просил его избавить.
    static let reducedDuration: Double = 0.2

    /// Доля пружины, после которой проявляется хром.
    static let chromeFraction: Double = 0.6

    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: reducedDuration)
            : .spring(response: response, dampingFraction: dampingFraction)
    }

    /// Через сколько после начала движения появляется хром.
    static func chromeDelay(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : response * chromeFraction
    }

    /// Сколько длится сам переход.
    ///
    /// Ждать его СНОМ нельзя (CLAUDE.md, «Анимацию можно прервать») — это
    /// число описывает пружину, а «кадр приехал» узнаётся у самой анимации
    /// через `withAnimation(_:completionCriteria:_:completion:)`. Остаётся
    /// для тестов и для тех, кому нужна длительность, а не событие.
    static func settleDelay(reduceMotion: Bool) -> Double {
        reduceMotion ? reducedDuration : response
    }
}
