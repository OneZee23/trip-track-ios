import SwiftUI

/// Значок «Плюс» у имени — в ленте, в чужом профиле, в комментариях.
///
/// Рисуется значком, а не словом: имя рядом бывает длинным, а строка «Плюс» в
/// тринадцати языках разной длины и однажды отняла бы у имени половину строки.
struct PlusBadge: View {
    var size: CGFloat = 13

    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        Image(systemName: "plus.diamond.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(red: 0.99, green: 0.82, blue: 0.42),
                             Color(red: 0.93, green: 0.55, blue: 0.16)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // `fixedSize` по той же причине, что у пилюли «Вы» рядом:
            // Dynamic Type не имеет права сжать значок в пользу имени —
            // сначала обрезается имя.
            .fixedSize()
            .accessibilityLabel(AppStrings.plusBadgeLabel(lang.language))
    }
}

/// Показывать ли значок. Чистая функция и своя таблица в тестах: правило
/// живёт в трёх местах показа сразу (лента, профиль, комментарии), и
/// разъехаться им нельзя.
enum PlusBadgeVisibility {
    /// - Parameters:
    ///   - isPlus: что сказал сервер про ЭТОТ аккаунт. `nil` — старый сервер
    ///     поля не прислал, и это «не сказано», а не «нет»: значок в таком
    ///     случае не рисуется, потому что рисовать нечего, но и решения
    ///     «подписки нет» здесь не принимается.
    ///   - isOwn: своя ли это карточка.
    ///   - showsOwnBadge: `SettingsManager.showPlusBadge` — тумблер в
    ///     «Приватности». Он про СВОЙ значок и только про него: прятать чужой
    ///     значок своей настройкой приложение не имеет права.
    static func shows(isPlus: Bool?, isOwn: Bool, showsOwnBadge: Bool) -> Bool {
        guard saysPlus(isPlus) else { return false }
        return isOwn ? showsOwnBadge : true
    }

    /// «Сервер сказал, что у этого аккаунта живая подписка?»
    ///
    /// `nil` — «не сказано», и ответ на него ОДИН на всю чужую косметику:
    /// нет. Функция названа и вынесена ровно затем, чтобы фон, рамка и значок
    /// на чужом профиле спрашивали одно и то же одним способом: пока правило
    /// стояло трижды по месту, фон и рамка читали «не сказано» как «да», а
    /// значок рядом — как «нет», и спор этих двух решался в пользу худшего
    /// случая — истёкшего подписчика, у которого сервер не вычистил поле.
    static func saysPlus(_ isPlus: Bool?) -> Bool { isPlus == true }
}
