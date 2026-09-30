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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ProPaywallView(feature: feature, onClose: { dismiss() })
    }
}
