import Foundation

extension AppStrings {
    static func hiddenEditorTitle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenEditorTitle", ru: "Скрыть от других", en: "Hide from others") }
    static func hiddenShowPublic(_ l: LanguageManager.Language) -> String { tr(l, "hiddenShowPublic", ru: "Как увидят другие", en: "How others will see it") }
    static func hiddenShowOwn(_ l: LanguageManager.Language) -> String { tr(l, "hiddenShowOwn", ru: "Ваша поездка", en: "Your trip") }
    static func hiddenStart(_ l: LanguageManager.Language) -> String { tr(l, "hiddenStart", ru: "Начало", en: "Start") }
    static func hiddenEnd(_ l: LanguageManager.Language) -> String { tr(l, "hiddenEnd", ru: "Конец", en: "End") }
    static func hiddenNone(_ l: LanguageManager.Language) -> String { tr(l, "hiddenNone", ru: "Нет", en: "None") }
    /// `startParking`/`endParking`: the edge hides only the parked time (0.9.5 locks), named instead of a distance.
    static func hiddenSummary(_ l: LanguageManager.Language, start: String, end: String, sections: Int,
                              startParking: Bool = false, endParking: Bool = false) -> String {
        var parts: [String] = []
        if startParking { parts.append(hiddenSummaryStartParking(l)) }
        else if !start.isEmpty { parts.append("\(hiddenStart(l)) \(start)") }
        if endParking { parts.append(hiddenSummaryEndParking(l)) }
        else if !end.isEmpty { parts.append("\(hiddenEnd(l)) \(end)") }
        if sections > 0 { parts.append(hiddenMiddleCount(l, count: sections)) }
        return parts.isEmpty ? hiddenNothing(l) : parts.joined(separator: " · ")
    }

    static func hiddenNothing(_ l: LanguageManager.Language) -> String {
        switch l {
        case .ru: "Ничего не скрыто"
        case .en: "Nothing is hidden"
        case .de: "Nichts wird verborgen"
        case .es: "No hay nada oculto"
        case .fr: "Rien n’est masqué"
        case .it: "Non c’è nulla di nascosto"
        case .pl: "Nic nie jest ukryte"
        case .id: "Tidak ada yang disembunyikan"
        case .tr: "Gizlenen bir şey yok"
        case .fil: "Walang nakatago"
        case .uk: "Нічого не приховано"
        case .kk: "Ештеңе жасырылмаған"
        case .pt: "Nada está oculto"
        }
    }

