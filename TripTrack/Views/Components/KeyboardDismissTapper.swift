import SwiftUI
import UIKit

/// Window-level "tap anywhere to close the keyboard".
///
/// The SwiftUI-only version of this (a `Color.clear` background with a tap
/// gesture) only ever saw the taps that fell through to empty space — on a
/// screen made of cards, a map and a scroll view, most taps are swallowed
/// before they get there, so the keyboard appeared to ignore five taps in a
/// row and then close on the sixth.
///
/// A recogniser on the window sees every touch. `cancelsTouchesInView =
/// false` plus simultaneous recognition means it only observes: buttons,
/// scrolling and every other gesture keep working exactly as before. Touches
/// that land inside a text input are ignored, so tapping the composer to
/// focus it doesn't immediately dismiss what it just opened.
struct KeyboardDismissTapper: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        // No window at make-time — attach on the next runloop pass.
        Task { @MainActor in context.coordinator.attach(to: view.window) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        Task { @MainActor in context.coordinator.attach(to: uiView.window) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func attach(to window: UIWindow?) {
            guard let window, recognizer == nil else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            // Observe, don't intercept.
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.window = window
            self.recognizer = tap
        }

        func detach() {
            if let recognizer { window?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            window = nil
        }

        @objc private func handleTap() {
            window?.endEditing(true)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            // Walk up from the touched view: anything inside a text input (or
            // the keyboard's own hosting window) is not a "tap outside".
            var view: UIView? = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}

extension View {
    /// See `KeyboardDismissTapper`.
    func dismissesKeyboardOnTapAnywhere() -> some View {
        background(KeyboardDismissTapper().allowsHitTesting(false))
    }
}
