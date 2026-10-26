import Foundation

extension AppStrings {
    static func profilePhotoCount(_ lang: LanguageManager.Language, n: Int, max: Int) -> String {
        tr(lang, "profilePhotoCount", ru: "{n} из {max}", en: "{n} of {max}")
            .replacingOccurrences(of: "{n}", with: String(n))
            .replacingOccurrences(of: "{max}", with: String(max))
    }
    static func profilePhotosSignIn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profilePhotosSignIn", ru: "Войдите, чтобы фото увидели другие", en: "Sign in so others can see your photos")
    }
    static func profilePhotosEmpty(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profilePhotosEmpty", ru: "Добавьте фото — их увидят на вашей карточке", en: "Add photos — people will see them on your card")
    }
    static func profilePhotosLimit(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profilePhotosLimit", ru: "В профиле уже девять фото", en: "Your profile already has nine photos")
    }
    static func profilePhotoFirst(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profilePhotoFirst", ru: "Сделать первой", en: "Make first")
    }
    static func profileShowcase(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileShowcase", ru: "Витрина", en: "Showcase")
    }
    static func profileShowcaseEmpty(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileShowcaseEmpty", ru: "Закрепите до трёх поездок через «…» на экране поездки — их первыми увидят на вашей карточке", en: "Pin up to three trips using “…” on a trip — people will see them first on your card")
    }
    /// Pins whose trips this phone does not have (pinned on another phone,
    /// no cloud library here). Without this line they took showcase slots
    /// with nothing on screen to unpin.
    static func profileShowcaseElsewhere(_ lang: LanguageManager.Language, count: Int) -> String {
        tr(lang, "profileShowcaseElsewhere", ru: "Ещё {n} — закреплено на другом устройстве",
           en: "{n} more — pinned on another device")
            .replacingOccurrences(of: "{n}", with: String(count))
    }
    static func profilePin(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profilePin", ru: "Закрепить в профиле", en: "Pin to profile")
    }
    static func profileUnpin(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileUnpin", ru: "Открепить из профиля", en: "Unpin from profile")
    }
    static func profileShowcaseLimit(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileShowcaseLimit", ru: "Уже закреплены три поездки — открепите одну", en: "Three trips are already pinned — unpin one")
    }
}

extension AppStrings {
    static func profileAddCover(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileAddCover", ru: "Добавить обложку", en: "Add cover")
    }
    /// Строка в «Мой профиль» — постоянная дверь к обложке, когда приглашение
    /// на «Я» скрыто крестиком (TestFlight 0.9.2 (96), 26 окт 2026: «если я не
    /// хочу ковер добавлять, он мне будет вечно его предлагать?»).
    static func myProfileRowCover(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileRowCover", ru: "Обложка", en: "Cover")
    }
    static func myProfileCoverUnset(_ lang: LanguageManager.Language) -> String {
        tr(lang, "myProfileCoverUnset", ru: "Не задана", en: "Not set")
    }
    static func profileCoverPromptHide(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileCoverPromptHide", ru: "Скрыть", en: "Hide")
    }
    static func profileAddPhoto(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileAddPhoto", ru: "Добавить фото", en: "Add photo")
    }
    static func profileMakeCover(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileMakeCover", ru: "Сделать обложкой", en: "Make cover")
    }
    static func profileJournalSignIn(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profileJournalSignIn", ru: "Войдите, чтобы журнал увидели другие", en: "Sign in so others can see your journal")
    }
    static func profilePinned(_ lang: LanguageManager.Language) -> String {
        tr(lang, "profilePinned", ru: "Закреплено", en: "Pinned")
    }
    static func profileRoutineCount(_ lang: LanguageManager.Language, count: Int) -> String {
        plural(lang, count,
               one: tr(lang, "profileRoutineOne", ru: "{n} повторяющаяся поездка", en: "{n} repeated trip"),
               few: tr(lang, "profileRoutineFew", ru: "{n} повторяющиеся поездки", en: "{n} repeated trips"),
               many: tr(lang, "profileRoutineMany", ru: "{n} повторяющихся поездок", en: "{n} repeated trips"))
            .replacingOccurrences(of: "{n}", with: String(count))
    }
    static func profileMoreTrips(_ lang: LanguageManager.Language, count: Int) -> String {
        tr(lang, "profileMoreTrips", ru: "Ещё {n}", en: "{n} more")
            .replacingOccurrences(of: "{n}", with: String(count))
    }
    static func profileChapterSummary(_ lang: LanguageManager.Language, distance: String, trips: Int, regions: Int) -> String {
        [distance, "\(trips) \(nounTrips(lang, trips))", "\(regions) \(nounRegions(lang, regions))"].joined(separator: " · ")
    }
}
