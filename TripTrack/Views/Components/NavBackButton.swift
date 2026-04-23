import SwiftUI

/// Unified back button. Prefers the custom `\.previewPop` environment
/// action (injected by `PreviewNavigator` in the profile-preview flow)
/// over the built-in `\.dismiss` — so a tap pops our SwiftUI stack
/// instead of dismissing the whole fullScreenCover.
/// Native swipe-back on a real `NavigationStack` still works because the
/// stack sets `\.dismiss` automatically and `\.previewPop` stays nil
/// outside `PreviewNavigator`.
struct NavBackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.previewPop) private var previewPop
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            if let previewPop {
                NavFlashDebug.log.debug("NavBackButton.tap route=previewPop")
                previewPop()
            } else {
                NavFlashDebug.log.debug("NavBackButton.tap route=dismiss")
                dismiss()
            }
        } label: {
            Image(systemName: "chevron.backward.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(c.textTertiary)
        }
    }
}
