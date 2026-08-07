import SwiftUI
import UIKit

extension View {
    /// Tap anywhere that isn't itself interactive to put the keyboard away.
    ///
    /// Attached as a BACKGROUND on purpose: buttons, links and the composer
    /// keep first claim on the touch, and only taps that fall through to
    /// empty space reach this layer. The alternative — dropping focus
    /// automatically after sending — takes the decision away from the user,
    /// who may well be about to write a second comment.
    func dismissesKeyboardOnBackgroundTap() -> some View {
        background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
        )
    }
}
