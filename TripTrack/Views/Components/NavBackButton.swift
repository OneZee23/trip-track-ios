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

    var body: some View {
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
            // Canon control (117:944): surface circle + dark chevron, 44pt
            // hit area. Was a grey `chevron.backward.circle.fill` glyph —
            // inverted against the design and unpaired with the trailing «…».
            NavCircleIcon(systemImage: "chevron.backward")
        }
        // Иконка без текста: без подписи VoiceOver говорит просто «кнопка», а
        // это кнопка «назад» на каждом втором экране приложения.
        .accessibilityLabel(AppStrings.back(LanguageManager.currentLanguage))
    }
}
