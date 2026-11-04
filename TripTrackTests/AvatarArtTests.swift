import XCTest
import UIKit
@testable import TripTrack

/// The avatar artwork that replaces the platform emoji, the same set as the Android app's (`AvatarArt`).
final class AvatarArtTests: XCTestCase {
    func testEveryPickableAvatarHasArtInTheBundle() {
        for emoji in MyProfileView.avatars {
            let name = AvatarArt.imageName(for: emoji)
            XCTAssertNotNil(name, emoji)
            XCTAssertNotNil(name.flatMap { UIImage(named: $0) }, emoji)
        }
    }

    /// Retired from the picker; people still wear them.
    func testRetiredAvatarsStillHaveArt() {
        for emoji in ["🌅", "🎸", "📷", "🎮", "🚀", "🚙"] {
            XCTAssertNotNil(AvatarArt.imageName(for: emoji).flatMap { UIImage(named: $0) }, emoji)
        }
    }

    func testTheVariationSelectorIsOptional() {
        XCTAssertEqual(AvatarArt.imageName(for: "👱‍♀️"), AvatarArt.imageName(for: "👱‍♀"))
        XCTAssertNotNil(AvatarArt.imageName(for: "👱‍♀️"))
    }

    /// Anything else keeps the font: a car on an old account, a medal in the inbox.
    func testOtherEmojiFallBackToTheFont() {
        XCTAssertNil(AvatarArt.imageName(for: "🚗"))
        XCTAssertNil(AvatarArt.imageName(for: "🏅"))
    }

    func testTheSetIsTheAndroidEighteen() {
        XCTAssertEqual(AvatarArt.emojis.count, 18)
    }
}
