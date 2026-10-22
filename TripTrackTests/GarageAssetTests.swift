import UIKit
import XCTest

@testable import TripTrack

final class GarageAssetTests: XCTestCase {
    func testEveryPlatformHasAllThreeScalesAndLoads() throws {
        for style in VehicleCardStyle.allCases {
            let name = "platform_" + (style == .none ? "asphalt" : String(style.rawValue.dropFirst(5)))
            try assertAsset(name)
        }
        try assertAsset("platform_shadow")
    }
    func testEveryBodyAndColourHasAMatteVariantInAppOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for body in VehicleAvatar.styles {
            for color in VehicleAvatar.colors {
                let name = "pixel_\(body)_\(color)_matte"
                try assertAsset(name)
                XCTAssertFalse(
                    FileManager.default.fileExists(
                        atPath: root.appendingPathComponent("TripTrackLiveActivity/Assets.xcassets/\(name).imageset")
                            .path))
            }
        }
    }
    private func assertAsset(_ name: String) throws {
        XCTAssertNotNil(UIImage(named: name), name)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("TripTrack/Resources/Assets.xcassets/\(name).imageset")
        let data = try Data(contentsOf: folder.appendingPathComponent("Contents.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try XCTUnwrap(json["images"] as? [[String: String]])
        XCTAssertEqual(Set(images.compactMap { $0["scale"] }), Set(["1x", "2x", "3x"]))
        for image in images {
            let filename = try XCTUnwrap(image["filename"])
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(filename).path))
        }
    }
}
