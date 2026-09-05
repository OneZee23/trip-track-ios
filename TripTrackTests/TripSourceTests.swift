import XCTest
import CoreLocation
@testable import TripTrack

/// Источник поездок для экранов, которые умеют быть и своими, и чужими (0.6.3).
///
/// И карта, и статистика — чистые функции от массива `Trip`. Единственное, что
/// отличает чужой экран от своего, это откуда приехал массив. Здесь проверяется
/// самое хрупкое место этой развилки: маппинг серверного DTO в `Trip` так,
/// чтобы `MapExploration.build` получил РАБОЧИЕ координаты. Пустой
/// `previewCoordinates` не падает — он рисует пустую карту, и это тот отказ,
/// который проходит мимо глаз до самого прода.
final class TripSourceTests: XCTestCase {

    /// Полилиния из двух точек в том же бинарном формате, что пишет
    /// `Trip.encodePolyline` и хранит сервер в `preview_polyline`.
    private func samplePolylineBase64() -> String {
        let coords = [
            CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            CLLocationCoordinate2D(latitude: 56.3269, longitude: 44.0059),
        ]
        return Trip.encodePolyline(coords).base64EncodedString()
    }

    private func dto(polyline: String?) -> PublicTripDTO {
        PublicTripDTO(
            id: UUID(),
            startDate: Date(timeIntervalSince1970: 1_780_000_000),
            endDate: Date(timeIntervalSince1970: 1_780_017_880),
            distance: 412_000,
            duration: 17_880,
            region: "Нижегородская обл.",
            previewPolyline: polyline
        )
    }

    // MARK: - Маппинг

    func testMapsTheGeometryTheMapActuallyDraws() throws {
        let trip = dto(polyline: samplePolylineBase64()).asTrip()

        XCTAssertFalse(
            trip.previewCoordinates.isEmpty,
            "MapExploration.build читает previewCoordinates — пустой массив рисует пустую карту, а не падает"
        )
        XCTAssertEqual(trip.previewCoordinates.count, 2)
        XCTAssertEqual(trip.previewCoordinates[0].latitude, 55.7558, accuracy: 0.001)
    }

    func testCarriesDistanceAndRegionForTheAggregates() {
        let trip = dto(polyline: samplePolylineBase64()).asTrip()

        XCTAssertEqual(trip.distance, 412_000, accuracy: 0.5)
        XCTAssertEqual(trip.region, "Нижегородская обл.")
        XCTAssertEqual(trip.endDate?.timeIntervalSince1970, 1_780_017_880)
    }

    func testAlwaysMarksARemoteTripPublic() {
        let trip = dto(polyline: samplePolylineBase64()).asTrip()

        XCTAssertFalse(
            trip.isPrivate,
            "эндпоинт отдаёт только публичные — приватный флаг здесь означал бы, что фильтр на сервере протёк"
        )
    }

    func testSurvivesATripWithNoGeometry() {
        let trip = dto(polyline: nil).asTrip()

        XCTAssertTrue(trip.previewCoordinates.isEmpty)
        XCTAssertEqual(trip.distance, 412_000, accuracy: 0.5,
                       "поездка без полилинии всё равно считается в километрах и регионах")
    }

    func testIgnoresGarbageInsteadOfCrashing() {
        let trip = dto(polyline: "не base64 ни разу").asTrip()

        XCTAssertNil(trip.previewPolyline)
        XCTAssertTrue(trip.previewCoordinates.isEmpty)
    }

    // MARK: - Пагинация

    func testRemoteSourceFollowsTheCursorAcrossPages() async {
        let stub = StubTripTransport(pages: [
            (trips: [dto(polyline: samplePolylineBase64())], next: "cursor-2"),
            (trips: [dto(polyline: samplePolylineBase64())], next: nil),
        ])
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        let trips = await source.load().trips

        XCTAssertEqual(trips.count, 2)
        XCTAssertEqual(stub.requestedCursors, [nil, "cursor-2"])
    }

