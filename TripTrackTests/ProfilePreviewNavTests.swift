import XCTest
@testable import TripTrack

/// `Array<ProfilePreviewDest>.cappedAppend` — единственная дверь, через
/// которую социальные экраны кладутся в путь (лента, чужой профиль, хаб
/// путешествий, инбокс). Два правила: потолок глубины (обход бага SwiftUI с
/// мигающим «← Назад» на четвёртом экране) и идемпотентность — тот же экран
/// наверху не кладётся вторым. У путешествия второй экземпляр это ещё и
/// второй `POST /social/journey`.
final class ProfilePreviewNavTests: XCTestCase {

    private let journeyId = UUID()

    func testDoubleTapDoesNotStackTheSameScreenTwice() {
        var path: [ProfilePreviewDest] = []
        path.cappedAppend(.publicJourney(journeyId))
        path.cappedAppend(.publicJourney(journeyId))
        XCTAssertEqual(path, [.publicJourney(journeyId)])
    }

    /// Идемпотентность смотрит ТОЛЬКО на верх пути: вернуться на экран, с
    /// которого ушёл вглубь, — законный переход, а не дубликат.
    func testSameScreenDeeperInThePathStillPushes() {
        let other = UUID()
        var path: [ProfilePreviewDest] = [.publicJourney(journeyId), .trip(other)]
        path.cappedAppend(.publicJourney(journeyId))
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(path.last, .publicJourney(journeyId))
    }

    /// Другое путешествие — другой экран, сколько бы раз подряд по ним ни
    /// нажали.
    func testDifferentDestinationStillPushes() {
        var path: [ProfilePreviewDest] = []
        path.cappedAppend(.publicJourney(journeyId))
        path.cappedAppend(.publicJourney(UUID()))
        XCTAssertEqual(path.count, 2)
    }

    /// Потолок не сдвинулся: на нём самый глубокий экран заменяется, а не
    /// добавляется.
    func testDepthStaysCapped() {
        var path: [ProfilePreviewDest] = []
        for _ in 0..<6 { path.cappedAppend(.trip(UUID())) }
        XCTAssertEqual(path.count, [ProfilePreviewDest].previewDepthCap)
    }
}
