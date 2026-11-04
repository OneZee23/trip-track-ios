import Foundation

extension AppStrings {
    static func hiddenEditorTitle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenEditorTitle", ru: "Скрыть от других", en: "Hide from others") }
    static func hiddenShowPublic(_ l: LanguageManager.Language) -> String { tr(l, "hiddenShowPublic", ru: "Как увидят другие", en: "How others will see it") }
    static func hiddenShowOwn(_ l: LanguageManager.Language) -> String { tr(l, "hiddenShowOwn", ru: "Ваша поездка", en: "Your trip") }
    static func hiddenStart(_ l: LanguageManager.Language) -> String { tr(l, "hiddenStart", ru: "Начало", en: "Start") }
    static func hiddenEnd(_ l: LanguageManager.Language) -> String { tr(l, "hiddenEnd", ru: "Конец", en: "End") }
    static func hiddenNone(_ l: LanguageManager.Language) -> String { tr(l, "hiddenNone", ru: "Нет", en: "None") }
    static func hiddenDefault(_ l: LanguageManager.Language) -> String { tr(l, "hiddenDefault", ru: "по умолчанию", en: "default") }
    static func hiddenTapMapHint(_ l: LanguageManager.Language) -> String { tr(l, "hiddenTapMapHint", ru: "Нажмите на маршрут, чтобы выбрать участок", en: "Tap the route to choose a section") }
    static func hiddenTapStart(_ l: LanguageManager.Language) -> String { tr(l, "hiddenTapStart", ru: "Нажмите на маршрут, где начинается участок", en: "Tap where the section starts") }
    static func hiddenTapEnd(_ l: LanguageManager.Language) -> String { tr(l, "hiddenTapEnd", ru: "Нажмите на маршрут, где заканчивается участок", en: "Tap where the section ends") }
    static func hiddenSummary(_ l: LanguageManager.Language, start: String, end: String, sections: Int) -> String {
        tr(l, "hiddenSummary", ru: "Начало {start} · конец {end} · участков в середине: {count}", en: "Start {start} · end {end} · middle sections: {count}")
            .replacingOccurrences(of: "{start}", with: start).replacingOccurrences(of: "{end}", with: end).replacingOccurrences(of: "{count}", with: String(sections))
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
        tr(l, "hiddenLocalCardBody", ru: "Скрытые участки: {pieces}, фото с них: {photos}. Они не попадут в ленту и облачную копию.", en: "Hidden sections: {pieces}; photos from them: {photos}. They stay out of the feed and cloud copy.")
            .replacingOccurrences(of: "{pieces}", with: String(pieces)).replacingOccurrences(of: "{photos}", with: String(photos))
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
    static func hiddenChooseEdge(_ l: LanguageManager.Language) -> String { tr(l, "hiddenChooseEdge", ru: "Скрыть расстояние", en: "Hide distance") }
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
    static func hiddenSettingsFootnote(_ l: LanguageManager.Language) -> String { tr(l, "hiddenSettingsFootnote", ru: "Поменять можно в Настройках → Конфиденциальность", en: "Change this in Settings → Privacy") }
    static func hiddenPublishPreviewTitle(_ l: LanguageManager.Language) -> String { tr(l, "hiddenPublishPreviewTitle", ru: "Так её увидят в ленте и в профиле", en: "How it will look in the feed and profile") }
    static func hiddenPublishRow(_ l: LanguageManager.Language, summary: String) -> String {
        tr(l, "hiddenPublishRow", ru: "Скрыто: {summary}", en: "Hidden: {summary}")
            .replacingOccurrences(of: "{summary}", with: summary)
    }
    static func hiddenOvernightHint(_ l: LanguageManager.Language) -> String { tr(l, "hiddenOvernightHint", ru: "Скрыть конец? Здесь вы ночевали", en: "Hide the end? You stayed overnight here") }
    static func hiddenHomeHint(_ l: LanguageManager.Language) -> String { tr(l, "hiddenHomeHint", ru: "Скрыть начало? Здесь ваш дом", en: "Hide the start? Your home is here") }
    static func hiddenQuickHide(_ l: LanguageManager.Language) -> String { tr(l, "hiddenQuickHide", ru: "Скрыть 500 м", en: "Hide 500 m") }
    static func hiddenPrivacyIntro(_ l: LanguageManager.Language) -> String { tr(l, "hiddenPrivacyIntro", ru: "Скрывается у всех поездок, кроме тех, где вы задали своё. Ни в ленту, ни в облако не уходит.", en: "Applies to trips without a custom setting. Hidden parts stay out of the feed and cloud.") }
    static func hiddenPrivacyModeFootnote(_ l: LanguageManager.Language) -> String { tr(l, "hiddenPrivacyModeFootnote", ru: "В режиме съёмки карты и «Места» скрывают закрытые участки, дом и синюю точку. Экран записи сохраняет точку.", en: "Filming mode hides private sections, home and your location dot on maps and Places. The recording screen keeps the dot.") }
    static func hiddenRouteLockAccessibility(_ l: LanguageManager.Language) -> String { tr(l, "hiddenRouteLockAccessibility", ru: "Граница скрытого участка", en: "Hidden route boundary") }
}
