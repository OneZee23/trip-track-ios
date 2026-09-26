import XCTest
import UIKit
@testable import TripTrack

/// Отступы кадрирования камеры «Атласа».
///
/// MapKit подгоняет камеру по СУММЕ безопасной зоны карты и переданного
/// `edgePadding` — поля разметки участвуют в кадрировании (CLAUDE.md, 0.7.0).
/// Карта «Атласа» отдаёт листу ~290 pt снизу через `additionalSafeAreaInsets`,
/// а `.region` просил сверх того ещё 480: на экране 874 pt по вертикали
/// оставалось −68, и MapKit отвечал кадром в ПЯТЬ раз шире запрошенного —
/// «нажал регион, а меня унесло куда-то вникуда» (владелец, 26 сен 2026).
/// Замер на устройстве до правки — `ratio=5.34`, после — `1.29`.
///
/// Числом, а не глазом: «карта смотрит не туда» не выражается ни возвращаемым
/// значением экрана, ни его состоянием — только остатком площади.
final class MapCameraPaddingTests: XCTestCase {
    /// Геометрия, на которой это и сломалось: iPhone 17 Pro Max, «Атлас» с
    /// карточкой региона.
    private let size = CGSize(width: 402, height: 874)
    private let safeArea = UIEdgeInsets(top: 62, left: 6, bottom: 290, right: 0)

    private func viewport(_ insets: UIEdgeInsets) -> CGSize {
        CGSize(width: size.width - safeArea.left - safeArea.right - insets.left - insets.right,
               height: size.height - safeArea.top - safeArea.bottom - insets.top - insets.bottom)
    }

    func testRegionPaddingLeavesTheMapSomethingToDrawIn() {
        let chrome = MapCameraCommand.Padding.region.chrome
        // То, что стояло до правки: хром уезжал в MapKit как есть.
        let naive = viewport(chrome)
        XCTAssertLessThan(naive.height, 0,
                          "иначе этот тест не про ту поломку: сырой хром обязан уходить в минус")

        let fixed = viewport(MapCameraCommand.Padding.region.insets(safeArea: safeArea, size: size))
        XCTAssertGreaterThanOrEqual(fixed.height, MapCameraCommand.Padding.minimumViewport)
        XCTAssertGreaterThanOrEqual(fixed.width, MapCameraCommand.Padding.minimumViewport)
    }

    /// Добавка просится сверх безопасной зоны, а не вместо неё: пока место
    /// есть, сумма равна заказанному хрому — карта кадрируется ровно под
    /// карточку, не теснее и не свободнее.
    func testPaddingAddsOnlyWhatTheSafeAreaDoesNotAlreadyGive() {
        let tall = CGSize(width: 402, height: 1600)
        let chrome = MapCameraCommand.Padding.region.chrome
        let insets = MapCameraCommand.Padding.region.insets(safeArea: safeArea, size: tall)

        XCTAssertEqual(insets.bottom + safeArea.bottom, chrome.bottom, accuracy: 0.01)
        XCTAssertEqual(insets.top + safeArea.top, chrome.top, accuracy: 0.01)
        XCTAssertEqual(insets.right, chrome.right, accuracy: 0.01,
                       "справа зоны нет — добавка равна хрому целиком")
    }

    /// Зона, которая сама больше хрома, добавки не получает вовсе.
    func testSafeAreaLargerThanTheChromeAsksForNothing() {
        let generous = UIEdgeInsets(top: 200, left: 60, bottom: 600, right: 60)
        let insets = MapCameraCommand.Padding.overview.insets(
            safeArea: generous, size: CGSize(width: 402, height: 1600))
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertEqual(insets.left, 0)
        XCTAssertEqual(insets.right, 0)
    }

    /// Отрицательных отступов не бывает ни при каком размере: именно на них
    /// MapKit и отвечает кадром во весь мир.
    func testNoPaddingIsEverNegativeOnAnyGeometry() {
        for height in stride(from: 80.0, through: 1600.0, by: 40.0) {
            for padding in [MapCameraCommand.Padding.overview, .region, .trip] {
                let insets = padding.insets(
                    safeArea: safeArea, size: CGSize(width: 402, height: height))
                XCTAssertGreaterThanOrEqual(insets.top, 0, "h=\(height)")
                XCTAssertGreaterThanOrEqual(insets.bottom, 0, "h=\(height)")
                XCTAssertGreaterThanOrEqual(insets.left, 0, "h=\(height)")
                XCTAssertGreaterThanOrEqual(insets.right, 0, "h=\(height)")
                let free = height - safeArea.top - safeArea.bottom
                if free > MapCameraCommand.Padding.minimumViewport {
                    XCTAssertLessThanOrEqual(
                        insets.top + insets.bottom,
                        free - MapCameraCommand.Padding.minimumViewport + 0.01,
                        "карте обязано остаться место, h=\(height)")
                }
            }
        }
    }
}
