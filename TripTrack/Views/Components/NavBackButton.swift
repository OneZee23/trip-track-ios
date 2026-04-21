import SwiftUI

/// Unified back button for pushed views inside a NavigationStack.
/// Place in `ToolbarItem(placement: .topBarLeading)` alongside
/// `.navigationBarBackButtonHidden(true)` on the view.
/// Native swipe-back gesture continues to work.
struct NavBackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            Image(systemName: "chevron.backward.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(c.textTertiary)
        }
    }
}
