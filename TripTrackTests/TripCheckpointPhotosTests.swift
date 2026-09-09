import XCTest
@testable import TripTrack

/// Снимки сами находят свою отметку.
///
/// Остановились у моря, нажали флажок, сняли три кадра — связь между ними
/// уже есть в самих временах, и просить человека прикреплять руками значит
/// заставлять его повторить то, что он сделал самим фактом съёмки.
final class TripCheckpointPhotosTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func track(seconds: Int) -> [TrackPoint] {
        (0...seconds).map { t in
            TrackPoint(latitude: 45 + Double(t) * 10 / 111_320, longitude: 38.9,
                       speed: 10, timestamp: start.addingTimeInterval(Double(t)))
        }
    }

    private func checkpoint(at seconds: TimeInterval, id: UUID = UUID(), photoId: UUID? = nil,
                            photoIds: [UUID] = []) -> TripCheckpoint {
        TripCheckpoint(id: id, timestamp: start.addingTimeInterval(seconds),
                       latitude: 45 + seconds * 10 / 111_320, longitude: 38.9,
                       distanceFromStart: seconds * 10, elapsedFromStart: seconds,
                       photoId: photoId, photoIds: photoIds)
    }

    /// Прикреплённый рукой снимок принадлежит отметке, даже если по времени
    /// он ближе к другой: слово человека старше автоматики.
    func testAnAttachedPhotoStaysWithItsCheckpointEvenWhenTimeSaysOtherwise() {
        let far = photo(capturedAt: 3_000)
        let near = checkpoint(at: 3_000)
        let mine = checkpoint(at: 100, photoIds: [far.id])
        let links = TripCheckpointPhotos.link(checkpoints: [mine, near], photos: [far], points: [])
        XCTAssertEqual(links[mine.id]?.map(\.id), [far.id])
        XCTAssertNil(links[near.id])
    }

    /// Порядок на полке: обложка, потом прикреплённые как прикрепляли, потом
    /// подобранные по времени.
    func testCoverThenAttachedThenAutomatic() {
        let a = photo(capturedAt: nil), b = photo(capturedAt: nil), cover = photo(capturedAt: nil)
        let cp = checkpoint(at: 100, photoId: cover.id, photoIds: [a, b].map(\.id))
        // Без трека привязка по времени не работает — снимок находит отметку по координате кадра.
        let auto = photo(capturedAt: 120, lat: cp.latitude, lon: cp.longitude)
        let links = TripCheckpointPhotos.link(checkpoints: [cp], photos: [auto, b, cover, a], points: [])
        XCTAssertEqual(links[cp.id]?.map(\.id), [cover.id, a.id, b.id, auto.id])
    }

    private func photo(capturedAt seconds: TimeInterval?, id: UUID = UUID(),
                       lat: Double? = nil, lon: Double? = nil) -> TripPhoto {
        TripPhoto(id: id, filename: "\(id).jpg", caption: nil, timestamp: start,
                  capturedAt: seconds.map { start.addingTimeInterval($0) },
                  exifLatitude: lat, exifLongitude: lon)
    }

    /// Трека может не быть вовсе (поездка с сервера без точек) — координата
    /// кадра всё равно находит отметку.
    func testAGeotaggedPhotoLinksEvenWithoutATrack() {
        let cp = checkpoint(at: 1_000)
        let p = photo(capturedAt: nil, lat: cp.latitude, lon: cp.longitude)
        let links = TripCheckpointPhotos.link(checkpoints: [cp], photos: [p], points: [])
        XCTAssertEqual(links[cp.id]?.map(\.id), [p.id])
    }

    /// Кадр, снятый через две минуты после флажка, — кадр этой отметки.
    func testAPhotoTakenMinutesAfterTheFlagBelongsToIt() {
        let cp = checkpoint(at: 1_000)
        let p = photo(capturedAt: 1_120)
        let links = TripCheckpointPhotos.link(checkpoints: [cp], photos: [p], points: track(seconds: 3_000))
        XCTAssertEqual(links[cp.id]?.map(\.id), [p.id])
    }

    /// Обед через полчаса — уже не «у моря».
    func testAPhotoOutsideTheWindowStaysFree() {
        let cp = checkpoint(at: 1_000)
        let p = photo(capturedAt: 1_000 + TripCheckpointPhotos.timeWindow + 60)
        let links = TripCheckpointPhotos.link(checkpoints: [cp], photos: [p], points: track(seconds: 3_000))
        XCTAssertNil(links[cp.id])
    }

    /// Слово человека сильнее времени: прикреплённый кадр — обложка, даже если
    /// снят в другом конце поездки.
    func testAnAttachedPhotoIsTheCoverRegardlessOfTime() {
        let cover = photo(capturedAt: 2_900)
        let near = photo(capturedAt: 1_010)
        let cp = checkpoint(at: 1_000, photoId: cover.id)
        let links = TripCheckpointPhotos.link(checkpoints: [cp], photos: [near, cover], points: track(seconds: 3_000))
        XCTAssertEqual(links[cp.id]?.first?.id, cover.id, "обложка должна быть первой")
        XCTAssertEqual(links[cp.id]?.count, 2)
    }

    /// Один кадр — одной отметке, ближайшей по времени.
    func testEachPhotoGoesToExactlyOneCheckpoint() {
        let a = checkpoint(at: 1_000)
        let b = checkpoint(at: 1_400)
        let p = photo(capturedAt: 1_300)
        let links = TripCheckpointPhotos.link(checkpoints: [a, b], photos: [p], points: track(seconds: 3_000))
        XCTAssertNil(links[a.id])
        XCTAssertEqual(links[b.id]?.map(\.id), [p.id])
    }

    /// Без времени съёмки, но с координатой в кадре — по месту.
    func testAGeotaggedPhotoWithoutTimeLinksByPlace() {
        let cp = checkpoint(at: 1_000)
        let p = photo(capturedAt: nil, lat: cp.latitude + 50 / 111_320, lon: cp.longitude)
        let links = TripCheckpointPhotos.link(checkpoints: [cp], photos: [p], points: track(seconds: 3_000))
        XCTAssertEqual(links[cp.id]?.map(\.id), [p.id])
    }

    /// Снимок до 0.6.5 — ни времени, ни координаты — никуда не привязывается.
    func testAPhotoWithNoMetadataStaysFree() {
        let cp = checkpoint(at: 1_000)
        let p = photo(capturedAt: nil)
        let links = TripCheckpointPhotos.link(checkpoints: [cp], photos: [p], points: track(seconds: 3_000))
        XCTAssertTrue(links.isEmpty)
    }
}
