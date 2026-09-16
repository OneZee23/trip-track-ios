import Foundation

/// Слова ВЕХИ — одной дверью, как `RiddleCopy` у загадки.
///
/// У вехи нет имени в базе: `Discovery.title` ей не даётся нарочно (имя
/// зависит от языка телефона, а колонка — нет), и карточка без этих строк
/// показывала бы одно слово «ВЕХА» и дату. Заголовок собирается ПРИ ПОКАЗЕ из
/// ключа — тем же приёмом, которым `TripMoments` собирает «Отметка 2», а
/// `RiddleCopy.type(ofRiddleKey:)` достаёт тип загадки.
///
/// Второй копии вехи в `Discovery` нет и не будет: `Milestone` — это половина
/// ключа по построению (`MilestoneHit.key`), и колонка однажды разошлась бы с
/// ключом.
enum MilestoneCopy {

    /// Веха из ключа находки («firstRegion:RU-KDA» → `.firstRegion`).
    ///
    /// Ключ без хвоста («above2000») законен: у вехи, которая бывает раз в
    /// жизни, хвоста нет вовсе.
    static func milestone(ofKey key: String) -> Milestone? {
        Milestone(rawValue: head(ofKey: key))
    }

    /// Заголовок карточки: «Первый раз в регионе».
    ///
    /// `nil` — ключ не разобрался (чужая версия, будущая веха): экран в этом
    /// случае оставляет карточку без заголовка, а не печатает сырой ключ.
    static func title(forKey key: String, _ lang: LanguageManager.Language) -> String? {
        milestone(ofKey: key).map { AppStrings.milestoneTitle(lang, $0) }
    }

    /// Место вехи словами: имя региона у «первого региона», пара стран у
    /// границы.
    ///
    /// У остальных — `nil`, и это не пропуск: хвост ключа у них ДЕНЬ
    /// (`yyyy-MM-dd`), а дата на карточке и так напечатана строкой ниже.
    static func place(
        forKey key: String, _ lang: LanguageManager.Language, atlas: RegionAtlas = .shared
    ) -> String? {
        guard let milestone = milestone(ofKey: key), let tail = tail(ofKey: key) else { return nil }
        switch milestone {
        case .firstRegion:
            return atlas.region(id: tail)?.localizedName(lang)
        case .countryBorder:
            let names = tail.split(separator: "-").compactMap {
                atlas.countryName(String($0), lang)
            }
            return names.count == 2 ? names.joined(separator: " — ") : nil
        default:
            return nil
        }
    }

    private static func head(ofKey key: String) -> String {
        guard let separator = key.firstIndex(of: ":") else { return key }
        return String(key[key.startIndex..<separator])
    }

    private static func tail(ofKey key: String) -> String? {
        guard let separator = key.firstIndex(of: ":") else { return nil }
        let tail = String(key[key.index(after: separator)...])
        return tail.isEmpty ? nil : tail
    }
}

/// Подпись находки для VoiceOver — одна на все места показа.
///
/// «Печать: веха» одинакова у всех тридцати вех и отвечает ровно на половину
/// вопроса. Вторую половину — что именно за веха, какой регион — знает только
/// ключ, поэтому собирается она здесь, а не в трёх экранах по-своему.
enum DiscoveryCopy {
    static func accessibility(
        for discovery: Discovery, _ lang: LanguageManager.Language
    ) -> String {
        var parts = [AppStrings.sealAccessibility(lang, kind: discovery.kind)]
        if let name = discovery.title, !name.isEmpty {
            parts.append(name)
        } else if discovery.kind == .milestone,
                  let title = MilestoneCopy.title(forKey: discovery.key, lang) {
            parts.append(title)
        } else if discovery.kind == .riddle {
            parts.append(AppStrings.riddleSolvedTitle(lang))
        }
        if let place = MilestoneCopy.place(forKey: discovery.key, lang) { parts.append(place) }
        return parts.joined(separator: ". ")
    }
}