    func testRemoteSourceStopsWhenTheServerRepeatsACursor() async {
        // Защита от бесконечного цикла: сервер, повторяющий курсор, иначе
        // держал бы клиент в вечной пагинации на одном и том же ответе.
        let stub = StubTripTransport(pages: [
            (trips: [dto(polyline: samplePolylineBase64())], next: "same"),
            (trips: [dto(polyline: samplePolylineBase64())], next: "same"),
            (trips: [dto(polyline: samplePolylineBase64())], next: "same"),
        ])
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        let trips = await source.load().trips

        XCTAssertLessThanOrEqual(stub.requestedCursors.count, 2)
        XCTAssertFalse(trips.isEmpty)
    }

    func testRemoteSourceReturnsEmptyWhenTheOwnerHidTheMap() async {
        // Сервер в этом случае отдаёт пустой список, а не ошибку — экран
        // обязан показать пустое состояние, а не «не удалось загрузить».
        let stub = StubTripTransport(pages: [(trips: [], next: nil)])
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        let trips = await source.load().trips

        XCTAssertTrue(trips.isEmpty)
    }

    func testRemoteSourceSurvivesATransportFailure() async {
        let source = RemoteTripSource(accountId: UUID(), transport: FailingTripTransport())

        let result = await source.load()

        XCTAssertTrue(result.trips.isEmpty, "сетевой отказ не должен ронять экран")
        XCTAssertTrue(
            result.failed,
            "отказ обязан быть отличим от «человек ничего не опубликовал» — иначе экран соврёт про другого"
        )
    }

    func testASuccessfulEmptyAnswerIsNotAFailure() async {
        let stub = StubTripTransport(pages: [(trips: [], next: nil)])
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        let result = await source.load()

        XCTAssertTrue(result.trips.isEmpty)
        XCTAssertFalse(result.failed)
    }

    func testDoesNotCountTheSameTripTwiceAcrossPages() async {
        // Включающая граница кейсета возвращает пограничную поездку на обеих
        // страницах. Без дедупа это удвоенный километраж и дважды нарисованный
        // маршрут — лента уже наступала на это.
        let shared = dto(polyline: samplePolylineBase64())
        let stub = StubTripTransport(pages: [
            (trips: [shared], next: "cursor-2"),
            (trips: [shared], next: nil),
        ])
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        let result = await source.load()

        XCTAssertEqual(result.trips.count, 1)
    }

    func testARepeatedCursorIsReportedAsTruncatedNotComplete() async {
        let stub = StubTripTransport(pages: [
            (trips: [dto(polyline: samplePolylineBase64())], next: "same"),
            (trips: [dto(polyline: samplePolylineBase64())], next: "same"),
        ])
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        let result = await source.load()

        XCTAssertTrue(result.failed, "сервер обещал ещё страницу — данные неполны")
    }

    func testAsksForTheServersMaximumPageSize() async {
        let stub = StubTripTransport(pages: [(trips: [], next: nil)])
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        _ = await source.load()

        XCTAssertEqual(stub.requestedLimits, [RemoteTripSource.pageSize],
                       "без явного лимита сервер отдаёт 200, и потолок страниц молча вчетверо ниже")
    }

    func testAFailureMidPaginationIsReportedNotHiddenBehindPartialData() async {
        let stub = StubTripTransport(pages: [
            (trips: [dto(polyline: samplePolylineBase64())], next: "cursor-2"),
        ], failAfterPages: 1)
        let source = RemoteTripSource(accountId: UUID(), transport: stub)

        let result = await source.load()

        XCTAssertEqual(result.trips.count, 1)
        XCTAssertTrue(result.failed, "частичная карта с уверенными числами выглядит как полная")
    }
}

// MARK: - Стабы

private final class StubTripTransport: PublicTripsTransport, @unchecked Sendable {
    private var pages: [(trips: [PublicTripDTO], next: String?)]
    private let failAfterPages: Int?
    private(set) var requestedCursors: [String?] = []
    private(set) var requestedLimits: [Int] = []

