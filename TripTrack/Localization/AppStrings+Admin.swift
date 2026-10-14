import Foundation

/// Админка (0.9.0). Экран видит только `is_admin`, то есть владелец, —
/// поэтому строки только на русском и английском: остальные языки
/// откатываются на английский по общему правилу `tr`, и это осознанно.
extension AppStrings {
    static func adminPanelTitle(_ l: LanguageManager.Language) -> String {
        tr(l, "adminPanelTitle", ru: "Админка", en: "Admin panel")
    }
    static func adminPanelSubtitle(_ l: LanguageManager.Language) -> String {
        tr(l, "adminPanelSubtitle", ru: "Подписки PRO, события Apple, флаги", en: "PRO subscriptions, Apple events, flags")
    }
    static func adminAccounts(_ l: LanguageManager.Language) -> String {
        tr(l, "adminAccounts", ru: "аккаунтов", en: "accounts")
    }
    static func adminNew7d(_ l: LanguageManager.Language) -> String {
        tr(l, "adminNew7d", ru: "новых за 7 дней", en: "new in 7 days")
    }
    static func adminActive7d(_ l: LanguageManager.Language) -> String {
        tr(l, "adminActive7d", ru: "активных за 7 дней", en: "active in 7 days")
    }
    static func adminProActive(_ l: LanguageManager.Language) -> String {
        tr(l, "adminProActive", ru: "PRO сейчас", en: "PRO now")
    }
    static func adminProSplit(_ l: LanguageManager.Language, trial: Int, paid: Int) -> String {
        tr(l, "adminProSplit", ru: "пробных {trial} · платных {paid}", en: "{trial} trial · {paid} paid")
            .replacingOccurrences(of: "{trial}", with: "\(trial)")
            .replacingOccurrences(of: "{paid}", with: "\(paid)")
    }
    static func adminTripsLine(_ l: LanguageManager.Language, trips: Int, manual: Int) -> String {
        tr(l, "adminTripsLine", ru: "поездок {trips} · вписанных {manual}", en: "{trips} trips · {manual} added by hand")
            .replacingOccurrences(of: "{trips}", with: "\(trips)")
            .replacingOccurrences(of: "{manual}", with: "\(manual)")
    }
    static func adminSubscriptions(_ l: LanguageManager.Language) -> String {
        tr(l, "adminSubscriptions", ru: "Подписки", en: "Subscriptions")
    }
    static func adminEvents(_ l: LanguageManager.Language) -> String {
        tr(l, "adminEvents", ru: "События Apple", en: "Apple events")
    }
    static func adminFlags(_ l: LanguageManager.Language) -> String {
        tr(l, "adminFlags", ru: "Флаги", en: "Flags")
    }
    static func adminFlagsFootnote(_ l: LanguageManager.Language) -> String {
        tr(l, "adminFlagsFootnote",
           ru: "Доходит до телефонов за минуту на сервере и до шести часов на устройстве. «По умолчанию» — значение, вшитое в приложение.",
           en: "Reaches phones within a minute on the server and up to six hours on the device. «Default» is the value built into the app.")
    }
    static func adminDefault(_ l: LanguageManager.Language) -> String {
        tr(l, "adminDefault", ru: "по умолчанию", en: "default")
    }
    static func adminTrial(_ l: LanguageManager.Language) -> String {
        tr(l, "adminTrial", ru: "пробная", en: "trial")
    }
    static func adminPaid(_ l: LanguageManager.Language) -> String {
        tr(l, "adminPaid", ru: "платная", en: "paid")
    }
    static func adminYearly(_ l: LanguageManager.Language) -> String {
        tr(l, "adminYearly", ru: "Год", en: "Yearly")
    }
    static func adminMonthly(_ l: LanguageManager.Language) -> String {
        tr(l, "adminMonthly", ru: "Месяц", en: "Monthly")
    }
    static func adminUnattached(_ l: LanguageManager.Language) -> String {
        tr(l, "adminUnattached", ru: "Не привязана к аккаунту", en: "Not attached to an account")
    }
    static func adminUntil(_ l: LanguageManager.Language, date: String) -> String {
        tr(l, "adminUntil", ru: "до {date}", en: "until {date}")
            .replacingOccurrences(of: "{date}", with: date)
    }
    static func adminRenewOff(_ l: LanguageManager.Language) -> String {
        tr(l, "adminRenewOff", ru: "продление выключено", en: "auto-renew off")
    }
    static func adminYou(_ l: LanguageManager.Language) -> String {
        tr(l, "adminYou", ru: "это вы", en: "you")
    }
    static func adminAccountSince(_ l: LanguageManager.Language, date: String) -> String {
        tr(l, "adminAccountSince", ru: "аккаунт с {date}", en: "account since {date}")
            .replacingOccurrences(of: "{date}", with: date)
    }
    static func adminNothingYet(_ l: LanguageManager.Language) -> String {
        tr(l, "adminNothingYet", ru: "Пока ничего", en: "Nothing yet")
    }
    static func adminLoadFailed(_ l: LanguageManager.Language) -> String {
        tr(l, "adminLoadFailed", ru: "Не удалось загрузить. Нужен сервер с админкой.", en: "Could not load. The server needs the admin update.")
    }
}
