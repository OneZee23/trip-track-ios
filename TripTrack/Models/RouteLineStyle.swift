import SwiftUI
import UIKit

/// Цвет линии маршрута на СВОИХ картах — четвёртая косметика «Плюса».
///
/// Единственная из четырёх, которая никуда не уезжает: выбор виден только
/// владельцу телефона, поэтому живёт в `UserDefaults` и ни в базе, ни на
/// проводе его нет (спека §2, пункт 4). Соответственно и второго телефона у
/// него не бывает — «не синкается» это решение, а не недоделка.
///
/// `.speed` — бесплатный вариант и умолчание: тот самый градиент скорости
/// (`SpeedColorScale`), который рисовался всегда. Шесть цветов — платные.
enum RouteLineStyle: String, CaseIterable, Identifiable {
    /// Градиент скорости — как было до 0.8.0.
    case speed   = ""
    case amber   = "amber"
    case crimson = "crimson"
    case violet  = "violet"
    case teal    = "teal"
    case lime    = "lime"
    case ice     = "ice"

    var id: String { rawValue }

    var isPlus: Bool { self != .speed }

    /// Имя собственное у цветов; у градиента — описание поведения, поэтому
    /// оно единственное идёт через `AppStrings.routeLineSpeedGradient`.
    var displayName: String {
        switch self {
        case .speed:   return ""
        case .amber:   return "Amber"
        case .crimson: return "Crimson"
        case .violet:  return "Violet"
        case .teal:    return "Teal"
        case .lime:    return "Lime"
        case .ice:     return "Ice"
        }
    }

    /// Чем красить линию. `nil` у градиента — «цвета нет, спрашивай скорость»:
    /// именно этим `nil` места отрисовки и отличают два режима, без второго
    /// флага рядом.
    var uiColor: UIColor? {
        switch self {
        case .speed:   return nil
        case .amber:   return UIColor(red: 0xF5/255, green: 0xA6/255, blue: 0x23/255, alpha: 0.95)
        case .crimson: return UIColor(red: 0xE0/255, green: 0x33/255, blue: 0x44/255, alpha: 0.95)
        case .violet:  return UIColor(red: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 0.95)
        case .teal:    return UIColor(red: 0x18/255, green: 0xB5/255, blue: 0xA8/255, alpha: 0.95)
        case .lime:    return UIColor(red: 0x86/255, green: 0xCB/255, blue: 0x2E/255, alpha: 0.95)
        case .ice:     return UIColor(red: 0x6F/255, green: 0xB6/255, blue: 0xE8/255, alpha: 0.95)
        }
    }

    var color: Color? { uiColor.map(Color.init(uiColor:)) }

    /// Та же дверь и то же правило, что у трёх остальных косметик: «Плюс»
    /// кончился — снова градиент скорости, выбор в `UserDefaults` цел.
    func effective(isPlus: Bool) -> RouteLineStyle {
        (self.isPlus && !isPlus) ? .speed : self
    }

    static func from(_ raw: String?) -> RouteLineStyle {
        guard let raw, !raw.isEmpty else { return .speed }
        return RouteLineStyle(rawValue: raw) ?? .speed
    }

    // MARK: - Хранение

    static let storageKey = "com.triptrack.settings.routeLineStyle"
    /// Зеркало «Плюс активен» для тех, кто спрашивает цвет ВНЕ главного
    /// актёра.
    ///
    /// `PlusAccess` главноактёрный, а цвет линии спрашивают жилка «Атласа»
    /// (считается на фоновой очереди) и `MKOverlayRenderer`, который MapKit
    /// зовёт параллельно на нескольких потоках. Спросить оттуда `PlusAccess`
    /// нельзя ни синхронно, ни безопасно — поэтому бит кладётся в те же
    /// `UserDefaults`, откуда читается сам выбор, и пишут его места показа
    /// карт с главного потока (`RouteMapView.makeUIView`,
    /// `MyMapRepresentable.makeUIView`, пикер в настройках).
    static let plusMirrorKey = "com.triptrack.settings.routeLineStylePlus"

    private static var store: UserDefaults { .standard }

    /// Что ВЫБРАНО. Сам выбор, без оглядки на подписку: пикер показывает
    /// именно его, иначе у человека без «Плюса» галочка прыгала бы на
    /// «Градиент скорости» и стирала бы его выбор на глазах.
    static var stored: RouteLineStyle {
        get { from(store.string(forKey: storageKey)) }
        set {
            guard newValue != stored else { return }
            store.set(newValue.rawValue, forKey: storageKey)
            announce()
        }
    }

    /// Запомнить, активен ли «Плюс», — зовётся с главного потока.
    static func rememberPlus(_ isPlus: Bool) {
        guard store.bool(forKey: plusMirrorKey) != isPlus else { return }
        store.set(isPlus, forKey: plusMirrorKey)
        announce()
    }

    /// Чем красить ПРЯМО СЕЙЧАС, с любого потока. `nil` — градиент скорости.
    ///
    /// Зовут её там, где ГОТОВЯТ картинку: `init` рендерера маршрута и жилки,
    /// растр экранной вуали, постер. В `draw` её не зовёт никто — цвет там
    /// лежит снимком (`RouteVeinRenderer.veinColor`).
    static var currentUIColor: UIColor? {
        stored.effective(isPlus: store.bool(forKey: plusMirrorKey)).uiColor
    }

    /// Сказать картам, что цвет сменился.
    ///
    /// Рендереры держат СНИМОК цвета и сами его не переспрашивают — иначе
    /// пришлось бы читать `UserDefaults` на каждом кадре жеста. Поэтому
    /// перерисовку заказывает эта дверь, а карта на неё переставляет оверлей:
    /// MapKit спрашивает рендерер заново только у нового оверлея.
    private static func announce() {
        NotificationCenter.default.post(name: .routeLineStyleChanged, object: nil)
    }
}

extension Notification.Name {
    /// Человек сменил цвет линии маршрута — или подписка «Плюс» зажглась
    /// либо погасла, что для карты одно и то же событие.
    static let routeLineStyleChanged = Notification.Name("routeLineStyleChanged")
}
