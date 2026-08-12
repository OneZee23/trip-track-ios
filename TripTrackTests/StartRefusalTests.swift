import XCTest
@testable import TripTrack

/// The start control has one rule: after a swipe, either the trip is
/// recording or the screen says why it is not.
///
/// It was broken in the worst possible way — the slider slid home in silence
/// while a recording had actually begun that nobody could see, and swiping
/// again stopped it. Silence is not an outcome, so the refusal has to be a
/// value with a message behind it.
@MainActor
final class StartRefusalTests: XCTestCase {

    func testEveryRefusalHasSomethingToSay() {
        let refusals: [MapViewModel.StartRefusal] = [.locationDenied, .recoveryPending, .unknown, .noFix]
        for refusal in refusals {
            for language in [LanguageManager.Language.ru, .en] {
                let text = Self.message(for: refusal, language)
                XCTAssertFalse(
                    text.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(refusal) in \(language) has no message — that is the silent slider again"
                )
            }
        }
    }

    /// Each reason has to read differently, or a person hitting two different
    /// walls is told the same thing twice.
    func testRefusalsDoNotShareCopy() {
        let texts = [
            Self.message(for: .locationDenied, .ru),
            Self.message(for: .recoveryPending, .ru),
            Self.message(for: .unknown, .ru),
            Self.message(for: .noFix, .ru),
        ]
        XCTAssertEqual(Set(texts).count, texts.count, "two refusals say the same thing")
    }

    /// The catch-all exists precisely because the list of causes cannot be
    /// complete. It must stay in the enum.
    func testThereIsACatchAllRefusal() {
        XCTAssertNotEqual(MapViewModel.StartRefusal.unknown, .locationDenied)
        XCTAssertNotEqual(MapViewModel.StartRefusal.unknown, .recoveryPending)
    }

    /// Mirrors `TrackingView.refusalToast`. Kept here rather than reaching
    /// into the view so the copy contract is testable without a UI run.
    private static func message(
        for refusal: MapViewModel.StartRefusal, _ lang: LanguageManager.Language
    ) -> String {
        switch refusal {
        case .recoveryPending: return AppStrings.startRefusedRecovery(lang)
        case .locationDenied:  return AppStrings.startRefusedNoGeo(lang)
        case .unknown:         return AppStrings.startRefusedUnknown(lang)
        case .noFix:           return AppStrings.startRefusedNoFix(lang)
        }
    }
}
