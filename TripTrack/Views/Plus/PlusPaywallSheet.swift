import SwiftUI

/// Точка входа на витрину PRO.
///
/// Тонкая обёртка: сам экран — `ProPaywallView`. Обёртка оставлена потому, что
/// её зовут пять мест (замок каждой из пяти фич, строка «Я», настройки), и
/// переименовать их все ради одной буквы значило бы тронуть пять экранов в
/// релизной ветке ради нуля для человека. Заводишь шестой вход — веди сюда же.
struct PlusPaywallSheet: View {
    /// С какой фичи пришли, если пришли с замка. Витрина откроет её
    /// демонстрацию сразу.
    var feature: PlusFeature? = nil
    var origin: ProBoughtView.Origin = .storefront

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared
    @State private var choosing: ProShowcaseKind?

    /// Куда ведёт «Вы в PRO» (14 окт 2026): туда, ради чего купили. Прежде
    /// кнопка вела к фону профиля даже того, кто пришёл с рамки или цвета
    /// линии, — и купленное приходилось искать самому. Фон машины правит
    /// только её форма, вписанную поездку — её лист: там кнопка просто
    /// возвращает обратно (`nil`).
    static func nextKind(after feature: PlusFeature?) -> ProShowcaseKind? {
        switch feature {
        case .avatarFrame: return .avatarFrame
        case .routeLineStyle: return .routeLine
        case .vehicleCardStyle, .manualTrip: return nil
        case .profileBackgrounds, nil: return .profileBackground
        }
    }

    var body: some View {
        // Меняем содержимое того же листа: закрытие пейвола и одновременный
        // показ второго sheet могут потерять переход в SwiftUI.
        if let kind = choosing {
            ProShowcaseSheet(
                kind: kind,
                current: current(kind),
                onPick: { settings.selectCosmetic(kind, id: $0,
                                                  isPlus: PlusAccess.shared.isPlus) },
                onOpenPro: { choosing = nil })
        } else {
            ProPaywallView(
                feature: feature,
                origin: origin,
                nextKind: Self.nextKind(after: feature),
                onPickBackground: { choosing = Self.nextKind(after: feature) },
                onClose: { dismiss() })
        }
    }

    private func current(_ kind: ProShowcaseKind) -> String {
        switch kind {
        case .profileBackground: return settings.profileBackground
        case .avatarFrame: return settings.avatarFrame ?? ""
        case .routeLine: return RouteLineStyle.stored.rawValue
        case .vehicleCard: return ""
        }
    }
}
