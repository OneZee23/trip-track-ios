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
    @State private var choosingBackground = false

    var body: some View {
        // Меняем содержимое того же листа: закрытие пейвола и одновременный
        // показ второго sheet могут потерять переход в SwiftUI.
        if choosingBackground {
            ProShowcaseSheet(
                kind: .profileBackground,
                current: settings.profileBackground,
                onPick: { settings.selectCosmetic(.profileBackground, id: $0,
                                                  isPlus: PlusAccess.shared.isPlus) },
                onOpenPro: { choosingBackground = false })
        } else {
            ProPaywallView(
                feature: feature,
                origin: origin,
                onPickBackground: { choosingBackground = true },
                onClose: { dismiss() })
        }
    }
}
