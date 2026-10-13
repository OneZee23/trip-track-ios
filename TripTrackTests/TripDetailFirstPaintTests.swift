import XCTest
import SwiftUI
@testable import TripTrack

/// A metric is already known when the detail opens. Its first render must
/// contain the value without waiting for onAppear, a timer, or a stagger.
@MainActor
final class TripDetailFirstPaintTests: XCTestCase {
    func testDistanceValueIsPresentOnTheFirstLightFrame() throws {
        try assertImmediateValue(
            DetailStatCard(value: "49", unit: "км", label: "Дистанция", color: .red),
            scheme: .light)
    }

    func testDurationSegmentsArePresentOnTheFirstDarkFrame() throws {
        try assertImmediateValue(
            DetailStatCard(segments: [.init(value: "4", unit: "ч"), .init(value: "58", unit: "мин")],
                           label: "Время", color: .red),
            scheme: .dark)
    }

    private func assertImmediateValue(_ card: DetailStatCard, scheme: ColorScheme,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let renderer = ImageRenderer(content: card
            .frame(width: 190, height: 90)
            .background(AppTheme.colors(for: scheme).bg)
            .environment(\.colorScheme, scheme))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, file: file, line: line)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let redPixels = pixels.withUnsafeMutableBytes { bytes -> Int in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let values = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: values.count, by: 4).reduce(0) { total, index in
                total + (values[index] > 180 && values[index + 1] < 120 && values[index + 2] < 120 ? 1 : 0)
            }
        }
        XCTAssertGreaterThan(redPixels, 30,
                             "The known metric is invisible on its first frame", file: file, line: line)
    }
}
