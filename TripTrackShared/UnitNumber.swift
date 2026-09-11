import Foundation

/// Как печатается само ЧИСЛО — по языку, и одинаково по обе стороны границы
/// процесса.
///
/// Разделитель разрядов и разделитель дробной части — это не оформление, а
/// часть строки: «12 000» и «12,000» читаются как разные числа, а «7.7» на
/// немецком телефоне читается как опечатка. Приложение это уже умело
/// (`AppStrings.groupedNumber`, `AppStrings.decimalSeparator`), но умело
/// ТОЛЬКО ВНУТРИ СЕБЯ: у виджета своего форматтера не было вовсе — он печатал
/// `String(format: "%.1f")`, то есть точку в любом языке и разряды слитно.
/// Пока на локскрине стояли километры, разница пряталась за тем, что число там
/// редко переваливает за тысячу; с милями расходятся ещё и десятые, потому что
/// граница «до скольких показывать десятые» у них другая.
///
/// Поэтому таблица одна и живёт в `TripTrackShared` — единственной папке,
/// которую компилируют оба таргета. `AppStrings` и `Measure` ходят сюда же:
/// два одинаковых форматтера по разные стороны границы разъезжаются не сразу,
/// а через релиз, когда кто-то поправит один из них.
///
/// Ключ — СЫРОЙ КОД языка (`"ru"`, `"fil"`), а не `LanguageManager.Language`:
/// этого типа в виджете не существует. Ровно так же устроены подписи в
/// `LiveActivityStrings`. Неизвестный код падает на английский — то же
/// правило, что у `AppStrings.tr`.
enum UnitNumber {

    /// Локаль, которой строится каждый форматтер. Копия таблицы
    /// `LanguageManager.Language.locale` — и то, что это копия, держит тест
    /// (`LiveActivityUnitTests.testLocaleTableMatchesTheApp`): язык добавляют
    /// в приложении, а вспомнить про вторую сторону границы некому.
    static func locale(code: String) -> Locale {
        switch code {
        case "ru":  return Locale(identifier: "ru_RU")
        case "de":  return Locale(identifier: "de_DE")
        case "es":  return Locale(identifier: "es_ES")
        case "fr":  return Locale(identifier: "fr_FR")
        case "it":  return Locale(identifier: "it_IT")
        case "pl":  return Locale(identifier: "pl_PL")
        case "id":  return Locale(identifier: "id_ID")
        case "tr":  return Locale(identifier: "tr_TR")
        case "fil": return Locale(identifier: "fil_PH")
        case "uk":  return Locale(identifier: "uk_UA")
        case "kk":  return Locale(identifier: "kk_KZ")
        case "pt":  return Locale(identifier: "pt_BR")
        default:    return Locale(identifier: "en_US")
        }
    }

    /// Запятая или точка. Спрашивается у локали, а не пишется списком:
    /// английский, филиппинский и индонезийский ставят точку там, где почти
    /// вся Европа ставит запятую, и список этот только растёт.
    static func decimalSeparator(code: String) -> String {
        locale(code: code).decimalSeparator ?? "."
    }

    /// «12 000» — целое с разрядами по языку.
    static func grouped(_ value: Int, code: String) -> String {
        let formatter = formatters[normalized(code)] ?? formatters["en"]
        return formatter?.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// «12,4» — одна десятая, с разделителем по языку.
    ///
    /// Через `%.1f` и замену точки, а не через `NumberFormatter`: форматтер с
    /// `maximumFractionDigits = 1` округляет по своим правилам и на границе
    /// «.05» отвечает иначе, чем `(value * 10).rounded() / 10`. Пока это одна
    /// строка в одном месте, разойтись ей не с чем.
    static func tenths(_ value: Double, code: String) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded)
            .replacingOccurrences(of: ".", with: decimalSeparator(code: code))
    }

    // MARK: - Форматтеры

    private static func normalized(_ code: String) -> String {
        supported.contains(code) ? code : "en"
    }

    private static let supported: Set<String> = [
        "en", "ru", "de", "es", "fr", "it", "pl", "id", "tr", "fil", "uk", "kk", "pt"
    ]

    /// По одному на язык, построены один раз: `NumberFormatter` дорог в
    /// постройке, а список поездок прокручивают.
    private static let formatters: [String: NumberFormatter] = {
        var map: [String: NumberFormatter] = [:]
        for code in supported {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = locale(code: code)
            if code == "ru" { f.groupingSeparator = "\u{00A0}" }
            if code == "en" { f.groupingSeparator = "," }
            // Разделитель разрядов обязан быть НЕРАЗРЫВНЫМ. С обычным пробелом
            // строка «Volkswagen Polo · 2019 · 12 000 км» переносится ВНУТРИ
            // числа — «12» остаётся на одной строке, «000 км» уезжает на
            // следующую. Ловится не в тестах, а глазами на узкой карточке, и то
            // не сразу. Локали, которые сами группируют пробелом (fr, pl, kk,
            // uk), приходят сюда с U+0020 и чинятся тем же правилом.
            if let sep = f.groupingSeparator, sep == " " {
                f.groupingSeparator = "\u{00A0}"
            }
            map[code] = f
        }
        return map
    }()
}