    private static func hiddenMiddleCount(_ l: LanguageManager.Language, count: Int) -> String {
        switch l {
        case .ru: "\(count) \(plural(l, count, one: "участок", few: "участка", many: "участков")) в середине"
        case .en: "\(count) \(plural(l, count, one: "section", many: "sections")) in the middle"
        case .de: "\(count) \(plural(l, count, one: "Abschnitt", many: "Abschnitte")) in der Mitte"
        case .es: "\(count) \(plural(l, count, one: "tramo", many: "tramos")) en medio"
        case .fr: "\(count) \(plural(l, count, one: "portion", many: "portions")) au milieu"
        case .it: "\(count) \(plural(l, count, one: "tratto", many: "tratti")) in mezzo"
        case .pl: "\(count) \(plural(l, count, one: "odcinek", few: "odcinki", many: "odcinków")) w środku"
        case .id: "\(count) bagian tengah"
        case .tr: "Ortada \(count) bölüm"
        case .fil: "\(count) bahaging nasa gitna"
        case .uk: "\(count) \(plural(l, count, one: "ділянка", few: "ділянки", many: "ділянок")) посередині"
        case .kk: "Ортада \(count) бөлік"
        case .pt: "\(count) \(plural(l, count, one: "trecho", many: "trechos")) no meio"
        }
    }
    static func hiddenSectionTitle(_ l: LanguageManager.Language, start: String, end: String) -> String {
        tr(l, "hiddenSectionTitle", ru: "Участок {start} — {end}", en: "Section {start} — {end}")
            .replacingOccurrences(of: "{start}", with: start).replacingOccurrences(of: "{end}", with: end)
    }
    static func hiddenAddSection(_ l: LanguageManager.Language) -> String { tr(l, "hiddenAddSection", ru: "+ Скрыть участок в середине", en: "+ Hide a middle section") }
    static func hiddenNumbersTitle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenNumbersTitle", ru: "Цифры для других", en: "Numbers for others") }
    static func hiddenAllTrip(_ l: LanguageManager.Language) -> String { tr(l, "hiddenAllTrip", ru: "Вся поездка", en: "Whole trip") }
    static func hiddenWithoutHidden(_ l: LanguageManager.Language) -> String { tr(l, "hiddenWithoutHidden", ru: "Без скрытого", en: "Visible parts") }
    static func hiddenNumbersPreview(_ l: LanguageManager.Language, distance: String, duration: String) -> String {
        tr(l, "hiddenNumbersPreview", ru: "Другие увидят {distance} и {duration}", en: "Others will see {distance} and {duration}")
            .replacingOccurrences(of: "{distance}", with: distance).replacingOccurrences(of: "{duration}", with: duration)
    }
    static func hiddenLocalCardTitle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenLocalCardTitle", ru: "Останется только на этом телефоне", en: "Stays on this phone") }
    static func hiddenLocalCardBody(_ l: LanguageManager.Language, pieces: Int, photos: Int) -> String {
        let count = plural(l, pieces,
            one: "скрытый кусок", few: "скрытых куска", many: "скрытых кусков")
        let hiddenParts = "\(pieces) \(count)"
        switch l {
        case .ru:
            let piece = plural(l, pieces, one: "скрытый кусок", few: "скрытых куска", many: "скрытых кусков")
            if photos == 0 {
                let verb = plural(l, pieces, one: "не попадёт", few: "не попадут", many: "не попадут")
                return "\(pieces) \(piece) \(verb) ни в ленту, ни в облачную копию."
            }
            return "\(pieces) \(piece) и \(photos) фото оттуда не попадут ни в ленту, ни в облачную копию."
        case .en:
            let piece = plural(l, pieces, one: "hidden piece", many: "hidden pieces")
            if photos == 0 { return "\(pieces) \(piece) won't reach the feed or cloud copy." }
            return "\(pieces) \(piece) and \(photos) \(plural(l, photos, one: "photo", many: "photos")) from them won't reach the feed or cloud copy."
        case .de:
            let sections = plural(l, pieces, one: "verborgener Abschnitt", many: "verborgene Abschnitte")
            if photos == 0 { return "\(pieces) \(sections) erscheinen weder im Feed noch in der Cloud-Kopie." }
            return "\(pieces) \(sections) und \(photos) \(plural(l, photos, one: "Foto", many: "Fotos")) davon erscheinen weder im Feed noch in der Cloud-Kopie."
        case .es:
            let sections = plural(l, pieces, one: "tramo oculto", many: "tramos ocultos")
            if photos == 0 { return "\(pieces) \(sections) no aparecerán en el feed ni en la copia en la nube." }
            return "\(pieces) \(sections) y \(photos) \(plural(l, photos, one: "foto", many: "fotos")) no aparecerán en el feed ni en la copia en la nube."
        case .fr:
            let sections = plural(l, pieces, one: "portion masquée", many: "portions masquées")
            if photos == 0 { return "\(pieces) \(sections) ne sera envoyée ni dans le fil ni dans la copie cloud." }
            return "\(pieces) \(sections) et \(photos) \(plural(l, photos, one: "photo", many: "photos")) ne seront envoyées ni dans le fil ni dans la copie cloud."
        case .it:
            let sections = plural(l, pieces, one: "tratto nascosto", many: "tratti nascosti")
            if photos == 0 { return "\(pieces) \(sections) non finirà nel feed né nella copia cloud." }
            return "\(pieces) \(sections) e \(photos) foto non finiranno nel feed né nella copia cloud."
        case .pl:
            let sections = plural(l, pieces, one: "ukryty odcinek", few: "ukryte odcinki", many: "ukrytych odcinków")
            if photos == 0 {
                let verb = pieces >= 2 && (2...4).contains(abs(pieces) % 10) && !(12...14).contains(abs(pieces) % 100) ? "nie trafią" : "nie trafi"
                return "\(pieces) \(sections) \(verb) do kanału ani kopii w chmurze."
            }
            return "\(pieces) \(sections) i \(photos) \(plural(l, photos, one: "zdjęcie", few: "zdjęcia", many: "zdjęć")) stamtąd nie trafią do kanału ani kopii w chmurze."
        case .id:
            let sections = plural(l, pieces, one: "bagian tersembunyi", many: "bagian tersembunyi")
            if photos == 0 { return "\(pieces) \(sections) tidak akan masuk ke feed atau salinan cloud." }
            return "\(pieces) \(sections) dan \(photos) foto darinya tidak akan masuk ke feed atau salinan cloud."
        case .tr:
            let sections = plural(l, pieces, one: "gizli bölüm", many: "gizli bölüm")
            if photos == 0 { return "\(pieces) \(sections) akışa veya bulut kopyasına gitmez." }
            return "\(pieces) \(sections) ve bunlardan \(photos) fotoğraf akışa veya bulut kopyasına gitmez."
        case .fil:
            let sections = plural(l, pieces, one: "nakatagong bahagi", many: "nakatagong bahagi")
            let photoNoun = plural(l, photos, one: "larawan", many: "larawan")
            if photos == 0 { return "Hindi mapupunta sa feed o cloud copy ang \(pieces) \(sections)." }
            return "Hindi mapupunta sa feed o cloud copy ang \(pieces) \(sections) at \(photos) \(photoNoun) kasama nito."
        case .uk:
            let sections = plural(l, pieces, one: "прихована ділянка", few: "приховані ділянки", many: "прихованих ділянок")
            if photos == 0 {
                let verb = plural(l, pieces, one: "не потрапить", few: "не потраплять", many: "не потраплять")
                return "\(pieces) \(sections) \(verb) ні у стрічку, ні в хмарну копію."
            }
            return "\(pieces) \(sections) і \(photos) фото звідти не потраплять ні у стрічку, ні в хмарну копію."
        case .kk:
            let sections = plural(l, pieces, one: "жасырын бөлік", many: "жасырын бөлік")
            if photos == 0 { return "\(pieces) \(sections) лентаға да, бұлттағы көшірмеге де жіберілмейді." }
            return "\(pieces) \(sections) пен олардағы \(photos) фото лентаға да, бұлттағы көшірмеге де жіберілмейді."
        case .pt:
            let sections = plural(l, pieces, one: "trecho oculto", many: "trechos ocultos")
            if photos == 0 { return "\(pieces) \(sections) não irá para o feed nem para a cópia na nuvem." }
            return "\(pieces) \(sections) e \(photos) \(plural(l, photos, one: "foto", many: "fotos")) não irão para o feed nem para a cópia na nuvem."
        }
    }
    static func hiddenTitleHint(_ l: LanguageManager.Language, title: String) -> String {
        tr(l, "hiddenTitleHint", ru: "Название «{title}» называет место финиша. Изменить название", en: "The title “{title}” names the finish. Change title")
            .replacingOccurrences(of: "{title}", with: title)
    }
    static func hiddenTitleHintStart(_ l: LanguageManager.Language, title: String) -> String {
        tr(l, "hiddenTitleHintStart", ru: "Название «{title}» называет место старта. Изменить название", en: "The title “{title}” names the starting place. Rename")
            .replacingOccurrences(of: "{title}", with: title)
    }
    static func hiddenAlreadySeen(_ l: LanguageManager.Language) -> String { tr(l, "hiddenAlreadySeen", ru: "Кто уже видел поездку, мог запомнить её целиком.", en: "People who saw this trip may remember the full route.") }
    static func hiddenLocalOnlyNotice(_ l: LanguageManager.Language) -> String { tr(l, "hiddenLocalOnlyNotice", ru: "Скрытые куски есть только на телефоне, где записана поездка.", en: "Hidden sections are available only on the phone that recorded this trip.") }
    static func hiddenSectionStartHandle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSectionStartHandle", ru: "Начало скрытого участка", en: "Hidden section start") }
    static func hiddenSectionEndHandle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSectionEndHandle", ru: "Конец скрытого участка", en: "Hidden section end") }
    static func hiddenQuestionTitle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenQuestionTitle", ru: "Скрывать начало и конец поездок?", en: "Hide the start and end of trips?") }
    static func hiddenQuestionBody(_ l: LanguageManager.Language) -> String { tr(l, "hiddenQuestionBody", ru: "Дом и место ночёвки не попадут ни в ленту, ни в облачную копию. Сами вы увидите поездку целиком.", en: "Your home and overnight stops stay out of the feed and cloud copy. You will still see the whole trip.") }
    static func hiddenQuestionWholeTrips(_ l: LanguageManager.Language, count: Int) -> String {
        tr(l, "hiddenQuestionWholeTrips", ru: "Целиком скроется маршрут у {count} {trips}", en: "The whole route of {count} published trips will be hidden")
            .replacingOccurrences(of: "{count}", with: String(count))
            .replacingOccurrences(of: "{trips}", with: AppStrings.tripsGenitive(l, count: count))
    }
    static func hiddenOptionDetail(_ l: LanguageManager.Language, metres: Int) -> String {
        switch metres {
        case 200: return tr(l, "hiddenOption200", ru: "двор, парковка", en: "driveway, parking")
        case 500: return tr(l, "hiddenOption500", ru: "квартал, стоянка", en: "neighbourhood, campsite")
        case 1_000: return tr(l, "hiddenOption1000", ru: "надёжнее для кемпинга", en: "more privacy at a campsite")
        default: return hiddenNone(l)
        }
    }
    static func hiddenSave(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSave", ru: "Сохранить", en: "Save") }
    static func hiddenSettingsFootnote(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSettingsFootnote", ru: "Поменять можно в Настройках → Приватность", en: "Change this in Settings → Privacy") }
    static func hiddenPublishPreviewTitle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenPublishPreviewTitle", ru: "Так её увидят в ленте и в профиле", en: "How it will look in the feed and profile") }
    static func hiddenPublishRow(_ l: LanguageManager.Language, summary: String) -> String {
        guard summary != hiddenNothing(l) else { return hiddenEditorTitle(l) }
        return tr(l, "hiddenPublishRow", ru: "Скрыто: {summary}", en: "Hidden: {summary}")
            .replacingOccurrences(of: "{summary}", with: summary)
    }
    static func hiddenOvernightHint(_ l: LanguageManager.Language) -> String { tr(l, "hiddenOvernightHint", ru: "Скрыть конец? Здесь вы ночевали", en: "Hide the end? You stayed overnight here") }
    static func hiddenHomeHint(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHomeHint", ru: "Скрыть начало? Здесь ваш дом", en: "Hide the start? Your home is here") }
    static func hiddenQuickHide(_ l: LanguageManager.Language, distance: String) -> String {
        tr(l, "hiddenQuickHide", ru: "Скрыть {distance}", en: "Hide {distance}")
            .replacingOccurrences(of: "{distance}", with: distance)
    }
    static func hiddenPrivacyIntro(_ l: LanguageManager.Language) -> String { tr(l, "hiddenPrivacyIntro", ru: "Скрытые участки скрываются во всех поездках, кроме тех, где вы задали своё расстояние. Они не попадают ни в ленту, ни в облако.", en: "Applies to trips without a custom setting. Hidden parts stay out of the feed and cloud.") }
    static func hiddenPrivacyModeFootnote(_ l: LanguageManager.Language) -> String { tr(l, "hiddenPrivacyModeFootnote", ru: "В режиме съёмки карты и «Места» скрывают закрытые участки, дом и синюю точку. Экран записи сохраняет точку.", en: "Filming mode hides private sections, home and your location dot on maps and Places. The recording screen keeps the dot.") }
    static func hiddenRouteLockAccessibility(_ l: LanguageManager.Language) -> String { tr(l, "hiddenRouteLockAccessibility", ru: "Граница скрытого участка", en: "Hidden route boundary") }
}
