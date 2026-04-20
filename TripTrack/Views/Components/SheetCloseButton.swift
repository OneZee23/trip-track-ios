import SwiftUI

/// Unified close button for all modal sheets. Place in `ToolbarItem(placement: .topBarTrailing)`.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(c.textTertiary)
        }
    }
}
