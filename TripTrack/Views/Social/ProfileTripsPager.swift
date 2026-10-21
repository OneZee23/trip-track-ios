import Foundation

/// Догрузка поездок чужого профиля (0.9.1).
///
/// Шапка пишет «Поездки · 45», а профиль приносит только десять последних
/// (`recentTrips` — превью). Остальные идут страницами с
/// `/users/:id/profile-trips` тем же курсором ленты; первая страница
/// продолжается с последней из десяти, без лишнего запроса.
///
/// Чистая структура, а не состояние экрана: что звать, когда остановиться и
/// как не задвоить карточку — проверяется тестом, а не прокруткой.
struct ProfileTripsPager: Equatable {
    static let pageSize = 20
    /// Догружать, когда до конца осталось столько карточек, — тот же порог,
    /// что у `PublicJourneysView`: прокрутка не замирает в ожидании сети.
    static let prefetchDistance = 3

    private(set) var cursor: String?
    /// Сервер обещает поездок больше, чем уже есть, — без этого признака
    /// профиль с ровно десятью поездками сделал бы холостой запрос.
    private(set) var exhausted = false
    private(set) var isLoading = false
    private var seenCursors = Set<String>()

    /// После загрузки профиля: десять превью и сколько всего публичных.
    mutating func reset(preview: [SocialFeedTrip], publicCount: Int?) {
        isLoading = false
        seenCursors = []
        guard let last = preview.last, (publicCount ?? 0) > preview.count else {
            cursor = nil
            exhausted = true
            return
        }
        cursor = APIEndpoint.feedCursor(startDate: last.startDate, id: last.id)
        exhausted = false
    }

    /// Пора ли просить следующую страницу, глядя на появившуюся карточку.
    func shouldLoad(appearedIndex: Int, loadedCount: Int) -> Bool {
        guard !exhausted, !isLoading, cursor != nil else { return false }
        return appearedIndex >= loadedCount - Self.prefetchDistance
    }

    mutating func begin() { isLoading = true }

    /// Новая страница: новые карточки дописываются, повторы (граница
    /// страниц, обновление профиля посреди прокрутки) отбрасываются.
    mutating func apply(_ page: SocialFeedResponse, to cards: inout [SocialFeedTrip]) {
        isLoading = false
        var known = Set(cards.map(\.id))
        for trip in page.trips where known.insert(trip.id).inserted {
            cards.append(trip)
        }
        if let next = page.nextCursor, !next.isEmpty, seenCursors.insert(next).inserted {
            cursor = next
        } else {
            cursor = nil
            exhausted = true
        }
    }

    /// Страница не пришла: уже показанное остаётся, список просто перестаёт
    /// расти до следующего обновления профиля — как у `PublicJourneysView`.
    mutating func fail() {
        isLoading = false
        exhausted = true
    }
}
