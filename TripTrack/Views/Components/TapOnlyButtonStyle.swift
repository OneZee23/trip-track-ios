import SwiftUI

/// A button that answers to a tap and refuses everything else.
///
/// SwiftUI's stock button fires on lift as long as the finger is still inside
/// the frame — and on a 52pt-tall control that leaves a lot of room to move.
/// A thumb that lands on «Пауза» and flicks upward by 18pt has, as far as the
/// button is concerned, tapped it. On the recording screen that costs the rest
/// of the drive: the trip pauses silently and the road stops being written down
/// until someone notices the lock screen.
///
/// So: track the travel, and trigger only if the touch stayed put. Anything
/// that moves is a swipe someone started on top of a button, not a decision.
///
/// Built on `PrimitiveButtonStyle` rather than a raw gesture so the control
/// keeps its button role — VoiceOver still activates it the usual way.
struct TapOnlyButtonStyle: PrimitiveButtonStyle {
    /// How far a finger may drift and still count as a tap. Roughly the wobble
    /// of a thumb pressing a control in a moving car; anything past it reads as
    /// a deliberate direction.
    var slop: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        TapOnly(configuration: configuration, slop: slop)
    }

    private struct TapOnly: View {
        let configuration: Configuration
        let slop: CGFloat
        /// `@GestureState`, not `@State`: SwiftUI resets it for us when the
        /// gesture is cancelled instead of ended — an incoming call, a
        /// notification pulled down mid-press, the app going to the
        /// background. With plain state the control kept its pressed dimming
        /// for the rest of the drive and read as disabled.
        @GestureState private var isPressed = false

        var body: some View {
            configuration.label
                .opacity(isPressed ? 0.72 : 1)
                .animation(.easeOut(duration: 0.12), value: isPressed)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressed) { value, pressed, _ in
                            pressed = travel(value.translation) <= slop
                        }
                        .onEnded { value in
                            guard travel(value.translation) <= slop else { return }
                            configuration.trigger()
                        }
                )
        }

        private func travel(_ t: CGSize) -> CGFloat {
            max(abs(t.width), abs(t.height))
        }
    }
}
