import SwiftUI

/// Вход в чаевые — ОДНА приглушённая строка в самом низу «Я».
///
/// Не карточка и не плитка, и ни одного акцентного элемента: чаевые
/// отличаются от тарифа ВСЕМ (спека §11). Терракота в этой версии закреплена
/// за покупкой и за числами; здесь покупки в смысле доступа нет вовсе — за
/// чаевыми не открывается ничего, и сказано это словами на самом листе
/// (требование Apple 3.1.1, а не вежливость).
///
/// До 0.8.4 это была карточка 68 с акцентной плиткой, шевроном и подписью —
/// то есть выглядела ровно как строка подписки, и намекала, что чаевые что-то
/// дают. Написана она была в 0.8.0 и ни разу никуда не подключена: «Плюс» был
/// спрятан целиком.
struct ProfileSupportRow: View {
    let onTap: () -> Void

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var lang: LanguageManager

    /// Видна ли строка.
    ///
    /// Чистой функцией, потому что ответ неочевиден: чаевые видны и
    /// ПОДПИСЧИКУ — это решение владельца, а не забытый гейт (спека §11:
    /// «Видны всем с витриной, и с PRO, и без»). Прячет их только витрина,
    /// которая платного не продаёт: там нет ни строки чаевых, ни раздела
    /// «Подписка» (состояние 17).
    static func isVisible(status: ProStatus) -> Bool {
        status != .hiddenStorefront
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart")
                    .font(.system(size: 14))
                Text(AppStrings.tipsEntry(lang.language))
                    .font(AppType.meta)
            }
            .foregroundStyle(c.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile_support_row")
    }
}
