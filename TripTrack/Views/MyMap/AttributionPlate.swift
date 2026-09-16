import UIKit
import MapKit
import os

/// Светлая подложка под логотипом Apple и ссылкой «Legal» на «Атласе».
///
/// Зачем она есть. С фикс-волны 2 карта «Атласа» ДНЕВНАЯ (иначе открытый
/// коридор выходил темнее закрытого тумана — см. `MyMapRepresentable`), а
/// атрибуция — сабвью самого `MKMapView`, и цвет её следует стилю КАРТЫ: на
/// дневной она тёмно-серая. Лежит она при этом поверх нашего тёмного тумана,
/// и замер по кадрам дал контраст 1.6 : 1 — «Legal» не читался вовсе. Правило
/// проекта записано отдельным пунктом: логотип и «Legal» обязаны быть видны,
/// прятать их нельзя, попытка рискует ревью.
///
/// Что делает подложка: кладёт под саму атрибуцию светлый скруглённый
/// прямоугольник — то есть возвращает ей тот фон, на который Apple её и
/// рисует. Ни одного приватного метода: только `subviews` и имя класса, как
/// у `FogVeilView.attach(inside:)`, и ни одна чужая вью не трогается.
///
/// Чего она НЕ делает: не красит атрибуцию, не двигает её и не перехватывает
/// нажатия (`isUserInteractionEnabled = false`) — «Legal» обязан открываться.
///
/// Не нашли атрибуцию — карта возвращается на НОЧНОЙ стиль
/// (`onAttributionNotFound`). Видимость важнее полярности: тёмный «Атлас» это
/// то, как он выглядел до фикс-волны 2, а нечитаемая атрибуция — возврат из
/// ревью.
@MainActor
final class AttributionPlate {

    /// Скругление, поле вокруг атрибуции и цвет — из решения контроллера.
    static let corner: CGFloat = 8
    static let padding: CGFloat = 6
    static let fill = UIColor(red: 0xF4/255, green: 0xF4/255, blue: 0xF2/255, alpha: 1)
    static let opacity: CGFloat = 0.88

    /// Сколько раз пробуем встать. Атрибуция появляется в дереве карты не
    /// обязательно к первому проходу разметки — ровно как контейнеры, которые
    /// ищет `VeilSeat`.
    static let maxTries = 20

    private static let log = Logger(subsystem: "com.onezee.TripTrack", category: "attribution")
    /// Про откат рассказываем ОДИН раз за запуск.
    private static var loggedFallback = false

    /// Подложка встать не смогла: зовущий обязан вернуть карту в ночной стиль.
    var onAttributionNotFound: (() -> Void)?

    private let plate = UIView()
    private weak var root: UIView?
    private var targets: [UIView] = []
    private var tries = 0

    private(set) var isSeated = false

    init() {
        plate.backgroundColor = Self.fill.withAlphaComponent(Self.opacity)
        plate.layer.cornerRadius = Self.corner
        plate.layer.cornerCurve = .continuous
        // Нажатия проходят насквозь: «Legal» — ссылка, и перехватить её тап
        // значило бы спрятать её надёжнее, чем это делал туман.
        plate.isUserInteractionEnabled = false
        plate.isHidden = true
    }

