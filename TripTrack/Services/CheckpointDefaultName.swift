import Foundation

/// Имя от человека — священно. Дефолтное «Отметка N» (на любом из тринадцати
/// языков) и пустое — единственное, что геокодер вправе затереть
/// (`TripManager.applyPlaceName`).
///
/// Чистая функция, а не строка внутри `TripManager`: паттерн регулярки
/// собирается НАСТОЯЩЕЙ Swift-конкатенацией вокруг экранированного слова.
/// До этого файла на месте вызова стояло `"^\\(word) \\d+$"` — ДВА
/// бэкслеша, то есть буквальный текст `\(word)` внутри регулярки, а не
/// подстановка переменной `word` (та требует одного бэкслеша, `\(word)`).
/// Регулярка искала буквальную подстроку «(word) 7» и не совпадала
/// практически никогда, поэтому геокодер терял право переименовать
/// дефолтную отметку в реальное место.
enum CheckpointDefaultName {
    /// `true` для пустого имени и для «<слово отметки> N» на любом из
    /// тринадцати языков — «Отметка 7», «Checkpoint 12» и так далее.
    static func looksLikeDefaultCheckpointName(_ name: String) -> Bool {
        if name.isEmpty { return true }
        return LanguageManager.Language.allCases.contains { lang in
            let word = NSRegularExpression.escapedPattern(for: AppStrings.checkpointWord(lang))
            let pattern = "^" + word + " \\d+$"
            return name.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
