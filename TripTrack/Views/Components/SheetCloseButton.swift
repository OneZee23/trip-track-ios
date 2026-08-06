import SwiftUI

/// Unified close button for all modal sheets. Place in `ToolbarItem(placement: .topBarTrailing)`.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button { dismiss() } label: {
            // Canon circle, same as every other close/back control in the
            // app — the old grey `xmark.circle.fill` glyph was the odd one
            // out on any screen that also showed a `NavCircleIcon`.
            NavCircleIcon(systemImage: "xmark")
        }
        .buttonStyle(.plain)
    }
}
