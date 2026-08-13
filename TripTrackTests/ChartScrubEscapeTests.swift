import XCTest
@testable import TripTrack

/// The rule that decides when a chart hands a touch back to the page.
///
/// The charts sit inside the detail's scroll view and claim a touch only when
/// it starts sideways. Everything here is about what happens AFTER that: the
/// finger turns and now wants to scroll the page, and the chart has to notice
/// and let go.
///
/// The version this replaced measured the total offset from where the drag
/// began, which asked the wrong question in the worst possible way — every
/// point read sideways along the chart raised the bar for escaping, so the
/// further along you had scrubbed the harder the page became to scroll, and a
/// long read could pin it outright. `long_scrub_then_turn` is that bug, and it
/// is the reason this file exists.
final class ChartScrubEscapeTests: XCTestCase {
    private let threshold = ScrubSurfaceView.escapeThreshold

    /// Runs a drag as a series of per-frame deltas and reports the vertical
    /// travel at which the surface let go, or nil if it never did.
    private func escapePoint(_ frames: [(dx: CGFloat, dy: CGFloat)]) -> CGFloat? {
        var commitment: CGFloat = 0
        var verticalTravel: CGFloat = 0
        for frame in frames {
            commitment = ScrubSurfaceView.advanceCommitment(
                commitment, dx: frame.dx, dy: frame.dy
            )
            verticalTravel += abs(frame.dy)
            if commitment > threshold { return verticalTravel }
        }
        return nil
    }

    func test_straight_down_lets_go_promptly() {
        // 2pt per frame is an unhurried drag, well under a flick.
        let escaped = escapePoint(Array(repeating: (dx: 0, dy: 2), count: 40))
        XCTAssertNotNil(escaped, "a finger going straight down must get the page back")
        XCTAssertLessThanOrEqual(
            escaped!, threshold + 2,
            "the page should move within a threshold's worth of vertical travel"
        )
    }

    func test_straight_up_lets_go_too() {
        // Scrolling back up the detail is the same gesture with the sign
        // flipped — direction is not the question, commitment is.
        XCTAssertNotNil(escapePoint(Array(repeating: (dx: 0, dy: -2), count: 40)))
    }

    func test_sideways_read_never_lets_go() {
        // Reading along the chart is the whole point of the surface; it must
        // hold the touch for as long as the finger keeps travelling sideways.
        XCTAssertNil(escapePoint(Array(repeating: (dx: 3, dy: 0), count: 200)))
    }

    func test_diagonal_is_left_with_the_chart() {
        // A 45° drag is genuinely ambiguous, and the touch was only claimed
        // because it started clearly sideways. Ambiguity keeps it there.
        XCTAssertNil(escapePoint(Array(repeating: (dx: 2, dy: 2), count: 200)))
    }

    func test_wobble_cannot_bank_its_way_out() {
        // A shaky finger reading the chart alternates a stray vertical frame
        // with sideways travel. Clamping at zero is what stops those strays
        // from accumulating into an escape over a long read.
        let wobble = (0..<200).map { i in
            i.isMultiple(of: 2) ? (dx: CGFloat(0), dy: CGFloat(3)) : (dx: CGFloat(4), dy: CGFloat(0))
        }
        XCTAssertNil(escapePoint(wobble))
    }

    func test_long_scrub_then_turn() {
        // The regression, stated as a drag: read 300pt along the chart — far
        // wider than any phone — then turn and scroll. What the finger did
        // before the turn must not cost it anything.
        let read = Array(repeating: (dx: CGFloat(4), dy: CGFloat(0)), count: 75)
        let turn = Array(repeating: (dx: CGFloat(0), dy: CGFloat(2)), count: 40)
        let escaped = escapePoint(read + turn)

        XCTAssertNotNil(escaped, "a long read must not pin the page")
        XCTAssertLessThanOrEqual(
            escaped!, threshold + 2,
            "the turn must cost the same as it would have on the first frame"
        )
    }

    func test_history_does_not_change_the_price_of_a_turn() {
        // Same claim as above, put as an equality: the escape point after a
        // long sideways read is identical to the one with no history at all.
        let turn = Array(repeating: (dx: CGFloat(0), dy: CGFloat(2)), count: 40)
        let afterLongRead = escapePoint(
            Array(repeating: (dx: CGFloat(4), dy: CGFloat(0)), count: 75) + turn
        )
        XCTAssertEqual(afterLongRead, escapePoint(turn))
    }
}
