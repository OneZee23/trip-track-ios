import SwiftUI

/// Publish only the top/not-top transition, not a per-frame scroll offset.
/// The photo owns the status area at rest; scrolled journal rows need the
/// same solid status-bar backdrop as the other tabs.
struct ProfileCoverScrollProbe: View {
    let space: String
    let onChange: (Bool) -> Void

    private struct ScrolledKey: PreferenceKey {
        static var defaultValue = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
    }

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ScrolledKey.self, value: geometry.frame(in: .named(space)).minY < -1)
        }
        .onPreferenceChange(ScrolledKey.self, perform: onChange)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