    init(pages: [(trips: [PublicTripDTO], next: String?)], failAfterPages: Int? = nil) {
        self.pages = pages
        self.failAfterPages = failAfterPages
    }

    func fetch(accountId: UUID, cursor: String?, limit: Int,
               vehicleId: UUID? = nil) async throws -> PublicTripsResponse {
        requestedLimits.append(limit)
        if let failAfterPages, requestedCursors.count >= failAfterPages {
            requestedCursors.append(cursor)
            throw APIError.transport("offline")
        }
        requestedCursors.append(cursor)
        guard !pages.isEmpty else { return PublicTripsResponse(trips: [], nextCursor: nil) }
        let page = pages.removeFirst()
        return PublicTripsResponse(trips: page.trips, nextCursor: page.next)
    }
}

private struct FailingTripTransport: PublicTripsTransport {
    func fetch(accountId: UUID, cursor: String?, limit: Int,
               vehicleId: UUID? = nil) async throws -> PublicTripsResponse {
        throw APIError.transport("offline")
    }
}

/// Построение URL с query-строкой (0.6.3).
///
/// `/users/:id/trips?cursor=…` — первый эндпоинт в проекте с query-строкой, и
/// `URL.appendingPathComponent` для неё не годится: он кодирует `?` в `%3F` и
/// повторно кодирует `%` в `%25`. Запрос уходит в несуществующий путь, а
/// `RemoteTripSource` глотает отказ — чужая карта молча обрезается на первой
/// странице, без единой ошибки на экране.
final class APIEndpointQueryTests: XCTestCase {

    private let base = URL(string: "https://api.trip-track.app")!

    func testCursorlessPathIsUnchanged() {
        let path = APIEndpoint.userTrips("ABC", cursor: nil)

        XCTAssertEqual(path, "/users/ABC/trips")
    }

    func testLimitAndCursorTravelTogether() throws {
        let path = APIEndpoint.userTrips("ABC", cursor: "2026-08-01T10:00:00.000Z|1", limit: 500)

        let url = try XCTUnwrap(APIClient.url(base: base, path: path))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        XCTAssertEqual(items?.first(where: { $0.name == "limit" })?.value, "500")
        XCTAssertNotNil(items?.first(where: { $0.name == "cursor" })?.value)
    }

    func testCursorGoesIntoTheQueryString() {
        let path = APIEndpoint.userTrips("ABC", cursor: "2026-08-01T10:00:00.000Z|11111111")

        XCTAssertTrue(path.hasPrefix("/users/ABC/trips?cursor="))
        XCTAssertFalse(path.contains("|"), "разделитель курсора обязан быть экранирован")
    }

    func testBuiltURLKeepsTheQuestionMarkAsASeparator() throws {
        let path = APIEndpoint.userTrips("ABC", cursor: "2026-08-01T10:00:00.000Z|11111111")

        let url = try XCTUnwrap(APIClient.url(base: base, path: path))

        XCTAssertEqual(url.path, "/users/ABC/trips",
                       "«?» — разделитель, а не часть пути")
        XCTAssertNotNil(url.query, "курсор обязан доехать как query, иначе сервер его не увидит")
        XCTAssertFalse(url.absoluteString.contains("%3F"))
        XCTAssertFalse(url.absoluteString.contains("%25"), "двойное кодирование ломает значение курсора")
    }

    func testCursorSurvivesTheRoundTripIntact() throws {
        let cursor = "2026-08-01T10:00:00.000Z|11111111-1111-1111-1111-111111111111"
        let path = APIEndpoint.userTrips("ABC", cursor: cursor)

        let url = try XCTUnwrap(APIClient.url(base: base, path: path))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        XCTAssertEqual(items?.first(where: { $0.name == "cursor" })?.value, cursor)
    }

    func testAnOrdinaryPathStillBuildsTheSameWayItAlwaysHas() throws {
        let url = try XCTUnwrap(APIClient.url(base: base, path: "/users/ABC/profile"))

        XCTAssertEqual(url.absoluteString, "https://api.trip-track.app/users/ABC/profile")
    }
}
