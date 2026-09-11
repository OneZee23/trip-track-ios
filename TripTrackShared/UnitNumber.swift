import Foundation

/// Как печатается само ЧИСЛО — по языку, и одинаково по обе стороны границы
/// процесса.
///
/// Разделитель разрядов — не оформление, а часть строки: «12 000» и «12,000»
/// читаются как разные числа. Приложение это уже умело
/// (`AppStrings.groupedNumber`), но умело ТОЛЬКО ВНУТРИ СЕБЯ: у виджета своего
/// форматтера не было вовсе — он печатал `String(format: "%.1f")`, то есть
/// разряды слитно. Пока на локскрине стояли километры, разница пряталась за
/// тем, что число там редко переваливает за тысячу; с милями расходятся ещё и
/// десятые, потому что граница «до скольких показывать десятые» у них другая.
///
/// Разделитель ДРОБНОЙ части языку больше не подчиняется: с 0.6.7 он всегда
/// точка — см. `decimalSeparator(code:)`, там же записано, чьё это решение и
/// почему его нельзя «починить» обратно.
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

    /// ВСЕГДА ТОЧКА — во всех тринадцати языках, и это РЕШЕНИЕ ВЛАДЕЛЬЦА, а не
    /// недоделанная локализация.
    ///
    /// Дословно, 11 сентября 2026: «мне надо чтобы вне зависимости, всегда
    /// числа когда идут десятичными, разделялись точкой, просто для красоты».
    /// То есть осознанное отступление от правил локали: по ним русский,
    /// немецкий, французский и ещё восемь языков пишут здесь ЗАПЯТУЮ, и первое,
    /// что захочется сделать с этой строкой, — «починить» её обратно на
    /// `locale(code:).decimalSeparator`. НЕЛЬЗЯ: это вернёт владельцу ровно то,
    /// от чего он отказался. Правило держат `LocalizationTests.testDecimalSeparator`
    /// и `MeasureFormatTests.testDecimalSeparatorIsADotInEveryLanguage` — если
    /// они покраснели, значит кто-то уже «починил».
    ///
    /// Правило — про ДРОБНУЮ часть и только про неё. Разделитель РАЗРЯДОВ
    /// («12 000» против «12,000») по-прежнему берётся у языка ниже: его
    /// владелец не трогал, а спутать их нельзя — ни одно число в приложении не
    /// печатает разряды и десятые разом (`tenths` не группирует, `grouped` не
    /// дробит).
    ///
    /// Код языка остаётся в сигнатуре, хотя ответ от него больше не зависит:
    /// это единственная дверь, через которую разделитель попадает на экран, и
    /// звать её обязаны все — иначе отменить решение будет негде.
    static func decimalSeparator(code: String) -> String { "." }

    /// «12 000» — целое с разрядами по языку.
    static func grouped(_ value: Int, code: String) -> String {
        let formatter = formatters[normalized(code)] ?? formatters["en"]
        return formatter?.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// «12.4» — ВСЕГДА одна десятая, даже если она ноль.
    ///
    /// Через `%.1f` и замену разделителя, а не через `NumberFormatter`:
    /// форматтер с `maximumFractionDigits = 1` округляет по своим правилам и на
    /// границе «.05» отвечает иначе, чем `(value * 10).rounded() / 10`. Пока это
    /// одна строка в одном месте, разойтись ей не с чем.
    ///
    /// Замена сегодня меняет точку на точку — `%.1f` печатает по C-локали, а
    /// `decimalSeparator` отвечает точкой всем. Строка оставлена нарочно: она и
    /// есть та единственная дверь, и без неё отмена решения владельца прошла бы
    /// мимо печати числа.
    static func tenths(_ value: Double, code: String) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded)
            .replacingOccurrences(of: ".", with: decimalSeparator(code: code))
    }

    /// «1.5», но «2» — десятая печатается, только если она есть.
    ///
    /// Второе правило печати дробного числа, рядом с `tenths`, и разница между
    /// ними НЕ косметическая: `tenths` держит ШИРИНУ у живого счётчика (плашка
    /// REC, плитка записи, локскрин), который иначе прыгал бы на символ каждый
    /// километр; `upToTenth` печатает число, которое уже сложилось и больше не
    /// изменится, — а «142.0» у такого числа не десятая, а след форматтера.
    ///
    /// Округление СНАЧАЛА, целость проверяется ПОТОМ: 9.96 — это «10», а не
    /// «10.0», иначе хвост возвращался бы через округление с другой стороны.
    static func upToTenth(_ value: Double, code: String) -> String {
        let rounded = (value * 10).rounded() / 10
        guard rounded != rounded.rounded() else { return String(format: "%.0f", rounded) }
        return tenths(rounded, code: code)
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
