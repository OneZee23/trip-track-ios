import SwiftUI

/// What a screen shows while it is fetching.
///
/// It used to be a small car sprite floating over a dashed hairline on a bare
/// cream background — the one branded surface in the app still speaking a
/// different visual language from the drawn scenes everywhere else, and the
/// orange body washed out against the warm page it stood on.
///
/// It is a scene now, from the same family: the road is IN the picture, so the
/// drawn line went away with it. The car is on its way somewhere, which is what
/// waiting for a fetch is.
///
/// The breathing is deliberate and deliberately small. A completely still
/// indicator is indistinguishable from a screen that has hung, and the previous
/// version's answer — sliding the car across the frame — was removed because
/// the motion pulled the eye off the label every time a list refetched. Opacity
/// alone reads as alive without asking to be watched.
struct PixelCarLoader: View {
    var label: String?
    /// Height available for the artwork. Call sites pass anything from 80 for
    /// an inline row to 120 for a full screen, so the scene is fitted to what
    /// it is given rather than to a number chosen here.
    var height: CGFloat = 120

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let side = min(height, 132)

        VStack(spacing: 14) {
            Image("loading_road")
                .resizable()
                // After `resizable()`, as at every other pixel-art call site.
                .interpolation(.none)
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .opacity(breathing ? 1.0 : 0.72)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                    value: breathing
                )
                .onAppear { breathing = true }
                // The label says what is happening; the picture is decoration.
                .accessibilityHidden(true)

            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }
        }
    }
}
