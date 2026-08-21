import SwiftUI

/// The clubs the teaser promises, as data rather than as five hard-coded chips.
///
/// None of them exists yet — every screen that shows one says «СКОРО» in as
/// many words. What IS real is how many people said they would join each one:
/// that number comes from the waitlist (`GroupsWaitlistStore`), never from
/// this file.
struct Club: Identifiable, Hashable {
    /// Wire key — must match `CLUB_KEYS` on the server, which validates it.
    let id: String
    /// Kept as the fallback for a club whose mark has not been drawn — the
    /// catalogue is seeded here but the server validates the keys, so a key
    /// can arrive before its artwork does.
    let emoji: String
    /// Asset name of the drawn mark. The marks are deliberately generic —
    /// a roadster, a gear, a truck — because a recognisable Miata or Impreza
    /// silhouette is somebody else's registered trade dress, and these ship
    /// inside an App Store binary.
    var asset: String? { "club_\(id)" }
    /// Brand names stay in Latin in both languages.
    let nameRu: String
    let nameEn: String
    let blurbRu: String
    let blurbEn: String
    let tint: Color

    func name(_ lang: LanguageManager.Language) -> String {
        AppStrings.tr(lang, "club.\(id).name", ru: nameRu, en: nameEn)
    }
    func blurb(_ lang: LanguageManager.Language) -> String {
        AppStrings.tr(lang, "club.\(id).blurb", ru: blurbRu, en: blurbEn)
    }

    static func == (lhs: Club, rhs: Club) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Club {
    static let miata = Club(
        id: "miata",
        emoji: "🏎",
        nameRu: "Miata Club",
        nameEn: "Miata Club",
        blurbRu: "Сообщество владельцев Mazda MX-5. Автозаезды, покатушки выходного дня, обмен деталями и советами по тюнингу.",
        blurbEn: "Mazda MX-5 owners. Track days, weekend drives, parts and tuning advice.",
        tint: Color(red: 0.98, green: 0.90, blue: 0.90)
    )

    static let vag = Club(
        id: "vag",
        emoji: "⚙️",
        nameRu: "VAG Россия",
        nameEn: "VAG Club",
        blurbRu: "Volkswagen, Audi, Skoda, SEAT. Диагностика, прошивки, встречи по городам и общие выезды.",
        blurbEn: "Volkswagen, Audi, Skoda, SEAT. Diagnostics, tunes, city meetups and group drives.",
        tint: Color(red: 0.89, green: 0.93, blue: 0.99)
    )

    static let trucking = Club(
        id: "trucking",
        emoji: "🚚",
        nameRu: "Дальнобой",
        nameEn: "Trucking",
        blurbRu: "Те, кто живёт в рейсах. Маршруты, стоянки, погода на трассе и общий зачёт километров.",
        blurbEn: "For those who live on the road. Routes, stops, highway weather and a shared mileage board.",
        tint: Color(red: 0.88, green: 0.95, blue: 0.93)
    )

    static let offroad = Club(
        id: "offroad",
        emoji: "⛰️",
        nameRu: "Оффроуд 4×4",
        nameEn: "Off-road 4×4",
        blurbRu: "Грязь, броды и лебёдки. Совместные выезды, треки маршрутов и точки, куда стоит доехать.",
        blurbEn: "Mud, fords and winches. Group trips, shared tracks and places worth reaching.",
        tint: Color(red: 0.90, green: 0.96, blue: 0.88)
    )

    static let subaru = Club(
        id: "subaru",
        emoji: "🚙",
        nameRu: "Subaru Crew",
        nameEn: "Subaru Crew",
        blurbRu: "Боксеры и симметричный полный привод. Обслуживание, зимние покатушки, горнолыжные выезды.",
        blurbEn: "Boxers and symmetrical AWD. Maintenance, winter drives, ski trips.",
        tint: Color(red: 0.90, green: 0.92, blue: 0.98)
    )

    static let all: [Club] = [miata, vag, trucking, offroad, subaru]

    /// The three lines a club page promises. The same for every club: they are
    /// the FEATURE's promises, not one community's.
    static func perks(_ lang: LanguageManager.Language) -> [ClubPerk] {
        [
            ClubPerk(icon: "list.bullet.rectangle", text: AppStrings.clubPerkFeed(lang)),
            ClubPerk(icon: "trophy", text: AppStrings.clubPerkLeaderboard(lang)),
            ClubPerk(icon: "calendar", text: AppStrings.clubPerkMeetups(lang)),
        ]
    }

}

struct ClubPerk: Identifiable {
    let icon: String
    let text: String
    var id: String { icon }
}
