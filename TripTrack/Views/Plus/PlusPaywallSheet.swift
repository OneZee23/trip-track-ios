import SwiftUI

/// Заглушка пейвола «Плюс» — Задача 0 заводит гейт и замки, не витрину.
///
/// Задача 2 ЗАМЕНЯЕТ этот файл целиком: тарифы, «Восстановить покупки»,
/// ссылки на условия и приватность (спека §3). Здесь — ровно одна строка,
/// чтобы замок на любой из пяти точек (`PlusGate`) открывал что-то, а не
/// падал на несуществующем экране, и чтобы Задача 0 не рисовала витрину,
/// которую придётся выбросить.
struct PlusPaywallSheet: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Text(AppStrings.plusPaywallPlaceholder(lang.language))
            .font(.inter(16, weight: .semibold))
            .foregroundStyle(c.text)
            .padding(24)
            .contentSizedSheet(background: c.card)
    }
}
