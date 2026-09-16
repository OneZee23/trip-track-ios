import XCTest
@testable import TripTrack

/// Кто над кем лежит на экране поездки.
///
/// Поломка, из-за которой этот сторож написан: просмотрщик снимков висел
/// накладкой на `tripDetailBody`, а слой карты — на его результате. Накладки
/// ложатся в порядке ПРИМЕНЕНИЯ, значит карта оказывалась ВЫШЕ просмотрщика:
/// снимок честно разворачивался под непрозрачной картой, которая вдобавок
/// съедала касания, и «Открыть снимок» выглядела мёртвой кнопкой. Весь новый
/// путь «булавка → карточка → снимок» не работал вовсе.
///
/// Порядок накладок в SwiftUI поведенческим тестом не выражается — дерево
/// видов наружу не отдаётся. Поэтому сторож читает ИСХОДНИК, как это делают
/// `UnitsDisciplineTests` и `NoLiveSecretPromptsTests`.
final class TripDetailLayerOrderTests: XCTestCase {

    private var source: String!

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // TripTrackTests
            .deletingLastPathComponent()      // корень репозитория
            .appendingPathComponent("TripTrack/Views/Trips/TripDetailView.swift")
        source = try String(contentsOf: url, encoding: .utf8)
    }

    override func tearDown() {
        source = nil
        super.tearDown()
    }

    /// Просмотрщик — ПОСЛЕ карты, то есть выше неё.
    func testPhotoViewerLayerIsAppliedAfterTheMapLayer() throws {
        let map = try XCTUnwrap(source.range(of: ".overlay { fullscreenMapLayer() }"))
        let viewer = try XCTUnwrap(source.range(of: ".overlay { photoViewerLayer() }"))
        XCTAssertTrue(
            viewer.lowerBound > map.upperBound,
            "просмотрщик обязан применяться ПОСЛЕ карты, иначе снимок откроется под ней")
    }

    /// Обе накладки — в `body`, а не внутри `tripDetailBody`.
    ///
    /// `tripDetailBody` — это то, НА ЧТО вешается слой карты; повесить
    /// просмотрщик внутрь него значит вернуть ровно ту поломку, независимо от
    /// того, в каком порядке стоят строки.
    func testBothLayersLiveInTheScreenRoot() throws {
        let bodyStart = try XCTUnwrap(source.range(of: "    var body: some View {")).lowerBound
        let map = try XCTUnwrap(source.range(of: ".overlay { fullscreenMapLayer() }")).lowerBound
        let viewer = try XCTUnwrap(source.range(of: ".overlay { photoViewerLayer() }")).lowerBound
        XCTAssertTrue(map > bodyStart, "слой карты вне `body`")
        XCTAssertTrue(viewer > bodyStart, "слой просмотрщика вне `body`")

        let stageStart = try XCTUnwrap(source.range(of: "private var tripDetailStage: some View {")).lowerBound
        XCTAssertTrue(bodyStart < stageStart, "`body` обязан стоять выше `tripDetailStage` в файле")
        XCTAssertTrue(map < stageStart && viewer < stageStart,
                      "обе накладки обязаны жить в `body`, а не в теле экрана")
    }

    /// Просмотрщик как СЛОЙ обязан сам добрать безопасную зону.
    ///
    /// Под `.ignoresSafeArea(.container)` экрана поездки вставок в поддереве
    /// нет вовсе, и «×» садится на часы — та же поломка, что уже чинили хрому
    /// полноэкранной карты.
    func testViewerAsALayerAsksForItsSafeArea() {
        XCTAssertTrue(source.contains("addsSafeAreaInsets: true"),
                      "слой обязан добрать безопасную зону сам")
    }

    /// `.onDisappear` не имеет права разбирать карту: в `NavigationStack` он
    /// приходит и на ПУШ чужого экрана поверх поездки.
    func testScreenDoesNotTearDownTheMapOnDisappear() {
        XCTAssertFalse(source.contains(".onDisappear { mapHost.tearDown() }"),
                       "пуш паспорта машины разобрал бы карту живого экрана")
    }

    /// Ни одной цепочки «анимация + сон» (CLAUDE.md, «Анимацию можно
    /// прервать»): фазы раскрытия ведёт состояние и `completionCriteria`.
    func testExpansionHasNoSleepChain() {
        let expansion = source.range(of: "private func expandMap()").map {
            String(source[$0.lowerBound...].prefix(2_600))
        }
        XCTAssertNotNil(expansion)
        XCTAssertFalse(expansion?.contains("Task.sleep") ?? true,
                       "сон внутри раскрытия нечем отменить")
        XCTAssertTrue(source.contains("completionCriteria: .logicallyComplete"))
    }
}