    /// Вьюхи атрибуции — по ПОДСТРОКЕ имени класса, обходом ВШИРЬ.
    ///
    /// Подстрок ТРИ, и каждая оплачена наблюдением. На iOS 18 атрибуция — это
    /// одна вью `MKAppleLogoLabel` (та самая «` Maps`»), то есть «Logo»; в
    /// других сборках рядом с ней живёт ссылка «Legal» со словом
    /// `Attribution` или `Legal` в имени. Видны обязаны быть все, какие есть,
    /// поэтому ищутся все три. Имена приватные и Apple вправе их переписать —
    /// поэтому пустой ответ это законный случай, а не падение: подложка не
    /// садится, и карта возвращается в ночную.
    static let nameNeedles = ["Attribution", "Logo", "Legal"]
    ///
    /// Вширь, а не вглубь, по той же причине, что у вуали: нужен самый мелкий
    /// по глубине, а не первый попавшийся в чужом поддереве.
    static func attributionViews(in root: UIView) -> [UIView] {
        var queue = root.subviews
        var head = 0
        var found: [UIView] = []
        while head < queue.count {
            let view = queue[head]
            head += 1
            let name = NSStringFromClass(type(of: view))
            if nameNeedles.contains(where: name.contains) {
                found.append(view)
                // Внутрь найденного не идём: подложка нужна одна на всю
                // атрибуцию, а не по одной на каждую её букву.
                continue
            }
            queue.append(contentsOf: view.subviews)
        }
        return found
    }

    /// Встроиться в дерево карты. `false` — атрибуции не нашлось, зовущий
    /// обязан вернуть карту в ночной стиль.
    ///
    /// Принимает `UIView`, а не `MKMapView`, ровно потому, что карта ей нужна
    /// ТОЛЬКО как корень поиска: ни одного метода `MKMapView` подложка не
    /// зовёт. Заодно это и делает её проверяемой — тест подсовывает своё
    /// дерево с теми же именами классов и не зависит от версии MapKit.
    @discardableResult
    func attach(to root: UIView) -> Bool {
        if self.root !== root {
            self.root = root
            tries = 0
            isSeated = false
        }
        if isSeated {
            layout()
            return true
        }
        guard tries < Self.maxTries else { return false }
        tries += 1

        let found = Self.attributionViews(in: root)
        guard let first = found.first, let parent = first.superview else {
            if tries == Self.maxTries { standDown("атрибуция не найдена") }
            return false
        }
        targets = found
        // Ниже САМОЙ РАННЕЙ из найденных: подложка обязана лежать под всеми,
        // иначе накроет собой то, ради чего её кладут.
        let earliest = found.compactMap { view -> Int? in
            guard view.superview === parent else { return nil }
            return parent.subviews.firstIndex(of: view)
        }.min()
        if let earliest {
            parent.insertSubview(plate, at: earliest)
        } else {
            parent.insertSubview(plate, belowSubview: first)
        }
        isSeated = true
        layout()
        return true
    }

    /// Поставить подложку по месту атрибуции. Зовётся на каждом проходе
    /// разметки карты и на смене нижнего инсета: логотип с «Legal» ездят
    /// вместе с ним, а не сами по себе.
    func layout() {
        guard isSeated, let parent = plate.superview else { return }
        var union = CGRect.null
        for target in targets where !target.isHidden && target.bounds.width > 0 {
            union = union.union(target.convert(target.bounds, to: parent))
        }
        guard !union.isNull, union.width > 1, union.height > 1 else {
            plate.isHidden = true
            return
        }
        plate.isHidden = false
        plate.frame = union.insetBy(dx: -Self.padding, dy: -Self.padding)
    }

    /// Экран ушёл — подложка уходит с ним.
    func detach() {
        plate.removeFromSuperview()
        targets = []
        isSeated = false
        tries = 0
        root = nil
    }

    /// Только для теста: где лежит подложка в координатах своего родителя.
    var frameInSuperview: CGRect? { plate.superview == nil ? nil : plate.frame }

    /// Только для теста: лежит ли подложка ниже атрибуции.
    var sitsBelowAttribution: Bool {
        guard let parent = plate.superview,
              let mine = parent.subviews.firstIndex(of: plate) else { return false }
        return targets.allSatisfy { target in
            guard target.superview === parent,
                  let theirs = parent.subviews.firstIndex(of: target) else { return true }
            return mine < theirs
        }
    }

    private func standDown(_ reason: String) {
        if !Self.loggedFallback {
            Self.loggedFallback = true
            Self.log.notice(
                "подложка атрибуции: \(reason, privacy: .public) — карта возвращается в ночную")
        }
        onAttributionNotFound?()
    }
}
