import Foundation

/// Чистая механика вычищения персонального из диагностических payload'ов.
///
/// ПОЧЕМУ отдельным типом, а не методами внутри `SentryService`: правило
/// «в отчёт не уезжает ничего личного» должен держать тест, а не поездка
/// в Sentry с чужим `accountId` в URL. Здесь нет ни одного типа из SDK,
/// поэтому `PIIScrubberTests` гоняет ровно эту логику без запуска Sentry
/// и без линковки пакета в тестовую цель.
///
/// Список имён полей — в `PIISensitiveKeys.all`, общий с `APILogger`.
enum PIIScrubber {
    // MARK: - Словари

    /// Вычищает словарь рекурсивно: значение по «чувствительному» имени
    /// заменяется целиком, остальное обходится вглубь.
    static func redact(dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in dict {
            if PIISensitiveKeys.matches(k) {
                out[k] = redactedMarker
            } else {
                out[k] = redact(value: v)
            }
        }
        return out
    }

    /// Ходит и по словарям, И по массивам. Без ветки массива payload вида
    /// `[{"accessToken": "..."}]` проскочил бы целиком — в `data` крошек и
    /// в `extra` события регулярно лежат массивы словарей.
    static func redact(value: Any) -> Any {
        if let dict = value as? [String: Any] { return redact(dict: dict) }
        if let arr = value as? [Any] { return arr.map(redact(value:)) }
        return value
    }

    static let redactedMarker = "<redacted>"

    // MARK: - URL

    /// Оставляет от URL схему, хост и ФОРМУ пути; выбрасывает query,
    /// фрагмент и любые идентификаторы внутри пути.
    ///
    /// ПОЧЕМУ не «оставить URL как есть»: у нас в путях лежат чужие и свои
    /// идентификаторы (`/users/<accountId>/trips`, `/users/<id>/vehicles/<id>`),
    /// а в query — курсор ленты, который по формату есть `дата|id поездки`.
    /// Всё это — «кто и куда ездил», то есть ровно то, ради чего приложение
    /// и существует. При этом «какой эндпоинт упал» — половина ценности
    /// отчёта, поэтому форма пути сохраняется.
    ///
    /// Правило для сегмента КОНСЕРВАТИВНОЕ: узнаваемое слово маршрута
    /// (только буквы и дефис, короткое) остаётся, всё остальное — `<id>`.
    /// Незнакомое прячется по умолчанию: новый эндпоинт с ключом в пути
    /// не должен ждать, пока кто-то вспомнит про этот файл.
    static func redactURL(_ raw: String) -> String {
        guard let comps = URLComponents(string: raw), let host = comps.host else {
            // Разобрать не смогли — значит и решить, что там личного, не
            // можем. Отдаём метку, а не исходную строку.
            return redactedMarker
        }
        let scheme = comps.scheme ?? "https"
        let path = comps.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { maskPathSegment(String($0)) }
            .joined(separator: "/")
        return path.isEmpty ? "\(scheme)://\(host)" : "\(scheme)://\(host)/\(path)"
    }

    /// Сегмент пути считается безопасным, только если он похож на слово
    /// маршрута: латиница, дефис/подчёркивание/точка, не длиннее 24 знаков
    /// и БЕЗ цифр. UUID, курсоры, коды шаринга и числовые id цифры содержат
    /// (или длиннее), поэтому отсекаются.
    private static func maskPathSegment(_ segment: String) -> String {
        guard segment.count <= 24 else { return idMarker }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_.")
        guard segment.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return idMarker
        }
        return segment
    }

    static let idMarker = "<id>"
}
