import MapKit
import UIKit

/// Гнездо для карты, которую держит не SwiftUI, а `TripMapHost`.
///
/// Зачем оно есть. Карта поездки ОДНА на два представления — слот героя и
/// полноэкранную раскладку (см. `TripMapHost`), — а `UIViewRepresentable`
/// отдаёт свою вью во владение SwiftUI: разбирая представление, тот снимает
/// её с родителя. Пока представлений два, порядок «собрали новое, разобрали
/// старое» SwiftUI не обещает, и на возврате с полного экрана разбор
/// полноэкранного адаптера выдёргивал карту из УЖЕ занявшего её слота героя.
/// Дальше `updateUIView` приходил с `superview == nil`, вернуть карту было
/// некому, и человек видел на её месте пустой прямоугольник — репорт
/// владельца с устройства 23 сентября («выхожу, попадаю в деталку, а карта
/// просто чёрный прямоугольник»).
///
/// Здесь SwiftUI владеет ГНЕЗДОМ и волен создавать и разбирать его сколько
/// угодно: карта лежит внутри и явно передаётся активному контейнеру.
/// Разобранное гнездо уносит с собой пустоту.
///
/// Передача карты явная: `adopt` отзывает владение у прежнего гнезда.
/// Во время push SwiftUI вправе раскладывать оба гнезда одновременно.
/// Если каждое забирает карту обратно в `layoutSubviews`, разметка не
/// заканчивается вовсе: два вида бесконечно переносят одну MKMapView.
final class TripMapSlotView: UIView {

    /// Карта, живущая в этом гнезде. `weak` — держит её хост, а не гнездо:
    /// гнёзд за жизнь экрана несколько, карта одна.
    private(set) weak var map: MKMapView?
    private var lastReportedMapSize: CGSize?

    /// Забрать карту себе — СРАЗУ, не дожидаясь разметки.
    ///
    /// Ждать разметки нельзя: SwiftUI может сначала снять прежний слот.
    /// Только новый слот получает карту; прежний остаётся пустым даже если
    /// его `updateUIView` или `layoutSubviews` придут после передачи.
    func adopt(_ map: MKMapView) {
        guard map.superview !== self else { return }
        if let previous = map.superview as? TripMapSlotView {
            previous.map = nil
        }
        self.map = map
        lastReportedMapSize = nil
        map.removeFromSuperview()
        // A freshly mounted SwiftUI slot starts at 0×0. Keep the live map's
        // previous viewport until the destination has a real size: collapsing
        // it here needlessly invalidates MapKit's tiles during expansion.
        // Layout owns the frame explicitly. A flexible mask would add the
        // destination's first size to the retained frame before our callback.
        map.autoresizingMask = []
        if hasUsableSize { map.frame = bounds }
        addSubview(map)
        onAdopt?()
        reportSizeIfChanged()
    }

    /// Гнездо забрало карту себе. Повод перечитать то, что считается от места
    /// карты в дереве (посадка вуали), — но только повод: решает зовущий.
    var onAdopt: (() -> Void)?

    /// Карта получила новый размер. Единственный честный сигнал «вписывать
    /// маршрут можно»: MapKit считает подгонку по НЫНЕШНИМ границам вида, а
    /// до этой секунды у карты границы прежнего гнезда.
    var onResize: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let map else { return }
        guard map.superview === self else { return }
        guard hasUsableSize else { return }
        // A frame may already match after adoption; the coordinator still
        // needs the first usable size to fulfill its pending route fit.
        if map.frame != bounds { map.frame = bounds }
        reportSizeIfChanged()
    }

    private var hasUsableSize: Bool { bounds.width > 1 && bounds.height > 1 }

    private func reportSizeIfChanged() {
        guard hasUsableSize else { return }
        guard lastReportedMapSize != bounds.size else { return }
        lastReportedMapSize = bounds.size
        onResize?()
    }
}
