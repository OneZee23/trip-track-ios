import Foundation
import os

private let remoteTripsLog = Logger(subsystem: "com.triptrack", category: "social.trips")

/// Откуда экран берёт поездки (0.6.3).
///
/// Карта и статистика — чистые функции от массива `Trip`:
/// `MapExploration.build(trips:visitedHashes:atlas:)` строит маршруты, регионы
/// и километры по регионам, `MeAggregates.compute(trips:roads:)` — все числа.
/// Значит чужие экраны это не новые экраны, а те же самые с другим массивом на
/// входе, и вся развилка «свой / чужой» живёт здесь.
///
/// Форк рендера не предполагается ни при каком раскладе: карту предстоит
/// переделывать до 1.0, и правка обязана менять оба места сразу.
protocol TripSource: Sendable {
    func load() async -> TripSourceResult
}

/// Результат загрузки: поездки И признак отказа.
///
/// Без второго поля пустой массив означает сразу две несовместимые вещи —
/// «человек ничего не опубликовал» и «сеть отвалилась». Экран в обоих случаях
/// написал бы «Пока нечего показать», то есть соврал бы про другого человека,
/// и не предложил бы повтор.
struct TripSourceResult {
    var trips: [Trip]
    var failed: Bool

    static let empty = TripSourceResult(trips: [], failed: false)
}

// MARK: - Свои поездки

/// Сегодняшнее поведение: библиотека владельца из CoreData.
struct LocalTripSource: TripSource {
    let tripManager: TripManager

    func load() async -> TripSourceResult {
        TripSourceResult(trips: await MainActor.run { tripManager.fetchTrips() }, failed: false)
    }
}

// MARK: - Чужие поездки

/// Публичные поездки другого аккаунта — постранично, с сервера.
///
/// Транспорт вынесен в протокол, чтобы тесты проверяли пагинацию без сети.
struct RemoteTripSource: TripSource {
    let accountId: UUID
    var transport: PublicTripsTransport = APIPublicTripsTransport()

    /// Потолок страниц за один заход. Размер страницы просим явно (`pageSize`),
    /// иначе сервер отдаёт свои 200 по умолчанию и потолок молча оказывается
    /// вчетверо ниже задуманного. 500 × 20 = десять тысяч публичных поездок,
    /// дальше которых не заходит ни один реальный аккаунт; предохранитель нужен
    /// на случай сервера, который отдаёт курсор бесконечно.
    private static let maxPages = 20
    /// Совпадает с потолком `take` на сервере.
    static let pageSize = 500

    func load() async -> TripSourceResult {
        var collected: [Trip] = []
        var cursor: String?
        var seenCursors = Set<String>()
        var seenIds = Set<UUID>()

        for _ in 0..<Self.maxPages {
            let page: PublicTripsResponse
            do {
                page = try await transport.fetch(
                    accountId: accountId, cursor: cursor, limit: Self.pageSize)
            } catch {
                // Сетевой отказ отдаёт то, что успели собрать. Экран покажет
                // неполную карту, но не «не удалось загрузить» поверх уже
                // нарисованных маршрутов.
                remoteTripsLog.error("public trips page failed: \(error.localizedDescription)")
                // Частично загруженная карта с уверенными числами хуже честного
                // «не удалось»: она выглядит как полная.
                return TripSourceResult(trips: collected, failed: true)
            }

            // Дедуп по id: граница кейсета может оказаться включающей, и тогда
            // поездка приезжает дважды — на карте это удвоенный километраж и
            // дважды нарисованный маршрут. Ленте ровно этот фикс уже понадобился.
            for dto in page.trips where seenIds.insert(dto.id).inserted {
                collected.append(dto.asTrip())
            }

            guard let next = page.nextCursor, !next.isEmpty else {
                return TripSourceResult(trips: collected, failed: false)
            }
            // Сервер, повторяющий курсор, иначе держал бы клиент в вечной
            // пагинации на одном и том же ответе.
            guard seenCursors.insert(next).inserted else {
                // Курсор повторился — дальше идти некуда, но и полученное НЕ
                // полно: сервер обещал следующую страницу. Данные обрезаны
                // ровно так же, как на потолке страниц.
                remoteTripsLog.error("public trips cursor repeated — data is truncated")
                return TripSourceResult(trips: collected, failed: true)
            }
            cursor = next
        }
        // Дошли до потолка страниц, а сервер всё ещё предлагает следующую.
        // Это ОБРЕЗАННЫЕ данные: отдать их как полные значит нарисовать карту
        // с уверенными числами, которые меньше правды.
        remoteTripsLog.error("public trips hit the page cap — data is truncated")
        return TripSourceResult(trips: collected, failed: true)
    }
}

// MARK: - Транспорт

protocol PublicTripsTransport: Sendable {
    func fetch(accountId: UUID, cursor: String?, limit: Int) async throws -> PublicTripsResponse
}

struct APIPublicTripsTransport: PublicTripsTransport {
    func fetch(accountId: UUID, cursor: String?, limit: Int) async throws -> PublicTripsResponse {
        try await APIClient.shared.get(
            APIEndpoint.userTrips(accountId.uuidString, cursor: cursor, limit: limit),
            requiresAuth: AuthService.shared.isSignedIn
        )
    }
}

// MARK: - DTO

/// Одна публичная поездка чужого аккаунта.
///
/// Намеренно бедный тип — ровно то, что потребляют `MapExploration.build` и
/// `MeAggregates.compute`. Ни реакций, ни фото, ни автора: на сотнях поездок
/// это был бы заметный трафик ради полей, которые карта не рисует.
struct PublicTripDTO: Codable, Hashable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    /// Метры.
    let distance: Double
    /// Секунды за рулём.
    let duration: Int?
    let region: String?
    /// base64 бинарной полилинии — тот же формат, что в ленте и профиле.
    let previewPolyline: String?

    /// Разворачивает DTO в тот же `Trip`, что приходит из CoreData.
    ///
    /// Единственное поле, за которым надо следить, — `previewPolyline`:
    /// из него `Trip.previewCoordinates` достаёт координаты, а из них
    /// строится ВСЯ карта. Битая base64 не роняет экран, но рисует пустую
    /// карту, поэтому она отбрасывается явно, а не молча.
    func asTrip() -> Trip {
        let polyline = previewPolyline.flatMap { Data(base64Encoded: $0) }
        let seconds = Double(duration ?? 0)
        // `Trip.duration` считается как `endDate - startDate`, а у незакрытой
        // поездки `endDate` нет — без подстановки она получила бы «сейчас минус
        // старт», то есть росла бы на глазах. Тот же фолбэк, что в `Trip(social:)`.
        let resolvedEnd = endDate ?? (seconds > 0
            ? startDate.addingTimeInterval(seconds)
            : startDate)
        return Trip(
            id: id,
            startDate: startDate,
            endDate: resolvedEnd,
            distance: distance,
            maxSpeed: 0,
            averageSpeed: seconds > 0 ? distance / seconds : 0,
            trackPoints: [],
            photos: [],
            region: region,
            // Эндпоинт отдаёт только публичные поездки. Приватный флаг здесь
            // означал бы, что серверный фильтр протёк.
            isPrivate: false,
            previewPolyline: polyline,
            isOnServer: true
        )
    }
}

struct PublicTripsResponse: Codable {
    let trips: [PublicTripDTO]
    /// `${startDate.toISOString()}|${id}` либо `nil`, если страниц больше нет.
    let nextCursor: String?
}
